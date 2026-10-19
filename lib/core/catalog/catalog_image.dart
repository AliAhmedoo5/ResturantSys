/// Represents a catalog image attached to a menu item or deal.
class CatalogImage {
  const CatalogImage({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.relativeFilePath,
    this.thumbnailPath,
    this.contentType,
    this.byteCount,
    this.sha256Checksum,
    this.isPrimary = false,
    required this.createdAt,
    this.deletedAt,
  });

  final int id;

  /// Either 'menu_item' or 'deal'.
  final String entityType;

  /// Foreign key referencing the menu_items(id) or deals(id).
  final int entityId;

  /// Relative path under the media root directory (e.g. 'menu_items/10_12345.jpg').
  final String relativeFilePath;

  /// Optional relative path to a generated thumbnail.
  final String? thumbnailPath;

  /// MIME type (e.g. 'image/jpeg', 'image/png', 'image/webp').
  final String? contentType;

  /// File size in bytes.
  final int? byteCount;

  /// SHA-256 hex digest for integrity verification and deduplication.
  final String? sha256Checksum;

  /// True if this image is designated as the primary thumbnail for cashier grids.
  final bool isPrimary;

  final DateTime createdAt;
  final DateTime? deletedAt;

  bool get isActive => deletedAt == null;

  factory CatalogImage.fromMap(Map<String, Object?> map) {
    return CatalogImage(
      id: map['id'] as int,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int,
      relativeFilePath: map['relative_file_path'] as String,
      thumbnailPath: map['thumbnail_path'] as String?,
      contentType: map['content_type'] as String?,
      byteCount: map['byte_count'] as int?,
      sha256Checksum: map['sha256_checksum'] as String?,
      isPrimary: (map['is_primary'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      deletedAt: map['deleted_at'] != null
          ? DateTime.tryParse(map['deleted_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'relative_file_path': relativeFilePath,
      'thumbnail_path': thumbnailPath,
      'content_type': contentType,
      'byte_count': byteCount,
      'sha256_checksum': sha256Checksum,
      'is_primary': isPrimary ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  CatalogImage copyWith({
    int? id,
    String? entityType,
    int? entityId,
    String? relativeFilePath,
    String? thumbnailPath,
    String? contentType,
    int? byteCount,
    String? sha256Checksum,
    bool? isPrimary,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return CatalogImage(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      relativeFilePath: relativeFilePath ?? this.relativeFilePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      contentType: contentType ?? this.contentType,
      byteCount: byteCount ?? this.byteCount,
      sha256Checksum: sha256Checksum ?? this.sha256Checksum,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
