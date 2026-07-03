import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:video_player/video_player.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/shared.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';
import '../application/video_providers.dart';

/// Arguments for the video player route.
class VideoPlayerArgs {
  const VideoPlayerArgs({required this.itemId});
  final String itemId;
}

/// Full-screen encrypted video player.
///
/// Decrypts the selected video to a temp file, plays it with custom
/// controls (play/pause, scrubber, time, speed, fullscreen), resumes from
/// the last saved position, and — critically — deletes the decrypted temp
/// file and persists the new position on exit.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.args});

  final VideoPlayerArgs args;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  static const List<double> _speeds = <double>[0.5, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController? _controller;
  File? _tempFile;
  bool _chromeVisible = true;
  bool _initFailed = false;
  double _speed = 1.0;
  Timer? _hideTimer;

  // Captured for safe use in dispose (no ref/context after teardown).
  VaultFileStore? _fileStore;
  VaultItemsController? _itemsController;

  @override
  void initState() {
    super.initState();
    _fileStore = ref.read(vaultFileStoreProvider);
    _itemsController = ref.read(vaultItemsProvider.notifier);
    _prepare();
  }

  Future<void> _prepare() async {
    final VaultItem? item = _currentItem();
    if (item == null || item.relativePath == null) {
      setState(() => _initFailed = true);
      return;
    }
    try {
      final File temp = await _fileStore!.decryptToTempFile(
        item.relativePath!,
        extension: 'mp4',
      );
      _tempFile = temp;
      final VideoPlayerController controller = VideoPlayerController.file(temp);
      await controller.initialize();

      final int resumeMs = VideoProgress.positionMsOf(item);
      if (VideoProgress.shouldResume(
        resumeMs,
        controller.value.duration.inMilliseconds,
      )) {
        await controller.seekTo(Duration(milliseconds: resumeMs));
      }
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _scheduleHide();
    } on Object catch (e, st) {
      AppLogger.error('VideoPlayer', 'prepare failed', e, st);
      if (mounted) setState(() => _initFailed = true);
    }
  }

  VaultItem? _currentItem() {
    final List<VaultItem> videos = ref.read(videoItemsProvider);
    for (final VaultItem v in videos) {
      if (v.id == widget.args.itemId) return v;
    }
    return null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleHide();
  }

  void _togglePlay() {
    final VideoPlayerController? c = _controller;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _hideTimer?.cancel();
        _chromeVisible = true;
      } else {
        c.play();
        _scheduleHide();
      }
    });
  }

  Future<void> _cycleSpeed() async {
    final int idx = _speeds.indexOf(_speed);
    final double next = _speeds[(idx + 1) % _speeds.length];
    await _controller?.setPlaybackSpeed(next);
    setState(() => _speed = next);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // Restore portrait + system UI.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final VideoPlayerController? controller = _controller;
    final File? temp = _tempFile;
    if (controller != null) {
      // Persist resume position before tearing down.
      final int posMs = controller.value.position.inMilliseconds;
      _itemsController?.updateItem(
        widget.args.itemId,
        (VaultItem i) => i.copyWith(payload: VideoProgress.encode(posMs)),
      );
      controller.dispose();
    }
    // Delete the decrypted temp file immediately (don't wait for lock).
    if (temp != null) {
      unawaited(temp.delete().then<void>((_) {}, onError: (_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _initFailed
          ? _ErrorBody(onBack: () => Navigator.of(context).maybePop())
          : controller == null
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : GestureDetector(
                  onTap: _toggleChrome,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio == 0
                              ? 16 / 9
                              : controller.value.aspectRatio,
                          child: Hero(
                            tag: 'video_${widget.args.itemId}',
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _chromeVisible ? 1 : 0,
                        duration: AppMotion.fast,
                        child: IgnorePointer(
                          ignoring: !_chromeVisible,
                          child: _Controls(
                            controller: controller,
                            speed: _speed,
                            name: _currentItem()?.name ?? 'Video',
                            onBack: () => Navigator.of(context).maybePop(),
                            onPlayPause: _togglePlay,
                            onSpeed: _cycleSpeed,
                            onInteract: _scheduleHide,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.speed,
    required this.name,
    required this.onBack,
    required this.onPlayPause,
    required this.onSpeed,
    required this.onInteract,
  });

  final VideoPlayerController controller;
  final double speed;
  final String name;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onSpeed;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.65),
          ],
        ),
      ),
      child: Column(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Back',
                  icon: const Icon(Symbols.arrow_back, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: onSpeed,
                  child: Text(
                    '${speed}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Center(
            child: IconButton(
              iconSize: 64,
              onPressed: onPlayPause,
              icon: Icon(
                controller.value.isPlaying
                    ? Symbols.pause_circle
                    : Symbols.play_circle,
                fill: 1,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _Scrubber(
                controller: controller,
                onInteract: onInteract,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Position/duration text + a scrubber wired to the controller's value.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.controller, required this.onInteract});

  final VideoPlayerController controller;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (BuildContext context, VideoPlayerValue value, _) {
        final Duration total = value.duration;
        final Duration position = value.position;
        final double maxMs =
            total.inMilliseconds == 0 ? 1 : total.inMilliseconds.toDouble();
        final double posMs = position.inMilliseconds.clamp(0, maxMs).toDouble();

        return Row(
          children: <Widget>[
            Text(
              Formatters.duration(position),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  activeTrackColor: AppColors.royalBlue,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 0,
                  max: maxMs,
                  value: posMs,
                  onChanged: (double v) {
                    onInteract();
                    controller.seekTo(Duration(milliseconds: v.round()));
                  },
                ),
              ),
            ),
            Text(
              Formatters.duration(total),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Symbols.arrow_back, color: Colors.white),
            ),
          ),
          const Spacer(),
          const Icon(Symbols.error, color: Colors.white54, size: 48),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'This video could not be played.',
            style: TextStyle(color: Colors.white70),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
