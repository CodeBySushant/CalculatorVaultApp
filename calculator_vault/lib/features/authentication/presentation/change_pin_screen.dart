import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../shared/shared.dart';
import '../application/vault_session.dart';
import '../domain/pin_verifier.dart';
import 'widgets/pin_pad.dart';

enum _ChangeStep { verify, create, confirm }

/// Changes the vault PIN.
///
/// With [requireCurrent] (Settings → Change PIN) the current PIN must be
/// verified first. Without it (reset via recovery key) the flow starts at
/// creating a new PIN.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key, required this.requireCurrent});

  final bool requireCurrent;

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  static const Set<String> _weakPins = <String>{'1234', '0000', '1111'};

  late _ChangeStep _step =
      widget.requireCurrent ? _ChangeStep.verify : _ChangeStep.create;
  String _newPin = '';
  String _entry = '';
  String? _error;
  int _errorNonce = 0;
  bool _busy = false;

  void _onDigit(String digit) {
    if (_entry.length >= 8 || _busy) return;
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
      _busy = false;
      _entry = '';
      _error = message;
      _errorNonce++;
    });
  }

  Future<void> _submit() async {
    switch (_step) {
      case _ChangeStep.verify:
        setState(() => _busy = true);
        final bool ok = await ref.read(pinVerifierProvider).verify(_entry);
        if (!mounted) return;
        if (!ok) {
          _fail('Wrong PIN.');
          return;
        }
        setState(() {
          _busy = false;
          _entry = '';
          _step = _ChangeStep.create;
        });
      case _ChangeStep.create:
        if (_weakPins.contains(_entry) ||
            _entry.split('').toSet().length == 1) {
          _fail('That PIN is too easy to guess. Pick another.');
          return;
        }
        setState(() {
          _newPin = _entry;
          _entry = '';
          _step = _ChangeStep.confirm;
        });
      case _ChangeStep.confirm:
        if (_entry != _newPin) {
          setState(() => _step = _ChangeStep.create);
          _fail("PINs didn't match. Let's start over.");
          return;
        }
        setState(() => _busy = true);
        await ref.read(pinVerifierProvider).setPin(_newPin);
        if (!mounted) return;
        ref.read(vaultSessionProvider.notifier).unlock();
        context.go(AppRoutes.vault);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your PIN has been updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String title, String subtitle) = switch (_step) {
      _ChangeStep.verify => ('Enter current PIN', 'Verify it is really you.'),
      _ChangeStep.create => (
          'Create a new PIN',
          '4–8 digits. This opens your vault from the calculator.'
        ),
      _ChangeStep.confirm => ('Confirm new PIN', 'Type the same PIN again.'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.requireCurrent ? 'Change PIN' : 'Reset PIN'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: PinEntryPanel(
                key: ValueKey<_ChangeStep>(_step),
                title: title,
                subtitle: subtitle,
                entry: _entry,
                error: _error,
                errorNonce: _errorNonce,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                onSubmit: _submit,
                submitLabel:
                    _step == _ChangeStep.confirm ? 'Save PIN' : 'Continue',
                loading: _busy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
