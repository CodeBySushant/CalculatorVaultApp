import 'package:calculator_vault/features/authentication/domain/recovery_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_secure_storage.dart';

void main() {
  late FakeSecureStorage storage;
  late RecoveryKeyService service;

  setUp(() {
    storage = FakeSecureStorage();
    service = RecoveryKeyService(storage);
  });

  test('createAndStore returns a formatted 16-character code', () async {
    final String code = await service.createAndStore();
    expect(
      RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')
          .hasMatch(code),
      isTrue,
      reason: 'got "$code"',
    );
    expect(await service.isSet(), isTrue);
  });

  test('the plaintext code is never persisted', () async {
    final String code = await service.createAndStore();
    final String raw = code.replaceAll('-', '');
    expect(
      storage.values.values.any(
        (String v) => v.contains(code) || v.contains(raw),
      ),
      isFalse,
    );
  });

  test('verify accepts the code with or without formatting', () async {
    final String code = await service.createAndStore();
    expect(await service.verify(code), isTrue);
    expect(await service.verify(code.replaceAll('-', '')), isTrue);
    expect(await service.verify(code.toLowerCase()), isTrue);
    expect(await service.verify('${code.substring(0, 18)}X'), isFalse);
    expect(await service.verify('AAAA-BBBB-CCCC-DDDD'), isFalse);
  });

  test('regenerating replaces the old code', () async {
    final String first = await service.createAndStore();
    final String second = await service.createAndStore();
    expect(first, isNot(second));
    expect(await service.verify(first), isFalse);
    expect(await service.verify(second), isTrue);
  });

  test('verify with nothing stored returns false', () async {
    expect(await service.verify('AAAA-BBBB-CCCC-DDDD'), isFalse);
  });
}
