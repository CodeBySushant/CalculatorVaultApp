import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/shared.dart';
import '../../vault/domain/vault_item.dart';
import '../application/video_providers.dart';

/// A single video tile: poster (or gradient placeholder), a play glyph, a
/// duration badge, and favorite/selection overlays.
class VideoGridTile extends ConsumerWidget {
  const VideoGridTile({
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
              _Poster(item: item),
              // Play affordance.
              if (!selectionMode)
                Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Symbols.play_arrow,
                      color: Colors.white,
                      fill: 1,
                    ),
                  ),
                ),
              // Duration badge.
              if (item.durationMs > 0)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      Formatters.duration(
                        Duration(milliseconds: item.durationMs),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
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

class _Poster extends ConsumerWidget {
  const _Poster({required this.item});

  final VaultItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? thumbPath = item.thumbnailPath;
    if (thumbPath == null) return const _PosterPlaceholder();

    final AsyncValue<Uint8List> poster =
        ref.watch(videoPosterProvider(thumbPath));
    return poster.when(
      loading: () => const _PosterPlaceholder(),
      error: (_, __) => const _PosterPlaceholder(),
      data: (Uint8List bytes) => Hero(
        tag: 'video_${item.id}',
        child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.brandGradient),
      child: Center(
        child: Icon(Symbols.movie, color: Colors.white70, size: 28),
      ),
    );
  }
}
