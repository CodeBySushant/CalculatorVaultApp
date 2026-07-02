import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/crypto/crypto_service.dart';
import '../../../core/crypto/key_manager.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/vault_item.dart';

final vaultItemRepositoryProvider = Provider<VaultItemRepository>(
  (ref) => VaultItemRepository(
    box: ref.watch(hiveServiceProvider).vaultItems,
    keyManager: ref.watch(keyManagerProvider),
    crypto: ref.watch(cryptoServiceProvider),
  ),
);

/// Persists vault item metadata in Hive.
///
/// Sensitive fields — [VaultItem.name] and [VaultItem.payload] — are
/// AES-256-GCM encrypted with the master key before touching disk.
/// Structural fields (type, timestamps, flags, encrypted-file path) stay
/// plaintext: they reveal nothing beyond what the vault directory listing
/// already shows, and keeping them queryable avoids decrypting the world
/// for a count.
class VaultItemRepository {
  VaultItemRepository({
    required Box<dynamic> box,
    required KeyManager keyManager,
    required CryptoService crypto,
  })  : _box = box,
        _keyManager = keyManager,
        _crypto = crypto;

  static const String _tag = 'VaultItemRepo';

  final Box<dynamic> _box;
  final KeyManager _keyManager;
  final CryptoService _crypto;

  /// Loads and decrypts every stored item. Entries that fail to decrypt are
  /// skipped (and logged) rather than bricking the whole vault.
  Future<List<VaultItem>> loadAll() async {
    final List<VaultItem> items = <VaultItem>[];
    for (final dynamic raw in _box.values) {
      if (raw is! Map) continue;
      try {
        items.add(await _decode(raw));
      } on AppException catch (e) {
        AppLogger.error(_tag, 'skipping undecryptable item', e);
      }
    }
    return items;
  }

  /// Inserts or updates an item, encrypting sensitive fields.
  Future<void> put(VaultItem item) async {
    try {
      await _box.put(item.id, await _encode(item));
    } on Exception catch (e) {
      throw StorageException('Could not save the vault item.', cause: e);
    }
  }

  /// Removes an item's metadata. Safe when absent.
  Future<void> remove(String id) async {
    try {
      await _box.delete(id);
    } on Exception catch (e) {
      throw StorageException('Could not remove the vault item.', cause: e);
    }
  }

  Future<Map<String, Object?>> _encode(VaultItem item) async {
    final key = await _keyManager.getMasterKey();
    return <String, Object?>{
      'id': item.id,
      'type': item.type.name,
      'name': await _crypto.encryptString(item.name, key),
      'path': item.relativePath,
      'thumb': item.thumbnailPath,
      'size': item.byteLength,
      'folder': item.folderId,
      'created': item.createdAt.millisecondsSinceEpoch,
      'updated': item.updatedAt.millisecondsSinceEpoch,
      'fav': item.favorite,
      'pin': item.pinned,
      'trashed': item.trashedAt?.millisecondsSinceEpoch,
      'mime': item.mimeType,
      'payload': item.payload == null
          ? null
          : await _crypto.encryptString(item.payload!, key),
    };
  }

  Future<VaultItem> _decode(Map<dynamic, dynamic> map) async {
    final key = await _keyManager.getMasterKey();
    final int? trashed = map['trashed'] as int?;
    final String? encPayload = map['payload'] as String?;
    return VaultItem(
      id: map['id'] as String,
      type: VaultItemType.values.byName(map['type'] as String),
      name: await _crypto.decryptString(map['name'] as String, key),
      relativePath: map['path'] as String?,
      thumbnailPath: map['thumb'] as String?,
      byteLength: map['size'] as int? ?? 0,
      folderId: map['folder'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated'] as int),
      favorite: map['fav'] as bool? ?? false,
      pinned: map['pin'] as bool? ?? false,
      trashedAt:
          trashed == null ? null : DateTime.fromMillisecondsSinceEpoch(trashed),
      mimeType: map['mime'] as String?,
      payload: encPayload == null
          ? null
          : await _crypto.decryptString(encPayload, key),
    );
  }
}
