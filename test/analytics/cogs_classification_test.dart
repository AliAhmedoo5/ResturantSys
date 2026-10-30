import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
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
  late OrderAndCheckoutController orders;

  setUp(() async {
    store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    db = await store.initialize();
    catalog = CatalogAndRecipeController(database: db);
    final auth = AuthService(database: db)
      ..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    analytics = AnalyticsService(database: db, authService: auth);
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: 1);
    await shifts.openShift(staffId: 2, openingFloat: 0);
    orders = OrderAndCheckoutController(database: db);
  });

  tearDown(() => store.close());

  AnalyticsQuery live() => AnalyticsQuery(
    startDate: DateTime(2026),
    endDateExclusive: DateTime(2027),
    live: true,
  );

  test('checkout separates food and packaging COGS at event time by dining type', () async {
    final cat = await catalog.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FFFFFF');
    final burger = await catalog.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 200);
    final patty = await catalog.createRawIngredient(
      name: 'Beef Patty',
      storageUnit: StorageUnit.count,
      currentStock: 100,
      costPerRecipeUnit: 50, // 5000 paisa
    );
    final packaging = await catalog.createRawIngredient(
      name: 'Takeaway Packaging Box',
      storageUnit: StorageUnit.count,
      currentStock: 100,
      costPerRecipeUnit: 10, // 1000 paisa
    );
    await catalog.setRecipeForMenuItem(menuItemId: burger.id, items: [(rawIngredientId: patty.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(burger.id, true);

    // 1. Takeaway checkout consumes 1 patty (FOOD) + 1 automatic packaging box (PACKAGING)
    final takeawayResult = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.takeaway,
      items: [CartItem(menuItem: burger, quantity: 1)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 200)],
    );

    // Verify raw event records in order_cost_events
    final events = await db.query(
      'order_cost_events',
      where: 'order_id = ?',
      whereArgs: [takeawayResult.order.id],
      orderBy: 'id ASC',
    );
    expect(events, hasLength(2));
    final foodEvent = events.firstWhere((e) => e['ingredient_id'] == patty.id);
    final packagingEvent = events.firstWhere((e) => e['ingredient_id'] == packaging.id);

    expect(foodEvent['classification'], 'FOOD');
    expect(foodEvent['cost_paisa'], 5000);
    expect(packagingEvent['classification'], 'PACKAGING');
    expect(packagingEvent['cost_paisa'], 1000);

    // 2. Dine-In checkout consumes 1 patty (FOOD) without automatic packaging
    final dineInResult = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: burger, quantity: 1)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 200)],
    );
    final dineInEvents = await db.query(
      'order_cost_events',
      where: 'order_id = ?',
      whereArgs: [dineInResult.order.id],
    );
    expect(dineInEvents, hasLength(1));
    expect(dineInEvents.single['classification'], 'FOOD');
    expect(dineInEvents.single['cost_paisa'], 5000);

    // 3. Load profitability analytics
    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);

    // Combined realized COGS = 5000 (Takeaway food) + 1000 (Takeaway packaging) + 5000 (Dine-In food) = 11000
    final cogs = report.metrics.firstWhere((m) => m.id == 'cogs').value;
    final foodCogs = report.metrics.firstWhere((m) => m.id == 'food_cogs').value;
    final packagingCogs = report.metrics.firstWhere((m) => m.id == 'packaging_cogs').value;
    final unclassifiedCogs = report.metrics.firstWhere((m) => m.id == 'unclassified_cogs').value;

    expect(cogs, 11000);
    expect(foodCogs, 10000);
    expect(packagingCogs, 1000);
    expect(unclassifiedCogs, 0);
    expect(foodCogs! + packagingCogs! + unclassifiedCogs!, equals(cogs));

    // Dining type metrics breakdown
    final foodDineIn = report.metrics.firstWhere((m) => m.id == 'food_cogs_dine_in').value;
    final packagingDineIn = report.metrics.firstWhere((m) => m.id == 'packaging_cogs_dine_in').value;
    final foodTakeaway = report.metrics.firstWhere((m) => m.id == 'food_cogs_takeaway').value;
    final packagingTakeaway = report.metrics.firstWhere((m) => m.id == 'packaging_cogs_takeaway').value;
    final foodDelivery = report.metrics.firstWhere((m) => m.id == 'food_cogs_delivery').value;
    final packagingDelivery = report.metrics.firstWhere((m) => m.id == 'packaging_cogs_delivery').value;

    expect(foodDineIn, 5000);
    expect(packagingDineIn, 0);
    expect(foodTakeaway, 5000);
    expect(packagingTakeaway, 1000);
    expect(foodDelivery, 0);
    expect(packagingDelivery, 0);

    expect(foodDineIn! + foodTakeaway! + foodDelivery!, equals(foodCogs));
    expect(packagingDineIn! + packagingTakeaway! + packagingDelivery!, equals(packagingCogs));

    // Rows contain classification and dining_type
    final costRows = report.rows.where((r) => r.sourceType == 'order_cost_events').toList();
    expect(costRows, hasLength(3));
    expect(costRows.every((r) => r.cells['dining_type'] != null), isTrue);
    expect(costRows.every((r) => r.cells['classification'] != null), isTrue);
  });

  test('revisions and returns preserve classification faithfully from source event', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Meal', basePrice: 100);
    final ingredient = await catalog.createRawIngredient(
      name: 'Portion',
      storageUnit: StorageUnit.count,
      currentStock: 20,
      costPerRecipeUnit: 20, // 2000 paisa
    );
    await catalog.createRawIngredient(
      name: 'Takeaway packaging',
      storageUnit: StorageUnit.count,
      currentStock: 20,
      costPerRecipeUnit: 5, // 500 paisa
    );
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(item.id, true);

    final checkout = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.takeaway,
      items: [CartItem(menuItem: item, quantity: 2)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 200)],
    );

    await db.update('orders', {'token_status': 'CONFIRMED'}, where: 'id=?', whereArgs: [checkout.order.id]);

    // Update raw ingredient unit cost in catalog - later rate changes must not reprice previous lots
    await db.update('raw_ingredients', {'cost_per_recipe_unit': 90}, where: 'id=?', whereArgs: [ingredient.id]);

    // Revise order: reduce from 2 to 1 (return 1 meal)
    await orders.reviseOrder(
      orderId: checkout.order.id,
      cashierId: 2,
      reason: 'Customer changed mind',
      commandId: 'rev-1',
      newItems: [CartItem(menuItem: item, quantity: 1)],
    );

    final returnEvents = await db.query(
      'order_cost_events',
      where: "kind = 'RETURN'",
      orderBy: 'id ASC',
    );
    expect(returnEvents, hasLength(1));
    final returnEvt = returnEvents.single;
    expect(returnEvt['classification'], 'FOOD');
    expect(returnEvt['cost_paisa'], 2000);
    expect(returnEvt['source_event_id'], isNotNull);

    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    // Realized COGS = (2 * 2000 - 2000) food + 500 packaging = 2500
    expect(report.metrics.firstWhere((m) => m.id == 'food_cogs').value, 2000);
    expect(report.metrics.firstWhere((m) => m.id == 'packaging_cogs').value, 500);
    expect(report.metrics.firstWhere((m) => m.id == 'cogs').value, 2500);
  });

  test('cooked waste disposition preserves classification without deducting from COGS', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Meal', basePrice: 100);
    final ingredient = await catalog.createRawIngredient(
      name: 'Meat',
      storageUnit: StorageUnit.count,
      currentStock: 20,
      costPerRecipeUnit: 30, // 3000 paisa
    );
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(item.id, true);

    final checkout = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: item, quantity: 2)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 200)],
    );

    // Token status PREPARING means cooked cancellation wastes the food
    await db.update('orders', {'token_status': 'PREPARING'}, where: 'id=?', whereArgs: [checkout.order.id]);

    await orders.cancelOrder(
      orderId: checkout.order.id,
      cashierId: 2,
      reason: 'Kitchen burnt the food',
      commandId: 'cmd-test-cogs-cancel',
    );

    final wasteEvents = await db.query(
      'order_cost_events',
      where: "kind = 'COOKED_WASTE'",
      orderBy: 'id ASC',
    );
    expect(wasteEvents, isNotEmpty);
    expect(wasteEvents.first['classification'], 'FOOD');
    expect(wasteEvents.first['source_event_id'], isNotNull);

    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    // Cooked waste remains consumed cost; it does not reduce realized COGS
    expect(report.metrics.firstWhere((m) => m.id == 'food_cogs').value, 6000);
    expect(report.metrics.firstWhere((m) => m.id == 'cogs').value, 6000);
  });

  test('ingredient renaming does not rewrite historical cost classification rows', () async {
    final cat = await catalog.createCategory(name: 'Items', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 100);
    final box = await catalog.createRawIngredient(
      name: 'Takeaway packaging box',
      storageUnit: StorageUnit.count,
      currentStock: 50,
      costPerRecipeUnit: 8,
    );
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: box.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(item.id, true);

    final checkout = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: item, quantity: 1)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)],
    );

    // Initial event recorded as PACKAGING
    final initialEvent = (await db.query(
      'order_cost_events',
      where: 'order_id = ?',
      whereArgs: [checkout.order.id],
    )).single;
    expect(initialEvent['classification'], 'PACKAGING');

    // Rename the ingredient later to something that looks like food
    await db.update('raw_ingredients', {'name': 'Burger Bun Special'}, where: 'id = ?', whereArgs: [box.id]);

    // Historical row MUST remain unchanged as PACKAGING
    final afterRenameEvent = (await db.query(
      'order_cost_events',
      where: 'order_id = ?',
      whereArgs: [checkout.order.id],
    )).single;
    expect(afterRenameEvent['classification'], 'PACKAGING');

    // Immutability trigger prevents direct updates
    await expectLater(
      db.update('order_cost_events', {'classification': 'FOOD'}, where: 'id = ?', whereArgs: [initialEvent['id']]),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('explicit category property on ingredient determines classification', () async {
    final cat = await catalog.createCategory(name: 'Drinks', displayOrder: 1, colorHex: '#FFFFFF');
    final drink = await catalog.createMenuItem(categoryId: cat.id, name: 'Soda', basePrice: 50);
    // Explicit category PACKAGING even without packaging in name
    final cup = await catalog.createRawIngredient(
      name: 'Plastic Cup 350ml',
      storageUnit: StorageUnit.count,
      currentStock: 100,
      costPerRecipeUnit: 3, // 300 paisa
      category: 'PACKAGING',
    );
    await catalog.setRecipeForMenuItem(menuItemId: drink.id, items: [(rawIngredientId: cup.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(drink.id, true);

    final checkout = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: drink, quantity: 2)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)],
    );

    final event = (await db.query(
      'order_cost_events',
      where: 'order_id = ?',
      whereArgs: [checkout.order.id],
    )).single;
    expect(event['classification'], 'PACKAGING');

    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    expect(report.metrics.firstWhere((m) => m.id == 'packaging_cogs').value, 600);
    expect(report.metrics.firstWhere((m) => m.id == 'packaging_cogs_dine_in').value, 600);
    expect(report.metrics.firstWhere((m) => m.id == 'food_cogs').value, 0);
  });

  test('legacy unclassified cost events remain explicit without retroactive guessing', () async {
    // Insert pre-upgrade order with unclassified cost event (null classification)
    final orderId = await db.insert('orders', {
      'business_day_id': 1,
      'shift_id': 1,
      'cashier_id': 2,
      'token_number': 99,
      'dining_type': 'DINE_IN',
      'subtotal': 150,
      'grand_total': 150,
      'payment_status': 'SETTLED',
      'token_status': 'DELIVERED',
      'created_at': '2026-10-25 12:00:00',
    });
    final ingId = await db.insert('raw_ingredients', {
      'name': 'Legacy Ingredient',
      'storage_unit': 'g',
      'current_stock': 10,
      'cost_per_recipe_unit': 10,
      'created_at': '2026-10-25 10:00:00',
    });
    await db.insert('order_cost_coverage', {
      'order_id': orderId,
      'policy': 'EVENT_ACQUISITION_RATE_V1',
      'recorded_at': '2026-10-25 12:00:00',
    });
    await db.insert('order_cost_events', {
      'order_id': orderId,
      'ingredient_id': ingId,
      'revision': 0,
      'kind': 'CONSUME',
      'quantity': 1,
      'unit_cost_rupees': 10,
      'cost_paisa': 1000,
      'classification': null, // legacy unclassified
      'recorded_at': '2026-10-25 12:00:00',
    });

    final report = (await analytics.load(live())).section(AnalyticsFamily.profitability);
    final cogs = report.metrics.firstWhere((m) => m.id == 'cogs').value;
    final foodCogs = report.metrics.firstWhere((m) => m.id == 'food_cogs').value;
    final packagingCogs = report.metrics.firstWhere((m) => m.id == 'packaging_cogs').value;
    final unclassifiedCogs = report.metrics.firstWhere((m) => m.id == 'unclassified_cogs').value;

    expect(cogs, 1000);
    expect(foodCogs, 0);
    expect(packagingCogs, 0);
    expect(unclassifiedCogs, 1000);
    expect(foodCogs! + packagingCogs! + unclassifiedCogs!, equals(cogs));

    final row = report.rows.firstWhere((r) => r.sourceId == '$orderId' || r.cells['order_id'] == orderId);
    expect(row.cells['classification'], 'UNCLASSIFIED');
  });

  test('charts and CSV export reconcile food and packaging safe contributors', () async {
    final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 200);
    final patty = await catalog.createRawIngredient(
      name: 'Burger Patty',
      storageUnit: StorageUnit.count,
      currentStock: 50,
      costPerRecipeUnit: 40, // 4000 paisa
    );
    await catalog.createRawIngredient(
      name: 'Takeaway Packaging',
      storageUnit: StorageUnit.count,
      currentStock: 50,
      costPerRecipeUnit: 8, // 800 paisa
    );
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: patty.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(item.id, true);

    final checkout = await orders.checkoutOrder(
      businessDayId: 1,
      shiftId: 1,
      cashierId: 2,
      diningType: DiningType.takeaway,
      items: [CartItem(menuItem: item, quantity: 1)],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 200)],
    );

    final snapshot = await analytics.load(live());
    final report = snapshot.section(AnalyticsFamily.profitability);

    // Chart: cogs_classification
    final classChart = report.charts.firstWhere((c) => c.id == 'cogs_classification');
    final foodPoint = classChart.points.firstWhere((p) => p.label == 'Food COGS');
    final packagingPoint = classChart.points.firstWhere((p) => p.label == 'Packaging COGS');

    expect(foodPoint.value, 4000);
    expect(packagingPoint.value, 800);
    expect(foodPoint.rows.single.cells['order_id'], checkout.order.id);
    expect(foodPoint.rows.single.cells['classification'], 'FOOD');
    expect(packagingPoint.rows.single.cells['classification'], 'PACKAGING');

    // Chart: cogs_dining_type
    final diningChart = report.charts.firstWhere((c) => c.id == 'cogs_dining_type');
    final takeawayFoodPoint = diningChart.points.firstWhere((p) => p.label == 'Takeaway · Food');
    final takeawayPackagingPoint = diningChart.points.firstWhere((p) => p.label == 'Takeaway · Packaging');

    expect(takeawayFoodPoint.value, 4000);
    expect(takeawayPackagingPoint.value, 800);

    // CSV export includes metrics and classification columns
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.profitability);
    expect(csv, contains('Historical food COGS'));
    expect(csv, contains('Historical packaging COGS'));
    expect(csv, contains('FOOD'));
    expect(csv, contains('PACKAGING'));
    expect(csv, contains('TAKEAWAY'));
  });
}
