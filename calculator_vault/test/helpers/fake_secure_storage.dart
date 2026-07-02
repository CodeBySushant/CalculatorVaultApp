import 'package:calculator_vault/core/services/secure_storage_service.dart';

/// In-memory replacement for platform secure storage, shared by every test
/// suite that needs it.
class FakeSecureStorage extends SecureStorageService {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
}
