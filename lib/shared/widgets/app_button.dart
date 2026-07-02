import 'package:flutter/material.dart';

import '../../core/utils/app_haptics.dart';
import '../design/app_tokens.dart';
import '../theme/app_colors.dart';
import 'animated_press.dart';

/// Visual styles for [AppButton].
enum AppButtonVariant {
  /// Brand gradient background — the single most important action on screen.
  primary,

  /// Tonal (secondary container) — common actions.
  tonal,

  /// Transparent with primary-colored label — low-emphasis actions.
  ghost,

  /// Error-tinted — destructive actions (delete, remove).
  destructive,
}

/// The app-wide button. Handles haptics, loading state, icons and variants.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
  });

  final String label;

  /// Pass `null` to render the disabled state.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final (Color background, Color foreground, Gradient? gradient) =
        switch (variant) {
      AppButtonVariant.primary => (
          Colors.transparent,
          Colors.white,
          AppColors.brandGradient,
        ),
      AppButtonVariant.tonal => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          null,
        ),
      AppButtonVariant.ghost => (Colors.transparent, scheme.primary, null),
      AppButtonVariant.destructive => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          null,
        ),
    };

    final Widget content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (loading) ...<Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ] else if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: foreground),
        ),
      ],
    );

    return AnimatedPress(
      enabled: _enabled,
      child: Semantics(
        button: true,
        enabled: _enabled,
        label: label,
        child: AnimatedOpacity(
          opacity: _enabled ? 1 : 0.5,
          duration: AppMotion.fast,
          child: Material(
            color: background,
            borderRadius: AppRadius.mdAll,
            child: Ink(
              decoration: BoxDecoration(
                gradient: _enabled ? gradient : null,
                color: !_enabled && variant == AppButtonVariant.primary
                    ? scheme.surfaceContainerHighest
                    : null,
                borderRadius: AppRadius.mdAll,
              ),
              child: InkWell(
                borderRadius: AppRadius.mdAll,
                onTap: _enabled
                    ? () {
                        AppHaptics.light();
                        onPressed!();
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 15,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
