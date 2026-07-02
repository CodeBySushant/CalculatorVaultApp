import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exception.dart';

/// Shared stateless instance for the whole app.
final cryptoServiceProvider = Provider<CryptoService>((_) => CryptoService());

/// AES-256-GCM encryption for the vault.
///
/// Two shapes of data:
///
/// **Blobs** (notes, passwords, metadata, wrapped keys) — one-shot AES-GCM:
/// `[version:1][nonce:12][mac:16][ciphertext]`.
///
/// **Files** (photos, videos, documents) — envelope encryption with a
/// per-file random data key wrapped by the master key, and the payload
/// encrypted in independent chunks so arbitrarily large files stream with
/// bounded memory. Heavy work runs in a background isolate.
///
/// File format `CVL1`:
/// ```
/// magic 'CVL1'            4 bytes
/// wrappedKeyLen           2 bytes (big-endian)
/// wrappedKey              blob-encrypted 32-byte data key
/// plaintextLength         8 bytes (big-endian)
/// noncePrefix             8 random bytes
/// chunks:                 repeated
///   cipherLen             4 bytes (big-endian)
///   mac                   16 bytes
///   ciphertext            cipherLen bytes
/// ```
/// Each chunk's 12-byte nonce is `noncePrefix + chunkIndex` — unique per
/// chunk, and any reordering, substitution, or truncation fails
/// authentication or the final length check.
class CryptoService {
  static const int blobVersion = 1;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int defaultChunkSize = 1024 * 1024; // 1 MiB plaintext chunks

  final AesGcm _aes = AesGcm.with256bits();

  /// Generates a fresh random 256-bit key.
  Future<SecretKey> newKey() => _aes.newSecretKey();

  // ---------------------------------------------------------------------
  // Blobs
  // ---------------------------------------------------------------------

  /// Encrypts [plain] into a self-contained blob.
  Future<Uint8List> encryptBlob(List<int> plain, SecretKey key) async {
    final SecretBox box = await _aes.encrypt(plain, secretKey: key);
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..addByte(blobVersion)
      ..add(box.nonce)
      ..add(box.mac.bytes)
      ..add(box.cipherText);
    return builder.toBytes();
  }

