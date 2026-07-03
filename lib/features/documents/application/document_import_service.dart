import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../vault/domain/vault_item.dart';

final documentImportServiceProvider = Provider<DocumentImportService>(
  (ref) => DocumentImportService(
    fileStore: ref.watch(vaultFileStoreProvider),
  ),
);

typedef DocImportProgress = void Function(int done, int total);

/// Picks arbitrary files from device storage and imports them into the
/// vault, encrypting each. Picking uses the system document picker (Storage
/// Access Framework on Android / document picker on iOS) via `file_picker`,
/// which grants scoped, one-shot read access — no broad storage permission.
class DocumentImportService {
  DocumentImportService({required VaultFileStore fileStore})
      : _fileStore = fileStore;

  static const String _tag = 'DocImport';

  final VaultFileStore _fileStore;
  final Uuid _uuid = const Uuid();

  /// Opens the picker, imports each chosen file, returns the created items.
  /// Empty list on cancel.
  Future<List<VaultItem>> pickAndImport({DocImportProgress? onProgress}) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } on Exception catch (e, st) {
      AppLogger.error(_tag, 'picker failed', e, st);
      throw const PermissionException('Could not open the file picker.');
    }
    if (result == null || result.files.isEmpty) return const <VaultItem>[];

    final List<PlatformFile> files = result.files;
    final List<VaultItem> imported = <VaultItem>[];
    for (int i = 0; i < files.length; i++) {
      onProgress?.call(i, files.length);
      final PlatformFile file = files[i];
      final String? path = file.path;
      if (path == null) {
        AppLogger.error(_tag, 'no path for ${file.name}');
        continue;
      }
      try {
        imported.add(await _importOne(file, path));
      } on AppException catch (e) {
        AppLogger.error(_tag, 'skipping ${file.name}', e);
      }
      // file_picker caches picked files in a temp dir; clean our copy.
      try {
        await File(path).delete();
      } on FileSystemException {
        // Best effort.
      }
    }
    onProgress?.call(files.length, files.length);
    return imported;
  }

  Future<VaultItem> _importOne(PlatformFile file, String path) async {
    final String id = _uuid.v4();
    final VaultFileRef ref =
        await _fileStore.importFile(path, category: 'documents');
    final DateTime now = DateTime.now();
    return VaultItem(
      id: id,
      type: VaultItemType.document,
      name: file.name.isEmpty ? 'Document' : file.name,
      relativePath: ref.relativePath,
      byteLength: ref.byteLength,
      mimeType: _mimeFor(file.extension),
      createdAt: now,
      updatedAt: now,
    );
  }

  String? _mimeFor(String? extension) {
    if (extension == null) return null;
    return switch (extension.toLowerCase()) {
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'md' || 'markdown' => 'text/markdown',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => null,
    };
  }
}

