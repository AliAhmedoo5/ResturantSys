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
}

