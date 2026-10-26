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
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 25), endDateExclusive: DateTime(2026, 10, 26));
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
}
