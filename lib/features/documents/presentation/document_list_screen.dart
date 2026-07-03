import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/shared.dart';
import '../../authentication/application/vault_session.dart';
import '../../vault/application/selection_controller.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';
import '../../vault/presentation/widgets/vault_item_tile.dart';
import '../application/document_import_service.dart';
import '../application/document_providers.dart';
import '../data/document_types.dart';
import 'document_viewer_screen.dart';

/// Documents category: an encrypted document list with import, multi-select,
/// and tap-to-view (in-app for images/text, system viewer for the rest).
class DocumentListScreen extends ConsumerStatefulWidget {
  const DocumentListScreen({super.key});

  @override
  ConsumerState<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends ConsumerState<DocumentListScreen> {
  SortMode _sort = SortMode.newest;
  bool _importing = false;
  int _done = 0;
  int _total = 0;

  List<VaultItem> _sorted() {
    final List<VaultItem> docs = <VaultItem>[
      ...ref.watch(documentItemsProvider)
    ]..sort(compareItems(_sort));
    return docs;
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _done = 0;
      _total = 0;
    });
    try {
      final List<VaultItem> items =
          await ref.read(vaultSessionProvider.notifier).withoutAutoLock(
                () => ref.read(documentImportServiceProvider).pickAndImport(
                  onProgress: (int done, int total) {
                    if (mounted) {
                      setState(() {
                        _done = done;
                        _total = total;
                      });
                    }
                  },
                ),
              );
      for (final VaultItem item in items) {
        await ref.read(vaultItemsProvider.notifier).add(item);
      }
      if (mounted && items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              items.length == 1
                  ? '1 document added to your vault'
                  : '${items.length} documents added to your vault',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not import documents'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _rename(VaultItem item) async {
    final TextEditingController controller =
        TextEditingController(text: item.name);
    await showAppBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => Column(
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
      ),
    );
    controller.dispose();
  }

  void _openViewer(VaultItem item) {
    context.push(
      AppRoutes.documentViewer,
      extra: DocumentViewerArgs(itemId: item.id),
    );
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
    final List<VaultItem> docs = _sorted();
    final Set<String> selection = ref.watch(selectionProvider);
    final bool selectionMode = selection.isNotEmpty;
    final SelectionController selector = ref.read(selectionProvider.notifier);
    final VaultItemsController controller =
        ref.read(vaultItemsProvider.notifier);

    return PopScope(
      canPop: !selectionMode,
      onPopInvokedWithResult: (bool didPop, _) {
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
                        selector.selectAll(docs.map((VaultItem i) => i.id)),
                  ),
                  IconButton(
                    tooltip: 'Favorite',
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
                title: Text('Documents (${docs.length})'),
                actions: <Widget>[
                  PopupMenuButton<SortMode>(
                    tooltip: 'Sort',
                    icon: const Icon(Symbols.sort),
                    initialValue: _sort,
                    onSelected: (SortMode mode) => setState(() => _sort = mode),
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<SortMode>>[
                      PopupMenuItem<SortMode>(
                        value: SortMode.newest,
                        child: Text('Newest first'),
                      ),
                      PopupMenuItem<SortMode>(
                        value: SortMode.oldest,
                        child: Text('Oldest first'),
                      ),
                      PopupMenuItem<SortMode>(
                        value: SortMode.nameAZ,
                        child: Text('Name A–Z'),
                      ),
                      PopupMenuItem<SortMode>(
                        value: SortMode.largest,
                        child: Text('Largest first'),
                      ),
                    ],
                  ),
                ],
              ),
        floatingActionButton: selectionMode
            ? null
            : FloatingActionButton.extended(
                onPressed: _importing ? null : _import,
                icon: const Icon(Symbols.upload_file),
                label: const Text('Add'),
              ),
        body: Stack(
          children: <Widget>[
            if (docs.isEmpty && !_importing)
              EmptyState(
                icon: Symbols.folder_open,
                title: 'No documents yet',
                message: 'Add PDFs, images, and files to keep them '
                    'encrypted and private.',
                actionLabel: 'Add documents',
                onAction: _import,
              )
            else
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  96,
                ),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final VaultItem item = docs[index];
                  final bool selected = selection.contains(item.id);
                  final (IconData icon, Color tint) = documentVisual(item.name);
                  return _DocumentTile(
                    item: item,
                    icon: icon,
                    tint: tint,
                    selected: selected,
                    selectionMode: selectionMode,
                    onTap: () => selectionMode
                        ? selector.toggle(item.id)
                        : _openViewer(item),
                    onLongPress: () => selector.toggle(item.id),
                    onFavorite: () => controller.toggleFavorite(item.id),
                    onMenu: (VaultItemMenuAction action) {
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
                          break;
                      }
                    },
                  );
                },
              ),
            if (_importing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ImportBanner(done: _done, total: _total),
              ),
          ],
        ),
      ),
    );
  }
}

/// A document row with a file-type icon (rather than the generic doc icon).
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.item,
    required this.icon,
    required this.tint,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
    required this.onMenu,
  });

  final VaultItem item;
  final IconData icon;
  final Color tint;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;
  final ValueChanged<VaultItemMenuAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 22, color: tint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (item.pinned) ...<Widget>[
                      Icon(Symbols.keep, size: 14, color: scheme.primary),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        item.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${Formatters.bytes(item.byteLength)} · '
                  '${Formatters.date(item.updatedAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (selectionMode)
            Icon(
              selected ? Symbols.check_circle : Symbols.circle,
              color: selected ? scheme.primary : scheme.outlineVariant,
              fill: selected ? 1 : 0,
            )
          else ...<Widget>[
            IconButton(
              tooltip: item.favorite ? 'Unfavorite' : 'Favorite',
              onPressed: onFavorite,
              icon: Icon(
                Symbols.star,
                size: 22,
                fill: item.favorite ? 1 : 0,
                color:
                    item.favorite ? AppColors.warning : scheme.onSurfaceVariant,
              ),
            ),
            PopupMenuButton<VaultItemMenuAction>(
              tooltip: 'More',
              onSelected: onMenu,
              icon: Icon(Symbols.more_vert,
                  size: 22, color: scheme.onSurfaceVariant),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<VaultItemMenuAction>>[
                for (final VaultItemMenuAction action in <VaultItemMenuAction>[
                  VaultItemMenuAction.rename,
                  VaultItemMenuAction.pin,
                  VaultItemMenuAction.trash,
                ])
                  PopupMenuItem<VaultItemMenuAction>(
                    value: action,
                    child: Row(
                      children: <Widget>[
                        Icon(action.icon(item), size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Text(action.label(item)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportBanner extends StatelessWidget {
  const _ImportBanner({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: AppCard(
          elevated: true,
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  total == 0
                      ? 'Preparing…'
                      : 'Encrypting $done of $total documents…',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
