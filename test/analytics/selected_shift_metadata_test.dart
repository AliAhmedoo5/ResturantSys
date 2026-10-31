import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('selected opening-float-only Shift retains its Business Day in snapshot and export metadata', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    final shift = await shifts.openShift(staffId: cashier['id'] as int, openingFloat: 123);
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    addTearDown(auth.session.dispose);
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2020, 1, 2), shiftId: shift.id));
    final cash = snapshot.section(AnalyticsFamily.cash);
    expect(cash.metrics.singleWhere((m) => m.id == 'opening_float').value, 12300);
    expect(cash.rows.singleWhere((r) => r.cells['kind'] == 'Shift reconciliation').cells['business_day_id'], day.id);
    expect(snapshot.businessDayIds, [day.id]);
    expect(AnalyticsExportService().csv(snapshot, AnalyticsFamily.cash), contains('business_day_ids,${day.id}'));
  });
}
