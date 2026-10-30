import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Ticket #81: Customer history classification (first-time vs returning)', () {
    late Directory tempDir;
    late String dbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('customer_hist_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      db = await posDb.initialize();

      authService = AuthService(database: db);
      final manager = (await db.query('staff', where: 'id = 1')).single;
      authService.session.login(Staff.fromMap(manager));

      // Day 1 (Historical): 2026-10-20
      final dayHistorical = await db.insert('business_days', {
        'opened_at': '2026-10-20 09:00:00',
        'closed_at': '2026-10-20 23:00:00',
        'status': 'CLOSED',
        'opened_by_staff_id': 1,
      });
      final shiftHistorical = await db.insert('shifts', {
        'business_day_id': dayHistorical,
        'staff_id': 2,
        'opened_at': '2026-10-20 09:00:00',
        'closed_at': '2026-10-20 23:00:00',
        'status': 'CLOSED',
        'opening_float': 1000,
      });

      // Customer A historical order on 2026-10-20
      await db.insert('orders', {
        'business_day_id': dayHistorical,
        'shift_id': shiftHistorical,
        'cashier_id': 2,
        'token_number': 101,
        'dining_type': 'TAKEAWAY',
        'subtotal': 500,
        'grand_total': 500,
        'payment_status': 'SETTLED',
        'customer_phone': '03001112233',
        'created_at': '2026-10-20 14:00:00',
      });

      // Day 2 (Selected cohort): 2026-10-25
      final daySelected = await db.insert('business_days', {
        'opened_at': '2026-10-25 09:00:00',
        'closed_at': '2026-10-25 23:00:00',
        'status': 'CLOSED',
        'opened_by_staff_id': 1,
      });
      final shiftSelected = await db.insert('shifts', {
        'business_day_id': daySelected,
        'staff_id': 2,
        'opened_at': '2026-10-25 09:00:00',
        'closed_at': '2026-10-25 23:00:00',
        'status': 'CLOSED',
        'opening_float': 1000,
      });

      // Customer A order in selected cohort (single order in cohort, but returning from available history)
      await db.insert('orders', {
        'business_day_id': daySelected,
        'shift_id': shiftSelected,
        'cashier_id': 2,
        'token_number': 201,
        'dining_type': 'TAKEAWAY',
        'subtotal': 600,
        'grand_total': 600,
        'payment_status': 'SETTLED',
        'customer_phone': '03001112233',
        'created_at': '2026-10-25 12:00:00',
      });

      // Customer B order in selected cohort (first purchase ever)
      await db.insert('orders', {
        'business_day_id': daySelected,
        'shift_id': shiftSelected,
        'cashier_id': 2,
        'token_number': 202,
        'dining_type': 'TAKEAWAY',
        'subtotal': 800,
        'grand_total': 800,
        'payment_status': 'SETTLED',
        'customer_phone': '03009998877',
        'created_at': '2026-10-25 14:00:00',
      });

      // Guest order (no phone)
      await db.insert('orders', {
        'business_day_id': daySelected,
        'shift_id': shiftSelected,
        'cashier_id': 2,
        'token_number': 203,
        'dining_type': 'TAKEAWAY',
        'subtotal': 400,
        'grand_total': 400,
        'payment_status': 'SETTLED',
        'customer_phone': null,
        'created_at': '2026-10-25 16:00:00',
      });
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Classifies first-time vs returning customers across available history while preserving selected repeat rate', () async {
      final query = AnalyticsQuery(
        startDate: DateTime(2026, 10, 25),
        endDateExclusive: DateTime(2026, 10, 26),
      );

      final service = AnalyticsService(database: db, authService: authService);
      final snapshot = await service.load(query);

      final customerSection = snapshot.section(AnalyticsFamily.customers);
      AnalyticsMetric metric(String id) => customerSection.metrics.firstWhere((m) => m.id == id);

      expect(metric('known_customers').value, 2, reason: 'Customer A and Customer B');
      expect(metric('first_time_customers').value, 1, reason: 'Customer B is first-time');
      expect(metric('returning_customers').value, 1, reason: 'Customer A is returning from 2026-10-20');
      expect(metric('repeat_rate').value, 0, reason: 'Neither placed >=2 orders inside the selected 2026-10-25 range');
      expect(metric('guest_orders').value, 1, reason: '1 order without phone number');

      // Verify row classification
      final customerRows = customerSection.rows.where((r) => r.cells['kind'] == 'Customer aggregate').toList();
      expect(customerRows.length, 2);

      final rowA = customerRows.firstWhere((r) => (r.cells['customer'] as String).endsWith('2233'));
      expect(rowA.cells['history_classification'], 'Returning');
      expect(rowA.cells['first_order_date'], contains('2026-10-20'));

      final rowB = customerRows.firstWhere((r) => (r.cells['customer'] as String).endsWith('8877'));
      expect(rowB.cells['history_classification'], 'First-time');
      expect(rowB.cells['first_order_date'], contains('2026-10-25'));

      // Verify safe masking
      expect(customerSection.rows.map((r) => r.cells.toString()).join(), isNot(contains('03001112233')));
      expect(customerSection.rows.map((r) => r.cells.toString()).join(), isNot(contains('03009998877')));

      // Verify exports
      final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.customers);
      expect(csv, contains('First-time customers'));
      expect(csv, contains('Returning customers'));
      expect(csv, contains('First-time'));
      expect(csv, contains('Returning'));
      expect(csv, isNot(contains('03001112233')));
    });
  });
}
