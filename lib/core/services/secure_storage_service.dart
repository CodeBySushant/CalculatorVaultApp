import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/app_exception.dart';
import '../utils/app_logger.dart';

/// Riverpod provider for the app-wide [SecureStorageService] singleton.
final secureStorageServiceProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

/// Thin, typed wrapper around [FlutterSecureStorage].
///
/// All sensitive values — PIN hash, salt, wrapped master key, biometric
/// flags — go through this service. Nothing sensitive is ever written to
/// Hive or SharedPreferences.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const String _tag = 'SecureStorage';

  final FlutterSecureStorage _storage;

  /// Reads a value, returning `null` when the key does not exist.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'read failed for key=$key', e, st);
      throw StorageException('Could not read secure value.', cause: e);
    }
  }

  /// Writes (or overwrites) a value.
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'write failed for key=$key', e, st);
      throw StorageException('Could not save secure value.', cause: e);
    }
  }

  /// Deletes a single key. Safe to call when the key is absent.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'delete failed for key=$key', e, st);
      throw StorageException('Could not delete secure value.', cause: e);
    }
  }

  /// Returns whether a key currently exists.
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'containsKey failed for key=$key', e, st);
      throw StorageException('Could not check secure value.', cause: e);
    }
  }
}
