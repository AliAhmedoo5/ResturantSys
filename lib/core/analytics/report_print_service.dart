import 'dart:io';
import 'package:path/path.dart' as p;

import 'analytics_export_service.dart';
import 'analytics_models.dart';

typedef PlatformPrintHandler = Future<bool> Function(List<int> bytes, {String? documentTitle});
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Platform adapter for opening the standard Windows print dialog for a report PDF.
class WindowsReportPrintAdapter {
  final PlatformPrintHandler? _handler;
  final ProcessRunner? _processRunner;

  const WindowsReportPrintAdapter({
    PlatformPrintHandler? printHandler,
    ProcessRunner? processRunner,
  })  : _handler = printHandler,
        _processRunner = processRunner;

  /// Sends the PDF to the Windows print system.
  /// Returns `true` if accepted/printed, `false` if cancelled or unavailable.
  Future<bool> printPdf(List<int> pdfBytes, {String? documentTitle}) async {
    if (_handler != null) {
      return await _handler(pdfBytes, documentTitle: documentTitle);
    }
    if (!Platform.isWindows && _processRunner == null) {
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
      final escapedPath = tempFile.path.replaceAll("'", "''");
      final psScript = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
\$dialog = New-Object System.Windows.Forms.PrintDialog
\$dialog.UseEXDialog = \$true
\$dialog.AllowSomePages = \$false
\$dialog.AllowSelection = \$false
\$res = \$dialog.ShowDialog()
if (\$res -eq [System.Windows.Forms.DialogResult]::OK) {
  \$printer = \$dialog.PrinterSettings.PrinterName
  Start-Process -FilePath '$escapedPath' -Verb PrintTo -ArgumentList "`"\$printer`"" -PassThru | ForEach-Object { \$_ | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue }
  Write-Output "SUCCESS"
  exit 0
} else {
  Write-Output "CANCELLED"
  exit 1
}
''';
      final runner = _processRunner ?? Process.run;
      final result = await runner(
        'powershell',
        [
          '-NoProfile',
          '-STA',
          '-Command',
          psScript,
        ],
      );

      final stdoutStr = result.stdout.toString();
      final stderrStr = result.stderr.toString();

      if (result.exitCode == 0 && stdoutStr.contains('SUCCESS')) {
        return true;
      } else if (result.exitCode == 1 || stdoutStr.contains('CANCELLED')) {
        return false;
      } else {
        throw ProcessException(
          'powershell',
          ['-Command', psScript],
          'Print dialog invocation failed: ${stderrStr.isNotEmpty ? stderrStr : stdoutStr}',
          result.exitCode,
        );
      }
    } finally {
      // Do not prematurely delete the temp PDF while the background spooler is active.
      // Schedule cleanup after a delay.
      Future.delayed(const Duration(minutes: 5), () async {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      });
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
