import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/discount_rules.dart';
import 'package:resturant_sys/core/catalog/discount_stack.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/inventory/stock_count_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late PosDatabase store;
  late Database db;
  late CatalogAndRecipeController catalog;
  late AnalyticsService analytics;
  setUp(() async {
    store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    db = await store.initialize();
    catalog = CatalogAndRecipeController(database: db);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    analytics = AnalyticsService(database: db, authService: auth);
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: 1);
    await shifts.openShift(staffId: 2, openingFloat: 0);
  });
  tearDown(() => store.close());
  AnalyticsQuery live() => AnalyticsQuery(startDate: DateTime(2026), endDateExclusive: DateTime(2027), live: true);

  test('sale COGS and gross profit survive later ingredient price changes', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Meal', basePrice: 100);
    final ingredient = await catalog.createRawIngredient(name: 'Portion', storageUnit: StorageUnit.count, currentStock: 10, costPerRecipeUnit: 20);
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 2.0)]);
    await catalog.toggleMenuItemActive(item.id, true);
    await OrderAndCheckoutController(database: db).checkoutOrder(businessDayId: 1, shiftId: 1, cashierId: 2,
      diningType: DiningType.dineIn, items: [CartItem(menuItem: item)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    await db.update('raw_ingredients', {'cost_per_recipe_unit': 90}, where: 'id=?', whereArgs: [ingredient.id]);
    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    expect(report.metrics.firstWhere((m) => m.id == 'cogs').value, 4000);
    expect(report.metrics.firstWhere((m) => m.id == 'gross_profit').value, 6000);
  });

  test('posted physical variance is visible with its movement evidence', () async {
    final ingredient = await catalog.createRawIngredient(name: 'Cups', storageUnit: StorageUnit.count, currentStock: 10, costPerRecipeUnit: 2);
    final counts = StockCountController(db);
    final id = await counts.start(managerId: 1, ingredientIds: [ingredient.id], reason: 'Shelf count');
    await counts.submit(managerId: 1, id: id, quantities: {ingredient.id: 8});
    await counts.review(managerId: 1, id: id, approve: true);
    await counts.post(managerId: 1, id: id);
    final report = (await analytics.load(live())).section(AnalyticsFamily.inventory);
    final row = report.rows.singleWhere((r) => r.cells['kind'] == 'Physical count');
    expect(row.cells['variance'], -2);
    expect(row.cells['movement_id'], isNotNull);
    expect(row.cells['status'], 'POSTED');
  });

  test('stacking uses remaining eligible balances and is independent of click order', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Meal', basePrice: 100);
    final lines = [CartItem(menuItem: item)];
    const percent = DiscountPreset(id: 1, name: 'Half', type: DiscountType.percentage, value: 50, isActive: true, rules: DiscountRules(stackable: true));
    const flat = DiscountPreset(id: 2, name: 'Ten', type: DiscountType.flat, value: 10, isActive: true, rules: DiscountRules(stackable: true));
    expect(DiscountStack.amounts(items: lines, discounts: [flat, percent]), {1: 5000, 2: 1000});
    expect(DiscountStack.amounts(items: lines, discounts: [percent, flat]), {1: 5000, 2: 1000});
    expect(() => DiscountStack.amounts(items: lines, discounts: [percent, percent]), throwsArgumentError);
    expect(() => DiscountStack.amounts(items: lines, discounts: [percent, flat.copyWith(rules: const DiscountRules())]), throwsStateError);
    final capped = DiscountStack.amounts(items: lines, discounts: [percent, flat.copyWith(value: 999)]);
    expect(capped.values.reduce((a, b) => a + b), 10000);
  });

  test('stacked checkout snapshots each preset and enforces each daily limit once', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Meal', basePrice: 100);
    final ingredient = await catalog.createRawIngredient(name: 'Portion', storageUnit: StorageUnit.count, costPerRecipeUnit: 10);
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(item.id, true);
    for (var i = 0; i < 2; i++) {
      await catalog.saveManagedDiscount(managerId: 1, create: true, preset: DiscountPreset(id: 0, name: 'Offer $i', type: DiscountType.flat,
        value: 10, isActive: true, rules: const DiscountRules(stackable: true, dailyLimit: 1)));
    }
    final discounts = await catalog.getDiscountPresets();
    final controller = OrderAndCheckoutController(database: db);
    Future<CheckoutResult> pay(String command) => controller.checkoutOrder(commandId: command, businessDayId: 1, shiftId: 1, cashierId: 2,
      diningType: DiningType.dineIn, items: [CartItem(menuItem: item)], discounts: discounts,
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 80)]);
    final first = await pay('once');
    expect((await pay('once')).order.id, first.order.id);
    expect(await db.query('order_discounts'), hasLength(2));
    await expectLater(pay('twice'), throwsStateError);
    expect(await db.query('orders'), hasLength(1));
  });

  test('raw returns reverse original cost and cooked cancellations never double count', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Meal', basePrice: 100);
    final ingredient = await catalog.createRawIngredient(name: 'Portion', storageUnit: StorageUnit.count, currentStock: 20, costPerRecipeUnit: 20);
    final packaging = await catalog.createRawIngredient(name: 'Takeaway packaging', storageUnit: StorageUnit.count, currentStock: 20, costPerRecipeUnit: 5);
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(item.id, true);
    final controller = OrderAndCheckoutController(database: db);
    Future<CheckoutResult> pay() => controller.checkoutOrder(businessDayId: 1, shiftId: 1, cashierId: 2,
      diningType: DiningType.takeaway, items: [CartItem(menuItem: item)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    final raw = await pay();
    await db.update('orders', {'token_status': 'CONFIRMED'}, where: 'id=?', whereArgs: [raw.order.id]);
    await db.update('raw_ingredients', {'cost_per_recipe_unit': 90}, where: 'id=?', whereArgs: [ingredient.id]);
    await controller.cancelOrder(orderId: raw.order.id, cashierId: 2, reason: 'Unstarted', commandId: 'raw-cancel');
    var report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    expect(report.metrics.firstWhere((m) => m.id == 'cogs').value, 0);
    expect((await catalog.getRawIngredient(packaging.id)).currentStock, 20);
    final cooked = await pay();
    await controller.cancelOrder(orderId: cooked.order.id, cashierId: 2, reason: 'Cooked', commandId: 'cooked-cancel');
    await controller.cancelOrder(orderId: cooked.order.id, cashierId: 2, reason: 'Cooked', commandId: 'cooked-cancel');
    report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    expect(report.metrics.firstWhere((m) => m.id == 'cogs').value, 9500);
    expect(report.metrics.firstWhere((m) => m.id == 'gross_profit').value, -9500);
    expect(report.metrics.firstWhere((m) => m.id == 'net_profit').value, -9500);
  });

  test('unknown rates and pre-upgrade orders withhold profit instead of inventing zero costs', () async {
    await db.insert('orders', {'business_day_id': 1, 'shift_id': 1, 'cashier_id': 2, 'token_number': 1,
      'dining_type': 'DINE_IN', 'subtotal': 100, 'grand_total': 100, 'payment_status': 'SETTLED', 'created_at': DateTime.now().toIso8601String()});
    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    expect(report.metrics.firstWhere((m) => m.id == 'cogs').value, isNull);
    expect(report.metrics.firstWhere((m) => m.id == 'net_profit').value, isNull);
  });
}
