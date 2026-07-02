import 'package:flutter/foundation.dart';

/// Lightweight, debug-only logger.
///
/// Logs are stripped in release builds so no vault-related information can
/// ever leak through logcat / Console on production devices.
abstract final class AppLogger {
  static void info(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void error(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[$tag][ERROR] $message${error != null ? ' | $error' : ''}');
      if (stackTrace != null) {
        debugPrintStack(stackTrace: stackTrace, maxFrames: 12);
      }
    }
  }
}
