import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/vault_file_store.dart';
import '../../../core/utils/app_logger.dart';
import '../../vault/application/vault_items_controller.dart';
import '../../vault/domain/vault_item.dart';

/// All non-trashed videos (pinned first, newest first).
final videoItemsProvider = Provider<List<VaultItem>>((ref) {
  return ref
      .watch(activeItemsProvider)
      .where((VaultItem i) => i.type == VaultItemType.video)
      .toList();
});

/// Decrypted poster-frame bytes for a video thumbnail path. Kept alive so
/// scrolling the grid does not repeatedly decrypt the same poster.
final videoPosterProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, thumbPath) {
  ref.keepAlive();
  return ref.watch(vaultFileStoreProvider).readThumbnail(thumbPath);
});

/// Saved playback position for a video, decoded from its encrypted payload.
///
/// Stored in [VaultItem.payload] as small JSON so resume survives app
/// restarts without a separate store.
class VideoProgress {
  const VideoProgress({required this.positionMs});

  final int positionMs;

  /// Parses progress out of an item's payload; defaults to 0.
  static int positionMsOf(VaultItem item) {
    final String? payload = item.payload;
    if (payload == null || payload.isEmpty) return 0;
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map && decoded['posMs'] is int) {
        return decoded['posMs'] as int;
      }
    } on FormatException catch (e) {
      AppLogger.error('VideoProgress', 'bad payload', e);
    }
    return 0;
  }

  /// Encodes a position into a payload string.
  static String encode(int positionMs) =>
      jsonEncode(<String, int>{'posMs': positionMs});

  /// Whether [positionMs] is far enough into a clip of [durationMs] to be
  /// worth resuming (past 5s, before the last 5%).
  static bool shouldResume(int positionMs, int durationMs) {
    if (positionMs < 5000 || durationMs <= 0) return false;
    return positionMs < (durationMs * 0.95);
  }
}
