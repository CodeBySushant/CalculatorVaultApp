import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// A frosted-glass surface: backdrop blur + translucent tint + hairline
/// border. Use sparingly — over imagery (photo viewer controls) and on
/// overlays, never as the default card.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.55,
    this.borderRadius,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final double blur;

  /// Tint opacity of the surface color behind the blur.
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = borderRadius ?? AppRadius.lgAll;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: opacity),
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
