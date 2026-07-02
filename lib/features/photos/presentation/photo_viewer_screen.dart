import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../shared/shared.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';
import '../application/photo_providers.dart';

/// Arguments for the photo viewer route.
class PhotoViewerArgs {
  const PhotoViewerArgs({required this.initialId});

  /// The photo to open first; the viewer swipes across all photos.
  final String initialId;
}

/// Immersive full-screen photo viewer: pinch/double-tap zoom, swipe between
/// photos, slideshow, share, favorite and delete.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({super.key, required this.args});

  final PhotoViewerArgs args;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _controller;
  late int _index;
  bool _chromeVisible = true;
  Timer? _slideshow;

  @override
  void initState() {
    super.initState();
    final List<VaultItem> photos = ref.read(photoItemsProvider);
    _index = photos.indexWhere((VaultItem i) => i.id == widget.args.initialId);
    if (_index < 0) _index = 0;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _slideshow?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _toggleSlideshow() {
    if (_slideshow != null) {
      _slideshow!.cancel();
      setState(() => _slideshow = null);
      return;
    }
    setState(() {
      _chromeVisible = false;
      _slideshow = Timer.periodic(const Duration(seconds: 3), (_) {
        final int count = ref.read(photoItemsProvider).length;
        if (count <= 1) return;
        final int next = (_controller.page!.round() + 1) % count;
        _controller.animateToPage(
          next,
          duration: AppMotion.slow,
          curve: AppMotion.emphasized,
        );
      });
    });
  }

  Future<void> _share(VaultItem item) async {
    if (item.relativePath == null) return;
    try {
      final file = await ref
          .read(vaultFileStoreProvider)
          .decryptToTempFile(item.relativePath!, extension: 'jpg');
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share this photo'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _delete(VaultItem item) async {
    _slideshow?.cancel();
    _slideshow = null;
    await ref.read(vaultItemsProvider.notifier).moveToTrash(<String>[item.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Moved to trash'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(vaultItemsProvider.notifier).restore(<String>[item.id]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultItem> photos = ref.watch(photoItemsProvider);

    // If the current (or every) photo was deleted, leave gracefully.
    if (photos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(backgroundColor: Colors.black);
    }
    final int safeIndex = _index.clamp(0, photos.length - 1);
    final VaultItem current = photos[safeIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _controller,
            itemCount: photos.length,
            onPageChanged: (int i) => setState(() => _index = i),
            itemBuilder: (BuildContext context, int i) => _ZoomablePhoto(
              item: photos[i],
              onTap: _toggleChrome,
            ),
          ),
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: AppMotion.fast,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: _ViewerChrome(
                item: current,
                index: safeIndex,
                total: photos.length,
                slideshowActive: _slideshow != null,
                onClose: () => Navigator.of(context).maybePop(),
                onFavorite: () {
                  AppHaptics.selection();
                  ref
                      .read(vaultItemsProvider.notifier)
                      .toggleFavorite(current.id);
                },
                onShare: () => _share(current),
                onSlideshow: _toggleSlideshow,
                onDelete: () => _delete(current),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One zoomable page. Decrypts the full image and wraps it in an
/// InteractiveViewer with double-tap-to-zoom.
class _ZoomablePhoto extends ConsumerStatefulWidget {
  const _ZoomablePhoto({required this.item, required this.onTap});

  final VaultItem item;
  final VoidCallback onTap;

  @override
  ConsumerState<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends ConsumerState<_ZoomablePhoto> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
    } else {
      final Offset position = _doubleTapDetails!.localPosition;
      _transform.value = Matrix4.identity()
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? path = widget.item.relativePath;
    final AsyncValue<Uint8List> bytes = path == null
        ? const AsyncValue<Uint8List>.loading()
        : ref.watch(photoBytesProvider(path));

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (TapDownDetails d) => _doubleTapDetails = d,
      onDoubleTap: _handleDoubleTap,
      child: bytes.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        error: (_, __) => const Center(
          child: Icon(Symbols.broken_image, color: Colors.white, size: 48),
        ),
        data: (Uint8List data) => InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Hero(
              tag: 'photo_${widget.item.id}',
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerChrome extends StatelessWidget {
  const _ViewerChrome({
    required this.item,
    required this.index,
    required this.total,
    required this.slideshowActive,
    required this.onClose,
    required this.onFavorite,
    required this.onShare,
    required this.onSlideshow,
    required this.onDelete,
  });

  final VaultItem item;
  final int index;
  final int total;
  final bool slideshowActive;
  final VoidCallback onClose;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onSlideshow;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _bar(
          context,
          gradientFromTop: true,
          child: Row(
            children: <Widget>[
              _iconButton(Symbols.arrow_back, 'Back', onClose),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      item.name,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${index + 1} of $total',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _iconButton(
                item.favorite ? Symbols.star : Symbols.star,
                'Favorite',
                onFavorite,
                fill: item.favorite,
                color: item.favorite ? AppColors.warning : Colors.white,
              ),
            ],
          ),
        ),
        const Spacer(),
        _bar(
          context,
          gradientFromTop: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _iconButton(Symbols.share, 'Share', onShare),
              _iconButton(
                slideshowActive ? Symbols.pause : Symbols.slideshow,
                'Slideshow',
                onSlideshow,
              ),
              _iconButton(Symbols.delete, 'Move to trash', onDelete),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(
    BuildContext context, {
    required bool gradientFromTop,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.only(
        top: gradientFromTop ? MediaQuery.paddingOf(context).top + 8 : 12,
        bottom:
            gradientFromTop ? 12 : MediaQuery.paddingOf(context).bottom + 12,
        left: AppSpacing.sm,
        right: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: gradientFromTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: gradientFromTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: child,
    );
  }

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool fill = false,
    Color color = Colors.white,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color, fill: fill ? 1 : 0),
    );
  }
}
