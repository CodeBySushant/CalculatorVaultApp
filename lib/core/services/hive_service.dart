import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../utils/app_logger.dart';

/// Riverpod provider for the app-wide [HiveService] singleton.
final hiveServiceProvider = Provider<HiveService>((ref) => HiveService());

/// Owns Hive initialization and access to non-sensitive boxes.
///
/// Only non-sensitive data lives in Hive (theme mode, UI preferences,
/// vault metadata that is itself encrypted before storage). Secrets always
/// go through [SecureStorageService].
class HiveService {
  static const String _tag = 'Hive';

  bool _initialized = false;

  /// Whether [init] has completed successfully.
  bool get isInitialized => _initialized;

  /// Initializes Hive and opens boxes required at startup.
  ///
  /// Must be called once from `main()` before `runApp`.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Hive.initFlutter();
      await Hive.openBox<dynamic>(AppConstants.settingsBox);
      await Hive.openBox<dynamic>(AppConstants.calcHistoryBox);
      await Hive.openBox<dynamic>(AppConstants.vaultItemsBox);
      _initialized = true;
      AppLogger.info(_tag, 'initialized');
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'initialization failed', e, st);
      throw StorageException(
        'Local storage could not be initialized.',
        cause: e,
      );
    }
  }

  /// The settings box. [init] must have completed first.
  Box<dynamic> get settings {
    if (!_initialized) {
      throw const StorageException('HiveService used before init().');
    }
    return Hive.box<dynamic>(AppConstants.settingsBox);
  }

  /// The calculator history box. [init] must have completed first.
  Box<dynamic> get calcHistory {
    if (!_initialized) {
      throw const StorageException('HiveService used before init().');
    }
    return Hive.box<dynamic>(AppConstants.calcHistoryBox);
  }

  /// The vault item metadata box. [init] must have completed first.
  Box<dynamic> get vaultItems {
    if (!_initialized) {
      throw const StorageException('HiveService used before init().');
    }
    return Hive.box<dynamic>(AppConstants.vaultItemsBox);
  }

  /// Flushes and closes all boxes. Called on app teardown in tests.
  Future<void> close() async {
    await Hive.close();
    _initialized = false;
  }
}
