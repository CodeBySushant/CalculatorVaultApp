import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/shared.dart';
import '../../vault/application/selection_controller.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';
import '../application/photo_import_service.dart';
import '../application/photo_providers.dart';
import 'photo_grid_tile.dart';
import 'photo_viewer_screen.dart';

/// Photos category: an encrypted photo grid with import, multi-select, and
/// tap-to-open full-screen viewing.
class PhotoGridScreen extends ConsumerStatefulWidget {
  const PhotoGridScreen({super.key});

  @override
  ConsumerState<PhotoGridScreen> createState() => _PhotoGridScreenState();
}

class _PhotoGridScreenState extends ConsumerState<PhotoGridScreen> {
  bool _importing = false;
  int _done = 0;
  int _total = 0;

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _done = 0;
      _total = 0;
    });
    try {
      final List<VaultItem> items =
          await ref.read(photoImportServiceProvider).pickAndImport(
        onProgress: (int done, int total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
      for (final VaultItem item in items) {
        await ref.read(vaultItemsProvider.notifier).add(item);
      }
      if (mounted && items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              items.length == 1
                  ? '1 photo added to your vault'
                  : '${items.length} photos added to your vault',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not import photos'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _openViewer(VaultItem item) {
    context.push(
      AppRoutes.photoViewer,
      extra: PhotoViewerArgs(initialId: item.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultItem> photos = ref.watch(photoItemsProvider);
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
                        selector.selectAll(photos.map((VaultItem i) => i.id)),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${ids.length} moved to trash'),
                          behavior: SnackBarBehavior.floating,
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () => controller.restore(ids),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              )
            : AppBar(title: Text('Photos (${photos.length})')),
        floatingActionButton: selectionMode
            ? null
            : FloatingActionButton.extended(
                onPressed: _importing ? null : _import,
                icon: const Icon(Symbols.add_photo_alternate),
                label: const Text('Add'),
              ),
        body: Stack(
          children: <Widget>[
            if (photos.isEmpty && !_importing)
              EmptyState(
                icon: Symbols.image,
                title: 'No photos yet',
                message: 'Add photos to keep them encrypted and private. '
                    'They never appear in your device gallery.',
                actionLabel: 'Add photos',
                onAction: _import,
              )
            else
              GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  96,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: context.responsive<int>(
                    compact: 3,
                    medium: 4,
                    expanded: 6,
                  ),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                ),
                itemCount: photos.length,
                itemBuilder: (BuildContext context, int index) {
                  final VaultItem item = photos[index];
                  final bool selected = selection.contains(item.id);
                  return PhotoGridTile(
                    item: item,
                    selected: selected,
                    selectionMode: selectionMode,
                    onTap: () => selectionMode
                        ? selector.toggle(item.id)
                        : _openViewer(item),
                    onLongPress: () => selector.toggle(item.id),
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
                      : 'Encrypting $done of $total photos…',
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
