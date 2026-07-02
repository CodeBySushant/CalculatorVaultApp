import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/secure_storage_service.dart';
import 'hashed_secret_store.dart';

/// Riverpod provider — overridden with a fake in tests.
final pinVerifierProvider = Provider<PinVerifier>(
  (ref) => PinVerifier(ref.watch(secureStorageServiceProvider)),
);

/// Hashes and verifies the vault PIN.
///
/// The PIN itself is never persisted — see [HashedSecretStore] for the
/// hashing scheme (PBKDF2-HMAC-SHA256, random salt, constant-time compare).
class PinVerifier {
  PinVerifier(SecureStorageService storage)
      : _store = HashedSecretStore(
          storage,
          hashKey: SecureKeys.pinHash,
          saltKey: SecureKeys.pinSalt,
        );

  final HashedSecretStore _store;

  /// Whether the user has configured a vault PIN yet.
  Future<bool> isPinSet() => _store.isSet();

  /// Hashes [pin] with a fresh random salt and persists hash + salt.
  Future<void> setPin(String pin) => _store.setSecret(pin);

  /// Removes the stored PIN entirely (used by the forgot-PIN reset flow).
  Future<void> clearPin() => _store.clear();

  /// Returns true only when [candidate] matches the stored PIN.
  ///
  /// Never throws: any storage failure returns false so the calculator
  /// simply continues behaving like a calculator.
  Future<bool> verify(String candidate) => _store.verify(candidate);
}
