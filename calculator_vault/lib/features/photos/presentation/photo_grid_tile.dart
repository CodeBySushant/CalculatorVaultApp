import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../shared/shared.dart';
import '../../vault/domain/vault_item.dart';
import '../application/photo_providers.dart';

/// A single square photo tile in the grid. Decrypts and renders its
/// thumbnail, with favorite/selection overlays and a hero for the viewer
/// transition.
class PhotoGridTile extends ConsumerWidget {
  const PhotoGridTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedPress(
        child: ClipRRect(
          borderRadius: AppRadius.smAll,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: scheme.surfaceContainerHighest),
              _Thumbnail(item: item),
              if (item.favorite && !selectionMode)
                const Positioned(
                  left: 6,
                  bottom: 6,
                  child: Icon(
                    Symbols.star,
                    size: 18,
                    fill: 1,
                    color: AppColors.warning,
                    shadows: <Shadow>[
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
              if (selectionMode)
                Container(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.08),
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    selected ? Symbols.check_circle : Symbols.circle,
                    fill: selected ? 1 : 0,
                    color: selected ? scheme.primary : Colors.white,
                    shadows: const <Shadow>[
                      Shadow(blurRadius: 4, color: Colors.black54),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.item});

  final VaultItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? thumbPath = item.thumbnailPath;
    if (thumbPath == null) {
      return const _ThumbnailFallback();
    }

    final AsyncValue<Uint8List> thumb =
        ref.watch(photoThumbnailProvider(thumbPath));
    return thumb.when(
      loading: () => const ColoredBox(color: Colors.transparent),
      error: (_, __) => const _ThumbnailFallback(),
      data: (Uint8List bytes) => Hero(
        tag: 'photo_${item.id}',
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Symbols.broken_image,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
