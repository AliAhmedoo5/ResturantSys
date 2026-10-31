import 'dart:io';
import 'package:path/path.dart' as p;

import 'analytics_export_service.dart';
import 'analytics_models.dart';

typedef PlatformPrintHandler = Future<bool> Function(List<int> bytes, {String? documentTitle});

/// Platform adapter for opening the standard Windows print dialog for a report PDF.
class WindowsReportPrintAdapter {
  final PlatformPrintHandler? _handler;

  const WindowsReportPrintAdapter({
    PlatformPrintHandler? printHandler,
  }) : _handler = printHandler;

  /// Sends the PDF to the Windows print system.
  /// Returns `true` if accepted/printed, `false` if cancelled or unavailable.
  Future<bool> printPdf(List<int> pdfBytes, {String? documentTitle}) async {
    if (_handler != null) {
      return await _handler!(pdfBytes, documentTitle: documentTitle);
    }
    if (!Platform.isWindows) {
      return false;
    }
    return await _printWindowsNative(pdfBytes, documentTitle: documentTitle);
  }

  Future<bool> _printWindowsNative(List<int> pdfBytes, {String? documentTitle}) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      p.join(tempDir.path, 'print_report_${DateTime.now().microsecondsSinceEpoch}.pdf'),
    );
    try {
      await tempFile.writeAsBytes(pdfBytes, flush: true);
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Process -FilePath "${tempFile.path}" -Verb Print -PassThru | ForEach-Object { \$_ | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue }',
        ],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }
}

enum ReportPrintStatus {
  printed,
  cancelled,
  unauthorized,
  failed,
}

class ReportPrintResult {
  final ReportPrintStatus status;
  final String? message;

  const ReportPrintResult({
    required this.status,
    this.message,
  });

  bool get isSuccess => status == ReportPrintStatus.printed;
}

/// Service orchestrating Manager report printing with authorization checks
/// and platform dialog interaction.
class ReportPrintService {
  final WindowsReportPrintAdapter adapter;
  final AnalyticsExportService exportService;

  ReportPrintService({
    WindowsReportPrintAdapter? adapter,
    AnalyticsExportService? exportService,
  })  : adapter = adapter ?? const WindowsReportPrintAdapter(),
        exportService = exportService ?? AnalyticsExportService();

  Future<ReportPrintResult> printReport(
    AnalyticsSnapshot snapshot,
    AnalyticsFamily family, {
    bool Function()? canPrint,
  }) async {
    try {
      if (canPrint != null && !canPrint()) {
        return const ReportPrintResult(
          status: ReportPrintStatus.unauthorized,
          message: 'Print authorization expired.',
        );
      }

      final bytes = await exportService.pdf(snapshot, family);

      if (canPrint != null && !canPrint()) {
        return const ReportPrintResult(
          status: ReportPrintStatus.unauthorized,
          message: 'Print authorization expired.',
        );
      }

      final title = 'Manager analytics - ${snapshot.section(family).title}';
      final printed = await adapter.printPdf(bytes, documentTitle: title);

      if (printed) {
        return const ReportPrintResult(
          status: ReportPrintStatus.printed,
          message: 'Sent to printer.',
        );
      } else {
        return const ReportPrintResult(
          status: ReportPrintStatus.cancelled,
          message: 'Print was cancelled.',
        );
      }
    } catch (e) {
      return ReportPrintResult(
        status: ReportPrintStatus.failed,
        message: 'Could not print report: $e',
      );
    }
  }
}
