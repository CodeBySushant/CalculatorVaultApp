/// Content categories stored in the vault.
enum VaultItemType { photo, video, document, note, password, voiceNote }

/// Metadata for a single vault item.
///
/// This is the decrypted, in-memory representation. At rest (Hive) the
/// [name] and [payload] fields are AES-256-GCM encrypted — see
/// `VaultItemRepository`.
class VaultItem {
  const VaultItem({
    required this.id,
    required this.type,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.relativePath,
    this.thumbnailPath,
    this.byteLength = 0,
    this.folderId,
    this.favorite = false,
    this.pinned = false,
    this.trashedAt,
    this.mimeType,
    this.payload,
  });

  /// UUID; for file-backed items it matches the encrypted file name stem.
  final String id;

  final VaultItemType type;

  /// Display name (file name, note title, password entry title).
  final String name;

  /// Location of the encrypted file inside the vault store; null for
  /// record-only items (notes, passwords).
  final String? relativePath;

  /// Location of the encrypted thumbnail blob; null when there is no
  /// thumbnail (documents, notes, passwords).
  final String? thumbnailPath;

  /// Original plaintext size in bytes (0 for record-only items).
  final int byteLength;

  /// Folder/album the item belongs to; null = root.
  final String? folderId;

  final DateTime createdAt;
  final DateTime updatedAt;

  final bool favorite;

  /// Pinned items sort before everything else in their list.
  final bool pinned;

  /// When non-null the item is in the trash (auto-purged after 30 days).
  final DateTime? trashedAt;

  final String? mimeType;

  /// Encrypted-at-rest structured content (note body, password record).
  final String? payload;

  bool get isTrashed => trashedAt != null;

  VaultItem copyWith({
    String? name,
    String? relativePath,
    String? thumbnailPath,
    int? byteLength,
    String? folderId,
    DateTime? updatedAt,
    bool? favorite,
    bool? pinned,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    String? mimeType,
    String? payload,
  }) {
    return VaultItem(
      id: id,
      type: type,
      name: name ?? this.name,
      relativePath: relativePath ?? this.relativePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      byteLength: byteLength ?? this.byteLength,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      favorite: favorite ?? this.favorite,
      pinned: pinned ?? this.pinned,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      mimeType: mimeType ?? this.mimeType,
      payload: payload ?? this.payload,
    );
  }
}
