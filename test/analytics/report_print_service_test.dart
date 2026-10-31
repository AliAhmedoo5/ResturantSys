import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/report_print_service.dart';

AnalyticsSnapshot _fixture() => AnalyticsSnapshot(
  query: AnalyticsQuery(
    startDate: DateTime(2026, 10, 1),
    endDateExclusive: DateTime(2026, 10, 2),
    cashierId: 7,
    paymentMethod: 'CASH',
  ),
  generatedAt: DateTime.utc(2026, 10, 1, 21),
  generatedByStaffId: 3,
  businessDayIds: [42],
  notes: ['Legacy precision is estimated'],
  sections: [
    AnalyticsSection(
      family: AnalyticsFamily.sales,
      title: 'Sales',
      metrics: [
        const AnalyticsMetric(
          id: 'value',
          label: 'Recorded value',
          value: 12345,
          unit: AnalyticsUnit.paisa,
          explanation: 'Sum eligible committed orders',
          quality: AnalyticsQuality.estimated,
          sampleCount: 1,
          populationCount: 2,
        ),
      ],
      columns: [
        const AnalyticsColumn(key: 'label', label: 'Label'),
        const AnalyticsColumn(key: 'amount', label: 'Recorded value', unit: AnalyticsUnit.paisa),
      ],
      rows: [
        AnalyticsRow(
          id: 'row-1',
          sourceType: 'orders',
          sourceId: '81',
          cells: {'label': 'Item #1', 'amount': -125},
        ),
      ],
    ),
  ],
);

void main() {
  group('ReportPrintService & WindowsReportPrintAdapter', () {
    test('printReport generates PDF with snapshot metadata and succeeds when confirmed', () async {
      List<int>? capturedBytes;
      String? capturedTitle;

      final adapter = WindowsReportPrintAdapter(
        printHandler: (bytes, {documentTitle}) async {
          capturedBytes = bytes;
          capturedTitle = documentTitle;
          return true;
        },
      );

      final service = ReportPrintService(adapter: adapter);
      final result = await service.printReport(
        _fixture(),
        AnalyticsFamily.sales,
        canPrint: () => true,
      );

      expect(result.status, ReportPrintStatus.printed);
      expect(result.isSuccess, isTrue);
      expect(capturedBytes, isNotNull);
      expect(capturedBytes!.take(4).toList(), [37, 80, 68, 70]); // %PDF
      expect(capturedTitle, contains('Sales'));

      if (Platform.isLinux) {
        final temp = await Directory.systemTemp.createTemp('print-test-');
        addTearDown(() => temp.delete(recursive: true));
        final tempFile = File('${temp.path}/doc.pdf');
        await tempFile.writeAsBytes(capturedBytes!);
        final proc = await Process.run('pdftotext', [tempFile.path, '-']);
        if (proc.exitCode == 0) {
          final text = proc.stdout as String;
          expect(text, contains('PKR 123.45'));
          expect(text, contains('cashier_id: 7'));
          expect(text, contains('Sum eligible committed orders'));
          expect(text, contains('estimated'));
        }
      }
    });

    test('printReport cancels cleanly when user dismisses or cancels print dialog', () async {
      final adapter = WindowsReportPrintAdapter(
        printHandler: (bytes, {documentTitle}) async => false,
      );

      final service = ReportPrintService(adapter: adapter);
      final result = await service.printReport(
        _fixture(),
        AnalyticsFamily.sales,
        canPrint: () => true,
      );

      expect(result.status, ReportPrintStatus.cancelled);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('cancelled'));
    });

    test('printReport fails safely when authorization expires before print generation', () async {
      var callCount = 0;
      final adapter = WindowsReportPrintAdapter(
        printHandler: (bytes, {documentTitle}) async {
          callCount++;
          return true;
        },
      );

      final service = ReportPrintService(adapter: adapter);
      final result = await service.printReport(
        _fixture(),
        AnalyticsFamily.sales,
        canPrint: () => false,
      );

      expect(result.status, ReportPrintStatus.unauthorized);
      expect(result.isSuccess, isFalse);
      expect(callCount, 0);
    });

    test('printReport fails safely when authorization expires during/after generation', () async {
      var callCount = 0;
      var authorized = true;
      final adapter = WindowsReportPrintAdapter(
        printHandler: (bytes, {documentTitle}) async {
          callCount++;
          return true;
        },
      );

      final service = ReportPrintService(adapter: adapter);
      final result = await service.printReport(
        _fixture(),
        AnalyticsFamily.sales,
        canPrint: () {
          // Expires right after initial check
          final cur = authorized;
          authorized = false;
          return cur;
        },
      );

      expect(result.status, ReportPrintStatus.unauthorized);
      expect(result.isSuccess, isFalse);
      expect(callCount, 0);
    });

    test('printReport handles adapter errors safely without throwing unhandled exceptions', () async {
      final adapter = WindowsReportPrintAdapter(
        printHandler: (bytes, {documentTitle}) async {
          throw Exception('Printer device offline or driver failed');
        },
      );

      final service = ReportPrintService(adapter: adapter);
      final result = await service.printReport(
        _fixture(),
        AnalyticsFamily.sales,
        canPrint: () => true,
      );

      expect(result.status, ReportPrintStatus.failed);
      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Printer device offline'));
    });

    test('WindowsReportPrintAdapter native print dialog handles success, cancel, and error distinction', () async {
      // 1. Success
      final successAdapter = WindowsReportPrintAdapter(
        processRunner: (exe, args) async {
          expect(exe, 'powershell');
          expect(args, contains('-STA'));
          return ProcessResult(1234, 0, 'SUCCESS\n', '');
        },
      );
      final successResult = await ReportPrintService(adapter: successAdapter).printReport(
        _fixture(),
        AnalyticsFamily.sales,
      );
      expect(successResult.status, ReportPrintStatus.printed);
      expect(successResult.isSuccess, isTrue);

      // 2. User cancellation
      final cancelAdapter = WindowsReportPrintAdapter(
        processRunner: (exe, args) async => ProcessResult(1235, 1, 'CANCELLED\n', ''),
      );
      final cancelResult = await ReportPrintService(adapter: cancelAdapter).printReport(
        _fixture(),
        AnalyticsFamily.sales,
      );
      expect(cancelResult.status, ReportPrintStatus.cancelled);
      expect(cancelResult.isSuccess, isFalse);

      // 3. Process execution failure (distinguished from cancel)
      final errorAdapter = WindowsReportPrintAdapter(
        processRunner: (exe, args) async => ProcessResult(1236, 127, '', 'Fatal powershell crash'),
      );
      final errorResult = await ReportPrintService(adapter: errorAdapter).printReport(
        _fixture(),
        AnalyticsFamily.sales,
      );
      expect(errorResult.status, ReportPrintStatus.failed);
      expect(errorResult.isSuccess, isFalse);
      expect(errorResult.message, contains('Print dialog invocation failed'));
    });
  });
}
