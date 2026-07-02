import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/crypto/key_manager.dart';
import 'core/crypto/vault_file_store.dart';
import 'core/services/hive_service.dart';
import 'core/services/secure_storage_service.dart';
import 'core/utils/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge rendering with transparent system bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Initialize local storage before the first frame.
  final HiveService hiveService = HiveService();
  await hiveService.init();

  // Crypto stack: one SecureStorageService and one KeyManager instance for
  // the whole app, so the master key can never be generated twice.
  final SecureStorageService secureStorage = SecureStorageService();
  final KeyManager keyManager = KeyManager(secureStorage);
  final Directory documentsDir = await getApplicationDocumentsDirectory();
  final Directory temporaryDir = await getTemporaryDirectory();
  final VaultFileStore fileStore = VaultFileStore(
    baseDir: Directory('${documentsDir.path}/vault'),
    tempDir: Directory('${temporaryDir.path}/vault_temp'),
    keyManager: keyManager,
  );
  // Any decrypted temp files from a previous run must not survive a
  // restart.
  await fileStore.clearTemp();

  // Surface uncaught framework errors during development.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.error(
      'Flutter',
      'Uncaught error',
      details.exception,
      details.stack,
    );
  };

  runApp(
    ProviderScope(
      overrides: <Override>[
        hiveServiceProvider.overrideWithValue(hiveService),
        secureStorageServiceProvider.overrideWithValue(secureStorage),
        keyManagerProvider.overrideWithValue(keyManager),
        vaultFileStoreProvider.overrideWithValue(fileStore),
      ],
      child: const CalculatorVaultApp(),
    ),
  );
}
