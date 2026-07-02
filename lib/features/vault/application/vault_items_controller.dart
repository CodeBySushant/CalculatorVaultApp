import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/crypto/vault_file_store.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../data/vault_item_repository.dart';
import '../domain/vault_item.dart';

/// Sort options for item lists.
enum SortMode { newest, oldest, nameAZ, nameZA, largest }

final vaultItemsProvider =
    AsyncNotifierProvider<VaultItemsController, List<VaultItem>>(
  VaultItemsController.new,
);

/// All non-trashed items, pinned first, newest first.
final activeItemsProvider = Provider<List<VaultItem>>((ref) {
  final List<VaultItem> items =
      ref.watch(vaultItemsProvider).value ?? const <VaultItem>[];
  final List<VaultItem> active = items
      .where((VaultItem i) => !i.isTrashed)
      .toList()
    ..sort(compareItems(SortMode.newest));
  return active;
});

/// Trashed items, most recently trashed first.
final trashedItemsProvider = Provider<List<VaultItem>>((ref) {
  final List<VaultItem> items =
      ref.watch(vaultItemsProvider).value ?? const <VaultItem>[];
  return items.where((VaultItem i) => i.isTrashed).toList()
    ..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));
});

/// Non-trashed favorites.
final favoriteItemsProvider = Provider<List<VaultItem>>((ref) {
  return ref
      .watch(activeItemsProvider)
      .where((VaultItem i) => i.favorite)
      .toList();
});

/// Item counts per category for the vault home cards.
final categoryCountsProvider = Provider<Map<VaultItemType, int>>((ref) {
  final Map<VaultItemType, int> counts = <VaultItemType, int>{
    for (final VaultItemType t in VaultItemType.values) t: 0,
  };
  for (final VaultItem item in ref.watch(activeItemsProvider)) {
    counts[item.type] = counts[item.type]! + 1;
  }
  return counts;
});

/// Comparator for a [SortMode]; pinned items always sort first.
int Function(VaultItem, VaultItem) compareItems(SortMode mode) {
  int inner(VaultItem a, VaultItem b) => switch (mode) {
        SortMode.newest => b.updatedAt.compareTo(a.updatedAt),
        SortMode.oldest => a.updatedAt.compareTo(b.updatedAt),
        SortMode.nameAZ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortMode.nameZA => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        SortMode.largest => b.byteLength.compareTo(a.byteLength),
      };
  return (VaultItem a, VaultItem b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return inner(a, b);
  };
}

/// Owns the in-memory item list and every mutation. All writes persist to
/// the encrypted repository before updating state.
class VaultItemsController extends AsyncNotifier<List<VaultItem>> {
  static const String _tag = 'VaultItems';

  VaultItemRepository get _repo => ref.read(vaultItemRepositoryProvider);
  VaultFileStore get _files => ref.read(vaultFileStoreProvider);

  @override
  Future<List<VaultItem>> build() async {
    final List<VaultItem> items =
        await ref.watch(vaultItemRepositoryProvider).loadAll();
    return _purgeExpired(items);
  }

  /// Deletes trash older than the retention window (files + metadata).
  Future<List<VaultItem>> _purgeExpired(List<VaultItem> items) async {
    final DateTime cutoff =
        DateTime.now().subtract(AppConstants.trashRetention);
    final List<VaultItem> kept = <VaultItem>[];
    for (final VaultItem item in items) {
      if (item.trashedAt != null && item.trashedAt!.isBefore(cutoff)) {
        await _deleteBacking(item);
        await _repo.remove(item.id);
      } else {
        kept.add(item);
      }
    }
    return kept;
  }

  Future<void> _deleteBacking(VaultItem item) async {
    for (final String? path in <String?>[
      item.relativePath,
      item.thumbnailPath,
    ]) {
      if (path == null) continue;
      try {
        await _files.delete(path);
      } on AppException catch (e) {
        AppLogger.error(
          _tag,
          'could not delete backing file for ${item.id}',
          e,
        );
      }
    }
  }

  List<VaultItem> get _current => state.value ?? const <VaultItem>[];

  Future<void> _apply(List<VaultItem> next) async {
    state = AsyncData<List<VaultItem>>(next);
  }

  /// Adds a new item (used by import flows in Phases 7–11).
  Future<void> add(VaultItem item) async {
    await _repo.put(item);
    await _apply(<VaultItem>[..._current, item]);
  }

  Future<void> _updateWhere(
    bool Function(VaultItem) test,
    VaultItem Function(VaultItem) transform,
  ) async {
    final List<VaultItem> next = <VaultItem>[];
    for (final VaultItem item in _current) {
      if (test(item)) {
        final VaultItem changed = transform(item);
        await _repo.put(changed);
        next.add(changed);
      } else {
        next.add(item);
      }
    }
    await _apply(next);
  }

  Future<void> rename(String id, String newName) async {
    final String trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await _updateWhere(
      (VaultItem i) => i.id == id,
      (VaultItem i) => i.copyWith(name: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> toggleFavorite(String id) async {
    await _updateWhere(
      (VaultItem i) => i.id == id,
      (VaultItem i) => i.copyWith(favorite: !i.favorite),
    );
  }

  Future<void> setFavorite(List<String> ids, bool value) async {
    final Set<String> set = ids.toSet();
    await _updateWhere(
      (VaultItem i) => set.contains(i.id),
      (VaultItem i) => i.copyWith(favorite: value),
    );
  }

  Future<void> togglePinned(String id) async {
    await _updateWhere(
      (VaultItem i) => i.id == id,
      (VaultItem i) => i.copyWith(pinned: !i.pinned),
    );
  }

  /// Soft delete: items move to trash and auto-purge after 30 days.
  Future<void> moveToTrash(List<String> ids) async {
    final Set<String> set = ids.toSet();
    final DateTime now = DateTime.now();
    await _updateWhere(
      (VaultItem i) => set.contains(i.id),
      (VaultItem i) => i.copyWith(trashedAt: now, pinned: false),
    );
  }

  Future<void> restore(List<String> ids) async {
    final Set<String> set = ids.toSet();
    await _updateWhere(
      (VaultItem i) => set.contains(i.id),
      (VaultItem i) => i.copyWith(clearTrashedAt: true),
    );
  }

  /// Hard delete: removes encrypted files and metadata permanently.
  Future<void> deleteForever(List<String> ids) async {
    final Set<String> set = ids.toSet();
    final List<VaultItem> next = <VaultItem>[];
    for (final VaultItem item in _current) {
      if (set.contains(item.id)) {
        await _deleteBacking(item);
        await _repo.remove(item.id);
      } else {
        next.add(item);
      }
    }
    await _apply(next);
  }

  Future<void> emptyTrash() async {
    await deleteForever(
      _current
          .where((VaultItem i) => i.isTrashed)
          .map((VaultItem i) => i.id)
          .toList(),
    );
  }
}
