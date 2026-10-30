import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import '../orders/order_and_checkout_controller_test.dart' show publishFixtures;

void main() {
  setUpAll(sqfliteFfiInit);
  test('weekday average includes completed zero-order days and separates open activity', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    final shifts = ShiftAndCashController(database: db);
    final now = DateTime.now().toUtc();
    final day = await shifts.openBusinessDay(openedByStaffId: 1, openedAt: now.subtract(const Duration(days: 14)));
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Weekdays', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Tea', basePrice: 100);
    await publishFixtures(catalog);
    final orders = OrderAndCheckoutController(database: db);
    Future<void> checkout(int dayId, int shiftId, String key) async {
      await orders.checkoutOrder(commandId: key, businessDayId: dayId, shiftId: shiftId,
        cashierId: 2, diningType: DiningType.dineIn,
        items: [CartItem(menuItem: await catalog.getMenuItem(menu.id))],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    }
    await checkout(day.id, shift.id, 'weekday-completed');
    await shifts.closeShift(shiftId: shift.id, staffId: 2, countedCash: 100);
    await shifts.closeBusinessDay(closedByStaffId: 1);
    await shifts.openBusinessDay(openedByStaffId: 1, openedAt: now.subtract(const Duration(days: 7)));
    final zeroShift = await shifts.openShift(staffId: 2, openingFloat: 0);
    await shifts.closeShift(shiftId: zeroShift.id, staffId: 2, countedCash: 0);
    await shifts.closeBusinessDay(closedByStaffId: 1);
    final open = await shifts.openBusinessDay(openedByStaffId: 1, openedAt: now);
    final liveShift = await shifts.openShift(staffId: 2, openingFloat: 0);
    await checkout(open.id, liveShift.id, 'weekday-open');
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100)));
    final section = snapshot.section(AnalyticsFamily.orders);
    final weekdays = section.rows.where((r) => r.cells['kind'] == 'Weekday comparison');
    expect(weekdays, hasLength(7));
    final active = weekdays.singleWhere((r) => r.cells['completed_business_days'] == 2);
    expect(active.cells['completed_confirmed_orders'], 1);
    expect(active.cells['confirmed_orders'], 2);
    expect(active.cells['orders_per_completed_day'], 0.5);
    expect(active.cells['open_business_days'], 1);
    expect(active.cells['open_confirmed_orders'], 1);
    expect(weekdays.where((r) => r != active).every((r) => r.cells['orders_per_completed_day'] == null), isTrue);
    final chart = section.charts.singleWhere((c) => c.id == 'weekday_average');
    expect(chart.points.first.value, 0.5);
    expect(chart.points.first.explanation, contains('1 / 2'));
    expect(AnalyticsExportService().csv(snapshot, AnalyticsFamily.orders), contains('orders per completed day'));
    expect(() => active.cells.clear(), throwsUnsupportedError);
  });
  test('overnight weekdays, observed hours and week/month buckets follow selected time basis', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    // Retained historical import evidence; no mutation of sealed recording times.
    final day = await db.insert('business_days', {'opened_at': '2026-09-30T18:00:00+05:00', 'status': 'OPEN', 'opened_by_staff_id': 1});
    final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': 2,
      'opened_at': '2026-09-30T18:00:00+05:00', 'closed_at': '2026-10-01T02:00:00+05:00', 'opening_float': 0, 'status': 'CLOSED'});
    await db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': 2,
      'token_number': 1, 'dining_type': 'TAKEAWAY', 'subtotal': 100, 'grand_total': 100,
      'payment_status': 'SETTLED', 'created_at': '2026-09-30T20:00:00Z'});
    await db.update('business_days', {'status': 'CLOSED', 'closed_at': '2026-10-01T02:00:00+05:00'}, where: 'id=?', whereArgs: [day]);
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 9, 1), endDateExclusive: DateTime(2026, 11, 1));
    final operational = await service.load(query);
    final rows = operational.section(AnalyticsFamily.orders).rows;
    final matrix = rows.where((r) => r.cells['kind'] == 'Weekday/hour workload');
    expect(matrix, hasLength(168));
    expect(matrix.singleWhere((r) => r.cells['weekday'] == 3 && r.cells['hour'] == 1).cells['confirmed_orders'], 1);
    expect(matrix.singleWhere((r) => r.cells['weekday'] == 3 && r.cells['hour'] == 0).cells['confirmed_orders'], 0);
    expect(matrix.singleWhere((r) => r.cells['weekday'] == 2 && r.cells['hour'] == 0).cells['confirmed_orders'], isNull);
    final week = rows.singleWhere((r) => r.cells['kind'] == 'Weekly workload');
    expect(week.cells['period_start'], '2026-09-28');
    expect(week.cells['period_end_exclusive'], '2026-10-05');
    expect(rows.singleWhere((r) => r.cells['kind'] == 'Monthly workload').cells['period_start'], '2026-09-01');
    final calendar = await service.load(query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime));
    final calendarRows = calendar.section(AnalyticsFamily.orders).rows;
    final thursday = calendarRows.singleWhere((r) => r.cells['kind'] == 'Calendar weekday total' && r.cells['weekday'] == 4);
    expect(thursday.cells['confirmed_orders'], 1);
    expect(thursday.cells['orders_per_completed_day'], isNull);
    expect(calendarRows.singleWhere((r) => r.cells['kind'] == 'Weekday/hour workload' && r.cells['weekday'] == 4 && r.cells['hour'] == 1).cells['confirmed_orders'], 1);
    expect(calendarRows.singleWhere((r) => r.cells['kind'] == 'Monthly workload' && r.cells['period_start'] == '2026-10-01').cells['confirmed_orders'], 1);
    final csv = AnalyticsExportService().csv(calendar, AnalyticsFamily.orders);
    expect(csv, contains('2026-10-05'));
    expect(csv, contains('Calendar weekday'));
    expect(calendar.section(AnalyticsFamily.orders).charts.any((c) => c.id == 'workload_weeks'), isTrue);
    final overnightOnly = await service.load(query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime,
      startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)));
    final coveredZero = overnightOnly.section(AnalyticsFamily.orders).rows.singleWhere((r) => r.cells['kind'] == 'Weekday/hour workload' && r.cells['weekday'] == 4 && r.cells['hour'] == 0);
    expect(coveredZero.cells['confirmed_orders'], 0);
    expect(coveredZero.cells['contributing_business_day_ids'], '$day');
    final shifts = ShiftAndCashController(database: db);
    final zeroDay = await shifts.openBusinessDay(openedByStaffId: 1, openedAt: DateTime.parse('2026-09-23T18:00:00+05:00'));
    await shifts.closeBusinessDay(closedByStaffId: 1, closedAt: DateTime.parse('2026-09-24T02:00:00+05:00'));
    final emptyOvernight = await service.load(query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime,
      startDate: DateTime(2026, 9, 24), endDateExclusive: DateTime(2026, 9, 25)));
    final observedHours = emptyOvernight.section(AnalyticsFamily.orders).rows.where((r) => r.cells['kind'] == 'Weekday/hour workload');
    final zeroHour = observedHours.singleWhere((r) => r.cells['weekday'] == 4 && r.cells['hour'] == 1);
    expect(zeroHour.cells['confirmed_orders'], 0, reason: 'A prior-date zero-order Business Day still supplies observed overnight calendar coverage');
    expect(zeroHour.cells['contributing_business_day_ids'], '${zeroDay.id}');
    expect(observedHours.singleWhere((r) => r.cells['weekday'] == 4 && r.cells['hour'] == 2).cells['confirmed_orders'], isNull,
      reason: 'Closure is exclusive; later calendar hours are not observed zeros');
  });
}
