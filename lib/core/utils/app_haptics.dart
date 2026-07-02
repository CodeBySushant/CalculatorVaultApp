import 'package:flutter/services.dart';

/// Centralized haptic feedback so intensity stays consistent app-wide.
abstract final class AppHaptics {
  /// Key presses, small toggles.
  static void light() => HapticFeedback.lightImpact();

  /// Confirmations, card taps.
  static void medium() => HapticFeedback.mediumImpact();

  /// Pickers, tab switches.
  static void selection() => HapticFeedback.selectionClick();

  /// Destructive actions and errors (wrong PIN, delete).
  static void heavy() => HapticFeedback.heavyImpact();
}
