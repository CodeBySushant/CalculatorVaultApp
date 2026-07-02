import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_constants.dart';
import 'core/crypto/vault_file_store.dart';
import 'core/router/app_router.dart';
import 'core/services/hive_service.dart';
import 'core/services/secure_screen_service.dart';
import 'features/authentication/application/vault_session.dart';
import 'shared/shared.dart';

/// App-wide theme mode, persisted in the Hive settings box.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final HiveService hive = ref.read(hiveServiceProvider);
    final Object? stored = hive.settings.get(AppConstants.keyThemeMode);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final HiveService hive = ref.read(hiveServiceProvider);
    await hive.settings.put(AppConstants.keyThemeMode, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Root widget: wires the router, themes, and Material You dynamic color.
class CalculatorVaultApp extends ConsumerWidget {
  const CalculatorVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(appRouterProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    // Security: the moment the vault locks or the session ends, wipe any
    // temporarily decrypted files (video playback, share exports). While a
    // session exists at all, FLAG_SECURE blocks screenshots and recents
    // previews on Android.
    ref.listen<VaultSessionState>(vaultSessionProvider,
        (VaultSessionState? previous, VaultSessionState next) {
      if (next != VaultSessionState.unlocked) {
        ref.read(vaultFileStoreProvider).clearTemp();
      }
      final SecureScreenService secureScreen =
          ref.read(secureScreenServiceProvider);
      if (next == VaultSessionState.none) {
        secureScreen.disable();
      } else {
        secureScreen.enable();
      }
    });

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: AppTheme.light(dynamicScheme: lightDynamic),
          darkTheme: AppTheme.dark(dynamicScheme: darkDynamic),
          routerConfig: router,
          builder: (BuildContext context, Widget? child) =>
              PrivacyShield(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
