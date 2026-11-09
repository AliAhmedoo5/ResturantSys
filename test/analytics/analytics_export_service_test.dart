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

  test('workbook zip entry uncompressed sizes match actual utf8 byte counts even with non-ascii characters and includes styles', () {
    final snapWithUnicode = AnalyticsSnapshot(
      query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)),
      generatedAt: DateTime.utc(2026, 10, 1),
      businessDayIds: [1],
      notes: ['Customer phone (7–15 digits); guest = no phone'],
      sections: [
        AnalyticsSection(
          family: AnalyticsFamily.sales,
          title: 'Sales',
          metrics: [const AnalyticsMetric(id: 'val', label: 'Sale – Total', value: 1000, unit: AnalyticsUnit.paisa, explanation: 'Test – Unicode')],
          columns: [const AnalyticsColumn(key: 'col', label: 'Item – Name')],
          rows: [AnalyticsRow(id: 'r1', sourceType: 'orders', cells: {'col': 'Chicken Karahi – Special'})],
        ),
      ],
    );
    final bytes = AnalyticsExportService().workbook(snapWithUnicode);
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      final contentBytes = file.content as List<int>;
      expect(file.size, equals(contentBytes.length), reason: 'Uncompressed size header for ${file.name} must equal encoded byte length');
    }
    expect(archive.findFile('xl/styles.xml'), isNotNull, reason: 'Workbook must include xl/styles.xml for valid styling');
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

  test('Order operations PDF export renders without layout failure or page explosion', () async {
    final orderSection = AnalyticsSection(
      family: AnalyticsFamily.orders,
      title: 'Order operations',
      metrics: [
        const AnalyticsMetric(id: 'committed_orders', label: 'Committed orders', value: 6, unit: AnalyticsUnit.count, quality: AnalyticsQuality.complete, explanation: 'All selected committed orders'),
        const AnalyticsMetric(id: 'revised_orders', label: 'Orders revised', value: 1, unit: AnalyticsUnit.count, quality: AnalyticsQuality.complete, explanation: 'Distinct revised order count'),
        const AnalyticsMetric(id: 'cancelled_orders', label: 'Cancelled/refunded orders', value: 1, unit: AnalyticsUnit.count, quality: AnalyticsQuality.complete, explanation: 'Cancelled orders'),
        const AnalyticsMetric(id: 'prep_median', label: 'Median preparation time', value: 5.5, unit: AnalyticsUnit.minutes, quality: AnalyticsQuality.complete, explanation: 'Prep time median', sampleCount: 4, populationCount: 6),
        const AnalyticsMetric(id: 'active_holds', label: 'Current active Holds', value: 2, unit: AnalyticsUnit.count, quality: AnalyticsQuality.complete, explanation: 'Active holds'),
        const AnalyticsMetric(id: 'stale_holds', label: 'Current stale Holds', value: 1, unit: AnalyticsUnit.count, quality: AnalyticsQuality.complete, explanation: 'Stale holds'),
      ],
      columns: [
        const AnalyticsColumn(key: 'order_id', label: 'Order ID'),
        const AnalyticsColumn(key: 'token', label: 'Token'),
        const AnalyticsColumn(key: 'business_day_id', label: 'Business day ID'),
        const AnalyticsColumn(key: 'assigned_business_date', label: 'Assigned business date'),
        const AnalyticsColumn(key: 'cashier_id', label: 'Cashier ID'),
        const AnalyticsColumn(key: 'shift_id', label: 'Shift ID'),
        const AnalyticsColumn(key: 'dining_type', label: 'Dining type'),
        const AnalyticsColumn(key: 'payment_status', label: 'Payment status'),
        const AnalyticsColumn(key: 'token_status', label: 'Token status'),
        const AnalyticsColumn(key: 'recorded_value_paisa', label: 'Recorded value', unit: AnalyticsUnit.paisa),
        const AnalyticsColumn(key: 'prep_duration_minutes', label: 'Prep duration', unit: AnalyticsUnit.minutes),
        const AnalyticsColumn(key: 'prep_quality', label: 'Prep quality'),
        const AnalyticsColumn(key: 'rework_cycles', label: 'Rework cycles'),
        const AnalyticsColumn(key: 'created_at', label: 'Created at'),
        const AnalyticsColumn(key: 'kind', label: 'Kind'),
        const AnalyticsColumn(key: 'period', label: 'Period'),
        const AnalyticsColumn(key: 'confirmed_orders', label: 'Confirmed orders'),
        const AnalyticsColumn(key: 'eligible_orders', label: 'Eligible orders'),
        const AnalyticsColumn(key: 'average_ticket_paisa', label: 'Average ticket', unit: AnalyticsUnit.paisa),
        const AnalyticsColumn(key: 'count_rank', label: 'Count rank'),
        const AnalyticsColumn(key: 'period_status', label: 'Period status'),
        const AnalyticsColumn(key: 'weekday', label: 'Weekday'),
        const AnalyticsColumn(key: 'weekday_basis', label: 'Weekday basis'),
        const AnalyticsColumn(key: 'completed_confirmed_orders', label: 'Completed confirmed orders'),
        const AnalyticsColumn(key: 'orders_per_completed_day', label: 'Orders per completed day'),
        const AnalyticsColumn(key: 'hold_id', label: 'Hold ID'),
        const AnalyticsColumn(key: 'age_minutes', label: 'Age minutes'),
        const AnalyticsColumn(key: 'aging_status', label: 'Aging status'),
        const AnalyticsColumn(key: 'cashier_name_current', label: 'Cashier name current'),
        const AnalyticsColumn(key: 'revision', label: 'Revision'),
        const AnalyticsColumn(key: 'action', label: 'Action'),
        const AnalyticsColumn(key: 'reason', label: 'Reason'),
        const AnalyticsColumn(key: 'delta_paisa', label: 'Delta', unit: AnalyticsUnit.paisa),
      ],
      rows: [
        AnalyticsRow(id: 'workload-day-1', sourceType: 'order_workload', cells: {'kind': 'Daily workload', 'period': '2026-11-03 · Business Day #1', 'confirmed_orders': 2, 'recorded_value_paisa': 182000}),
        for (var h = 0; h < 24; h++)
          AnalyticsRow(id: 'workload-hour-$h', sourceType: 'order_workload', cells: {'kind': 'Hourly workload', 'period': '${h.toString().padLeft(2, "0")}:00', 'hour': h, 'confirmed_orders': h == 13 ? 2 : 0, 'recorded_value_paisa': h == 13 ? 182000 : 0}),
        for (var w = 1; w <= 7; w++)
          AnalyticsRow(id: 'weekday-$w', sourceType: 'weekday_order_peaks', cells: {'kind': 'Weekday comparison', 'period': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1], 'weekday': w, 'confirmed_orders': w == 2 ? 2 : 0}),
        AnalyticsRow(id: 'held_carts-1', sourceType: 'held_carts', sourceId: '1', cells: {'kind': 'Current active Hold', 'hold_id': 1, 'cashier_id': 2, 'age_minutes': 35.0, 'aging_status': 'Stale'}),
        AnalyticsRow(id: 'orders-1', sourceType: 'orders', sourceId: '1', cells: {'order_id': 1, 'token': 'T-1', 'dining_type': 'DINE_IN', 'payment_status': 'SETTLED', 'recorded_value_paisa': 90000, 'prep_duration_minutes': 4.5, 'created_at': '2026-11-03 13:10:00'}),
        AnalyticsRow(id: 'orders-2', sourceType: 'orders', sourceId: '2', cells: {'order_id': 2, 'token': 'T-2', 'dining_type': 'DELIVERY', 'payment_status': 'SETTLED', 'recorded_value_paisa': 92000, 'prep_duration_minutes': 6.0, 'created_at': '2026-11-03 13:40:00'}),
        AnalyticsRow(id: 'order_revisions-1', sourceType: 'order_revisions', sourceId: '1', cells: {'order_id': 1, 'revision': 1, 'action': 'UPDATE_ITEMS', 'reason': 'Customer added drinks', 'delta_paisa': 15000}),
      ],
    );

    final snapshot = AnalyticsSnapshot(
      query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)),
      generatedAt: DateTime.utc(2026, 10, 1, 21),
      businessDayIds: [1],
      sections: [orderSection],
    );

    final directory = await Directory.systemTemp.createTemp('analytics-orders-export-');
    addTearDown(() => directory.delete(recursive: true));
    final service = AnalyticsExportService();

    final file = await service.saveToDirectory(snapshot, AnalyticsFamily.orders, AnalyticsExportFormat.pdf, directory.path);
    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.take(4), [37, 80, 68, 70]); // %PDF
  });
}
