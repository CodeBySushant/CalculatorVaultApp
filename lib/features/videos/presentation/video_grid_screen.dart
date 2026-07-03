import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/shared.dart';
import '../../authentication/application/vault_session.dart';
import '../../vault/application/selection_controller.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';
import '../application/video_import_service.dart';
import '../application/video_providers.dart';
import 'video_grid_tile.dart';
import 'video_player_screen.dart';

/// Videos category: encrypted video grid with import, multi-select, and
/// tap-to-play.
class VideoGridScreen extends ConsumerStatefulWidget {
  const VideoGridScreen({super.key});

  @override
  ConsumerState<VideoGridScreen> createState() => _VideoGridScreenState();
}

class _VideoGridScreenState extends ConsumerState<VideoGridScreen> {
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
          await ref.read(vaultSessionProvider.notifier).withoutAutoLock(
                () => ref.read(videoImportServiceProvider).pickAndImport(
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
                  ? '1 video added to your vault'
                  : '${items.length} videos added to your vault',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not import videos'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _openPlayer(VaultItem item) {
    context.push(
      AppRoutes.videoPlayer,
      extra: VideoPlayerArgs(itemId: item.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultItem> videos = ref.watch(videoItemsProvider);
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
                        selector.selectAll(videos.map((VaultItem i) => i.id)),
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
            : AppBar(title: Text('Videos (${videos.length})')),
        floatingActionButton: selectionMode
            ? null
            : FloatingActionButton.extended(
                onPressed: _importing ? null : _import,
                icon: const Icon(Symbols.video_call),
                label: const Text('Add'),
              ),
        body: Stack(
          children: <Widget>[
            if (videos.isEmpty && !_importing)
              EmptyState(
                icon: Symbols.movie,
                title: 'No videos yet',
                message: 'Add videos to keep them encrypted and private. '
                    'They never appear in your device gallery.',
                actionLabel: 'Add videos',
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
                      compact: 2, medium: 3, expanded: 4),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 16 / 10,
                ),
                itemCount: videos.length,
                itemBuilder: (BuildContext context, int index) {
                  final VaultItem item = videos[index];
                  final bool selected = selection.contains(item.id);
                  return VideoGridTile(
                    item: item,
                    selected: selected,
                    selectionMode: selectionMode,
                    onTap: () => selectionMode
                        ? selector.toggle(item.id)
                        : _openPlayer(item),
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
                      : 'Encrypting $done of $total videos…',
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
