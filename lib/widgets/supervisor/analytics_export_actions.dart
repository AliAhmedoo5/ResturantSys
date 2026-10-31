import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/analytics/analytics_export_service.dart';
import '../../core/analytics/analytics_models.dart';
import '../../core/analytics/report_print_service.dart';

/// The native picker and print dialog are UI boundaries; all formats use the shown snapshot.
class AnalyticsExportActions extends StatefulWidget {
  const AnalyticsExportActions({
    super.key,
    required this.snapshot,
    required this.family,
    required this.canExport,
    this.pickDirectory,
    this.compact = false,
    this.exportService,
    this.printService,
  });

  final AnalyticsSnapshot snapshot;
  final AnalyticsFamily family;
  final bool Function() canExport;
  final Future<String?> Function()? pickDirectory;
  final bool compact;
  final AnalyticsExportService? exportService;
  final ReportPrintService? printService;

  @override
  State<AnalyticsExportActions> createState() => _AnalyticsExportActionsState();
}

class _AnalyticsExportActionsState extends State<AnalyticsExportActions> {
  bool _busy = false;
  String? _message;
  bool _failed = false;
  String _stage = '';
  int _current = 0;
  int _total = 100;
  bool _cancelling = false;
  ExportCancellationToken? _cancellationToken;

  Future<void> _export(AnalyticsExportFormat format) async {
    if (_busy || !widget.canExport()) return;
    final canExport = widget.canExport;
    final snapshot = widget.snapshot;
    final family = widget.family;
    final token = ExportCancellationToken();

    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
      _cancelling = false;
      _stage = 'Starting export...';
      _current = 0;
      _total = 100;
      _cancellationToken = token;
    });

    try {
      final directory = await (widget.pickDirectory?.call() ?? getDirectoryPath());
      if (directory == null || !mounted || !canExport()) return;
      if (token.isCancelled) return;

      final service = widget.exportService ?? AnalyticsExportService();
      final file = await service.saveToDirectory(
        snapshot,
        family,
        format,
        directory,
        canWrite: () => mounted && canExport(),
        cancellationToken: token,
        onProgress: (stage, current, total) {
          if (mounted) {
            setState(() {
              _stage = stage;
              _current = current;
              _total = total;
            });
          }
        },
      );

      if (mounted && canExport()) {
        setState(() => _message = 'Saved ${format.name.toUpperCase()} to ${file.path}');
      }
    } on ExportCancelledException {
      if (mounted && canExport()) {
        setState(() {
          _failed = false;
          _message = 'Export cancelled.';
        });
      }
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = e.message;
        });
      }
    } catch (_) {
      if (mounted && canExport()) {
        setState(() {
          _failed = true;
          _message = 'Could not save export. Choose a writable directory and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellationToken = null;
          _cancelling = false;
        });
      }
    }
  }

  Future<void> _print() async {
    if (_busy || !widget.canExport()) return;
    final canExport = widget.canExport;
    final snapshot = widget.snapshot;
    final family = widget.family;

    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
      _cancelling = false;
      _stage = 'Opening Windows print dialog...';
      _cancellationToken = null;
    });

    try {
      final service = widget.printService ?? ReportPrintService();
      final result = await service.printReport(
        snapshot,
        family,
        canPrint: () => mounted && canExport(),
      );

      if (mounted && canExport()) {
        setState(() {
          switch (result.status) {
            case ReportPrintStatus.printed:
              _failed = false;
              _message = result.message ?? 'Sent to printer.';
            case ReportPrintStatus.cancelled:
              _failed = false;
              _message = 'Print was cancelled.';
            case ReportPrintStatus.unauthorized:
              _failed = true;
              _message = result.message ?? 'Print authorization expired.';
            case ReportPrintStatus.failed:
              _failed = true;
              _message = result.message ?? 'Could not print report.';
          }
        });
      }
    } catch (e) {
      if (mounted && canExport()) {
        setState(() {
          _failed = true;
          _message = 'Could not print report: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellationToken = null;
          _cancelling = false;
        });
      }
    }
  }

  void _cancelExport() {
    _cancellationToken?.cancel();
    if (mounted) {
      setState(() {
        _cancelling = true;
        _stage = 'Cancelling export...';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.compact)
                PopupMenuButton<Object>(
                  key: const ValueKey('analytics_export_menu'),
                  enabled: !_busy && widget.canExport(),
                  tooltip: 'Export or print displayed snapshot',
                  onSelected: (action) {
                    if (action is AnalyticsExportFormat) {
                      _export(action);
                    } else if (action == 'print') {
                      _print();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: AnalyticsExportFormat.csv,
                      child: Text('CSV (this report)'),
                    ),
                    PopupMenuItem(
                      value: AnalyticsExportFormat.xlsx,
                      child: Text('XLSX (all reports)'),
                    ),
                    PopupMenuItem(
                      value: AnalyticsExportFormat.pdf,
                      child: Text('PDF (this report)'),
                    ),
                    PopupMenuItem(
                      value: 'print',
                      child: Text('Print report'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Export'),
                        SizedBox(width: 8),
                        Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: _busy || !widget.canExport()
                      ? null
                      : () => _export(AnalyticsExportFormat.csv),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('CSV (this report)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !widget.canExport()
                      ? null
                      : () => _export(AnalyticsExportFormat.xlsx),
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('XLSX (all reports)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !widget.canExport()
                      ? null
                      : () => _export(AnalyticsExportFormat.pdf),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Save PDF'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('analytics_print_button'),
                  onPressed: _busy || !widget.canExport() ? null : _print,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Text(
                  _stage.isEmpty
                      ? 'Processing...'
                      : (_total > 0 && _current > 0
                          ? '$_stage ($_current/$_total)'
                          : _stage),
                ),
                if (_cancellationToken != null)
                  OutlinedButton.icon(
                    key: const ValueKey('analytics_export_cancel_button'),
                    onPressed: _cancelling ? null : _cancelExport,
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(_cancelling ? 'Cancelling...' : 'Cancel'),
                  ),
              ],
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: SelectableText(
                  _message!,
                  style: TextStyle(
                    color: _failed ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ),
            ),
        ],
      );
}
