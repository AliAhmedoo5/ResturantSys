import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('expense category scope reconciles postings and exports while drawer stays whole', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((r) => r['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final cashierId = people.firstWhere((r) => r['role'] == 'CASHIER')['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    final shift = await shifts.openShift(staffId: cashierId, openingFloat: 1000);
    final operations = OperationsController(db);
    final utilities = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    final repairs = await operations.saveCategory(managerId: managerId, name: 'Repairs');
    for (final item in [(utilities, 12000), (repairs, 7000)]) {
      await operations.postExpense(managerId: managerId, categoryId: item.$1,
        amountPaisa: item.$2, description: 'Synthetic expense', source: FundingSource.drawer,
        shiftId: shift.id, reason: 'Paid', requestKey: 'filter-${item.$1}');
    }
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100),
      live: true, domainFilters: {AnalyticsDimension.expenseCategory: '$utilities'});
    final snapshot = await service.load(query);
    expect(snapshot.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'operating_expense').value, 12000);
    expect(snapshot.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Expense ledger'), hasLength(1));
    expect(snapshot.section(AnalyticsFamily.cash).metrics.singleWhere((m) => m.id == 'expected_drawer').value, 81000);
    expect(snapshot.filterOptions.singleWhere((o) => o.dimension == AnalyticsDimension.expenseCategory && o.id == '$utilities').label, 'Utilities');
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(csv, contains('expenseCategory'));
    expect(csv, contains('Utilities'));
    expect(snapshot.notes.join(' '), contains('outside scope'));
    final clear = await service.load(query.copyWith(domainFilters: {}));
    expect(clear.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'operating_expense').value, 19000);
    expect(snapshot.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'operating_expense').value, 12000);
  });
}
