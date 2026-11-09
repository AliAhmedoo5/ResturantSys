import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('Closed historical zero baselines retain absolute order and purchase changes in every export', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((row) => row['role'] != 'CASHIER');
    final cashier = staff.firstWhere((row) => row['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    await db.insert('business_days', {'opened_at': '2026-10-24 18:00:00',
      'closed_at': '2026-10-25 17:00:00', 'status': 'CLOSED', 'opened_by_staff_id': manager['id']});
    final day = await db.insert('business_days', {'opened_at': '2026-10-25 18:00:00',
      'closed_at': '2026-10-26 17:00:00', 'status': 'OPEN', 'opened_by_staff_id': manager['id']});
    final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': cashier['id'],
      'opened_at': '2026-10-25 18:00:00', 'opening_float': 0, 'status': 'OPEN'});
    for (var token = 1; token <= 2; token++) {
      await db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': cashier['id'],
        'token_number': token, 'dining_type': 'TAKEAWAY', 'subtotal': token * 100, 'grand_total': token * 100,
        'payment_status': 'SETTLED', 'created_at': '2026-10-26 01:00:00'});
    }
    final ingredient = await db.insert('raw_ingredients', {'name': 'Synthetic flour', 'storage_unit': 'g',
      'current_stock': 100, 'low_stock_threshold': 10, 'created_at': '2026-10-25 18:00:00'});
    await db.insert('mandi_procurements', {'raw_ingredient_id': ingredient, 'traditional_unit': 'kg',
      'quantity': 1, 'converted_quantity': 1000, 'total_cost': 450, 'cost_per_recipe_unit': 0.45,
      'created_at': '2026-10-26 00:30:00'});
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(
      startDate: DateTime(2026, 10, 25),
      endDateExclusive: DateTime(2026, 10, 26),
      comparisonMode: AnalyticsComparisonMode.precedingPeriod,
    );
    final incomplete = await service.load(query);
    expect(incomplete.section(AnalyticsFamily.procurement).metrics.firstWhere((m) => m.id == 'purchase_spend').changeAbsolute, isNull);
    await db.update('business_days', {'status': 'CLOSED'}, where: 'id=?', whereArgs: [day]);
    final snapshot = await service.load(query);
    AnalyticsMetric metric(AnalyticsFamily family, String id) => snapshot.section(family).metrics.firstWhere((m) => m.id == id);
    expect(metric(AnalyticsFamily.sales, 'recorded_value').changeAbsolute, 30000);
    expect(metric(AnalyticsFamily.sales, 'orders').changeAbsolute, 2);
    expect(metric(AnalyticsFamily.procurement, 'purchase_spend').changeAbsolute, 45000);
    expect(metric(AnalyticsFamily.procurement, 'purchase_count').changeAbsolute, 1);
    expect(metric(AnalyticsFamily.procurement, 'purchase_spend').changePercent, isNull);
    final exports = AnalyticsExportService();
    final csv = exports.csv(snapshot, AnalyticsFamily.procurement);
    expect(csv, contains('Change percent,Change absolute'));
    expect(csv.split('\r\n').singleWhere((line) => line.startsWith('purchase_spend,')).endsWith(',,45000'), isTrue);
    final workbook = ZipDecoder().decodeBytes(exports.workbook(snapshot));
    final sheetIndex = snapshot.sections.indexWhere((s) => s.family == AnalyticsFamily.procurement) + 2;
    final xml = utf8.decode(workbook.findFile('xl/worksheets/sheet$sheetIndex.xml')!.content as List<int>);
    final row = RegExp(r'<row r="(\d+)">(?:(?!</row>).)*purchase_spend(?:(?!</row>).)*</row>', dotAll: true).firstMatch(xml)!;
    expect(row.group(0), contains('<c r="J${row.group(1)}"><v>45000</v></c>'));
    final directory = await Directory.systemTemp.createTemp('analytics-review-export-');
    addTearDown(() => directory.delete(recursive: true));
    final pdf = await exports.saveToDirectory(snapshot, AnalyticsFamily.procurement, AnalyticsExportFormat.pdf, directory.path);
    if (Platform.isLinux) {
      final result = await Process.run('pdftotext', [pdf.path, '-']);
      expect(result.exitCode, 0);
      expect((result.stdout as String).replaceAll(RegExp(r'\s+'), ' '), contains('Absolute change: PKR 450.00'));
    }
  });

  test('Known-customer ticket averages weight eligible orders and retain per-identity source averages in exports', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((row) => row['role'] != 'CASHIER');
    final cashier = staff.firstWhere((row) => row['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at': '2026-10-25 18:00:00',
      'closed_at': '2026-10-26 17:00:00', 'status': 'OPEN', 'opened_by_staff_id': manager['id']});
    final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': cashier['id'],
      'opened_at': '2026-10-25 18:00:00', 'opening_float': 0, 'status': 'OPEN'});
    final sourceIds = <int>[];
    const values = [100, 300, 500, 9000, 8000];
    const phones = ['+92 300 1234567', '03001234567', '03007654321', '', '03001234567'];
    for (var index = 0; index < values.length; index++) {
      sourceIds.add(await db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': cashier['id'],
        'token_number': index + 1, 'dining_type': 'TAKEAWAY', 'subtotal': values[index], 'grand_total': values[index],
        'payment_status': index == 4 ? 'CANCELLED' : 'SETTLED', 'customer_phone': phones[index],
        'created_at': '2026-10-26 01:00:00'}));
    }
    await db.update('business_days', {'status': 'CLOSED'}, where: 'id=?', whereArgs: [day]);
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(
      startDate: DateTime(2026, 10, 25),
      endDateExclusive: DateTime(2026, 10, 26),
      comparisonMode: AnalyticsComparisonMode.precedingPeriod,
    );
    final snapshot = await service.load(query);
    final section = snapshot.section(AnalyticsFamily.customers);
    final average = section.metrics.firstWhere((m) => m.id == 'known_customer_average_ticket');
    // A: (100 + 300) / 2 = 200; B: 500 / 1 = 500.
    // Weighted order mean = 900 / 3 = 300, rather than identity mean 350.
    expect(average.value, 30000);
    expect(average.unit, AnalyticsUnit.paisa);
    expect(average.sampleCount, 3);
    expect(average.populationCount, 3);
    final groups = section.rows.where((row) => row.cells['kind'] == 'Customer aggregate').toList();
    expect(groups.length, 2);
    final first = groups.singleWhere((row) => row.sourceId == '${sourceIds[0]},${sourceIds[1]}');
    expect(first.cells['average_ticket_paisa'], 20000);
    expect(first.cells['orders_in_range'], 2);
    expect(groups.singleWhere((row) => row.sourceId == '${sourceIds[2]}').cells['average_ticket_paisa'], 50000);
    expect(section.rows.map((row) => row.cells.toString()).join(), isNot(contains('03001234567')));
    final exports = AnalyticsExportService();
    final csv = exports.csv(snapshot, AnalyticsFamily.customers);
    final metricLine = csv.split('\r\n').singleWhere((line) => line.startsWith('known_customer_average_ticket,'));
    expect(metricLine, startsWith('known_customer_average_ticket,Known-customer average ticket,30000.0,paisa,complete,'));
    expect(metricLine.endsWith(',3,3,,'), isTrue);
    expect(csv, contains('recorded value paisa (paisa),average ticket paisa (paisa)'));
    expect(csv.split('\r\n').singleWhere((line) => line.startsWith('${first.id},')), contains(',40000,20000.0,'));
    final archive = ZipDecoder().decodeBytes(exports.workbook(snapshot));
    final sheetIndex = snapshot.sections.indexWhere((s) => s.family == AnalyticsFamily.customers) + 2;
    final xml = utf8.decode(archive.findFile('xl/worksheets/sheet$sheetIndex.xml')!.content as List<int>);
    final metricRow = RegExp(r'<row r="(\d+)">(?:(?!</row>).)*known_customer_average_ticket(?:(?!</row>).)*</row>', dotAll: true).firstMatch(xml)!;
    expect(metricRow.group(0), contains('<c r="C${metricRow.group(1)}"><v>30000.0</v></c>'));
    expect(metricRow.group(0), contains('<c r="G${metricRow.group(1)}"><v>3</v></c>'));
    final sourceRow = RegExp('<row r="(\\d+)">(?:(?!</row>).)*${RegExp.escape(first.id)}(?:(?!</row>).)*</row>', dotAll: true).firstMatch(xml)!;
    expect(sourceRow.group(0), contains('<c r="I${sourceRow.group(1)}"><v>20000.0</v></c>'));
    final directory = await Directory.systemTemp.createTemp('analytics-customer-average-');
    addTearDown(() => directory.delete(recursive: true));
    final pdf = await exports.saveToDirectory(snapshot, AnalyticsFamily.customers, AnalyticsExportFormat.pdf, directory.path);
    if (Platform.isLinux) {
      final result = await Process.run('pdftotext', [pdf.path, '-']);
      expect(result.exitCode, 0);
      final text = (result.stdout as String).replaceAll(RegExp(r'\s+'), ' ');
      expect(text, contains('Known-customer average ticket: PKR 300.00'));
      expect(text, contains('average ticket paisa: PKR 200.00'));
    }
    final empty = await service.load(query.copyWith(cashierId: 9999));
    final unavailable = empty.section(AnalyticsFamily.customers).metrics.firstWhere((m) => m.id == 'known_customer_average_ticket');
    expect(unavailable.value, isNull);
    expect(unavailable.quality, AnalyticsQuality.notApplicable);
    expect(unavailable.sampleCount, 0);
  });
}
