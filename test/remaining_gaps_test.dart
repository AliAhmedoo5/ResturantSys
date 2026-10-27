import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
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
}
