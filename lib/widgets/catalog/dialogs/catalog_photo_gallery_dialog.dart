import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/auth/staff.dart';
import '../../../core/catalog/catalog_image.dart';
import '../../../core/catalog/catalog_media_service.dart';
import '../../../core/theme/theme.dart';

/// Modal dialog allowing Managers to view, upload, designate primary,
/// and delete catalog photos for a menu item or deal.
class CatalogPhotoGalleryDialog extends StatefulWidget {
  const CatalogPhotoGalleryDialog({
    super.key,
    required this.mediaService,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    this.currentStaff,
    this.initialImages,
  });

  final CatalogMediaService mediaService;
  final String entityType;
  final int entityId;
  final String entityName;
  final Staff? currentStaff;
  final List<CatalogImage>? initialImages;

  @override
  State<CatalogPhotoGalleryDialog> createState() => _CatalogPhotoGalleryDialogState();
}

class _CatalogPhotoGalleryDialogState extends State<CatalogPhotoGalleryDialog> {
  bool _isLoading = true;
  List<CatalogImage> _images = [];
  String? _errorMessage;

  // Add photo form state
  bool _showAddForm = false;
  final TextEditingController _filePathController = TextEditingController();
  bool _makePrimaryOnUpload = false;
  bool _isUploading = false;

