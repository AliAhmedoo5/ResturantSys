import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/analytics/analytics_export_service.dart';
import '../../core/analytics/analytics_models.dart';

/// The native picker is the only UI boundary; all formats use the shown snapshot.
class AnalyticsExportActions extends StatefulWidget {
  const AnalyticsExportActions({
    super.key,
    required this.snapshot,
    required this.family,
    required this.canExport,
    this.pickDirectory,
    this.compact = false,
  });

  final AnalyticsSnapshot snapshot;
  final AnalyticsFamily family;
  final bool Function() canExport;
  final Future<String?> Function()? pickDirectory;
  final bool compact;

  @override
  State<AnalyticsExportActions> createState() => _AnalyticsExportActionsState();
}

class _AnalyticsExportActionsState extends State<AnalyticsExportActions> {
  bool _busy = false;
  String? _message;
  bool _failed = false;

  Future<void> _export(AnalyticsExportFormat format) async {
    if (_busy || !widget.canExport()) return;
    final canExport = widget.canExport;
    final snapshot = widget.snapshot;
    final family = widget.family;
    setState(() { _busy = true; _message = null; _failed = false; });
    try {
      final directory = await (widget.pickDirectory?.call() ?? getDirectoryPath());
      if (directory == null || !mounted || !canExport()) return;
      final file = await AnalyticsExportService().saveToDirectory(
        snapshot, family, format, directory,
        canWrite: () => mounted && canExport(),
      );
      if (mounted && canExport()) {
        setState(() => _message = 'Saved ${format.name.toUpperCase()} to ${file.path}');
      }
    } catch (_) {
      if (mounted && canExport()) {
        setState(() { _failed = true; _message = 'Could not save export. Choose a writable directory and retry.'; });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (widget.compact) PopupMenuButton<AnalyticsExportFormat>(
          key: const ValueKey('analytics_export_menu'),
          enabled: !_busy && widget.canExport(),
          tooltip: 'Export displayed snapshot',
          onSelected: _export,
          itemBuilder: (_) => const [
            PopupMenuItem(value: AnalyticsExportFormat.csv, child: Text('CSV (this report)')),
            PopupMenuItem(value: AnalyticsExportFormat.xlsx, child: Text('XLSX (all reports)')),
            PopupMenuItem(value: AnalyticsExportFormat.pdf, child: Text('PDF (this report)')),
          ],
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.file_download_outlined, size: 18), SizedBox(width: 8),
              Text('Export'), SizedBox(width: 8), Icon(Icons.expand_more, size: 18),
            ])),
        ) else
        for (final entry in const {
          AnalyticsExportFormat.csv: 'CSV (this report)',
          AnalyticsExportFormat.xlsx: 'XLSX (all reports)',
          AnalyticsExportFormat.pdf: 'PDF (this report)',
        }.entries)
          OutlinedButton.icon(
            onPressed: _busy || !widget.canExport() ? null : () => _export(entry.key),
            icon: const Icon(Icons.save_alt, size: 18), label: Text(entry.value),
          ),
        if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        if (_busy) const Text('Saving snapshot...'),
      ]),
      if (_message != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(liveRegion: true, child: SelectableText(_message!, style: TextStyle(color: _failed ? Theme.of(context).colorScheme.error : null))),
      ),
    ],
  );
}
