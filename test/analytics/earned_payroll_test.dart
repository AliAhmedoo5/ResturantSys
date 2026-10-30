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
  test('earned month reconciles accrual, advance recovery and later bank payment without another expense', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final employee = people.firstWhere((p) => p['role'] == 'CASHIER')['id'] as int;
    await ShiftAndCashController(database: db).openBusinessDay(openedByStaffId: managerId);
    final operations = OperationsController(db);
    await operations.setSalary(managerId: managerId, employeeId: employee,
      effectivePeriod: '2020-10', amountPaisa: 4650000, reason: 'Agreed monthly salary');
    await operations.postPayroll(managerId: managerId, employeeId: employee, period: '2020-10',
      kind: 'ADVANCE', amountPaisa: 500000, source: FundingSource.owner,
      reason: 'October salary advance', requestKey: 'earned-advance');
    final accrual = await operations.postPayroll(managerId: managerId, employeeId: employee, period: '2020-10',
      kind: 'ACCRUAL', amountPaisa: 2400000, reason: 'Prorated 16 days joined 16 October', requestKey: 'earned-accrual');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020, 10), endDateExclusive: DateTime(2020, 11));
    final unpaid = await service.load(query);
    num? value(AnalyticsSnapshot s, String id) => s.section(AnalyticsFamily.staff).metrics.singleWhere((m) => m.id == id).value;
    expect(value(unpaid, 'earned_salary'), 2400000);
    expect(value(unpaid, 'earned_unpaid'), 2400000);
    expect(value(unpaid, 'earned_advances'), 500000);
    await operations.postPayroll(managerId: managerId, employeeId: employee, period: '2020-10',
      kind: 'RECOVERY', amountPaisa: 500000, reason: 'Explicit advance recovery', requestKey: 'earned-recovery');
    await operations.postPayroll(managerId: managerId, employeeId: employee, period: '2020-10',
      kind: 'PAYMENT', amountPaisa: 1900000, source: FundingSource.bank,
      reason: 'Later bank salary payment', requestKey: 'earned-payment');
    final settled = await service.load(query);
    expect(value(settled, 'earned_salary'), 2400000);
    expect(value(settled, 'earned_paid'), 1900000);
    expect(value(settled, 'earned_recovered'), 500000);
    expect(value(settled, 'earned_unpaid'), 0);
    expect(value(settled, 'labor_cost'), 0);
    expect(value(unpaid, 'earned_unpaid'), 2400000);
    final evidence = settled.section(AnalyticsFamily.staff).rows.where((r) => r.sourceType == 'payroll_entries');
    expect(evidence, hasLength(4));
    expect(evidence.singleWhere((r) => r.sourceId == '$accrual').cells['earned_period'], '2020-10');
    final payment = evidence.singleWhere((r) => r.cells['payroll_kind'] == 'PAYMENT');
    expect(payment.cells['payment_source'], 'BANK');
    expect(payment.cells['payment_event_id'], isNotNull);
    expect(payment.cells['actual_at'], isNotNull);
    expect(payment.cells['recorded_at'], isNotNull);
    expect(payment.cells['business_day_id'], isNotNull);
    final current = await service.load(AnalyticsQuery(startDate: DateTime(2026), endDateExclusive: DateTime(2100), live: true));
    expect(current.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'finance_bank_outflow').value, 1900000);
    final csv = AnalyticsExportService().csv(settled, AnalyticsFamily.staff);
    expect(csv, contains('2020-10'));
    expect(csv, contains('2400000'));
    expect(csv, contains('payment event id'));
    expect(csv, contains('BANK'));
  });
}
