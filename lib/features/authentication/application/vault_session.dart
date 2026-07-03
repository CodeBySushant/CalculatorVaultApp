import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/hive_service.dart';

/// The vault access state for this app session.
enum VaultSessionState {
  /// Vault has not been unlocked in this session. The app looks like a
  /// plain calculator; the lock screen must never appear.
  none,

  /// Vault is open.
  unlocked,

  /// Vault was open but auto-locked (background / idle). Re-unlock happens
  /// on the lock screen (PIN or biometrics).
  locked,
}

/// Auto-lock idle timeout, read from settings (default 60s). Overridable in
/// tests; configurable in Settings (Phase 12).
final autoLockTimeoutProvider = Provider<Duration>((ref) {
  final Object? raw = ref
      .watch(hiveServiceProvider)
      .settings
      .get(AppConstants.keyAutoLockSeconds);
  final int seconds = raw is int && raw > 0
      ? raw
      : AppConstants.defaultAutoLockTimeout.inSeconds;
  return Duration(seconds: seconds);
});

final vaultSessionProvider =
    NotifierProvider<VaultSessionController, VaultSessionState>(
  VaultSessionController.new,
);

/// Owns the vault session lifecycle.
///
/// Locking triggers:
/// - The app going to background (`paused` / `hidden`) locks immediately.
///   `inactive` is deliberately ignored — it fires during the biometric
///   prompt and permission dialogs, which must not self-lock the vault.
/// - No user interaction inside the vault for [autoLockTimeoutProvider].
///   Vault screens report interaction via [touch].
class VaultSessionController extends Notifier<VaultSessionState> {
  Timer? _idleTimer;
  _SessionLifecycleObserver? _observer;

  /// While > 0, background lifecycle events do NOT lock the vault. This
  /// covers authorized excursions that necessarily background the app —
  /// the system photo/video picker, the share sheet, the biometric prompt —
  /// which must not be mistaken for the user leaving the app. It is a
  /// counter (not a bool) so overlapping operations nest correctly.
  int _autoLockSuspensions = 0;

  @override
  VaultSessionState build() {
    final _SessionLifecycleObserver observer =
        _SessionLifecycleObserver(onBackground: _onBackground);
    WidgetsBinding.instance.addObserver(observer);
    _observer = observer;
    ref.onDispose(() {
      _idleTimer?.cancel();
      WidgetsBinding.instance.removeObserver(observer);
    });
    return VaultSessionState.none;
  }

  /// Opens the vault (after PIN or biometric success).
  void unlock() {
    state = VaultSessionState.unlocked;
    _restartIdleTimer();
  }

  /// Locks an open vault. No-op unless currently unlocked.
  void lock() {
    _idleTimer?.cancel();
    if (state == VaultSessionState.unlocked) {
      state = VaultSessionState.locked;
    }
  }

  /// Wraps an operation that legitimately backgrounds the app (picker,
  /// share sheet) so it does not trigger the background auto-lock. Always
  /// restores locking afterward, even on error.
  Future<T> withoutAutoLock<T>(Future<T> Function() action) async {
    _autoLockSuspensions++;
    _idleTimer?.cancel();
    try {
      return await action();
    } finally {
      if (_autoLockSuspensions > 0) _autoLockSuspensions--;
      // Re-arm the idle timer if still unlocked.
      if (state == VaultSessionState.unlocked) _restartIdleTimer();
    }
  }

  /// Handles a background lifecycle event, honoring active suspensions.
  void _onBackground() {
    if (_autoLockSuspensions > 0) return;
    lock();
  }

  /// Ends the session entirely: back to plain-calculator mode, so the lock
  /// screen can no longer appear. Used by the vault's exit action.
  void end() {
    _idleTimer?.cancel();
    _autoLockSuspensions = 0;
    state = VaultSessionState.none;
  }

  /// Reports user interaction inside the vault, resetting the idle timer.
  void touch() {
    if (state == VaultSessionState.unlocked) {
      _restartIdleTimer();
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(ref.read(autoLockTimeoutProvider), lock);
  }

  /// Test hook: forwards a lifecycle event to the internal observer.
  @visibleForTesting
  void debugHandleLifecycle(AppLifecycleState lifecycleState) {
    _observer?.didChangeAppLifecycleState(lifecycleState);
  }
}

class _SessionLifecycleObserver with WidgetsBindingObserver {
  _SessionLifecycleObserver({required this.onBackground});

  final VoidCallback onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      onBackground();
    }
  }
}
