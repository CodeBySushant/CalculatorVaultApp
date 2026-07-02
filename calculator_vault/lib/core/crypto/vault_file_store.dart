import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';
import '../utils/app_logger.dart';
import 'crypto_service.dart';
import 'key_manager.dart';

/// Overridden in `main()` with directories from `path_provider`. Reading it
/// without the override is a programmer error.
final vaultFileStoreProvider = Provider<VaultFileStore>(
  (ref) => throw StateError(
    'vaultFileStoreProvider must be overridden in main()',
  ),
);

/// Reference to an encrypted file inside the vault store.
class VaultFileRef {
  const VaultFileRef({
    required this.id,
    required this.relativePath,
    required this.byteLength,
    required this.category,
  });

  /// UUID, also the on-disk file name stem.
  final String id;

  /// Path relative to the vault base directory, e.g. `photos/<id>.cvlt`.
  final String relativePath;

  /// Original plaintext size in bytes.
  final int byteLength;

  /// Content category folder (`photos`, `videos`, `documents`, ...).
  final String category;
}

/// Owns the encrypted files on disk.
///
/// Layout: `<appDocs>/vault/<category>/<uuid>.cvlt`, all in the app-private
/// sandbox (never visible to the system gallery or other apps). Temporary
/// decrypted files (video playback, sharing) live under a dedicated temp
/// folder that [clearTemp] wipes whenever the session leaves the unlocked
/// state.
class VaultFileStore {
  VaultFileStore({
    required this.baseDir,
    required this.tempDir,
    required KeyManager keyManager,
    CryptoService? crypto,
  })  : _keyManager = keyManager,
        _crypto = crypto ?? CryptoService();

  static const String _tag = 'VaultFileStore';

  final Directory baseDir;
  final Directory tempDir;
  final KeyManager _keyManager;
  final CryptoService _crypto;
  final Uuid _uuid = const Uuid();

  String absolutePath(String relativePath) => '${baseDir.path}/$relativePath';

  /// Encrypts [sourcePath] into the vault. With [deleteSource] the original
  /// is removed after a successful import (move-into-vault semantics).
  Future<VaultFileRef> importFile(
    String sourcePath, {
    required String category,
    bool deleteSource = false,
  }) async {
    final File source = File(sourcePath);
    final int size;
    try {
      size = await source.length();
    } on FileSystemException catch (e) {
      throw StorageException('Could not read the selected file.', cause: e);
    }

    final String id = _uuid.v4();
    final String relativePath = '$category/$id.cvlt';
    final File dest = File(absolutePath(relativePath));
    await dest.parent.create(recursive: true);

    final SecretKey masterKey = await _keyManager.getMasterKey();
    try {
      await _crypto.encryptFile(
        sourcePath: sourcePath,
        destPath: dest.path,
        masterKey: masterKey,
      );
    } on AppException {
      // Never leave a half-written vault file behind.
      if (await dest.exists()) await dest.delete();
      rethrow;
    }

    if (deleteSource) {
      try {
        await source.delete();
      } on FileSystemException catch (e) {
        AppLogger.error(_tag, 'could not delete source after import', e);
      }
    }
    return VaultFileRef(
      id: id,
      relativePath: relativePath,
      byteLength: size,
      category: category,
    );
  }

  /// Decrypts an entire file into memory (photos, documents).
  Future<Uint8List> readBytes(String relativePath) async {
    return _crypto.decryptFileToBytes(
      sourcePath: absolutePath(relativePath),
      masterKey: await _keyManager.getMasterKey(),
    );
  }

  /// Decrypts to a temp file for consumers that need a real path (video
  /// player, share sheet). Wiped by [clearTemp] on lock.
  Future<File> decryptToTempFile(
    String relativePath, {
    String extension = 'bin',
  }) async {
    await tempDir.create(recursive: true);
    final File temp = File('${tempDir.path}/${_uuid.v4()}.$extension');
    await _crypto.decryptFileToPath(
      sourcePath: absolutePath(relativePath),
      destPath: temp.path,
      masterKey: await _keyManager.getMasterKey(),
    );
    return temp;
  }

  /// Original plaintext size, read from the header without decrypting.
  Future<int> plaintextSize(String relativePath) =>
      _crypto.plaintextLength(absolutePath(relativePath));

  /// Encrypts small [bytes] (a thumbnail) as a one-shot blob under the
  /// master key and writes it to `thumbs/<id>.cvlt`. Returns the relative
  /// path. Thumbnails use blob (not envelope) encryption because they are
  /// tiny and always read whole.
  Future<String> writeThumbnail(String id, Uint8List bytes) async {
    final SecretKey masterKey = await _keyManager.getMasterKey();
    final Uint8List blob = await _crypto.encryptBlob(bytes, masterKey);
    final String relativePath = 'thumbs/$id.cvlt';
    final File file = File(absolutePath(relativePath));
    await file.parent.create(recursive: true);
    try {
      await file.writeAsBytes(blob, flush: true);
    } on FileSystemException catch (e) {
      throw StorageException('Could not write the thumbnail.', cause: e);
    }
    return relativePath;
  }

  /// Decrypts a thumbnail blob written by [writeThumbnail].
  Future<Uint8List> readThumbnail(String relativePath) async {
    final SecretKey masterKey = await _keyManager.getMasterKey();
    final Uint8List blob;
    try {
      blob = await File(absolutePath(relativePath)).readAsBytes();
    } on FileSystemException catch (e) {
      throw StorageException('Could not read the thumbnail.', cause: e);
    }
    return _crypto.decryptBlob(blob, masterKey);
  }

  /// Permanently deletes an encrypted file. Safe when already gone.
  Future<void> delete(String relativePath) async {
    final File file = File(absolutePath(relativePath));
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      throw StorageException('Could not delete the vault file.', cause: e);
    }
  }

  /// Wipes every temporary decrypted file. Called whenever the vault
  /// session leaves the unlocked state; never throws.
  Future<void> clearTemp() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException catch (e) {
      AppLogger.error(_tag, 'clearTemp failed', e);
    }
  }
}
