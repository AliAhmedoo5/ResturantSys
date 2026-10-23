import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/catalog/catalog_media_service.dart';
import '../../core/catalog/catalog_photo_change.dart';
import '../../core/theme/theme.dart';

/// Compact, single-picture input. Selection is staged until the owner is saved.
class CatalogPhotoField extends StatefulWidget {
  const CatalogPhotoField({
    super.key,
    this.mediaService,
    required this.entityType,
    this.entityId,
    required this.onChanged,
    required this.onBusyChanged,
    this.enabled = true,
    this.pickFile,
    this.imageBuilder,
  });

  final CatalogMediaService? mediaService;
  final String entityType;
  final int? entityId;
  final ValueChanged<CatalogPhotoChange?> onChanged;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  final Future<XFile?> Function()? pickFile;
  final Widget Function(BuildContext context, File file)? imageBuilder;

  @override
  State<CatalogPhotoField> createState() => _CatalogPhotoFieldState();
}

class _CatalogPhotoFieldState extends State<CatalogPhotoField> {
  CatalogPhotoChange? _change;
  File? _savedFile;
  bool _busy = false;
  bool _hovering = false;
  bool _loadFailed = false;
  String? _error;

  bool get _hasPhoto => _change == null ? _savedFile != null : _change!.bytes != null;
  bool get _enabled => widget.enabled && !_busy && !_loadFailed && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    if (widget.entityId != null && widget.mediaService != null) {
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSavedPhoto();
      });
    }
  }

  Future<void> _loadSavedPhoto() async {
    widget.onBusyChanged(true);
    setState(() {
      _busy = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final image = await widget.mediaService!.getPrimaryImage(widget.entityType, widget.entityId!);
      if (!mounted) return;
      setState(() {
        _savedFile = image == null ? null : widget.mediaService!.resolveFile(image.relativeFilePath);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _error = 'Could not load the saved picture. Retry before saving.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(_loadFailed);
      }
    }
  }

  Future<void> _browse() async {
    if (!_enabled) return;
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      final file = await (widget.pickFile?.call() ?? openFile(
        acceptedTypeGroups: const [XTypeGroup(
          label: 'Pictures',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          uniformTypeIdentifiers: ['public.jpeg', 'public.png', 'org.webmproject.webp'],
        )],
      ));
      if (file != null && mounted) await _validateAndStage(file);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the picture. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  Future<void> _drop(DropDoneDetails details) async {
    if (!_enabled) return;
    setState(() => _hovering = false);
    if (details.files.length != 1) {
      setState(() => _error = 'Choose one picture at a time.');
      return;
    }
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      await _validateAndStage(details.files.single);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  Future<void> _validateAndStage(XFile file) async {
    try {
      final name = file.name.toLowerCase();
      if (!['.jpg', '.jpeg', '.png', '.webp'].any(name.endsWith)) {
        throw const FormatException('Choose a JPEG, PNG or WebP picture.');
      }
      final size = await file.length();
      if (size == 0 || size > CatalogMediaService.defaultMaxFileSizeBytes) {
        throw const FormatException('Choose a non-empty picture up to 5 MB.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > CatalogMediaService.defaultMaxFileSizeBytes) {
        throw const FormatException('Choose a non-empty picture up to 5 MB.');
      }
      CatalogMediaService.validatePhotoBytes(bytes);
      // Decode before replacing the preview; a renamed or damaged file must
      // never displace a valid saved picture. Bound decoding to preview size.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160, targetHeight: 160);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted) return;
      final change = CatalogPhotoChange.replace(bytes: bytes, fileName: file.name);
      setState(() {
        _change = change;
        _error = null;
      });
      widget.onChanged(change);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'This picture could not be read. Choose a valid JPEG, PNG or WebP.');
    }
  }

  void _remove() {
    setState(() {
      _change = const CatalogPhotoChange.remove();
      _error = null;
    });
    widget.onChanged(_change);
  }

  Widget _preview() {
    const fallback = Icon(Icons.image_outlined, color: WarmCounterColors.lightSecondaryText);
    if (_change?.bytes != null) {
      return Image.memory(_change!.bytes!, fit: BoxFit.cover, cacheWidth: 160,
        errorBuilder: (_, error, stack) => fallback);
    }
    if (_hasPhoto && _savedFile != null) {
      return widget.imageBuilder?.call(context, _savedFile!) ?? Image.file(
        _savedFile!, fit: BoxFit.cover, cacheWidth: 160,
        errorBuilder: (_, error, stack) => fallback,
      );
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropTarget(
          key: const ValueKey('catalog_photo_drop_target'),
          enable: _enabled,
          onDragDone: _drop,
          onDragEntered: (_) { if (_enabled) setState(() => _hovering = true); },
          onDragExited: (_) {
            // Disabling a hovered target may also invoke this during rebuild.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _hovering) setState(() => _hovering = false);
            });
          },
          child: Material(
            color: WarmCounterColors.lightSurfaceMuted,
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            child: InkWell(
              key: const ValueKey('catalog_photo_browse'),
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              onTap: _enabled ? _browse : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  border: Border.all(color: _hovering
                      ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightBorder),
                ),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(width: 64, height: 64,
                      child: _busy ? const Center(child: SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))) : _preview()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_hovering ? 'Drop picture here' : _hasPhoto ? 'Change picture' : 'Add picture',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Text('Drag here or click to browse', style: WarmCounterTypography.caption),
                    const Text('JPEG, PNG, WebP · Up to 5 MB', style: WarmCounterTypography.caption),
                  ])),
                  if (_hasPhoto) IconButton(
                    key: const ValueKey('catalog_photo_remove'),
                    tooltip: 'Remove picture',
                    onPressed: _enabled ? _remove : null,
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(liveRegion: true, child: Text(_error!,
            style: const TextStyle(color: WarmCounterColors.lightDestructiveAction, fontSize: 12))),
        ),
        if (_loadFailed) TextButton(onPressed: _loadSavedPhoto, child: const Text('Retry picture')),
      ],
    );
  }
}
