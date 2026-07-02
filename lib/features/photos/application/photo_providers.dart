import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';

/// All non-trashed photos, honoring the active-items sort (pinned first,
/// newest first).
final photoItemsProvider = Provider<List<VaultItem>>((ref) {
  return ref
      .watch(activeItemsProvider)
      .where((VaultItem i) => i.type == VaultItemType.photo)
      .toList();
});

/// Decrypted thumbnail bytes for a given thumbnail path.
///
/// Kept alive once loaded so scrolling the grid does not repeatedly decrypt
/// the same thumbnail. Phase 14 revisits caching with a bounded LRU.
final photoThumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, thumbPath) {
  ref.keepAlive();
  return ref.watch(vaultFileStoreProvider).readThumbnail(thumbPath);
});

/// Decrypted full-resolution bytes for a photo, for the full-screen viewer.
final photoBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, relativePath) {
  return ref.watch(vaultFileStoreProvider).readBytes(relativePath);
});
