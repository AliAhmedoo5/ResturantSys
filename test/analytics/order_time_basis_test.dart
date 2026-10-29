import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('overnight order changes calendar bucket without changing its Business Day', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at': '2026-10-29T13:00:00Z', 'status': 'OPEN', 'opened_by_staff_id': manager['id']});
    final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': cashier['id'], 'opened_at': '2026-10-29T13:00:00Z', 'opening_float': 0, 'status': 'OPEN'});
    Future<int> order(int token, String time) => db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': cashier['id'], 'token_number': token, 'dining_type': 'TAKEAWAY', 'subtotal': 100, 'grand_total': 100, 'payment_status': 'SETTLED', 'created_at': time});
    await order(1, '2026-10-29T18:59:59Z'); // 23:59:59 Karachi
    final overnight = await order(2, '2026-10-29T20:00:00Z'); // 01:00 next date
    await order(3, '2026-10-31T00:00:00+05:00'); // Exclusive end
    final service = AnalyticsService(database: db, authService: auth);
    final operational = AnalyticsQuery(startDate: DateTime(2026, 10, 29), endDateExclusive: DateTime(2026, 10, 30));
    final calendar = operational.copyWith(startDate: DateTime(2026, 10, 30), endDateExclusive: DateTime(2026, 10, 31), timeBasis: AnalyticsTimeBasis.calendarTime, grouping: AnalyticsGrouping.week);
    final before = await service.load(operational);
    final after = await service.load(calendar);
    expect(before.section(AnalyticsFamily.orders).rows.where((r) => r.sourceType == 'orders').length, 3);
    final rows = after.section(AnalyticsFamily.orders).rows.where((r) => r.sourceType == 'orders').toList();
    expect(rows.map((r) => r.sourceId), ['$overnight']);
    expect(rows.single.cells['business_day_id'], day);
    expect(after.businessDayIds, contains(day));
    expect(after.query.timeBasis, AnalyticsTimeBasis.calendarTime);
    expect(after.query.grouping, AnalyticsGrouping.week);
    final bucket = after.section(AnalyticsFamily.sales).rows.singleWhere((r) => r.cells['kind'] == 'Daily total');
    expect(bucket.cells['period_start'], '2026-10-26'); // Monday
    expect(bucket.cells['recorded_value_paisa'], 10000);
    final csv = AnalyticsExportService().csv(after, AnalyticsFamily.sales);
    expect(csv, contains('calendarTime'));
    expect(csv, contains('week'));
    expect(csv, contains('Monday'));
    auth.session.lock();
    await expectLater(service.load(calendar), throwsStateError);
  });

  test('query retains time basis and grouping across filter and date changes', () {
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 11, 1));
    expect(query.timeBasis, AnalyticsTimeBasis.businessDay);
    final calendar = query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime, grouping: AnalyticsGrouping.month);
    expect(calendar, isNot(query));
    expect(calendar.copyWith(shiftId: 2).timeBasis, AnalyticsTimeBasis.calendarTime);
    expect(calendar.copyWith(shiftId: 2).grouping, AnalyticsGrouping.month);
  });

  test('same-date Business Days remain distinct even when one has no Orders', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final days = <int>[];
    for (final hour in [8, 18]) {
      days.add(await db.insert('business_days', {'opened_at': '2026-10-29 ${hour.toString().padLeft(2, '0')}:00:00', 'status': 'OPEN', 'opened_by_staff_id': manager['id']}));
    }
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2026, 10, 29), endDateExclusive: DateTime(2026, 10, 30)));
    final rows = snapshot.section(AnalyticsFamily.sales).rows.where((r) => r.cells['kind'] == 'Daily total').toList();
    expect(rows.map((r) => r.cells['business_day_id']), days);
    expect(rows.map((r) => r.sourceId), days.map((id) => '$id'));
    expect(rows.map((r) => r.cells['orders']), [0, 0]);
    expect(snapshot.businessDayIds, days);
  });
}
