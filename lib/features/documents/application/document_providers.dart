import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';

/// All non-trashed documents (pinned first, newest first).
final documentItemsProvider = Provider<List<VaultItem>>((ref) {
  return ref
      .watch(activeItemsProvider)
      .where((VaultItem i) => i.type == VaultItemType.document)
      .toList();
});

/// Decrypted full bytes for a document (used by the in-app image viewer).
final documentBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, relativePath) {
  return ref.watch(vaultFileStoreProvider).readBytes(relativePath);
});

/// Decrypted text for a document, decoded as UTF-8 (lenient — invalid bytes
/// become the replacement character rather than throwing).
final documentTextProvider = FutureProvider.autoDispose
    .family<String, String>((ref, relativePath) async {
  final Uint8List bytes =
      await ref.watch(vaultFileStoreProvider).readBytes(relativePath);
  return utf8.decode(bytes, allowMalformed: true);
});
