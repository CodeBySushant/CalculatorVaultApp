import 'package:flutter/material.dart';

/// Spacing scale. Use these instead of raw numbers everywhere.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Default horizontal screen padding.
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: 20);
}

/// Corner radius scale.
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
}

/// Motion durations and curves for a consistent animation feel.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;
}

/// Responsive breakpoints (Material 3 window size classes).
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
}

/// Soft shadow presets used on elevated cards and the splash logo.
abstract final class AppShadows {
  static List<BoxShadow> soft(Color tint) => <BoxShadow>[
        BoxShadow(
          color: tint.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> raised(Color tint) => <BoxShadow>[
        BoxShadow(
          color: tint.withValues(alpha: 0.18),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ];
}
