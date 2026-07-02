import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../services/secure_storage_service.dart';

/// Riverpod provider. Overridden in `main()` so the whole app shares one
/// instance (the master key must never be generated twice).
final keyManagerProvider = Provider<KeyManager>(
  (ref) => KeyManager(ref.watch(secureStorageServiceProvider)),
);

/// Owns the AES-256 master key.
///
/// The key is generated once from a CSPRNG and stored in platform secure
/// storage (Android Keystore-encrypted prefs / iOS Keychain). Every vault
/// file gets its own random data key, which is wrapped (encrypted) by this
/// master key — so the master key never directly touches bulk data, and a
/// future "re-wrap" (e.g. after key rotation) never requires re-encrypting
/// files.
///
/// Security model: encryption-at-rest with the key in hardware-backed
/// storage; the PIN is access control on top. This keeps the forgot-PIN
/// recovery flow able to restore access without data loss.
class KeyManager {
  KeyManager(this._storage);

  static const int _keyLength = 32;

  final SecureStorageService _storage;

  SecretKey? _cached;
  Future<SecretKey>? _inflight;

  /// Returns the master key, generating and persisting it on first use.
  /// Concurrent callers share a single load (no double-generation race).
  Future<SecretKey> getMasterKey() {
    final SecretKey? cached = _cached;
    if (cached != null) return Future<SecretKey>.value(cached);
    return _inflight ??= _loadOrCreate();
  }

  /// Proactively creates the master key (called at the end of PIN setup so
  /// the first vault import never pays key-generation latency).
  Future<void> ensureMasterKey() async {
    await getMasterKey();
  }

  Future<SecretKey> _loadOrCreate() async {
    try {
      final String? existing = await _storage.read(SecureKeys.masterKey);
      if (existing != null) {
        final SecretKey key = SecretKey(base64Decode(existing));
        _cached = key;
        return key;
      }
      final Random random = Random.secure();
      final List<int> bytes =
          List<int>.generate(_keyLength, (_) => random.nextInt(256));
      await _storage.write(SecureKeys.masterKey, base64Encode(bytes));
      final SecretKey key = SecretKey(bytes);
      _cached = key;
      return key;
    } finally {
      _inflight = null;
    }
  }

  /// Test hook: clears the in-memory cache.
  @visibleForTesting
  void debugResetCache() {
    _cached = null;
    _inflight = null;
  }
}
