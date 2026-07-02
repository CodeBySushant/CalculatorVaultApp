import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../shared/shared.dart';
import '../application/selection_controller.dart';
import '../application/vault_items_controller.dart';
import '../domain/vault_item.dart';
import 'widgets/vault_item_tile.dart';

/// Generic vault item list. Serves the five category screens and the
/// favorites collection; sorting, multi-select, rename, pin, favorite, and
/// move-to-trash all work here. Type-specific viewers and import flows
/// (Phases 7–11) build on top of this screen.
class VaultItemListScreen extends ConsumerStatefulWidget {
  const VaultItemListScreen.category(VaultItemType this.type, {super.key})
      : favoritesOnly = false;

  const VaultItemListScreen.favorites({super.key})
      : type = null,
        favoritesOnly = true;

  final VaultItemType? type;
  final bool favoritesOnly;

  @override
  ConsumerState<VaultItemListScreen> createState() =>
      _VaultItemListScreenState();
}

class _VaultItemListScreenState extends ConsumerState<VaultItemListScreen> {
  SortMode _sort = SortMode.newest;

  String get _title {
    if (widget.favoritesOnly) return 'Favorites';
    return switch (widget.type!) {
      VaultItemType.photo => 'Photos',
      VaultItemType.video => 'Videos',
      VaultItemType.document => 'Documents',
      VaultItemType.note => 'Notes',
      VaultItemType.password => 'Passwords',
      VaultItemType.voiceNote => 'Voice notes',
    };
  }

  List<VaultItem> _visibleItems() {
    final List<VaultItem> active = ref.watch(activeItemsProvider);
    final Iterable<VaultItem> filtered = widget.favoritesOnly
        ? active.where((VaultItem i) => i.favorite)
        : active.where((VaultItem i) => i.type == widget.type);
    return filtered.toList()..sort(compareItems(_sort));
  }

  Future<void> _rename(VaultItem item) async {
    final TextEditingController controller =
        TextEditingController(text: item.name);
    await showAppBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Rename', style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            AppTextField(controller: controller, autofocus: true),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Save',
              fullWidth: true,
              onPressed: () {
                ref
                    .read(vaultItemsProvider.notifier)
                    .rename(item.id, controller.text);
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  void _onMenuAction(VaultItem item, VaultItemMenuAction action) {
    final VaultItemsController controller =
        ref.read(vaultItemsProvider.notifier);
    switch (action) {
      case VaultItemMenuAction.rename:
        _rename(item);
      case VaultItemMenuAction.pin:
        controller.togglePinned(item.id);
      case VaultItemMenuAction.trash:
        controller.moveToTrash(<String>[item.id]);
        _showUndo(<String>[item.id]);
      case VaultItemMenuAction.restore:
      case VaultItemMenuAction.deleteForever:
        break; // Trash-screen actions; not offered here.
    }
  }

  void _showUndo(List<String> ids) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Moved to trash'
                : 'Moved ${ids.length} items to trash',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => ref.read(vaultItemsProvider.notifier).restore(ids),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultItem> items = _visibleItems();
    final Set<String> selection = ref.watch(selectionProvider);
    final bool selectionMode = selection.isNotEmpty;
    final SelectionController selector = ref.read(selectionProvider.notifier);
    final VaultItemsController controller =
        ref.read(vaultItemsProvider.notifier);

    return PopScope(
      canPop: !selectionMode,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) selector.clear();
      },
      child: Scaffold(
        appBar: selectionMode
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Symbols.close),
                  onPressed: selector.clear,
                ),
                title: Text('${selection.length} selected'),
                actions: <Widget>[
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Symbols.select_all),
                    onPressed: () =>
                        selector.selectAll(items.map((VaultItem i) => i.id)),
                  ),
                  IconButton(
                    tooltip: 'Add to favorites',
                    icon: const Icon(Symbols.star),
                    onPressed: () {
                      controller.setFavorite(selection.toList(), true);
                      selector.clear();
                    },
                  ),
                  IconButton(
                    tooltip: 'Move to trash',
                    icon: const Icon(Symbols.delete),
                    onPressed: () {
                      final List<String> ids = selection.toList();
                      controller.moveToTrash(ids);
                      selector.clear();
                      _showUndo(ids);
                    },
                  ),
                ],
              )
            : AppBar(
                title: Text('$_title (${items.length})'),
                actions: <Widget>[
                  PopupMenuButton<SortMode>(
                    tooltip: 'Sort',
                    icon: const Icon(Symbols.sort),
                    initialValue: _sort,
                    onSelected: (SortMode mode) => setState(() => _sort = mode),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<SortMode>>[
                      for (final (SortMode, String) entry
                          in const <(SortMode, String)>[
                        (SortMode.newest, 'Newest first'),
                        (SortMode.oldest, 'Oldest first'),
                        (SortMode.nameAZ, 'Name A–Z'),
                        (SortMode.nameZA, 'Name Z–A'),
                        (SortMode.largest, 'Largest first'),
                      ])
                        PopupMenuItem<SortMode>(
                          value: entry.$1,
                          child: Text(entry.$2),
                        ),
                    ],
                  ),
                ],
              ),
        body: items.isEmpty
            ? EmptyState(
                icon: widget.favoritesOnly
                    ? Symbols.star
                    : vaultTypeVisual(
                        widget.type!,
                        Theme.of(context).colorScheme,
                      ).$1,
                title: widget.favoritesOnly
                    ? 'No favorites yet'
                    : 'Nothing here yet',
                message: widget.favoritesOnly
                    ? 'Star items anywhere in the vault to collect them here.'
                    : 'Items you add to $_title will appear here, fully '
                        'encrypted.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final VaultItem item = items[index];
                  final bool selected = selection.contains(item.id);
                  return VaultItemTile(
                    item: item,
                    selected: selected,
                    selectionMode: selectionMode,
                    onTap: () {
                      if (selectionMode) {
                        selector.toggle(item.id);
                      }
                      // Type-specific viewers open here from Phase 7 on.
                    },
                    onLongPress: () => selector.toggle(item.id),
                    onToggleFavorite: () => controller.toggleFavorite(item.id),
                    menuActions: const <VaultItemMenuAction>[
                      VaultItemMenuAction.rename,
                      VaultItemMenuAction.pin,
                      VaultItemMenuAction.trash,
                    ],
                    onMenuAction: (VaultItemMenuAction action) =>
                        _onMenuAction(item, action),
                  );
                },
              ),
      ),
    );
  }
}
