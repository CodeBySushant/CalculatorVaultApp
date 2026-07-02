import 'dart:io';

import 'package:calculator_vault/core/crypto/crypto_service.dart';
import 'package:calculator_vault/core/crypto/key_manager.dart';
import 'package:calculator_vault/core/crypto/vault_file_store.dart';
import 'package:calculator_vault/features/vault/application/selection_controller.dart';
import 'package:calculator_vault/features/vault/application/vault_items_controller.dart';
import 'package:calculator_vault/features/vault/data/vault_item_repository.dart';
import 'package:calculator_vault/features/vault/domain/vault_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'helpers/fake_secure_storage.dart';

void main() {
  late Directory root;
  late Box<dynamic> box;
  late KeyManager keyManager;
  late VaultItemRepository repository;
  late VaultFileStore fileStore;
  int boxCounter = 0;

  VaultItem makeItem({
    String id = 'item-1',
    VaultItemType type = VaultItemType.document,
    String name = 'Tax Return 2026.pdf',
    String? relativePath,
    DateTime? trashedAt,
    String? payload,
  }) {
    final DateTime now = DateTime(2026, 7, 1);
    return VaultItem(
      id: id,
      type: type,
      name: name,
      relativePath: relativePath,
      byteLength: 1024,
      createdAt: now,
      updatedAt: now,
      trashedAt: trashedAt,
      payload: payload,
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cvlt_vault_test');
    Hive.init('${root.path}/hive');
    box = await Hive.openBox<dynamic>('items_test_${boxCounter++}');
    keyManager = KeyManager(FakeSecureStorage());
    repository = VaultItemRepository(
      box: box,
      keyManager: keyManager,
      crypto: CryptoService(),
    );
    fileStore = VaultFileStore(
      baseDir: Directory('${root.path}/vault'),
      tempDir: Directory('${root.path}/temp'),
      keyManager: keyManager,
    );
  });

  tearDown(() async {
    await box.deleteFromDisk();
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProviderContainer makeContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        vaultItemRepositoryProvider.overrideWithValue(repository),
        vaultFileStoreProvider.overrideWithValue(fileStore),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('VaultItemRepository', () {
    test('roundtrips items with decrypted fields', () async {
      await repository.put(makeItem(payload: '{"body":"secret text"}'));
      final List<VaultItem> loaded = await repository.loadAll();

      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Tax Return 2026.pdf');
      expect(loaded.single.payload, '{"body":"secret text"}');
      expect(loaded.single.type, VaultItemType.document);
    });

    test('name and payload are encrypted at rest', () async {
      await repository.put(makeItem(payload: 'secret text'));
      final Map<dynamic, dynamic> stored =
          box.get('item-1') as Map<dynamic, dynamic>;

      expect(stored['name'], isNot(contains('Tax Return')));
      expect(stored['payload'], isNot(contains('secret text')));
    });

    test('remove deletes the entry', () async {
      await repository.put(makeItem());
      await repository.remove('item-1');
      expect(await repository.loadAll(), isEmpty);
    });

    test('an undecryptable entry is skipped, not fatal', () async {
      await repository.put(makeItem());
      await box.put('corrupt', <String, Object?>{
        'id': 'corrupt',
        'type': 'note',
        'name': 'not-a-valid-encrypted-blob',
        'created': 0,
        'updated': 0,
      });

      final List<VaultItem> loaded = await repository.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'item-1');
    });
  });

  group('VaultItemsController', () {
    test('add, favorite, pin, rename flow', () async {
      final ProviderContainer container = makeContainer();
      await container.read(vaultItemsProvider.future);
      final VaultItemsController controller =
          container.read(vaultItemsProvider.notifier);

      await controller.add(makeItem());
      await controller.toggleFavorite('item-1');
      await controller.togglePinned('item-1');
      await controller.rename('item-1', '  Renamed.pdf  ');

      final VaultItem item = container.read(activeItemsProvider).single;
      expect(item.favorite, isTrue);
      expect(item.pinned, isTrue);
      expect(item.name, 'Renamed.pdf');
      expect(container.read(favoriteItemsProvider), hasLength(1));
      expect(
        container.read(categoryCountsProvider)[VaultItemType.document],
        1,
      );

      // Persisted, not just in memory.
      expect((await repository.loadAll()).single.name, 'Renamed.pdf');
    });

    test('trash, restore, and derived lists', () async {
      final ProviderContainer container = makeContainer();
      await container.read(vaultItemsProvider.future);
      final VaultItemsController controller =
          container.read(vaultItemsProvider.notifier);

      await controller.add(makeItem(id: 'a', name: 'A'));
      await controller.add(makeItem(id: 'b', name: 'B'));
      await controller.moveToTrash(<String>['a']);

      expect(container.read(activeItemsProvider).single.id, 'b');
      expect(container.read(trashedItemsProvider).single.id, 'a');

      await controller.restore(<String>['a']);
      expect(container.read(activeItemsProvider), hasLength(2));
      expect(container.read(trashedItemsProvider), isEmpty);
    });

    test('deleteForever removes the encrypted file and metadata', () async {
      // Import a real file so there is an encrypted file on disk.
      final String source = '${root.path}/plain.bin';
      await File(source).writeAsBytes(List<int>.filled(4096, 7));
      final VaultFileRef fileRef =
          await fileStore.importFile(source, category: 'documents');

      final ProviderContainer container = makeContainer();
      await container.read(vaultItemsProvider.future);
      final VaultItemsController controller =
          container.read(vaultItemsProvider.notifier);
      await controller
          .add(makeItem(id: fileRef.id, relativePath: fileRef.relativePath));

      final String encryptedPath = fileStore.absolutePath(fileRef.relativePath);
      expect(await File(encryptedPath).exists(), isTrue);

      await controller.deleteForever(<String>[fileRef.id]);
      expect(await File(encryptedPath).exists(), isFalse);
      expect(await repository.loadAll(), isEmpty);
      expect(container.read(activeItemsProvider), isEmpty);
    });

    test('expired trash is purged on load', () async {
      final String source = '${root.path}/old.bin';
      await File(source).writeAsBytes(List<int>.filled(1024, 1));
      final VaultFileRef fileRef =
          await fileStore.importFile(source, category: 'photos');

      // Seed the repository directly: trashed 40 days ago.
      await repository.put(
        makeItem(
          id: fileRef.id,
          type: VaultItemType.photo,
          relativePath: fileRef.relativePath,
          trashedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await repository.put(
        makeItem(
          id: 'fresh',
          trashedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );

      final ProviderContainer container = makeContainer();
      final List<VaultItem> loaded =
          await container.read(vaultItemsProvider.future);

      expect(loaded.map((VaultItem i) => i.id), <String>['fresh']);
      expect(
        await File(fileStore.absolutePath(fileRef.relativePath)).exists(),
        isFalse,
        reason: 'purge must delete the encrypted file too',
      );
    });

    test('emptyTrash only touches trashed items', () async {
      final ProviderContainer container = makeContainer();
      await container.read(vaultItemsProvider.future);
      final VaultItemsController controller =
          container.read(vaultItemsProvider.notifier);

      await controller.add(makeItem(id: 'keep', name: 'Keep'));
      await controller.add(makeItem(id: 'bin', name: 'Bin'));
      await controller.moveToTrash(<String>['bin']);
      await controller.emptyTrash();

      expect(container.read(activeItemsProvider).single.id, 'keep');
      expect(container.read(trashedItemsProvider), isEmpty);
    });
  });

  group('sorting', () {
    test('pinned items sort first within any mode', () {
      final VaultItem pinned = makeItem(id: 'p', name: 'zzz').copyWith(
        pinned: true,
      );
      final VaultItem normal = makeItem(id: 'n', name: 'aaa');
      final List<VaultItem> list = <VaultItem>[normal, pinned]
        ..sort(compareItems(SortMode.nameAZ));
      expect(list.first.id, 'p');
    });
  });

  group('SelectionController', () {
    test('toggle, selectAll, clear', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final SelectionController selection =
          container.read(selectionProvider.notifier);

      selection.toggle('a');
      selection.toggle('b');
      expect(container.read(selectionProvider), <String>{'a', 'b'});

      selection.toggle('a');
      expect(container.read(selectionProvider), <String>{'b'});

      selection.selectAll(<String>['x', 'y', 'z']);
      expect(container.read(selectionProvider), hasLength(3));

      selection.clear();
      expect(container.read(selectionProvider), isEmpty);
    });
  });
}
