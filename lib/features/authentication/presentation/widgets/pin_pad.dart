import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/utils/app_haptics.dart';
import '../../../../shared/shared.dart';

/// Filled/empty dots representing the typed PIN length (4–8 digits).
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.count,
    this.error = false,
  });

  /// Digits typed so far.
  final int count;

  /// Tints the dots with the error color.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int slots = max(4, count);
    final Color fill = error ? scheme.error : scheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < slots; i++)
          AnimatedContainer(
            duration: AppMotion.fast,
            curve: Curves.easeOut,
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? fill : Colors.transparent,
              border: Border.all(
                color: i < count ? fill : scheme.outlineVariant,
                width: 2,
              ),
            ),
          ),
      ],
    );
  }
}

/// Numeric PIN pad: digits 1–9, 0, backspace, and an optional biometric key.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// When non-null, a fingerprint key appears in the bottom-left slot.
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget padKey(Widget child, VoidCallback? onTap, {String? semanticLabel}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs + 2),
          child: AnimatedPress(
            enabled: enabled && onTap != null,
            child: Semantics(
              button: onTap != null,
              label: semanticLabel,
              child: Material(
                color: onTap == null
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: AppRadius.lgAll,
                child: InkWell(
                  borderRadius: AppRadius.lgAll,
                  onTap: enabled && onTap != null
                      ? () {
                          AppHaptics.light();
                          onTap();
                        }
                      : null,
                  child: SizedBox(height: 64, child: Center(child: child)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget digitKey(String digit) {
      return padKey(
        Text(digit, style: Theme.of(context).textTheme.headlineSmall),
        () => onDigit(digit),
        semanticLabel: 'PIN digit $digit',
      );
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(children: <Widget>[digitKey('1'), digitKey('2'), digitKey('3')]),
          Row(children: <Widget>[digitKey('4'), digitKey('5'), digitKey('6')]),
          Row(children: <Widget>[digitKey('7'), digitKey('8'), digitKey('9')]),
          Row(
            children: <Widget>[
              padKey(
                Icon(Symbols.fingerprint, size: 28, color: scheme.primary),
                onBiometric,
                semanticLabel: 'Unlock with biometrics',
              ),
              digitKey('0'),
              padKey(
                Icon(Symbols.backspace, size: 24, color: scheme.onSurface),
                onBackspace,
                semanticLabel: 'Delete digit',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Complete PIN entry panel: title, subtitle, dots, error, pad, submit.
///
/// Composed by the setup, lock, and change-PIN screens so PIN entry looks
/// and behaves identically everywhere.
class PinEntryPanel extends StatelessWidget {
  const PinEntryPanel({
    super.key,
    required this.title,
    required this.entry,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    this.subtitle,
    this.error,
    this.errorNonce = 0,
    this.submitLabel = 'Continue',
    this.loading = false,
    this.enabled = true,
    this.onBiometric,
  });

  final String title;
  final String? subtitle;

  /// Digits typed so far.
  final String entry;
  final String? error;

  /// Increment on each new error so the shake animation replays.
  final int errorNonce;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool loading;
  final bool enabled;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget dots = PinDots(count: entry.length, error: error != null);
    if (error != null) {
      dots = dots
          .animate(key: ValueKey<int>(errorNonce))
          .shake(hz: 5, duration: 400.ms);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        dots,
        SizedBox(
          height: 32,
          child: Center(
            child: error != null
                ? Text(
                    error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  )
                : null,
          ),
        ),
        PinPad(
          onDigit: onDigit,
          onBackspace: onBackspace,
          onBiometric: onBiometric,
          enabled: enabled && !loading,
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: submitLabel,
          loading: loading,
          fullWidth: true,
          onPressed: enabled && entry.length >= 4 && !loading ? onSubmit : null,
        ),
      ],
    );
  }
}
