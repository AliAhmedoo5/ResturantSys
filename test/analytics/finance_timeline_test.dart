import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('Manager finance timeline separates source, recorder and drawer owner without duplicate cash', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final cashier = people.firstWhere((p) => p['role'] == 'CASHIER');
    final managerId = manager['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    final shift = await shifts.openShift(staffId: cashier['id'] as int, openingFloat: 1000);
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    final id = await operations.postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 12000, description: 'Electricity', source: FundingSource.drawer,
      shiftId: shift.id, reason: 'Paid', requestKey: 'drawer-expense');
    await operations.postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 7000, description: 'Bank bill', source: FundingSource.bank,
      reason: 'Paid externally', requestKey: 'bank-expense');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final report = (await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100), live: true)))
      .section(AnalyticsFamily.expenses);
    final events = report.rows.where((r) => r.cells['kind'] == 'Finance payment').toList();
    expect(events, hasLength(2));
    final drawer = events.singleWhere((r) => r.cells['payment_source'] == 'DRAWER');
    expect(drawer.cells['source_id'], id);
    expect(drawer.cells['recorded_by'], managerId);
    expect(drawer.cells['shift_owner_id'], cashier['id']);
    expect(drawer.cells['amount_paisa'], -12000);
    expect(drawer.cells['actual_at'], isNotNull);
    expect(drawer.cells['recorded_at'], isNotNull);
    expect(events.singleWhere((r) => r.cells['payment_source'] == 'BANK').cells['shift_id'], isNull);
    expect(report.metrics.singleWhere((m) => m.id == 'finance_drawer_outflow').value, 12000);
    expect(report.metrics.singleWhere((m) => m.id == 'finance_bank_outflow').value, 7000);
  });
}
