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
  test('confirmed workload retains cancellation once and excludes Holds and revisions', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Workload', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Workload tea', basePrice: 100);
    await publishFixtures(catalog);
    final line = CartItem(menuItem: await catalog.getMenuItem(menu.id));
    final controller = OrderAndCheckoutController(database: db);
    await controller.holdCart(cashierId: 2, label: 'Not confirmed', items: [line], diningType: DiningType.dineIn);
    final first = await controller.checkoutOrder(commandId: 'workload-1', businessDayId: day.id, shiftId: shift.id,
      cashierId: 2, diningType: DiningType.dineIn, items: [line],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    await controller.checkoutOrder(commandId: 'workload-2', businessDayId: day.id, shiftId: shift.id,
      cashierId: 2, diningType: DiningType.dineIn, items: [line],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    await controller.cancelOrder(orderId: first.order.id, cashierId: 2, reason: 'Customer Cancelled', commandId: 'cancel-workload');
    await controller.recordCashierRefund(orderId: first.order.id, shiftId: shift.id, cashierId: 2,
      amountPaisa: 10000, method: PaymentMethod.cash, reason: 'Cancelled Order refund', commandId: 'workload-refund');
    final local = DateTime.now().toUtc().add(const Duration(hours: 5));
    final date = DateTime.utc(local.year, local.month, local.day);
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: date.subtract(const Duration(days: 1)), endDateExclusive: date.add(const Duration(days: 1))));
    final section = snapshot.section(AnalyticsFamily.orders);
    final daily = section.rows.singleWhere((r) => r.cells['kind'] == 'Daily workload');
    expect(daily.cells['confirmed_orders'], 2);
    expect(daily.cells['eligible_orders'], 1);
    expect(daily.cells['recorded_value_paisa'], 10000);
    expect(daily.cells['average_ticket_paisa'], 10000);
    expect(daily.cells['cancelled_orders'], 1);
    expect(daily.cells['order_ids'], '1,2');
    final hourly = section.rows.where((r) => r.cells['kind'] == 'Hourly workload').toList();
    expect(hourly, hasLength(24));
    expect(hourly.fold<int>(0, (sum, r) => sum + (r.cells['confirmed_orders'] as int)), 2);
    final chart = section.charts.singleWhere((c) => c.id == 'workload_hours');
    expect(chart.points.fold<num>(0, (sum, p) => sum + (p.value ?? 0)), 2);
    expect(chart.points.expand((p) => p.rows).map((r) => r.sourceId).toSet(), {'1', '2'});
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.orders);
    expect(csv, contains('Daily workload'));
    expect(csv, contains('Hourly workload'));
    expect(csv, contains('eligible_orders'));
    expect(() => daily.cells.clear(), throwsUnsupportedError);
  });
}

