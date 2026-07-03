import 'dart:io';

import 'package:calculator_vault/core/crypto/crypto_service.dart';
import 'package:calculator_vault/core/crypto/key_manager.dart';
import 'package:calculator_vault/core/crypto/vault_file_store.dart';
import 'package:calculator_vault/core/utils/formatters.dart';
import 'package:calculator_vault/features/vault/application/vault_items_controller.dart';
import 'package:calculator_vault/features/vault/data/vault_item_repository.dart';
import 'package:calculator_vault/features/vault/domain/vault_item.dart';
import 'package:calculator_vault/features/videos/application/video_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'helpers/fake_secure_storage.dart';

void main() {
  group('VideoProgress', () {
    test('shouldResume respects the 5s floor and 95% ceiling', () {
      expect(VideoProgress.shouldResume(2000, 60000), isFalse); // too early
      expect(VideoProgress.shouldResume(30000, 60000), isTrue); // mid clip
      expect(
        VideoProgress.shouldResume(59000, 60000),
        isFalse,
      ); // ~98%, near end
      expect(VideoProgress.shouldResume(10000, 0), isFalse); // unknown duration
    });

    test('encode/positionMsOf roundtrip through payload', () {
      final String payload = VideoProgress.encode(42000);
      final VaultItem item = VaultItem(
        id: 'v',
        type: VaultItemType.video,
        name: 'clip.mp4',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        payload: payload,
      );
      expect(VideoProgress.positionMsOf(item), 42000);
    });

    test('positionMsOf tolerates null and garbage payloads', () {
      VaultItem base(String? payload) => VaultItem(
            id: 'v',
            type: VaultItemType.video,
            name: 'clip.mp4',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            payload: payload,
          );
      expect(VideoProgress.positionMsOf(base(null)), 0);
      expect(VideoProgress.positionMsOf(base('')), 0);
      expect(VideoProgress.positionMsOf(base('not json')), 0);
      expect(VideoProgress.positionMsOf(base('{"other":1}')), 0);
    });
  });

  group('Formatters.duration', () {
    test('formats minutes and hours', () {
      expect(Formatters.duration(const Duration(seconds: 7)), '0:07');
      expect(
        Formatters.duration(const Duration(minutes: 3, seconds: 7)),
        '3:07',
      );
      expect(
        Formatters.duration(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
    });
  });

  group('durationMs persistence', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('cvlt_video_test');
      Hive.init('${root.path}/hive');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('durationMs survives an encrypt/decrypt repository roundtrip',
        () async {
      final Box<dynamic> box = await Hive.openBox<dynamic>('video_items');
      final VaultItemRepository repo = VaultItemRepository(
        box: box,
        keyManager: KeyManager(FakeSecureStorage()),
        crypto: CryptoService(),
      );

      final DateTime now = DateTime(2026, 7, 3);
      await repo.put(
        VaultItem(
          id: 'clip',
          type: VaultItemType.video,
          name: 'holiday.mp4',
          relativePath: 'videos/clip.cvlt',
          byteLength: 5000000,
          durationMs: 123456,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final VaultItem loaded = (await repo.loadAll()).single;
      expect(loaded.durationMs, 123456);
      expect(loaded.type, VaultItemType.video);

      await box.deleteFromDisk();
    });

    test('controller.update persists a new payload (resume position)',
        () async {
      final Box<dynamic> box = await Hive.openBox<dynamic>('video_items2');
      final KeyManager km = KeyManager(FakeSecureStorage());
      final VaultItemRepository repo = VaultItemRepository(
        box: box,
        keyManager: km,
        crypto: CryptoService(),
      );
      final VaultFileStore store = VaultFileStore(
        baseDir: Directory('${root.path}/vault'),
        tempDir: Directory('${root.path}/temp'),
        keyManager: km,
      );

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          vaultItemRepositoryProvider.overrideWithValue(repo),
          vaultFileStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      await container.read(vaultItemsProvider.future);
      final DateTime now = DateTime(2026, 7, 3);
      await container.read(vaultItemsProvider.notifier).add(
            VaultItem(
              id: 'clip',
              type: VaultItemType.video,
              name: 'clip.mp4',
              relativePath: 'videos/clip.cvlt',
              durationMs: 60000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await container.read(vaultItemsProvider.notifier).updateItem(
            'clip',
            (VaultItem i) => i.copyWith(payload: VideoProgress.encode(25000)),
          );

      final VaultItem updated = (await repo.loadAll()).single;
      expect(VideoProgress.positionMsOf(updated), 25000);

      await box.deleteFromDisk();
    });
  });
}
