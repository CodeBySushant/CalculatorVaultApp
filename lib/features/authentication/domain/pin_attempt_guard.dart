import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/secure_storage_service.dart';

/// Riverpod provider — overridden with a fake in tests.
final pinAttemptGuardProvider = Provider<PinAttemptGuard>(
  (ref) => PinAttemptGuard(ref.watch(secureStorageServiceProvider)),
);

/// Persistent brute-force protection for the vault PIN.
///
/// Both PIN entry paths — the secret calculator check AND the in-vault lock
/// screen — share this guard, so an attacker cannot dodge the cooldown by
/// switching surfaces or force-killing the app (the counter and the
/// lockout deadline live in platform secure storage, not in memory).
///
/// Policy: 5 consecutive failures start a 30-second lockout; every further
/// failure while at/above the threshold doubles the next lockout, capped at
/// 5 minutes. A single correct PIN resets everything.
///
/// While locked out the calculator path performs NO verification at all
/// (so pure digit entries simply evaluate as numbers — the disguise is
/// preserved and the lockout cannot be probed), and the lock screen shows
/// the countdown.
class PinAttemptGuard {
  PinAttemptGuard(this._storage);

  static const int maxAttempts = 5;
  static const Duration baseCooldown = Duration(seconds: 30);
  static const Duration maxCooldown = Duration(minutes: 5);

  final SecureStorageService _storage;

  /// Remaining lockout, or [Duration.zero] when attempts are allowed.
  /// Never throws: storage failures fail open to zero so the PIN path
  /// stays usable (the PBKDF2 cost still rate-limits verification).
  Future<Duration> remainingLockout() async {
    try {
      final String? raw = await _storage.read(SecureKeys.pinLockoutUntil);
      if (raw == null) return Duration.zero;
      final int? untilMs = int.tryParse(raw);
      if (untilMs == null) return Duration.zero;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      return untilMs > nowMs
          ? Duration(milliseconds: untilMs - nowMs)
          : Duration.zero;
    } on AppException {
      return Duration.zero;
    }
  }

  /// Whether a verification attempt may run right now.
  Future<bool> canAttempt() async =>
      (await remainingLockout()) == Duration.zero;

  /// Records a failed attempt. Returns the lockout that is now active
  /// (zero when still under the threshold).
  Future<Duration> recordFailure() async {
    try {
      final int attempts = (await _failedAttempts()) + 1;
      await _storage.write(SecureKeys.pinFailedAttempts, attempts.toString());
      if (attempts < maxAttempts) return Duration.zero;

      // 5th failure -> 30s, 6th -> 60s, 7th -> 120s ... capped at 5 min.
      final int doublings = attempts - maxAttempts;
      Duration cooldown = baseCooldown * (1 << doublings.clamp(0, 10));
      if (cooldown > maxCooldown) cooldown = maxCooldown;

      final int untilMs =
          DateTime.now().add(cooldown).millisecondsSinceEpoch;
      await _storage.write(SecureKeys.pinLockoutUntil, untilMs.toString());
      return cooldown;
    } on AppException {
      return Duration.zero;
    }
  }

  /// Clears the counter and any lockout (called after a correct PIN).
  Future<void> reset() async {
    try {
      await _storage.delete(SecureKeys.pinFailedAttempts);
      await _storage.delete(SecureKeys.pinLockoutUntil);
    } on AppException {
      // Best effort — a stale counter only makes the guard stricter.
    }
  }

  Future<int> _failedAttempts() async {
    final String? raw = await _storage.read(SecureKeys.pinFailedAttempts);
    return raw == null ? 0 : (int.tryParse(raw) ?? 0);
  }
}
