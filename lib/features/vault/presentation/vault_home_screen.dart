import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/shared.dart';
import '../../authentication/application/vault_session.dart';
import '../application/vault_items_controller.dart';
import '../domain/vault_item.dart';
import 'widgets/vault_item_tile.dart';

/// Vault home: library categories with live counts, plus favorites and
/// trash collections.
class VaultHomeScreen extends ConsumerWidget {
  const VaultHomeScreen({super.key});

  // Notes and Passwords (Phases 10–11) are hidden until their editors
  // ship — visible-but-unfinished sections invite bad reviews and Play
  // reviewer confusion. Re-add the tuples below when the features land.
  static const List<(VaultItemType, String)> _categories =
      <(VaultItemType, String)>[
    (VaultItemType.photo, 'Photos'),
    (VaultItemType.video, 'Videos'),
    (VaultItemType.document, 'Documents'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<VaultItemType, int> counts = ref.watch(categoryCountsProvider);
    final int favoriteCount = ref.watch(favoriteItemsProvider).length;
    final int trashCount = ref.watch(trashedItemsProvider).length;
    final AsyncValue<List<VaultItem>> itemsAsync =
        ref.watch(vaultItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Lock and exit',
            icon: const Icon(Symbols.lock),
            onPressed: () {
              ref.read(vaultSessionProvider.notifier).end();
              context.go(AppRoutes.calculator);
            },
          ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, _) => EmptyState(
          icon: Symbols.error,
          title: 'Could not open the vault',
          message: 'Something went wrong reading your vault index. '
              'Restart the app and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(vaultItemsProvider),
        ),
        data: (_) => ListView(
          padding: AppSpacing.screen,
          children: <Widget>[
            const SectionHeader(title: 'Library'),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount:
                  context.responsive<int>(compact: 2, medium: 3, expanded: 4),
              mainAxisSpacing: AppSpacing.sm + 4,
              crossAxisSpacing: AppSpacing.sm + 4,
              childAspectRatio: 1.3,
              children: <Widget>[
                for (final (int index, (VaultItemType, String) entry)
                    in _categories.indexed)
                  _CategoryCard(
                    type: entry.$1,
                    label: entry.$2,
                    count: counts[entry.$1] ?? 0,
                    onTap: () => context.go(AppRoutes.vaultItems(entry.$1)),
                  )
                      .animate(delay: (60 * index).ms)
                      .fadeIn(duration: AppMotion.normal)
                      .slideY(begin: 0.15, end: 0, curve: AppMotion.emphasized),
              ],
            ),
            const SectionHeader(title: 'Collections'),
            AppCard(
              onTap: () => context.go(AppRoutes.vaultFavorites),
              child: _CollectionRow(
                icon: Symbols.star,
                tint: AppColors.warning,
                label: 'Favorites',
                count: favoriteCount,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              onTap: () => context.go(AppRoutes.vaultTrash),
              child: _CollectionRow(
                icon: Symbols.delete,
                tint: Theme.of(context).colorScheme.error,
                label: 'Trash',
                count: trashCount,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.type,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final VaultItemType type;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color tint) =
        vaultTypeVisual(type, theme.colorScheme);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 22, color: tint),
          ),
          // Shrink-safe: on narrow grids / large font scales the text block
          // scales down instead of overflowing the card by a few pixels.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: theme.textTheme.titleSmall),
                  Text(
                    '$count ${count == 1 ? 'item' : 'items'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: AppRadius.smAll,
          ),
          child: Icon(icon, size: 22, color: tint),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
        Text('$count', style: theme.textTheme.bodyMedium),
        const SizedBox(width: AppSpacing.xs),
        Icon(
          Symbols.chevron_right,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
