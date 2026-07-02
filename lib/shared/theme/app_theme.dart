import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the light and dark [ThemeData] for the app.
///
/// When a device supports Material You, callers may pass the dynamic
/// [ColorScheme]s (from `dynamic_color`); otherwise the brand seed
/// ([AppColors.deepIndigo]) generates the scheme.
abstract final class AppTheme {
  static ThemeData light({ColorScheme? dynamicScheme}) {
    final ColorScheme scheme =
        (dynamicScheme ?? ColorScheme.fromSeed(seedColor: AppColors.deepIndigo))
            .copyWith(
      surface: AppColors.pureWhite,
      surfaceContainerLowest: AppColors.pureWhite,
      surfaceContainerLow: AppColors.lightGrey,
      outlineVariant: AppColors.lightOutline,
      error: AppColors.danger,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData dark({ColorScheme? dynamicScheme}) {
    final ColorScheme scheme = (dynamicScheme ??
            ColorScheme.fromSeed(
              seedColor: AppColors.deepIndigo,
              brightness: Brightness.dark,
            ))
        .copyWith(
      surface: AppColors.nearBlack,
      surfaceContainerLowest: AppColors.nearBlack,
      surfaceContainerLow: AppColors.darkGrey,
      outlineVariant: AppColors.darkOutline,
      error: AppColors.danger,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final TextTheme textTheme = AppTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
