import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/secure_storage_service.dart';
import '../../../core/utils/app_logger.dart';

/// Riverpod provider — overridden with a fake in tests.
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(
    LocalAuthentication(),
    ref.watch(secureStorageServiceProvider),
  ),
);

/// True when the device supports biometrics AND the user enabled them.
/// Drives the fingerprint key on the lock screen.
final biometricUnlockAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricServiceProvider).isAvailableAndEnabled(),
);

/// Fingerprint / Face unlock via `local_auth`.
///
/// Biometrics are a convenience on top of the PIN, never a replacement:
/// the calculator entry always uses the PIN, and biometric unlock only
/// appears on the in-vault lock screen. All failures degrade to `false`
/// so the PIN path always remains available.
class BiometricService {
  BiometricService(this._auth, this._storage);

  static const String _tag = 'Biometrics';

  final LocalAuthentication _auth;
  final SecureStorageService _storage;

  /// Whether this device can perform biometric authentication.
  Future<bool> isDeviceSupported() async {
    try {
      final bool supported = await _auth.isDeviceSupported();
      final bool hasBiometrics = await _auth.canCheckBiometrics;
      return supported && hasBiometrics;
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'support check failed', e);
      return false;
    }
  }

  /// The user's opt-in flag.
  Future<bool> isEnabled() async {
    final String? value = await _storage.read(SecureKeys.biometricsEnabled);
    return value == 'true';
  }

  /// Persists the opt-in flag.
  Future<void> setEnabled(bool enabled) =>
      _storage.write(SecureKeys.biometricsEnabled, enabled.toString());

  /// Supported by the device AND enabled by the user.
  Future<bool> isAvailableAndEnabled() async =>
      await isDeviceSupported() && await isEnabled();

  /// Shows the platform biometric prompt. Returns true on success; every
  /// failure or cancellation returns false.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'authenticate failed', e);
      return false;
    }
  }
}
