import 'package:flutter/material.dart';

import '../../core/utils/app_haptics.dart';
import '../design/app_tokens.dart';
import 'animated_press.dart';

/// The app-wide card surface.
///
/// Renders a rounded container on `surfaceContainerLow`. When [onTap] is
/// provided it becomes interactive with ripple, haptic and press animation.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.elevated = false,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  /// Adds a soft shadow for cards floating over content.
  final bool elevated;

  /// Overrides the default surface color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool interactive = onTap != null || onLongPress != null;

    final Widget card = Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        boxShadow: elevated ? AppShadows.soft(scheme.shadow) : null,
      ),
      child: Material(
        color: color ?? scheme.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap != null
              ? () {
                  AppHaptics.selection();
                  onTap!();
                }
              : null,
          onLongPress: onLongPress != null
              ? () {
                  AppHaptics.medium();
                  onLongPress!();
                }
              : null,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return interactive ? AnimatedPress(child: card) : card;
  }
}
