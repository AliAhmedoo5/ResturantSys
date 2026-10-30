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
  test('actual-time money peaks retain tied outflows, signed net and immutable export contributors', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId, openedAt: DateTime(2026, 10, 25, 18));
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    for (final hour in [1, 2]) {
      await operations.postExpense(managerId: managerId, categoryId: category,
        amountPaisa: 7000, description: 'Bank payment', source: FundingSource.bank,
        actualAt: DateTime.parse('2026-10-26T0$hour:00:00+05:00'),
        reason: 'Verified late entry', requestKey: 'bank-$hour');
    }
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 26), endDateExclusive: DateTime(2026, 10, 27), timeBasis: AnalyticsTimeBasis.calendarTime);
    final snapshot = await service.load(query);
    final section = snapshot.section(AnalyticsFamily.expenses);
    final hours = section.rows.where((r) => r.cells['kind'] == 'Hourly money flow' && r.cells['funding_stream'] == 'BANK').toList();
    final peaks = hours.where((r) => r.cells['outflow_peak'] == true).toList();
    expect(peaks.map((r) => r.cells['hour']), [1, 2]);
    expect(peaks.map((r) => r.cells['outflow_paisa']), [7000, 7000]);
    expect(peaks.map((r) => r.cells['net_paisa']), [-7000, -7000]);
    expect(peaks.every((r) => r.cells['least_net_rank'] == 1), isTrue);
    final day = section.rows.singleWhere((r) => r.cells['kind'] == 'Period money flow' && r.cells['funding_stream'] == 'BANK');
    expect(day.cells['inflow_paisa'], 0);
    expect(day.cells['outflow_paisa'], 14000);
    expect(day.cells['net_paisa'], -14000);
    expect(section.charts.any((c) => c.id == 'money_BANK_outflow_hours'), isTrue);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(csv, contains('Hourly money flow'));
    expect(csv, contains('least net rank'));
    expect(csv, contains('-14000'));
    final outside = await service.load(query.copyWith(startDate: DateTime(2026, 10, 26, 2, 0, 1)));
    expect(outside.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Money flow contributor'), isEmpty);
    expect(day.cells['net_paisa'], -14000, reason: 'Earlier snapshot stays immutable');
  });
}
