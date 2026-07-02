import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:calculator_vault/core/crypto/crypto_service.dart';
import 'package:calculator_vault/core/errors/app_exception.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final CryptoService crypto = CryptoService();
  late SecretKey masterKey;
  late Directory workDir;

  Uint8List randomBytes(int length, [int seed = 7]) {
    final Random random = Random(seed);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  setUp(() async {
    masterKey = await crypto.newKey();
    workDir = await Directory.systemTemp.createTemp('cvlt_crypto_test');
  });

  tearDown(() async {
    if (await workDir.exists()) await workDir.delete(recursive: true);
  });

  group('blobs', () {
    test('bytes roundtrip', () async {
      final Uint8List plain = randomBytes(1000);
      final Uint8List blob = await crypto.encryptBlob(plain, masterKey);
      expect(blob, isNot(plain));
      expect(await crypto.decryptBlob(blob, masterKey), plain);
    });

    test('string roundtrip', () async {
      const String secret = 'Sheetal — मेरा गुप्त नोट 🔒';
      final String encoded = await crypto.encryptString(secret, masterKey);
      expect(encoded.contains('गुप्त'), isFalse);
      expect(await crypto.decryptString(encoded, masterKey), secret);
    });

    test('same plaintext encrypts differently every time (random nonce)',
        () async {
      final Uint8List plain = randomBytes(64);
      final Uint8List a = await crypto.encryptBlob(plain, masterKey);
      final Uint8List b = await crypto.encryptBlob(plain, masterKey);
      expect(a, isNot(b));
    });

    test('tampered blob throws EncryptionException', () async {
      final Uint8List blob =
          await crypto.encryptBlob(randomBytes(128), masterKey);
      blob[blob.length - 1] ^= 0xFF;
      expect(
        () => crypto.decryptBlob(blob, masterKey),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('wrong key throws EncryptionException', () async {
      final Uint8List blob =
          await crypto.encryptBlob(randomBytes(128), masterKey);
      final SecretKey otherKey = await crypto.newKey();
      expect(
        () => crypto.decryptBlob(blob, otherKey),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('garbage input throws EncryptionException', () async {
      expect(
        () => crypto.decryptBlob(Uint8List.fromList(<int>[1, 2, 3]), masterKey),
        throwsA(isA<EncryptionException>()),
      );
      expect(
        () => crypto.decryptString('not-base64!!!', masterKey),
        throwsA(isA<EncryptionException>()),
      );
    });
  });

  group('files', () {
    Future<(String, String)> encryptSample(Uint8List content) async {
      final String source = '${workDir.path}/plain.bin';
      final String dest = '${workDir.path}/enc.cvlt';
      await File(source).writeAsBytes(content);
      await crypto.encryptFile(
        sourcePath: source,
        destPath: dest,
        masterKey: masterKey,
        chunkSize: 64 * 1024,
      );
      return (source, dest);
    }

    test('multi-chunk roundtrip to bytes', () async {
      // 200 KB with 64 KB chunks → 4 chunks including a partial final one.
      final Uint8List content = randomBytes(200 * 1024);
      final (_, String dest) = await encryptSample(content);

      final Uint8List cipher = await File(dest).readAsBytes();
      expect(cipher.length, greaterThan(content.length));

      final Uint8List decrypted = await crypto.decryptFileToBytes(
          sourcePath: dest, masterKey: masterKey);
      expect(decrypted, content);
    });

    test('roundtrip to a destination path', () async {
      final Uint8List content = randomBytes(150 * 1024, 21);
      final (_, String dest) = await encryptSample(content);

      final String out = '${workDir.path}/out.bin';
      await crypto.decryptFileToPath(
        sourcePath: dest,
        destPath: out,
        masterKey: masterKey,
      );
      expect(await File(out).readAsBytes(), content);
    });

    test('empty file roundtrip', () async {
      final (_, String dest) = await encryptSample(Uint8List(0));
      final Uint8List decrypted = await crypto.decryptFileToBytes(
          sourcePath: dest, masterKey: masterKey);
      expect(decrypted, isEmpty);
    });

    test('plaintextLength reads the header without decrypting', () async {
      final (_, String dest) = await encryptSample(randomBytes(70 * 1024));
      expect(await crypto.plaintextLength(dest), 70 * 1024);
    });

    test('tampered ciphertext fails authentication', () async {
      final (_, String dest) = await encryptSample(randomBytes(100 * 1024));
      final Uint8List bytes = await File(dest).readAsBytes();
      bytes[bytes.length - 5] ^= 0xFF;
      await File(dest).writeAsBytes(bytes);

      expect(
        () => crypto.decryptFileToBytes(sourcePath: dest, masterKey: masterKey),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('truncated file is detected', () async {
      final (_, String dest) = await encryptSample(randomBytes(100 * 1024));
      final Uint8List bytes = await File(dest).readAsBytes();
      await File(dest).writeAsBytes(bytes.sublist(0, bytes.length - 1000));

      expect(
        () => crypto.decryptFileToBytes(sourcePath: dest, masterKey: masterKey),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('decrypting with the wrong master key fails at key unwrap', () async {
      final (_, String dest) = await encryptSample(randomBytes(10 * 1024));
      final SecretKey otherKey = await crypto.newKey();
      expect(
        () => crypto.decryptFileToBytes(sourcePath: dest, masterKey: otherKey),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('a non-vault file is rejected by the magic check', () async {
      final String junk = '${workDir.path}/junk.cvlt';
      await File(junk).writeAsBytes(randomBytes(512));
      expect(
        () => crypto.decryptFileToBytes(sourcePath: junk, masterKey: masterKey),
        throwsA(isA<EncryptionException>()),
      );
    });
  });
}
