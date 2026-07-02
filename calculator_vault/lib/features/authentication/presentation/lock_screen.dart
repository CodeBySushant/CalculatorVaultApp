import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../shared/shared.dart';
import '../application/vault_session.dart';
import '../data/biometric_service.dart';
import '../domain/pin_verifier.dart';
import '../domain/recovery_key_service.dart';
import 'widgets/pin_pad.dart';

/// Shown when the vault auto-locked mid-session. Unlock with PIN or
/// biometrics; includes a forgot-PIN recovery path and brute-force cooldown
/// (5 wrong attempts → 30 second wait).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const int _maxAttempts = 5;
  static const Duration _cooldown = Duration(seconds: 30);

  String _entry = '';
  String? _error;
  int _errorNonce = 0;
  int _failedAttempts = 0;
  bool _verifying = false;
  int _cooldownSecondsLeft = 0;
  Timer? _cooldownTimer;

  bool get _inCooldown => _cooldownSecondsLeft > 0;

  @override
  void initState() {
    super.initState();
    // Offer biometrics immediately when enabled.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _tryBiometric(auto: true));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometric({bool auto = false}) async {
    final BiometricService biometrics = ref.read(biometricServiceProvider);
    if (!await biometrics.isAvailableAndEnabled()) return;
    if (_inCooldown || !mounted) return;
    final bool ok = await biometrics.authenticate('Unlock your vault');
    if (ok && mounted) {
      _unlock();
    } else if (!auto && mounted) {
      setState(() {
        _error = 'Biometric authentication failed';
        _errorNonce++;
      });
    }
  }

  void _onDigit(String digit) {
    if (_entry.length >= 8 || _verifying || _inCooldown) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _verifying = true);
    final bool ok = await ref.read(pinVerifierProvider).verify(_entry);
    if (!mounted) return;
    if (ok) {
      _unlock();
      return;
    }
    AppHaptics.heavy();
    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _startCooldown();
    } else {
      setState(() {
        _verifying = false;
        _entry = '';
        _error = 'Wrong PIN. ${_maxAttempts - _failedAttempts} attempts left.';
        _errorNonce++;
      });
    }
  }

  void _unlock() {
    ref.read(vaultSessionProvider.notifier).unlock();
    if (mounted) context.go(AppRoutes.vault);
  }

  void _startCooldown() {
    _failedAttempts = 0;
    setState(() {
      _verifying = false;
      _entry = '';
      _error = null;
      _cooldownSecondsLeft = _cooldown.inSeconds;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldownSecondsLeft--;
        if (_cooldownSecondsLeft <= 0) t.cancel();
      });
    });
  }

  Future<void> _forgotPin() async {
    final TextEditingController controller = TextEditingController();
    String? sheetError;
    final bool? verified = await showAppBottomSheet<bool>(
      context: context,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Enter recovery key',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Type the 16-character key you saved during setup.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: controller,
                  hint: 'XXXX-XXXX-XXXX-XXXX',
                  errorText: sheetError,
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Verify',
                  fullWidth: true,
                  onPressed: () async {
                    final bool ok = await ref
                        .read(recoveryKeyServiceProvider)
                        .verify(controller.text);
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.of(context).pop(true);
                    } else {
                      setSheetState(
                        () => sheetError = 'That key is not correct.',
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (verified == true && mounted) {
      context.go(AppRoutes.resetPin, extra: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool biometricsAvailable =
        ref.watch(biometricUnlockAvailableProvider).value ?? false;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Symbols.lock,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_inCooldown) ...<Widget>[
                    Text(
                      'Too many attempts',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Try again in $_cooldownSecondsLeft seconds.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  PinEntryPanel(
                    title: 'Vault locked',
                    subtitle: 'Enter your PIN to continue.',
                    entry: _entry,
                    error: _error,
                    errorNonce: _errorNonce,
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    onSubmit: _submit,
                    submitLabel: 'Unlock',
                    loading: _verifying,
                    enabled: !_inCooldown,
                    onBiometric: biometricsAvailable ? _tryBiometric : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Forgot PIN?',
                    variant: AppButtonVariant.ghost,
                    onPressed: _inCooldown ? null : _forgotPin,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
