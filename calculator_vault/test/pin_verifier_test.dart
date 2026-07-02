import 'package:calculator_vault/features/authentication/domain/pin_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_secure_storage.dart';

void main() {
  late FakeSecureStorage storage;
  late PinVerifier verifier;

  setUp(() {
    storage = FakeSecureStorage();
    verifier = PinVerifier(storage);
  });

  test('no PIN set: isPinSet false, verify always false', () async {
    expect(await verifier.isPinSet(), isFalse);
    expect(await verifier.verify('1234'), isFalse);
  });

  test('setPin stores hash and salt, never the PIN itself', () async {
    await verifier.setPin('4821');
    expect(await verifier.isPinSet(), isTrue);
    expect(
      storage.values.values.any((String v) => v.contains('4821')),
      isFalse,
    );
  });

  test('verify accepts the correct PIN and rejects others', () async {
    await verifier.setPin('4821');
    expect(await verifier.verify('4821'), isTrue);
    expect(await verifier.verify('4822'), isFalse);
    expect(await verifier.verify('482'), isFalse);
    expect(await verifier.verify('48210'), isFalse);
  });

  test('changing the PIN invalidates the old one', () async {
    await verifier.setPin('1111');
    await verifier.setPin('2222');
    expect(await verifier.verify('1111'), isFalse);
    expect(await verifier.verify('2222'), isTrue);
  });

  test('same PIN produces different hashes thanks to random salt', () async {
    await verifier.setPin('7777');
    final String? firstHash = await storage.read('vault_pin_hash');
    await verifier.setPin('7777');
    final String? secondHash = await storage.read('vault_pin_hash');
    expect(firstHash, isNotNull);
    expect(firstHash, isNot(secondHash));
  });

  test('clearPin removes everything', () async {
    await verifier.setPin('4821');
    await verifier.clearPin();
    expect(await verifier.isPinSet(), isFalse);
    expect(await verifier.verify('4821'), isFalse);
  });
}
