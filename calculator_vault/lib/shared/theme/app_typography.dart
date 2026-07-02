import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography system.
///
/// Manrope for display/headline (geometric, premium), Inter for body and
/// labels (excellent small-size readability). Sizes follow Material 3 with
/// tightened letter spacing on large styles.
abstract final class AppTypography {
  static TextTheme textTheme(Brightness brightness) {
    final Color primary = brightness == Brightness.dark
        ? const Color(0xFFF5F5F7)
        : const Color(0xFF111114);
    final Color secondary = brightness == Brightness.dark
        ? const Color(0xFFB9B9C3)
        : const Color(0xFF5A5A66);

    TextStyle display(double size, FontWeight weight, {double? spacing}) =>
        GoogleFonts.manrope(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing ?? -0.5,
          color: primary,
        );

    TextStyle body(double size, FontWeight weight, {Color? color}) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color ?? primary,
        );

    return TextTheme(
      displayLarge: display(56, FontWeight.w700, spacing: -1.5),
      displayMedium: display(44, FontWeight.w700, spacing: -1),
      displaySmall: display(36, FontWeight.w700),
      headlineLarge: display(30, FontWeight.w700),
      headlineMedium: display(26, FontWeight.w600),
      headlineSmall: display(22, FontWeight.w600),
      titleLarge: display(20, FontWeight.w600, spacing: -0.25),
      titleMedium: body(16, FontWeight.w600),
      titleSmall: body(14, FontWeight.w600),
      bodyLarge: body(16, FontWeight.w400),
      bodyMedium: body(14, FontWeight.w400),
      bodySmall: body(12, FontWeight.w400, color: secondary),
      labelLarge: body(14, FontWeight.w600),
      labelMedium: body(12, FontWeight.w600, color: secondary),
      labelSmall: body(11, FontWeight.w500, color: secondary),
    );
  }
}
