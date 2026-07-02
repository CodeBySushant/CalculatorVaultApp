import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/shared.dart';
import '../application/vault_items_controller.dart';
import '../domain/vault_item.dart';
import 'widgets/vault_item_tile.dart';

/// Trash: restore items or delete them forever. Everything here auto-purges
/// after the retention window.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  String _countdown(VaultItem item) {
    final int daysLeft = AppConstants.trashRetention.inDays -
        DateTime.now().difference(item.trashedAt!).inDays;
    final int clamped = daysLeft < 0 ? 0 : daysLeft;
    return 'Deleted ${_ago(item.trashedAt!)} · '
        '${clamped == 0 ? 'purging soon' : 'gone in $clamped d'}';
  }

  String _ago(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<VaultItem> items = ref.watch(trashedItemsProvider);
    final VaultItemsController controller =
        ref.read(vaultItemsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Trash (${items.length})'),
        actions: <Widget>[
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Empty trash',
              icon: const Icon(Symbols.delete_forever),
              onPressed: () async {
                final bool ok = await _confirm(
                  context,
                  title: 'Empty trash?',
                  message:
                      'All ${items.length} items will be permanently deleted. '
                      'This cannot be undone.',
                  confirmLabel: 'Delete all',
                );
                if (ok) await controller.emptyTrash();
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Symbols.delete,
              title: 'Trash is empty',
              message: 'Deleted items stay here for '
                  '30 days before being removed forever.',
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
                return VaultItemTile(
                  item: item,
                  subtitleOverride: _countdown(item),
                  onTap: () {},
                  onLongPress: () {},
                  menuActions: const <VaultItemMenuAction>[
                    VaultItemMenuAction.restore,
                    VaultItemMenuAction.deleteForever,
                  ],
                  onMenuAction: (VaultItemMenuAction action) async {
                    switch (action) {
                      case VaultItemMenuAction.restore:
                        await controller.restore(<String>[item.id]);
                      case VaultItemMenuAction.deleteForever:
                        final bool ok = await _confirm(
                          context,
                          title: 'Delete forever?',
                          message: '"${item.name}" will be permanently '
                              'deleted. This cannot be undone.',
                          confirmLabel: 'Delete',
                        );
                        if (ok) {
                          await controller.deleteForever(<String>[item.id]);
                        }
                      case VaultItemMenuAction.rename:
                      case VaultItemMenuAction.pin:
                      case VaultItemMenuAction.trash:
                        break;
                    }
                  },
                );
              },
            ),
    );
  }
}
