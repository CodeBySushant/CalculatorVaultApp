import 'package:calculator_vault/features/authentication/application/vault_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer({
    Duration timeout = const Duration(minutes: 1),
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        autoLockTimeoutProvider.overrideWithValue(timeout),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('starts in none state', () {
    final ProviderContainer container = makeContainer();
    expect(container.read(vaultSessionProvider), VaultSessionState.none);
  });

  test('unlock and lock transition correctly', () {
    final ProviderContainer container = makeContainer();
    final VaultSessionController session =
        container.read(vaultSessionProvider.notifier);

    session.unlock();
    expect(container.read(vaultSessionProvider), VaultSessionState.unlocked);

    session.lock();
    expect(container.read(vaultSessionProvider), VaultSessionState.locked);
  });

  test('lock is a no-op when the session was never unlocked', () {
    final ProviderContainer container = makeContainer();
    container.read(vaultSessionProvider.notifier).lock();
    expect(container.read(vaultSessionProvider), VaultSessionState.none);
  });

  test('end returns to none from any state', () {
    final ProviderContainer container = makeContainer();
    final VaultSessionController session =
        container.read(vaultSessionProvider.notifier);

    session.unlock();
    session.end();
    expect(container.read(vaultSessionProvider), VaultSessionState.none);
  });

  test('backgrounding the app locks an open vault', () {
    final ProviderContainer container = makeContainer();
    final VaultSessionController session =
        container.read(vaultSessionProvider.notifier);

    session.unlock();
    session.debugHandleLifecycle(AppLifecycleState.paused);
    expect(container.read(vaultSessionProvider), VaultSessionState.locked);
  });

  test('inactive lifecycle (biometric prompt) does NOT lock', () {
    final ProviderContainer container = makeContainer();
    final VaultSessionController session =
        container.read(vaultSessionProvider.notifier);

    session.unlock();
    session.debugHandleLifecycle(AppLifecycleState.inactive);
    expect(container.read(vaultSessionProvider), VaultSessionState.unlocked);
  });

  test('backgrounding when never unlocked stays none', () {
    final ProviderContainer container = makeContainer();
    final VaultSessionController session =
        container.read(vaultSessionProvider.notifier);

    session.debugHandleLifecycle(AppLifecycleState.paused);
    expect(container.read(vaultSessionProvider), VaultSessionState.none);
  });

  test('idle timeout locks the vault', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer container =
          makeContainer(timeout: const Duration(seconds: 30));
      final VaultSessionController session =
          container.read(vaultSessionProvider.notifier);

      session.unlock();
      async.elapse(const Duration(seconds: 31));
      expect(container.read(vaultSessionProvider), VaultSessionState.locked);
    });
  });

  test('touch resets the idle timer', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer container =
          makeContainer(timeout: const Duration(seconds: 30));
      final VaultSessionController session =
          container.read(vaultSessionProvider.notifier);

      session.unlock();
      async.elapse(const Duration(seconds: 20));
      session.touch();
      async.elapse(const Duration(seconds: 20));
      // 40s total, but only 20s since last touch — still unlocked.
      expect(container.read(vaultSessionProvider), VaultSessionState.unlocked);

      async.elapse(const Duration(seconds: 11));
      expect(container.read(vaultSessionProvider), VaultSessionState.locked);
    });
  });
}
