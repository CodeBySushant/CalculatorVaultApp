import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../vault/domain/vault_item.dart';

final videoImportServiceProvider = Provider<VideoImportService>(
  (ref) => VideoImportService(
    picker: ImagePicker(),
    fileStore: ref.watch(vaultFileStoreProvider),
  ),
);

/// Progress callback: [done] of [total] videos imported so far.
typedef VideoImportProgress = void Function(int done, int total);

/// Picks videos from the system gallery and imports them into the vault:
/// encrypts each file, extracts a poster frame and duration (both
/// best-effort), and deletes the picker's temp copy.
///
/// Like photo import, this uses the permission-free system picker. See the
/// photos README note about device-gallery deletion — the same applies.
class VideoImportService {
  VideoImportService({
    required ImagePicker picker,
    required VaultFileStore fileStore,
  })  : _picker = picker,
        _fileStore = fileStore;

  static const String _tag = 'VideoImport';

  static const Set<String> _videoExtensions = <String>{
    'mp4',
    'mov',
    'mkv',
    'avi',
    'webm',
    'm4v',
    '3gp',
    'ts',
    'flv',
  };

  final ImagePicker _picker;
  final VaultFileStore _fileStore;
  final Uuid _uuid = const Uuid();

  /// Opens the gallery (media mode), imports each chosen video, and returns
  /// the created items. Non-video selections are ignored. Empty on cancel.
  Future<List<VaultItem>> pickAndImport(
      {VideoImportProgress? onProgress}) async {
    final List<XFile> picked;
    try {
      picked = await _picker.pickMultipleMedia();
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'picker failed', e, st);
      throw const PermissionException('Could not open the video picker.');
    }
    final List<XFile> videos = picked.where((XFile f) => _isVideo(f)).toList();
    if (videos.isEmpty) return const <VaultItem>[];

    final List<VaultItem> imported = <VaultItem>[];
    for (int i = 0; i < videos.length; i++) {
      onProgress?.call(i, videos.length);
      final XFile file = videos[i];
      try {
        imported.add(await _importOne(file));
      } on AppException catch (e) {
        AppLogger.error(_tag, 'skipping ${file.name}', e);
      } finally {
        try {
          await File(file.path).delete();
        } on FileSystemException {
          // Best effort.
        }
      }
    }
    onProgress?.call(videos.length, videos.length);
    return imported;
  }

  Future<VaultItem> _importOne(XFile file) async {
    final String id = _uuid.v4();

    // Duration first, from the plaintext temp file (best-effort).
    final int durationMs = await _readDurationMs(file.path);

    final VaultFileRef ref =
        await _fileStore.importFile(file.path, category: 'videos');

    // Poster-frame extraction was removed (the video_thumbnail plugin is
    // incompatible with modern Gradle). The grid shows a gradient
    // placeholder; playback is unaffected. Can be revisited in Phase 14
    // with a Gradle-compatible extractor.
    final DateTime now = DateTime.now();
    return VaultItem(
      id: id,
      type: VaultItemType.video,
      name: _fileName(file),
      relativePath: ref.relativePath,
      byteLength: ref.byteLength,
      durationMs: durationMs,
      mimeType: file.mimeType ?? 'video/mp4',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Reads a video's duration by briefly initializing a player on the
  /// plaintext temp file. Returns 0 on any failure or timeout.
  Future<int> _readDurationMs(String path) async {
    final VideoPlayerController controller =
        VideoPlayerController.file(File(path));
    try {
      await controller.initialize().timeout(const Duration(seconds: 8));
      return controller.value.duration.inMilliseconds;
    } on Object catch (e) {
      AppLogger.error(_tag, 'duration read failed', e);
      return 0;
    } finally {
      await controller.dispose();
    }
  }

  bool _isVideo(XFile file) {
    final String? mime = file.mimeType;
    if (mime != null && mime.startsWith('video/')) return true;
    final String ext = file.name.split('.').last.toLowerCase();
    return _videoExtensions.contains(ext);
  }

  String _fileName(XFile file) {
    final String raw = file.name.isNotEmpty
        ? file.name
        : file.path.split(RegExp(r'[/\\]')).last;
    return raw.isEmpty ? 'Video' : raw;
  }
}
