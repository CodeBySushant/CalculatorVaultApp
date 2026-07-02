import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/shared.dart';
import '../../domain/vault_item.dart';

/// Icon and tint per item type, shared by tiles and category cards.
(IconData, Color) vaultTypeVisual(VaultItemType type, ColorScheme scheme) {
  return switch (type) {
    VaultItemType.photo => (Symbols.image, AppColors.royalBlue),
    VaultItemType.video => (Symbols.movie, AppColors.premiumPurple),
    VaultItemType.document => (Symbols.description, AppColors.cyan),
    VaultItemType.note => (Symbols.sticky_note_2, AppColors.emerald),
    VaultItemType.password => (Symbols.key, AppColors.deepIndigo),
    VaultItemType.voiceNote => (Symbols.mic, scheme.tertiary),
  };
}

/// Standard list tile for a vault item. Handles normal and selection modes.
class VaultItemTile extends StatelessWidget {
  const VaultItemTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleFavorite,
    this.menuActions = const <VaultItemMenuAction>[],
    this.onMenuAction,
    this.subtitleOverride,
  });

  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleFavorite;
  final List<VaultItemMenuAction> menuActions;
  final ValueChanged<VaultItemMenuAction>? onMenuAction;

  /// Custom subtitle (used by the trash screen for the countdown).
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (IconData icon, Color tint) = vaultTypeVisual(item.type, scheme);

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
                  subtitleOverride ??
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
            if (onToggleFavorite != null)
              IconButton(
                tooltip: item.favorite ? 'Unfavorite' : 'Favorite',
                onPressed: onToggleFavorite,
                icon: Icon(
                  Symbols.star,
                  size: 22,
                  fill: item.favorite ? 1 : 0,
                  color: item.favorite
                      ? AppColors.warning
                      : scheme.onSurfaceVariant,
                ),
              ),
            if (menuActions.isNotEmpty)
              PopupMenuButton<VaultItemMenuAction>(
                tooltip: 'More',
                onSelected: onMenuAction,
                icon: Icon(
                  Symbols.more_vert,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<VaultItemMenuAction>>[
                  for (final VaultItemMenuAction action in menuActions)
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

/// Per-item menu actions offered by list screens.
enum VaultItemMenuAction {
  rename,
  pin,
  trash,
  restore,
  deleteForever;

  String label(VaultItem item) => switch (this) {
        rename => 'Rename',
        pin => item.pinned ? 'Unpin' : 'Pin',
        trash => 'Move to trash',
        restore => 'Restore',
        deleteForever => 'Delete forever',
      };

  IconData icon(VaultItem item) => switch (this) {
        rename => Symbols.edit,
        pin => Symbols.keep,
        trash => Symbols.delete,
        restore => Symbols.restore_from_trash,
        deleteForever => Symbols.delete_forever,
      };
}
