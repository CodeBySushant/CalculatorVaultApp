import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:calculator_vault/core/crypto/key_manager.dart';
import 'package:calculator_vault/core/crypto/vault_file_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_secure_storage.dart';

void main() {
  group('KeyManager', () {
    late FakeSecureStorage storage;
    late KeyManager manager;

    setUp(() {
      storage = FakeSecureStorage();
      manager = KeyManager(storage);
    });

    test('generates a 32-byte key on first use and persists it', () async {
      final SecretKey key = await manager.getMasterKey();
      expect((await key.extractBytes()).length, 32);
      expect(storage.values.containsKey('vault_master_key'), isTrue);
    });

    test('returns the same key on subsequent calls', () async {
      final List<int> first =
          await (await manager.getMasterKey()).extractBytes();
      final List<int> second =
          await (await manager.getMasterKey()).extractBytes();
      expect(first, second);
    });

    test('concurrent first calls never double-generate', () async {
      final List<SecretKey> keys = await Future.wait(<Future<SecretKey>>[
        manager.getMasterKey(),
        manager.getMasterKey(),
        manager.getMasterKey(),
      ]);
      final List<int> reference = await keys.first.extractBytes();
      for (final SecretKey key in keys) {
        expect(await key.extractBytes(), reference);
      }
    });

    test('a new instance loads the persisted key, not a new one', () async {
      final List<int> original =
          await (await manager.getMasterKey()).extractBytes();
      final KeyManager fresh = KeyManager(storage);
      expect(await (await fresh.getMasterKey()).extractBytes(), original);
    });
  });

  group('VaultFileStore', () {
    late Directory root;
    late VaultFileStore store;
    late FakeSecureStorage storage;

    Uint8List randomBytes(int length) {
      final Random random = Random(99);
      return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)),
      );
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cvlt_store_test');
      storage = FakeSecureStorage();
      store = VaultFileStore(
        baseDir: Directory('${root.path}/vault'),
        tempDir: Directory('${root.path}/temp'),
        keyManager: KeyManager(storage),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<String> writeSource(Uint8List content) async {
      final String path = '${root.path}/source.jpg';
      await File(path).writeAsBytes(content);
      return path;
    }

    test('importFile encrypts into the category folder', () async {
      final Uint8List content = randomBytes(80 * 1024);
      final String source = await writeSource(content);

      final VaultFileRef ref =
          await store.importFile(source, category: 'photos');

      expect(ref.category, 'photos');
      expect(ref.byteLength, content.length);
      expect(ref.relativePath, startsWith('photos/'));
      expect(ref.relativePath, endsWith('.cvlt'));

      final Uint8List onDisk =
          await File(store.absolutePath(ref.relativePath)).readAsBytes();
      expect(onDisk, isNot(content), reason: 'must be encrypted at rest');
      // Source is untouched without deleteSource.
      expect(await File(source).exists(), isTrue);
    });

    test('deleteSource removes the original after import', () async {
      final String source = await writeSource(randomBytes(10 * 1024));
      await store.importFile(source, category: 'photos', deleteSource: true);
      expect(await File(source).exists(), isFalse);
    });

    test('readBytes roundtrips the content', () async {
      final Uint8List content = randomBytes(120 * 1024);
      final String source = await writeSource(content);
      final VaultFileRef ref =
          await store.importFile(source, category: 'documents');

      expect(await store.readBytes(ref.relativePath), content);
    });

    test('decryptToTempFile produces a matching plaintext file', () async {
      final Uint8List content = randomBytes(60 * 1024);
      final String source = await writeSource(content);
      final VaultFileRef ref =
          await store.importFile(source, category: 'videos');

      final File temp =
          await store.decryptToTempFile(ref.relativePath, extension: 'mp4');
      expect(temp.path, endsWith('.mp4'));
      expect(await temp.readAsBytes(), content);

      await store.clearTemp();
      expect(await temp.exists(), isFalse);
    });

    test('plaintextSize matches the original', () async {
      final String source = await writeSource(randomBytes(33 * 1024));
      final VaultFileRef ref =
          await store.importFile(source, category: 'documents');
      expect(await store.plaintextSize(ref.relativePath), 33 * 1024);
    });

    test('delete removes the encrypted file and is idempotent', () async {
      final String source = await writeSource(randomBytes(1024));
      final VaultFileRef ref =
          await store.importFile(source, category: 'photos');

      await store.delete(ref.relativePath);
      expect(
        await File(store.absolutePath(ref.relativePath)).exists(),
        isFalse,
      );
      // Second delete must not throw.
      await store.delete(ref.relativePath);
    });
  });
}
