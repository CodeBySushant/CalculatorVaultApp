import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/secure_storage_service.dart';

/// Stores and verifies a secret as a salted PBKDF2-HMAC-SHA256 hash.
///
/// The secret itself is never persisted: only a 256-bit hash
/// (100,000 iterations) plus its random 16-byte salt, both in platform
/// secure storage. Verification is constant-time.
///
/// Used by [PinVerifier] (vault PIN) and [RecoveryKeyService] (forgot-PIN
/// recovery code) with different storage keys.
class HashedSecretStore {
  HashedSecretStore(
    this._storage, {
    required this.hashKey,
    required this.saltKey,
  });

  static const int _iterations = 100000;
  static const int _saltLength = 16;

  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  final SecureStorageService _storage;
  final String hashKey;
  final String saltKey;

  /// Whether a secret has been stored.
  Future<bool> isSet() => _storage.containsKey(hashKey);

  /// Hashes [secret] with a fresh random salt and persists hash + salt.
  Future<void> setSecret(String secret) async {
    final Random random = Random.secure();
    final List<int> salt =
        List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final List<int> hash = await _derive(secret, salt);
    await _storage.write(saltKey, base64Encode(salt));
    await _storage.write(hashKey, base64Encode(hash));
  }

  /// Removes the stored hash and salt.
  Future<void> clear() async {
    await _storage.delete(hashKey);
    await _storage.delete(saltKey);
  }

  /// True only when [candidate] matches the stored secret.
  ///
  /// Never throws: storage failures return false.
  Future<bool> verify(String candidate) async {
    try {
      final String? saltB64 = await _storage.read(saltKey);
      final String? hashB64 = await _storage.read(hashKey);
      if (saltB64 == null || hashB64 == null) return false;
      final List<int> derived = await _derive(candidate, base64Decode(saltB64));
      return constantTimeEquals(derived, base64Decode(hashB64));
    } on AppException {
      return false;
    }
  }

  Future<List<int>> _derive(String secret, List<int> salt) async {
    final SecretKey key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  /// Constant-time byte comparison to avoid timing side channels.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