  // 1x1 Transparent PNG for sample upload in testing/demo environments
  static const List<int> samplePngBytes = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialImages != null) {
      _images = List.from(widget.initialImages!);
      _isLoading = false;
    } else {
      _loadImages();
    }
  }

  @override
  void dispose() {
    _filePathController.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final list = await widget.mediaService.getImagesForEntity(
        widget.entityType,
        widget.entityId,
        activeOnly: true,
      );
      if (mounted) {
        setState(() {
          _images = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setPrimary(CatalogImage image) async {
    try {
      await widget.mediaService.setPrimaryImage(
        image.id,
        staff: widget.currentStaff,
      );
      await _loadImages();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _deleteImage(CatalogImage image) async {
    try {
      await widget.mediaService.deleteImage(
        image.id,
        staff: widget.currentStaff,
        permanent: false,
      );
      await _loadImages();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _handleUpload({List<int>? explicitBytes, String? explicitName}) async {
    setState(() => _isUploading = true);
    try {
      List<int> bytes;
      String fileName;

      if (explicitBytes != null) {
        bytes = explicitBytes;
        fileName = explicitName ?? 'uploaded_image.png';
      } else {
        final rawPath = _filePathController.text.trim();
        if (rawPath.isEmpty) {
          throw ArgumentError('Please enter a valid image file path or use sample.');
        }
        final file = File(rawPath);
        if (!await file.exists()) {
          throw ArgumentError('File not found at path: $rawPath');
        }
        bytes = await file.readAsBytes();
        fileName = file.uri.pathSegments.last;
      }

      await widget.mediaService.saveImage(
        staff: widget.currentStaff,
        entityType: widget.entityType,
        entityId: widget.entityId,
        bytes: bytes,
        originalFileName: fileName,
        isPrimary: _makePrimaryOnUpload ? true : null,
      );

      _filePathController.clear();
      _makePrimaryOnUpload = false;
      _showAddForm = false;
      await _loadImages();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: WarmCounterColors.lightDestructiveAction,
      ),
    );
  }

  Widget _buildThumbnailPreview(File file) {
    const fallback = Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: WarmCounterColors.lightSecondaryText,
        size: 32,
      ),
    );
    try {
      if (!file.existsSync()) return fallback;
      final bytes = file.readAsBytesSync();
      return Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }

  Widget _buildImageTile(CatalogImage image) {
    final file = widget.mediaService.resolveFile(image.relativeFilePath);

    return Container(
      key: ValueKey('gallery_image_tile_${image.id}'),
      margin: const EdgeInsets.only(bottom: WarmCounterSpacing.space12),
      padding: const EdgeInsets.all(WarmCounterSpacing.space12),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: image.isPrimary
              ? WarmCounterColors.lightPrimaryAction
              : WarmCounterColors.lightBorder,
          width: image.isPrimary ? 2.0 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Thumbnail Preview
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 72,
              height: 72,
              color: WarmCounterColors.lightSurfaceMuted,
              child: _buildThumbnailPreview(file),
            ),
          ),
          const SizedBox(width: WarmCounterSpacing.space16),

          // Metadata & Primary Tag
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (image.isPrimary)
                      Container(
                        key: ValueKey('primary_badge_${image.id}'),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: WarmCounterColors.lightPrimaryAction,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PRIMARY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        image.relativeFilePath.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Format: ${image.contentType ?? "unknown"} | ${((image.byteCount ?? 0) / 1024).toStringAsFixed(1)} KB',
                  style: WarmCounterTypography.caption.copyWith(
                    color: WarmCounterColors.lightSecondaryText,
                  ),
                ),
                if (image.sha256Checksum != null && image.sha256Checksum!.isNotEmpty)
                  Text(
                    'SHA256: ${image.sha256Checksum!.substring(0, 12)}...',
                    style: WarmCounterTypography.caption.copyWith(
                      color: WarmCounterColors.lightSecondaryText,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!image.isPrimary)
                OutlinedButton.icon(
                  key: ValueKey('set_primary_image_${image.id}'),
                  icon: const Icon(Icons.star_outline, size: 16),
                  label: const Text('Make Primary'),
                  onPressed: () => _setPrimary(image),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WarmCounterColors.lightPrimaryAction,
                    side: const BorderSide(color: WarmCounterColors.lightPrimaryAction),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                key: ValueKey('delete_image_${image.id}'),
                icon: const Icon(
                  Icons.delete_outline,
                  color: WarmCounterColors.lightDestructiveAction,
                  size: 20,
                ),
                tooltip: 'Delete Photo',
                onPressed: () => _deleteImage(image),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoSection() {
    return Container(
      key: const ValueKey('add_photo_form_container'),
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      margin: const EdgeInsets.only(bottom: WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightSurfaceMuted,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload New Photo',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('image_file_path_input'),
            controller: _filePathController,
            decoration: const InputDecoration(
              labelText: 'Local Image File Path',
              hintText: r'C:\images\dish.jpg',
              prefixIcon: Icon(Icons.file_upload_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                key: const ValueKey('is_primary_checkbox'),
                value: _makePrimaryOnUpload,
                onChanged: (val) => setState(() => _makePrimaryOnUpload = val ?? false),
              ),
              const Text('Designate as primary thumbnail'),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('add_sample_photo_button'),
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: const Text('Upload Sample PNG'),
                onPressed: _isUploading
                    ? null
                    : () => _handleUpload(
                          explicitBytes: samplePngBytes,
                          explicitName: 'sample_${widget.entityType}.png',
                        ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const ValueKey('save_photo_button'),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_isUploading ? 'Uploading...' : 'Save Photo'),
                onPressed: _isUploading ? null : () => _handleUpload(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entityLabel = widget.entityType == 'menu_item' ? 'Menu Item' : 'Deal';

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Photos: ${widget.entityName}', style: WarmCounterTypography.pageHeading),
                Text(
                  'Manage gallery and primary cashier thumbnail for this $entityLabel.',
                  style: WarmCounterTypography.caption.copyWith(
                    color: WarmCounterColors.lightSecondaryText,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            key: const ValueKey('open_add_photo_button'),
            icon: Icon(_showAddForm ? Icons.close : Icons.add_photo_alternate_outlined, size: 16),
            label: Text(_showAddForm ? 'Cancel Upload' : 'Add Photo'),
            onPressed: () => setState(() => _showAddForm = !_showAddForm),
            style: ElevatedButton.styleFrom(
              backgroundColor: _showAddForm
                  ? WarmCounterColors.lightSurfaceMuted
                  : WarmCounterColors.lightPrimaryAction,
              foregroundColor: _showAddForm
                  ? WarmCounterColors.lightSecondaryText
                  : Colors.white,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            if (_showAddForm) _buildAddPhotoSection(),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                margin: const EdgeInsets.only(bottom: WarmCounterSpacing.space12),
                color: const Color(0xFFFFEBEE),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: WarmCounterColors.lightDestructiveAction),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          value: 0.75,
                          strokeWidth: 2.5,
                          color: WarmCounterColors.lightPrimaryAction,
                        ),
                      ),
                    )
                  : _images.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.photo_library_outlined,
                                size: 48,
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No photos attached yet.',
                                style: WarmCounterTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Items and deals with valid recipes sell normally with 0 photos.',
                                style: WarmCounterTypography.caption.copyWith(
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _images.length,
                          itemBuilder: (context, index) => _buildImageTile(_images[index]),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('close_photo_gallery_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
