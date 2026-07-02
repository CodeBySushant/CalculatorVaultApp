import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../core/errors/app_exception.dart';

final thumbnailServiceProvider =
    Provider<ThumbnailService>((_) => ThumbnailService());

/// Generates small, encrypted-later JPEG thumbnails from source images.
///
/// Decoding + resizing runs in a background isolate so importing large
/// photos never blocks the UI thread.
class ThumbnailService {
  /// Longest edge of the generated thumbnail, in pixels.
  static const int maxDimension = 400;
  static const int jpegQuality = 82;

  /// Produces JPEG thumbnail bytes for the image at [sourcePath].
  Future<Uint8List> generate(String sourcePath) {
    return Isolate.run(() => _generate(sourcePath));
  }
}

Uint8List _generate(String sourcePath) {
  final Uint8List bytes = File(sourcePath).readAsBytesSync();
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const UnknownException('This image format is not supported.');
  }

  // Bake in EXIF orientation so the thumbnail is displayed upright.
  final img.Image oriented = img.bakeOrientation(decoded);

  final img.Image resized = oriented.width >= oriented.height
      ? img.copyResize(oriented, width: ThumbnailService.maxDimension)
      : img.copyResize(oriented, height: ThumbnailService.maxDimension);

  return img.encodeJpg(resized, quality: ThumbnailService.jpegQuality);
}
