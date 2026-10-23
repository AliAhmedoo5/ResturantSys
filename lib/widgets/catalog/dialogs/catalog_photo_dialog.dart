import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/auth/staff.dart';
import '../../../core/catalog/catalog_media_service.dart';
import '../../../core/catalog/catalog_photo_change.dart';
import '../catalog_photo_field.dart';

/// Edits the one photo for an existing Menu Item or Deal.
class CatalogPhotoDialog extends StatefulWidget {
  const CatalogPhotoDialog({
    super.key,
    required this.mediaService,
    required this.entityType,
    required this.entityId,
    required this.entityName,
    this.currentStaff,
    this.imageBuilder,
  });

  final CatalogMediaService mediaService;
  final String entityType;
  final int entityId;
  final String entityName;
  final Staff? currentStaff;
  final Widget Function(BuildContext context, File file)? imageBuilder;

  @override
  State<CatalogPhotoDialog> createState() => _CatalogPhotoDialogState();
}

class _CatalogPhotoDialogState extends State<CatalogPhotoDialog> {
  CatalogPhotoChange? _change;
  bool _busy = true;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_busy || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.mediaService.saveEntityWithPhoto(
        entityType: widget.entityType,
        staff: widget.currentStaff,
        photoChange: _change,
        saveEntity: (_) async => widget.entityId,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the picture. Your previous picture is unchanged. Please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('Picture: ${widget.entityName}'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            CatalogPhotoField(
              mediaService: widget.mediaService,
              entityType: widget.entityType,
              entityId: widget.entityId,
              enabled: !_saving,
              imageBuilder: widget.imageBuilder,
              onChanged: (change) => _change = change,
              onBusyChanged: (busy) { if (mounted) setState(() => _busy = busy); },
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('save_catalog_picture'),
            onPressed: _saving || _busy ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