  /// Decrypts a blob produced by [encryptBlob].
  ///
  /// Throws [EncryptionException] on tampering or a wrong key.
  Future<Uint8List> decryptBlob(Uint8List blob, SecretKey key) async {
    const int headerLength = 1 + nonceLength + macLength;
    if (blob.length < headerLength || blob[0] != blobVersion) {
      throw const EncryptionException('This data is not a valid vault blob.');
    }
    final Uint8List nonce = blob.sublist(1, 1 + nonceLength);
    final Uint8List mac = blob.sublist(1 + nonceLength, headerLength);
    final Uint8List cipher = blob.sublist(headerLength);
    try {
      final List<int> clear = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError catch (e) {
      throw EncryptionException(
        'Decryption failed — the data may be corrupted.',
        cause: e,
      );
    }
  }

  /// Encrypts a string, returning base64 for storage in Hive.
  Future<String> encryptString(String plain, SecretKey key) async =>
      base64Encode(await encryptBlob(utf8.encode(plain), key));

  /// Decrypts a base64 blob back to a string.
  Future<String> decryptString(String encoded, SecretKey key) async {
    final Uint8List blob;
    try {
      blob = base64Decode(encoded);
    } on FormatException catch (e) {
      throw EncryptionException(
        'This data is not a valid vault blob.',
        cause: e,
      );
    }
    return utf8.decode(await decryptBlob(blob, key));
  }

  // ---------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------

  /// Encrypts the file at [sourcePath] into [destPath] using a fresh
  /// per-file data key wrapped by [masterKey]. Runs in an isolate.
  Future<void> encryptFile({
    required String sourcePath,
    required String destPath,
    required SecretKey masterKey,
    int chunkSize = defaultChunkSize,
  }) async {
    final SecretKey dataKey = await _aes.newSecretKey();
    final Uint8List dataKeyBytes =
        Uint8List.fromList(await dataKey.extractBytes());
    final Uint8List wrappedKey = await encryptBlob(dataKeyBytes, masterKey);
    try {
      await Isolate.run(
        () => _encryptFileImpl(
          sourcePath,
          destPath,
          dataKeyBytes,
          wrappedKey,
          chunkSize,
        ),
      );
    } on FileSystemException catch (e) {
      throw StorageException('Could not write the encrypted file.', cause: e);
    }
  }

  /// Decrypts an encrypted file fully into memory (photos, documents).
  Future<Uint8List> decryptFileToBytes({
    required String sourcePath,
    required SecretKey masterKey,
  }) async {
    final Uint8List dataKeyBytes = await _unwrapDataKey(sourcePath, masterKey);
    return Isolate.run(
      () => _decryptFileImpl(sourcePath, dataKeyBytes, destPath: null),
    ).then((Uint8List? bytes) => bytes!);
  }

  /// Decrypts an encrypted file to [destPath] on disk (video playback,
  /// export). Runs in an isolate with bounded memory.
  Future<void> decryptFileToPath({
    required String sourcePath,
    required String destPath,
    required SecretKey masterKey,
  }) async {
    final Uint8List dataKeyBytes = await _unwrapDataKey(sourcePath, masterKey);
    await Isolate.run(
      () => _decryptFileImpl(sourcePath, dataKeyBytes, destPath: destPath),
    );
  }

  /// Reads the original (plaintext) size from an encrypted file's header
  /// without decrypting anything.
  Future<int> plaintextLength(String sourcePath) async {
    final _FileHeader header = await _readHeader(sourcePath);
    return header.plaintextLength;
  }

  Future<Uint8List> _unwrapDataKey(
    String sourcePath,
    SecretKey masterKey,
  ) async {
    final _FileHeader header = await _readHeader(sourcePath);
    return decryptBlob(header.wrappedKey, masterKey);
  }

  Future<_FileHeader> _readHeader(String sourcePath) async {
    final RandomAccessFile file;
    try {
      file = await File(sourcePath).open();
    } on FileSystemException catch (e) {
      throw StorageException('Could not open the encrypted file.', cause: e);
    }
    try {
      return _parseHeader(file);
    } finally {
      await file.close();
    }
  }
}

// ---------------------------------------------------------------------------
// File format internals (top-level so they run inside Isolate.run).
// ---------------------------------------------------------------------------

const List<int> _magic = <int>[0x43, 0x56, 0x4C, 0x31]; // 'CVL1'
const int _noncePrefixLength = 8;

class _FileHeader {
  const _FileHeader({
    required this.wrappedKey,
    required this.plaintextLength,
    required this.noncePrefix,
    required this.headerLength,
  });

