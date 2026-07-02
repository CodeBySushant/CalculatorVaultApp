import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/app_logger.dart';

final secureScreenServiceProvider = Provider<SecureScreenService>(
  (ref) => SecureScreenService(),
);

/// Toggles Android's FLAG_SECURE via a method channel, blocking screenshots
/// and blanking the app in the recents screen while the vault is active.
///
/// The native side lives in `platform/android/MainActivity.kt` (copied into
/// the generated Android project — see `platform/README.md`). iOS has no
/// FLAG_SECURE equivalent; the Dart-side [PrivacyShield] covers the app
/// switcher there. If the native handler is missing (e.g. before the
/// platform file is copied, or in tests) every call degrades to a logged
/// no-op — never a crash.
class SecureScreenService {
  static const String _tag = 'SecureScreen';
  static const MethodChannel _channel =
      MethodChannel('calculator_vault/secure_screen');

  /// Blocks screenshots and recents previews (Android).
  Future<void> enable() => _invoke('enable');

  /// Restores normal capture behavior (Android).
  Future<void> disable() => _invoke('disable');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      AppLogger.info(_tag, '$method: native handler not installed');
    } on PlatformException catch (e) {
      AppLogger.error(_tag, '$method failed', e);
    }
  }
}
