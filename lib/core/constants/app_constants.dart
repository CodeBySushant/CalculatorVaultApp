/// Application-wide constants.
///
/// Keep every magic number and shared string here so the rest of the
/// codebase never hardcodes values.
abstract final class AppConstants {
  /// Public-facing application name (what the user sees on the launcher).
  static const String appName = 'Calculator';

  /// Internal project name used for logs and diagnostics.
  static const String internalName = 'CalculatorVault';

  /// Duration the splash screen stays visible before routing onward.
  static const Duration splashDuration = Duration(milliseconds: 1800);

  /// Default auto-lock timeout applied until the user changes it in Settings.
  static const Duration defaultAutoLockTimeout = Duration(minutes: 1);

  /// Hive box that stores non-sensitive app settings (theme, locale, flags).
  static const String settingsBox = 'settings';

  /// Hive box that stores calculator history (math only, never PIN entries).
  static const String calcHistoryBox = 'calc_history';

  /// Hive box that stores vault item metadata (sensitive fields encrypted).
  static const String vaultItemsBox = 'vault_items';

  /// How long trashed items are kept before permanent auto-deletion.
  static const Duration trashRetention = Duration(days: 30);

  /// Settings keys.
  static const String keyThemeMode = 'theme_mode';
  static const String keyAutoLockSeconds = 'auto_lock_seconds';
  static const String keyDynamicColor = 'dynamic_color';
  static const String keyOnboardingDone = 'onboarding_done';
}

/// Keys used with [FlutterSecureStorage]. Sensitive values only.
abstract final class SecureKeys {
  /// PBKDF2/Argon2-derived hash of the vault PIN (never the PIN itself).
  static const String pinHash = 'vault_pin_hash';

  /// Random salt used when hashing the PIN.
  static const String pinSalt = 'vault_pin_salt';

  /// The AES-256 master key that encrypts vault content (wrapped, base64).
  static const String masterKey = 'vault_master_key';

  /// Whether biometric unlock is enabled.
  static const String biometricsEnabled = 'biometrics_enabled';

  /// Salted hash of the forgot-PIN recovery key (never the key itself).
  static const String recoveryHash = 'vault_recovery_hash';

  /// Random salt used when hashing the recovery key.
  static const String recoverySalt = 'vault_recovery_salt';
}
