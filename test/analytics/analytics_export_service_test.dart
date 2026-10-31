import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';

AnalyticsSnapshot fixture() => AnalyticsSnapshot(
  query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2), cashierId: 7, paymentMethod: 'CASH'),
  generatedAt: DateTime.utc(2026, 10, 1, 21), generatedByStaffId: 3,
  businessDayIds: [42], notes: ['Legacy precision is estimated'],
  sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales',
    metrics: [const AnalyticsMetric(id: 'value', label: 'Recorded value', value: 12345, unit: AnalyticsUnit.paisa, explanation: 'Sum eligible committed orders', quality: AnalyticsQuality.estimated, sampleCount: 1, populationCount: 2)],
    columns: [const AnalyticsColumn(key: 'label', label: 'Label'), const AnalyticsColumn(key: 'amount', label: 'Recorded value', unit: AnalyticsUnit.paisa)],
    rows: [AnalyticsRow(id: 'row-1', sourceType: 'orders', sourceId: '81', cells: {'label': '=HYPERLINK("bad")\nquoted', 'amount': -125})],
  ), AnalyticsSection(family: AnalyticsFamily.profitability, title: 'Profitability', metrics: [const AnalyticsMetric(id: 'profit', label: 'Net profit', unit: AnalyticsUnit.paisa, quality: AnalyticsQuality.missing, explanation: 'No event-time costing')])],
);

void main() {
  test('saved PDF carries displayed PKR values, missing explanations and source metadata', () async {
    final directory = await Directory.systemTemp.createTemp('analytics-export-fixture-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AnalyticsExportService();
    final file = await service.saveToDirectory(fixture(), AnalyticsFamily.sales, AnalyticsExportFormat.pdf, directory.path);
    expect(await file.exists(), isTrue);
    expect((await file.readAsBytes()).take(4), [37, 80, 68, 70]);
    if (Platform.isLinux) {
      final result = await Process.run('pdftotext', [file.path, '-']);
      expect(result.exitCode, 0);
      final text = result.stdout as String;
      expect(text, contains('PKR 123.45'));
      expect(text, contains('cashier_id: 7'));
      expect(text, contains('generated_by_staff_id: 3'));
      expect(text, contains('orders / 81'));
      expect(text, contains('Sum eligible committed orders'));
      expect(text, contains('estimated'));
    }
    final other = await service.saveToDirectory(fixture(), AnalyticsFamily.sales, AnalyticsExportFormat.pdf, directory.path);
    expect(other.path, isNot(file.path), reason: 'Export never silently overwrites a previous file');
    final profit = await service.pdf(fixture(), AnalyticsFamily.profitability);
    expect(profit, isNotEmpty);
  });
  test('workbook includes every snapshot family, numeric paisa and missing coverage', () {
    final bytes = AnalyticsExportService().workbook(fixture());
    final archive = ZipDecoder().decodeBytes(bytes);
    String xml(String path) => utf8.decode(archive.findFile(path)!.content as List<int>);
    expect(xml('xl/workbook.xml'), contains('profitability'));
    final sales = xml('xl/worksheets/sheet2.xml');
    expect(sales, contains('<v>12345</v>'));
    expect(sales, contains('<v>-125</v>'));
    expect(sales, contains('paisa'));
    expect(sales, contains('orders'));
    expect(sales, contains('&apos;=HYPERLINK'));
    expect(sales, isNot(contains('<f>')));
    expect(xml('xl/worksheets/sheet3.xml'), contains('No event-time costing'));
    expect(xml('xl/worksheets/sheet3.xml'), contains('missing'));
    expect(xml('xl/worksheets/sheet1.xml'), contains('generated_by_staff_id'));
  });
  test('CSV preserves selected displayed values, provenance, missing quality and filters safely', () {
    final csv = AnalyticsExportService().csv(fixture(), AnalyticsFamily.sales);
    expect(csv, contains('12345'));
    expect(csv, contains('paisa'));
    expect(csv, contains('-125'));
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains('""bad""'));
    expect(csv, contains('orders'));
    expect(csv, contains('81'));
    expect(csv, contains('cashier_id,7'));
    expect(csv, contains('generated_by_staff_id,3'));
    expect(csv, contains('2026-10-02T02:00:00.000+05:00'));
    expect(csv, contains('estimated'));
    expect(csv, contains('Sum eligible committed orders'));
    expect(csv, isNot(contains('No event-time costing')));
  });

  test('saveToDirectory reports stage and progress updates monotonically', () async {
    final directory = await Directory.systemTemp.createTemp('analytics-progress-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AnalyticsExportService();
    final stages = <String>[];
    final progressValues = <int>[];

    final file = await service.saveToDirectory(
      fixture(),
      AnalyticsFamily.sales,
      AnalyticsExportFormat.csv,
      directory.path,
      onProgress: (stage, current, total) {
        stages.add(stage);
        progressValues.add(current);
        expect(current, lessThanOrEqualTo(total));
      },
    );

    expect(await file.exists(), isTrue);
    expect(stages, isNotEmpty);
    expect(progressValues, isNotEmpty);
  });

  test('saveToDirectory aborts immediately and cleans up partial file when cancelled', () async {
    final directory = await Directory.systemTemp.createTemp('analytics-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AnalyticsExportService();

    await expectLater(
      service.saveToDirectory(
        fixture(),
        AnalyticsFamily.sales,
        AnalyticsExportFormat.csv,
        directory.path,
        cancellationToken: ExportCancellationToken(() => true),
      ),
      throwsA(isA<ExportCancelledException>()),
    );

    final files = directory.listSync();
    expect(files.where((f) => f.path.endsWith('.partial')), isEmpty);
    expect(files.where((f) => f.path.endsWith('.csv')), isEmpty);
  });

  test('cancellation preserves pre-existing completed destination file without overwrite or deletion', () async {
    final directory = await Directory.systemTemp.createTemp('analytics-preserve-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AnalyticsExportService();

    // Create a pre-existing completed file in the directory
    final existingFile = File('${directory.path}/manager-analytics-sales-preexisting.csv');
    await existingFile.writeAsString('ORIGINAL_CONTENT_PRESERVED', flush: true);

    final token = ExportCancellationToken();
    var progressCount = 0;

    await expectLater(
      service.saveToDirectory(
        fixture(),
        AnalyticsFamily.sales,
        AnalyticsExportFormat.csv,
        directory.path,
        cancellationToken: token,
        onProgress: (stage, current, total) {
          progressCount++;
          // Cancel during progress
          token.cancel();
        },
      ),
      throwsA(isA<ExportCancelledException>()),
    );

    expect(progressCount, greaterThan(0));
    // Verify existing file is completely intact
    expect(await existingFile.exists(), isTrue);
    expect(await existingFile.readAsString(), 'ORIGINAL_CONTENT_PRESERVED');

    // Verify no partial file remains
    final files = directory.listSync();
    expect(files.where((f) => f.path.endsWith('.partial')), isEmpty);
  });

  test('saveToDirectory cleans partial file if authorization expires during export', () async {
    final directory = await Directory.systemTemp.createTemp('analytics-expiry-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AnalyticsExportService();
    var calls = 0;

    await expectLater(
      service.saveToDirectory(
        fixture(),
        AnalyticsFamily.sales,
        AnalyticsExportFormat.csv,
        directory.path,
        canWrite: () {
          calls++;
          // Fail authorization after initial checks
          return calls <= 1;
        },
      ),
      throwsA(isA<StateError>()),
    );

    final files = directory.listSync();
    expect(files.where((f) => f.path.endsWith('.partial')), isEmpty);
  });
}
