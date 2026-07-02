import 'package:flutter/material.dart';

/// Brand color palette.
///
/// Primary: deep indigo → royal blue → premium purple.
/// Accent: emerald and cyan.
/// Surfaces: pure white / near black with grey steps.
abstract final class AppColors {
  // Primary
  static const Color deepIndigo = Color(0xFF3730A3);
  static const Color royalBlue = Color(0xFF2563EB);
  static const Color premiumPurple = Color(0xFF7C3AED);

  // Accent
  static const Color emerald = Color(0xFF10B981);
  static const Color cyan = Color(0xFF06B6D4);

  // Surfaces — light
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color lightGrey = Color(0xFFF4F4F6);
  static const Color lightOutline = Color(0xFFE4E4EA);

  // Surfaces — dark
  static const Color nearBlack = Color(0xFF0B0B0F);
  static const Color darkGrey = Color(0xFF17171D);
  static const Color darkOutline = Color(0xFF2A2A33);

  // Semantic
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = emerald;

  /// Signature brand gradient used on the splash logo and hero surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepIndigo, royalBlue, premiumPurple],
  );
}
