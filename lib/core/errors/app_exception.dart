/// Base class for every recoverable, typed error in the application.
///
/// Layers above the data layer should catch [AppException] subtypes and
/// convert them into user-friendly UI states — never raw stack traces.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Human-readable, safe-to-display message.
  final String message;

  /// Optional underlying error for logging/diagnostics.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Errors reading from or writing to local storage (Hive, file system).
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// Errors while encrypting or decrypting vault content.
final class EncryptionException extends AppException {
  const EncryptionException(super.message, {super.cause});
}

/// Errors during PIN or biometric authentication.
final class AuthException extends AppException {
  const AuthException(super.message, {super.cause});
}

/// Errors caused by missing or denied platform permissions.
final class PermissionException extends AppException {
  const PermissionException(super.message, {super.cause});
}

/// Anything unexpected that we still want to surface gracefully.
final class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause});
}
