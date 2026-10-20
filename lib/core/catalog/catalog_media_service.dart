import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/staff.dart';
import '../auth/staff_role.dart';
import '../database/pos_database_constants.dart';
import 'catalog_image.dart';

/// Service managing catalog image persistence, checksum verification,
/// relative filesystem storage, and primary thumbnail designations.
class CatalogMediaService {
  CatalogMediaService({
    required this.database,
    String? baseDirectoryPath,
  }) : baseDirectoryPath = baseDirectoryPath ?? defaultBaseDirectoryPath();

  final Database database;
  final String baseDirectoryPath;

  /// Default maximum allowable image upload size (5 MB).
  static const int defaultMaxFileSizeBytes = 5 * 1024 * 1024;

  /// Default Windows %ProgramData%\ResturantPOS\media directory,
  /// falling back to user home directory or system temp on non-Windows.
  static String defaultBaseDirectoryPath() {
    if (Platform.isWindows) {
      final programData = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
      return '$programData\\${PosDatabaseConstants.defaultProgramDataFolder}\\media';
    } else {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return p.join(home, '.resturant_pos', 'media');
    }
  }

  /// Resolves a relative file path from the database to an absolute filesystem path.
  String resolveAbsolutePath(String relativePath) {
    final normalized = relativePath.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator);
    return p.normalize(p.join(baseDirectoryPath, normalized));
  }

  /// Resolves a relative file path to a [File] handle.
  File resolveFile(String relativePath) {
    return File(resolveAbsolutePath(relativePath));
  }

  void _verifyManagerRole(Staff? staff) {
    if (staff != null && staff.role == StaffRole.cashier) {
      throw StateError('Cashiers are not permitted to manage catalog media.');
    }
  }

  String _detectContentType(List<int> bytes, String originalFileName) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    final lower = originalFileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }

    throw ArgumentError(
      'Unsupported or corrupted image format. Only JPEG, PNG, and WebP are supported.',
    );
  }

  String _extensionForContentType(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }

  /// Safely stores image bytes on the local filesystem and records metadata in the database.
  Future<CatalogImage> saveImage({
    Staff? staff,
    required String entityType,
    required int entityId,
    required List<int> bytes,
    required String originalFileName,
    bool? isPrimary,
    int maxFileSizeBytes = defaultMaxFileSizeBytes,
  }) async {
    _verifyManagerRole(staff);

    if (entityType != 'menu_item' && entityType != 'deal') {
      throw ArgumentError("entityType must be 'menu_item' or 'deal', received '$entityType'.");
    }

    if (bytes.isEmpty) {
      throw ArgumentError('Image file cannot be empty.');
    }

    if (bytes.length > maxFileSizeBytes) {
      throw ArgumentError(
        'Image file (${bytes.length} bytes) exceeds maximum allowed size of ${maxFileSizeBytes ~/ (1024 * 1024)}MB.',
      );
    }

    final contentType = _detectContentType(bytes, originalFileName);
    final ext = _extensionForContentType(contentType);
    final checksum = sha256.convert(bytes).toString();

    final subfolder = entityType == 'menu_item' ? 'menu_items' : 'deals';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final shortHash = checksum.length >= 8 ? checksum.substring(0, 8) : checksum;
    final fileName = '${entityType}_${entityId}_${timestamp}_$shortHash.$ext';
    final relativePath = '$subfolder/$fileName';

    // Persist file safely to disk
    final targetFile = resolveFile(relativePath);
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(bytes, flush: true);

    // Database insertion wrapped in transaction
    return await database.transaction((txn) async {
      final existingActive = await txn.query(
        PosDatabaseConstants.tableCatalogImages,
        where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
        whereArgs: [entityType, entityId],
      );

      final designatePrimary = isPrimary ?? existingActive.isEmpty;

      if (designatePrimary) {
        await txn.update(
          PosDatabaseConstants.tableCatalogImages,
          {'is_primary': 0},
          where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
          whereArgs: [entityType, entityId],
        );
      }

      final now = DateTime.now().toIso8601String();
      final id = await txn.insert(
        PosDatabaseConstants.tableCatalogImages,
        {
          'entity_type': entityType,
          'entity_id': entityId,
          'relative_file_path': relativePath,
          'thumbnail_path': relativePath,
          'content_type': contentType,
          'byte_count': bytes.length,
          'sha256_checksum': checksum,
          'is_primary': designatePrimary ? 1 : 0,
          'created_at': now,
        },
      );

      return CatalogImage(
        id: id,
        entityType: entityType,
        entityId: entityId,
        relativeFilePath: relativePath,
        thumbnailPath: relativePath,
        contentType: contentType,
        byteCount: bytes.length,
        sha256Checksum: checksum,
        isPrimary: designatePrimary,
        createdAt: DateTime.parse(now),
      );
    });
  }

  /// Lists all images associated with an entity, ordered with primary first.
  Future<List<CatalogImage>> getImagesForEntity(
    String entityType,
    int entityId, {
    bool activeOnly = true,
  }) async {
    final whereConditions = ['entity_type = ?', 'entity_id = ?'];
    final whereArgs = <Object?>[entityType, entityId];

    if (activeOnly) {
      whereConditions.add('deleted_at IS NULL');
    }

    final rows = await database.query(
      PosDatabaseConstants.tableCatalogImages,
      where: whereConditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'is_primary DESC, id ASC',
    );

    return rows.map((r) => CatalogImage.fromMap(r)).toList();
  }

  /// Retrieves the active primary image for an entity.
  Future<CatalogImage?> getPrimaryImage(String entityType, int entityId) async {
    // 1. Check designated primary
    final primaryRows = await database.query(
      PosDatabaseConstants.tableCatalogImages,
      where: 'entity_type = ? AND entity_id = ? AND is_primary = 1 AND deleted_at IS NULL',
      whereArgs: [entityType, entityId],
      limit: 1,
    );

    if (primaryRows.isNotEmpty) {
      return CatalogImage.fromMap(primaryRows.first);
    }

    // 2. Fallback to oldest active image if none explicitly marked primary
    final fallbackRows = await database.query(
      PosDatabaseConstants.tableCatalogImages,
      where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
      whereArgs: [entityType, entityId],
      orderBy: 'id ASC',
      limit: 1,
    );

    if (fallbackRows.isNotEmpty) {
      return CatalogImage.fromMap(fallbackRows.first);
    }

    return null;
  }

  /// Retrieves primary images for all entities of [entityType], mapped by entity_id.
  Future<Map<int, CatalogImage>> getPrimaryImagesForEntities(String entityType) async {
    final rows = await database.query(
      PosDatabaseConstants.tableCatalogImages,
      where: 'entity_type = ? AND is_primary = 1 AND deleted_at IS NULL',
      whereArgs: [entityType],
    );

    final map = <int, CatalogImage>{};
    for (final r in rows) {
      final img = CatalogImage.fromMap(r);
      map[img.entityId] = img;
    }
    return map;
  }

  /// Designates an image as primary, demoting any existing primary image for that entity.
  Future<void> setPrimaryImage(int imageId, {Staff? staff}) async {
    _verifyManagerRole(staff);

    await database.transaction((txn) async {
      final rows = await txn.query(
        PosDatabaseConstants.tableCatalogImages,
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [imageId],
      );

      if (rows.isEmpty) {
        throw StateError('Image with ID $imageId not found or deleted.');
      }

      final img = CatalogImage.fromMap(rows.first);

      // Unset existing primary images for this entity
      await txn.update(
        PosDatabaseConstants.tableCatalogImages,
        {'is_primary': 0},
        where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
        whereArgs: [img.entityType, img.entityId],
      );

      // Set target image as primary
      await txn.update(
        PosDatabaseConstants.tableCatalogImages,
        {'is_primary': 1},
        where: 'id = ?',
        whereArgs: [imageId],
      );
    });
  }

  /// Deletes or deactivates an image.
  /// If [permanent] is true, deletes DB record and local file from disk.
  /// Otherwise performs a soft-delete by setting [deleted_at].
  Future<void> deleteImage(
    int imageId, {
    Staff? staff,
    bool permanent = false,
  }) async {
    _verifyManagerRole(staff);

    CatalogImage? imageToDelete;

    await database.transaction((txn) async {
      final rows = await txn.query(
        PosDatabaseConstants.tableCatalogImages,
        where: 'id = ?',
        whereArgs: [imageId],
      );

      if (rows.isEmpty) return;
      imageToDelete = CatalogImage.fromMap(rows.first);

      if (permanent) {
        await txn.delete(
          PosDatabaseConstants.tableCatalogImages,
          where: 'id = ?',
          whereArgs: [imageId],
        );
      } else {
        await txn.update(
          PosDatabaseConstants.tableCatalogImages,
          {
            'deleted_at': DateTime.now().toIso8601String(),
            'is_primary': 0,
          },
          where: 'id = ?',
          whereArgs: [imageId],
        );
      }

      // If the deleted image was primary, designate another active image as primary
      if (imageToDelete!.isPrimary) {
        final remainingRows = await txn.query(
          PosDatabaseConstants.tableCatalogImages,
          where: 'entity_type = ? AND entity_id = ? AND deleted_at IS NULL AND id != ?',
          whereArgs: [imageToDelete!.entityType, imageToDelete!.entityId, imageId],
          orderBy: 'id ASC',
          limit: 1,
        );

        if (remainingRows.isNotEmpty) {
          final nextPrimaryId = remainingRows.first['id'] as int;
          await txn.update(
            PosDatabaseConstants.tableCatalogImages,
            {'is_primary': 1},
            where: 'id = ?',
            whereArgs: [nextPrimaryId],
          );
        }
      }
    });

    if (permanent && imageToDelete != null) {
      try {
        final file = resolveFile(imageToDelete!.relativeFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Suppress filesystem removal errors during DB deletion
      }
    }
  }
}
