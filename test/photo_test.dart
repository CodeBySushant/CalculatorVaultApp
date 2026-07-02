import 'dart:io';
import 'dart:typed_data';

import 'package:calculator_vault/core/crypto/crypto_service.dart';
import 'package:calculator_vault/core/crypto/key_manager.dart';
import 'package:calculator_vault/core/crypto/vault_file_store.dart';
import 'package:calculator_vault/features/photos/data/thumbnail_service.dart';
import 'package:calculator_vault/features/vault/application/vault_items_controller.dart';
import 'package:calculator_vault/features/vault/data/vault_item_repository.dart';
import 'package:calculator_vault/features/vault/domain/vault_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart' as img;

import 'helpers/fake_secure_storage.dart';

void main() {
  late Directory root;

  Future<String> writeTestImage(int width, int height) async {
    final img.Image image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(90, 120, 200));
    // A diagonal so resize output is clearly a real image.
    for (int i = 0; i < width && i < height; i++) {
      image.setPixelRgb(i, i, 255, 255, 255);
    }
    final Uint8List png = img.encodePng(image);
    final String path = '${root.path}/src_${width}x$height.png';
    await File(path).writeAsBytes(png);
    return path;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cvlt_photo_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('ThumbnailService', () {
    final ThumbnailService service = ThumbnailService();

    test('downscales a landscape image to the max dimension', () async {
      final String path = await writeTestImage(1600, 1000);
      final Uint8List thumb = await service.generate(path);

      final img.Image? decoded = img.decodeImage(thumb);
      expect(decoded, isNotNull);
      expect(decoded!.width, ThumbnailService.maxDimension);
      expect(decoded.height, lessThan(ThumbnailService.maxDimension));
    });

    test('downscales a portrait image by height', () async {
      final String path = await writeTestImage(800, 1600);
      final Uint8List thumb = await service.generate(path);

      final img.Image decoded = img.decodeImage(thumb)!;
      expect(decoded.height, ThumbnailService.maxDimension);
      expect(decoded.width, lessThan(ThumbnailService.maxDimension));
    });

    test('produces a valid JPEG smaller than the source', () async {
      final String path = await writeTestImage(2000, 2000);
      final int sourceSize = await File(path).length();
      final Uint8List thumb = await service.generate(path);

      expect(thumb.length, lessThan(sourceSize));
      // JPEG SOI marker.
      expect(thumb[0], 0xFF);
      expect(thumb[1], 0xD8);
    });

    test('throws on non-image data', () async {
      final String bad = '${root.path}/not-an-image.png';
      await File(bad).writeAsBytes(<int>[1, 2, 3, 4, 5]);
      expect(service.generate(bad), throwsA(isA<Exception>()));
    });
  });

  group('VaultFileStore thumbnails', () {
    test('writeThumbnail then readThumbnail roundtrips', () async {
      final VaultFileStore store = VaultFileStore(
        baseDir: Directory('${root.path}/vault'),
        tempDir: Directory('${root.path}/temp'),
        keyManager: KeyManager(FakeSecureStorage()),
      );
      final Uint8List thumb =
          Uint8List.fromList(List<int>.generate(5000, (int i) => i % 256));

      final String path = await store.writeThumbnail('abc', thumb);
      expect(path, 'thumbs/abc.cvlt');

      final Uint8List onDisk =
          await File(store.absolutePath(path)).readAsBytes();
      expect(onDisk, isNot(thumb), reason: 'encrypted at rest');
      expect(await store.readThumbnail(path), thumb);
    });
  });

  group('deleteForever removes the thumbnail too', () {
    test('both full file and thumbnail are deleted', () async {
      Hive.init('${root.path}/hive');
      final Box<dynamic> box = await Hive.openBox<dynamic>('photo_items');
      final KeyManager keyManager = KeyManager(FakeSecureStorage());
      final VaultFileStore store = VaultFileStore(
        baseDir: Directory('${root.path}/vault'),
        tempDir: Directory('${root.path}/temp'),
        keyManager: keyManager,
      );
      final VaultItemRepository repo = VaultItemRepository(
        box: box,
        keyManager: keyManager,
        crypto: CryptoService(),
      );

      // Real encrypted file + thumbnail.
      final String source = '${root.path}/photo.bin';
      await File(source).writeAsBytes(List<int>.filled(8192, 3));
      final VaultFileRef fileRef =
          await store.importFile(source, category: 'photos');
      final String thumbPath =
          await store.writeThumbnail(fileRef.id, Uint8List(1024));

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          vaultItemRepositoryProvider.overrideWithValue(repo),
          vaultFileStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      await container.read(vaultItemsProvider.future);
      final DateTime now = DateTime.now();
      await container.read(vaultItemsProvider.notifier).add(
            VaultItem(
              id: fileRef.id,
              type: VaultItemType.photo,
              name: 'photo.jpg',
              relativePath: fileRef.relativePath,
              thumbnailPath: thumbPath,
              byteLength: fileRef.byteLength,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final String full = store.absolutePath(fileRef.relativePath);
      final String thumb = store.absolutePath(thumbPath);
      expect(await File(full).exists(), isTrue);
      expect(await File(thumb).exists(), isTrue);

      await container
          .read(vaultItemsProvider.notifier)
          .deleteForever(<String>[fileRef.id]);

      expect(await File(full).exists(), isFalse);
      expect(await File(thumb).exists(), isFalse);

      await box.deleteFromDisk();
    });
  });
}