  final Uint8List wrappedKey;
  final int plaintextLength;
  final Uint8List noncePrefix;
  final int headerLength;
}

const EncryptionException _corrupt =
    EncryptionException('This vault file is corrupted or not a vault file.');

Uint8List _readExactSync(RandomAccessFile file, int length) {
  final Uint8List bytes = file.readSync(length);
  if (bytes.length != length) throw _corrupt;
  return bytes;
}

_FileHeader _parseHeader(RandomAccessFile file) {
  final Uint8List magic = _readExactSync(file, 4);
  for (int i = 0; i < 4; i++) {
    if (magic[i] != _magic[i]) throw _corrupt;
  }
  final int wrappedLen =
      ByteData.sublistView(_readExactSync(file, 2)).getUint16(0);
  final Uint8List wrappedKey = _readExactSync(file, wrappedLen);
  final int plaintextLength =
      ByteData.sublistView(_readExactSync(file, 8)).getUint64(0);
  final Uint8List noncePrefix = _readExactSync(file, _noncePrefixLength);
  return _FileHeader(
    wrappedKey: wrappedKey,
    plaintextLength: plaintextLength,
    noncePrefix: noncePrefix,
    headerLength: 4 + 2 + wrappedLen + 8 + _noncePrefixLength,
  );
}

Uint8List _chunkNonce(Uint8List prefix, int index) {
  final Uint8List nonce = Uint8List(CryptoService.nonceLength);
  nonce.setRange(0, _noncePrefixLength, prefix);
  ByteData.sublistView(nonce).setUint32(_noncePrefixLength, index);
  return nonce;
}

Future<void> _encryptFileImpl(
  String sourcePath,
  String destPath,
  Uint8List dataKeyBytes,
  Uint8List wrappedKey,
  int chunkSize,
) async {
  final AesGcm aes = AesGcm.with256bits();
  final SecretKey key = SecretKey(dataKeyBytes);
  final Random random = Random.secure();
  final Uint8List noncePrefix = Uint8List.fromList(
    List<int>.generate(_noncePrefixLength, (_) => random.nextInt(256)),
  );

  final RandomAccessFile input = File(sourcePath).openSync();
  final RandomAccessFile output = File(destPath).openSync(mode: FileMode.write);
  try {
    final int total = input.lengthSync();

    // Header.
    output.writeFromSync(_magic);
    final ByteData lenData = ByteData(2)..setUint16(0, wrappedKey.length);
    output.writeFromSync(lenData.buffer.asUint8List());
    output.writeFromSync(wrappedKey);
    final ByteData plainLenData = ByteData(8)..setUint64(0, total);
    output.writeFromSync(plainLenData.buffer.asUint8List());
    output.writeFromSync(noncePrefix);

    // Chunks.
    int index = 0;
    int remaining = total;
    while (remaining > 0) {
      final int take = remaining < chunkSize ? remaining : chunkSize;
      final Uint8List plain = _readExactSync(input, take);
      final SecretBox box = await aes.encrypt(
        plain,
        secretKey: key,
        nonce: _chunkNonce(noncePrefix, index),
      );
      final ByteData cipherLen = ByteData(4)
        ..setUint32(0, box.cipherText.length);
      output.writeFromSync(cipherLen.buffer.asUint8List());
      output.writeFromSync(box.mac.bytes);
      output.writeFromSync(box.cipherText);
      remaining -= take;
      index++;
    }
    output.flushSync();
  } finally {
    input.closeSync();
    output.closeSync();
  }
}

/// Decrypts to [destPath] when given, otherwise returns the plaintext bytes.
Future<Uint8List?> _decryptFileImpl(
  String sourcePath,
  Uint8List dataKeyBytes, {
  required String? destPath,
}) async {
  final AesGcm aes = AesGcm.with256bits();
  final SecretKey key = SecretKey(dataKeyBytes);

  final RandomAccessFile input = File(sourcePath).openSync();
  RandomAccessFile? output;
  final BytesBuilder? builder = destPath == null ? BytesBuilder() : null;
  try {
    final _FileHeader header = _parseHeader(input);
    if (destPath != null) {
      output = File(destPath).openSync(mode: FileMode.write);
    }

    final int fileLength = input.lengthSync();
    int produced = 0;
    int index = 0;
    while (input.positionSync() < fileLength) {
      final int cipherLen =
          ByteData.sublistView(_readExactSync(input, 4)).getUint32(0);
      final Uint8List mac = _readExactSync(input, CryptoService.macLength);
      final Uint8List cipher = _readExactSync(input, cipherLen);
      final List<int> plain;
      try {
        plain = await aes.decrypt(
          SecretBox(
            cipher,
            nonce: _chunkNonce(header.noncePrefix, index),
            mac: Mac(mac),
          ),
          secretKey: key,
        );
      } on SecretBoxAuthenticationError {
        throw const EncryptionException(
          'Decryption failed — the file may be corrupted.',
        );
      }
      produced += plain.length;
      if (output != null) {
        output.writeFromSync(plain);
      } else {
        builder!.add(plain);
      }
      index++;
    }

    if (produced != header.plaintextLength) {
      throw const EncryptionException(
        'Decryption failed — the file is incomplete.',
      );
    }
    output?.flushSync();
    return builder?.toBytes();
  } finally {
    input.closeSync();
    output?.closeSync();
  }
}
