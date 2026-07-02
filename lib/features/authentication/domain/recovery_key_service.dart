import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/secure_storage_service.dart';
import 'hashed_secret_store.dart';

/// Riverpod provider — overridden with a fake in tests.
final recoveryKeyServiceProvider = Provider<RecoveryKeyService>(
  (ref) => RecoveryKeyService(ref.watch(secureStorageServiceProvider)),
);

/// Manages the forgot-PIN recovery key.
///
/// During setup a random 16-character code (formatted `XXXX-XXXX-XXXX-XXXX`)
/// is shown to the user exactly once. Only its salted hash is stored. If the
/// PIN is forgotten, entering the recovery code allows setting a new PIN.
class RecoveryKeyService {
  RecoveryKeyService(SecureStorageService storage)
      : _store = HashedSecretStore(
          storage,
          hashKey: SecureKeys.recoveryHash,
          saltKey: SecureKeys.recoverySalt,
        );

  /// Unambiguous alphabet: no 0/O or 1/I lookalikes.
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final HashedSecretStore _store;

  /// Whether a recovery key exists.
  Future<bool> isSet() => _store.isSet();

  /// Generates a fresh recovery code, stores its hash, and returns the
  /// formatted code for one-time display. Any previous code is replaced.
  Future<String> createAndStore() async {
    final Random random = Random.secure();
    final String raw = String.fromCharCodes(
      List<int>.generate(
        16,
        (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
      ),
    );
    await _store.setSecret(raw);
    return _format(raw);
  }

  /// Verifies user input against the stored code. Case-insensitive and
  /// tolerant of dashes/spaces. Never throws.
  Future<bool> verify(String input) {
    return _store.verify(_normalize(input));
  }

  static String _format(String raw) =>
      '${raw.substring(0, 4)}-${raw.substring(4, 8)}-'
      '${raw.substring(8, 12)}-${raw.substring(12, 16)}';

  static String _normalize(String input) =>
      input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}
