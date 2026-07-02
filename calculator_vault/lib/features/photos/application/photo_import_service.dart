import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../vault/domain/vault_item.dart';
import 'thumbnail_service.dart';

final photoImportServiceProvider = Provider<PhotoImportService>(
  (ref) => PhotoImportService(
    picker: ImagePicker(),
    fileStore: ref.watch(vaultFileStoreProvider),
    thumbnails: ref.watch(thumbnailServiceProvider),
  ),
);

/// Progress callback: [done] of [total] photos imported so far.
typedef ImportProgress = void Function(int done, int total);

/// Picks photos from the system gallery and imports them into the vault,
/// encrypting each file and generating an encrypted thumbnail.
///
/// Picking uses `image_picker`, which routes through the Android system
/// Photo Picker (API 33+) and iOS `PHPicker` — neither requires a runtime
/// permission, so the vault never has to request photo access. The picker
/// hands us a private temp copy of each selection; we encrypt it into the
/// vault and delete that temp copy. Removing the original from the device
/// gallery is intentionally NOT done here: the privacy-preserving picker
/// grants no delete rights, and requesting full media-management access
/// would defeat the point of a discreet vault. See README.
class PhotoImportService {
  PhotoImportService({
    required ImagePicker picker,
    required VaultFileStore fileStore,
    required ThumbnailService thumbnails,
  })  : _picker = picker,
        _fileStore = fileStore,
        _thumbnails = thumbnails;

  static const String _tag = 'PhotoImport';

  final ImagePicker _picker;
  final VaultFileStore _fileStore;
  final ThumbnailService _thumbnails;
  final Uuid _uuid = const Uuid();

  /// Opens the gallery, imports each chosen photo, and returns the created
  /// vault items. Returns an empty list if the user cancels.
  Future<List<VaultItem>> pickAndImport({ImportProgress? onProgress}) async {
    final List<XFile> picked;
    try {
      picked = await _picker.pickMultiImage();
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'picker failed', e, st);
      throw const PermissionException('Could not open the photo picker.');
    }
    if (picked.isEmpty) return const <VaultItem>[];

    final List<VaultItem> imported = <VaultItem>[];
    for (int i = 0; i < picked.length; i++) {
      onProgress?.call(i, picked.length);
      final XFile file = picked[i];
      try {
        imported.add(await _importOne(file));
      } on AppException catch (e) {
        AppLogger.error(_tag, 'skipping ${file.name}', e);
      } finally {
        // Remove the picker's temporary copy regardless of outcome.
        try {
          await File(file.path).delete();
        } on FileSystemException {
          // Best effort; the OS cleans its cache anyway.
        }
      }
    }
    onProgress?.call(picked.length, picked.length);
    return imported;
  }

  Future<VaultItem> _importOne(XFile file) async {
    final String id = _uuid.v4();
    final VaultFileRef ref =
        await _fileStore.importFile(file.path, category: 'photos');

    String? thumbnailPath;
    try {
      final thumbBytes = await _thumbnails.generate(file.path);
      thumbnailPath = await _fileStore.writeThumbnail(id, thumbBytes);
    } on AppException catch (e) {
      // A thumbnail failure must not fail the whole import; the grid falls
      // back to a placeholder icon for this item.
      AppLogger.error(_tag, 'thumbnail failed for ${file.name}', e);
    }

    final DateTime now = DateTime.now();
    return VaultItem(
      id: id,
      type: VaultItemType.photo,
      name: _fileName(file),
      relativePath: ref.relativePath,
      thumbnailPath: thumbnailPath,
      byteLength: ref.byteLength,
      mimeType: file.mimeType ?? _mimeFromName(file.name),
      createdAt: now,
      updatedAt: now,
    );
  }

  String _fileName(XFile file) {
    final String raw = file.name.isNotEmpty
        ? file.name
        : file.path.split(RegExp(r'[/\\]')).last;
    return raw.isEmpty ? 'Photo' : raw;
  }

  String _mimeFromName(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }
}
