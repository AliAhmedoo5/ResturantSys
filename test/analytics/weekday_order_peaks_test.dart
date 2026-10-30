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
}
