import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/crypto/key_manager.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/secure_screen_service.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../shared/shared.dart';
import '../data/biometric_service.dart';
import '../domain/pin_verifier.dart';
import '../domain/recovery_key_service.dart';
import 'widgets/pin_pad.dart';

enum _SetupStep { intro, create, confirm, biometric, recovery }

/// One-time first-launch flow: create PIN → confirm → biometric opt-in →
/// recovery key. After completion the app presents as a plain calculator
/// and the vault opens only via PIN + `=`.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  static const Set<String> _weakPins = <String>{'1234', '0000', '1111'};

  _SetupStep _step = _SetupStep.intro;
  String _firstPin = '';
  String _entry = '';
  String? _error;
  int _errorNonce = 0;
  bool _bioSupported = false;
  bool _bioOptIn = false;
  String? _recoveryCode;
  bool _recoverySaved = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // The recovery key is shown on this screen — block capture while here.
    ref.read(secureScreenServiceProvider).enable();
    ref.read(biometricServiceProvider).isDeviceSupported().then((bool ok) {
      if (mounted) setState(() => _bioSupported = ok);
    });
  }

  @override
  void dispose() {
    // Session is still `none` after setup; return to normal capture mode.
    ref.read(secureScreenServiceProvider).disable();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_entry.length >= 8) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _fail(String message) {
    AppHaptics.heavy();
    setState(() {
      _error = message;
      _errorNonce++;
      _entry = '';
    });
  }

  void _submitCreate() {
    if (_weakPins.contains(_entry) || _entry.split('').toSet().length == 1) {
      _fail('That PIN is too easy to guess. Pick another.');
      return;
    }
    setState(() {
      _firstPin = _entry;
      _entry = '';
      _error = null;
      _step = _SetupStep.confirm;
    });
  }

  void _submitConfirm() {
    if (_entry != _firstPin) {
      setState(() {
        _firstPin = '';
        _step = _SetupStep.create;
      });
      _fail("PINs didn't match. Let's start over.");
      return;
    }
    setState(() {
      _entry = '';
      _error = null;
      _step = _bioSupported ? _SetupStep.biometric : _SetupStep.recovery;
    });
    if (!_bioSupported) _generateRecovery();
  }

  Future<void> _chooseBiometric(bool optIn) async {
    setState(() {
      _bioOptIn = optIn;
      _step = _SetupStep.recovery;
    });
    await _generateRecovery();
  }

  Future<void> _generateRecovery() async {
    final String code =
        await ref.read(recoveryKeyServiceProvider).createAndStore();
    if (mounted) setState(() => _recoveryCode = code);
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await ref.read(pinVerifierProvider).setPin(_firstPin);
    await ref.read(biometricServiceProvider).setEnabled(_bioOptIn);
    // Generate the vault master key now so the first import is instant.
    await ref.read(keyManagerProvider).ensureMasterKey();
    if (!mounted) return;
    context.go(AppRoutes.calculator);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All set. Type your PIN and = to open your vault.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedSwitcher(
                duration: AppMotion.normal,
                switchInCurve: AppMotion.emphasized,
                transitionBuilder: (Widget child, Animation<double> anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: switch (_step) {
                  _SetupStep.intro => _buildIntro(),
                  _SetupStep.create => _buildPinStep(
                      key: const ValueKey<String>('create'),
                      title: 'Create your PIN',
                      subtitle:
                          '4–8 digits. This opens your vault from the calculator.',
                      onSubmit: _submitCreate,
                    ),
                  _SetupStep.confirm => _buildPinStep(
                      key: const ValueKey<String>('confirm'),
                      title: 'Confirm your PIN',
                      subtitle: 'Type the same PIN again.',
                      onSubmit: _submitConfirm,
                    ),
                  _SetupStep.biometric => _buildBiometric(),
                  _SetupStep.recovery => _buildRecovery(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    final ThemeData theme = Theme.of(context);
    return Column(
      key: const ValueKey<String>('intro'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: AppRadius.xlAll,
          ),
          child: const Icon(Symbols.shield_lock, size: 44, color: Colors.white),
        ).animate().scale(curve: AppMotion.spring, duration: AppMotion.slow),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Set up your private space',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Behind this calculator lives a fully encrypted vault for your '
          'photos, videos, notes and passwords.\n\n'
          'To open it, type your secret PIN in the calculator and press =. '
          'Wrong entries behave like normal math — nobody can tell the '
          'vault exists.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Create PIN',
          fullWidth: true,
          onPressed: () => setState(() => _step = _SetupStep.create),
        ),
      ],
    );
  }

  Widget _buildPinStep({
    required Key key,
    required String title,
    required String subtitle,
    required VoidCallback onSubmit,
  }) {
    return PinEntryPanel(
      key: key,
      title: title,
      subtitle: subtitle,
      entry: _entry,
      error: _error,
      errorNonce: _errorNonce,
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      onSubmit: onSubmit,
    );
  }

  Widget _buildBiometric() {
    final ThemeData theme = Theme.of(context);
    return Column(
      key: const ValueKey<String>('biometric'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Symbols.fingerprint, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Unlock with biometrics?',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Use your fingerprint or face to re-open the vault after it '
          'auto-locks. Your PIN always keeps working.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Enable biometrics',
          icon: Symbols.fingerprint,
          fullWidth: true,
          onPressed: () => _chooseBiometric(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Not now',
          variant: AppButtonVariant.ghost,
          fullWidth: true,
          onPressed: () => _chooseBiometric(false),
        ),
      ],
    );
  }

  Widget _buildRecovery() {
    final ThemeData theme = Theme.of(context);
    final String? code = _recoveryCode;
    return Column(
      key: const ValueKey<String>('recovery'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Save your recovery key',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'If you ever forget your PIN, this key is the only way back into '
          'your vault. Store it somewhere safe — it is shown only once.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (code == null)
          const Center(child: CircularProgressIndicator())
        else ...<Widget>[
          AppCard(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    code,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(letterSpacing: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Symbols.content_copy, size: 22),
                  onPressed: () async {
                    final ScaffoldMessengerState messenger =
                        ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: code));
                    AppHaptics.selection();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Recovery key copied'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            value: _recoverySaved,
            onChanged: (bool? v) => setState(() => _recoverySaved = v ?? false),
            title: Text(
              "I've saved my recovery key somewhere safe",
              style: theme.textTheme.bodyMedium,
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Finish setup',
            fullWidth: true,
            loading: _finishing,
            onPressed: _recoverySaved && !_finishing ? _finish : null,
          ),
        ],
      ],
    );
  }
}
