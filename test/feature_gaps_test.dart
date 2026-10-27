import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/discount_rules.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/inventory/stock_count_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/settings/keyboard_shortcut_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'orders/order_and_checkout_controller_test.dart' show publishFixtures;

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory temp;
  late PosDatabase pos;
  late Database db;
  late CatalogAndRecipeController catalog;
  late StockCountController counts;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('feature_gaps_');
    pos = PosDatabase(factory: databaseFactoryFfi, customPath: '${temp.path}/pos.db');
    db = await pos.initialize();
    catalog = CatalogAndRecipeController(database: db);
    counts = StockCountController(db);
  });
  tearDown(() async { await pos.close(); await temp.delete(recursive: true); });

  test('count requires Manager, approval, persists evidence and posts once', () async {
    final ingredient = await catalog.createRawIngredient(name: 'Flour', storageUnit: StorageUnit.kg,
      currentStock: 10, costPerRecipeUnit: 0.2);
    await expectLater(counts.start(managerId: 2, ingredientIds: [ingredient.id], reason: 'Weekly'), throwsStateError);
    final id = await counts.start(managerId: 1, ingredientIds: [ingredient.id], reason: 'Weekly');
    await expectLater(counts.submit(managerId: 1, id: id, quantities: {ingredient.id: -1}), throwsArgumentError);
    await counts.submit(managerId: 1, id: id, quantities: {ingredient.id: 8.5});
    await expectLater(counts.post(managerId: 1, id: id), throwsStateError);
    await counts.review(managerId: 1, id: id, approve: true);
    await counts.post(managerId: 1, id: id);
    await counts.post(managerId: 1, id: id);
    expect((await catalog.getRawIngredient(ingredient.id)).currentStock, 8.5);
    final line = (await counts.lines(1, id)).single;
    expect(line['variance'], -1.5);
    expect(line['estimated_cost_paisa'], -30000);
    expect(line['movement_id'], isNotNull);
    expect(await db.query('inventory_movements'), hasLength(2));
    await expectLater(db.update('stock_count_lines', {'counted': 99}, where: 'count_id=?', whereArgs: [id]), throwsA(isA<DatabaseException>()));
    await pos.close(); db = await pos.initialize();
    expect((await StockCountController(db).sessions(1)).single['status'], 'POSTED');
  });

  test('receipt during count and movement after approval require recount without stock changes', () async {
    final ingredient = await catalog.createRawIngredient(name: 'Cups', storageUnit: StorageUnit.count, currentStock: 10);
    final stale = await counts.start(managerId: 1, ingredientIds: [ingredient.id], reason: 'Shelf');
    await db.rawUpdate('UPDATE raw_ingredients SET current_stock=current_stock+5 WHERE id=?', [ingredient.id]);
    await expectLater(counts.submit(managerId: 1, id: stale, quantities: {ingredient.id: 9}), throwsStateError);
    final fresh = await counts.start(managerId: 1, ingredientIds: [ingredient.id], reason: 'Recount');
    await counts.submit(managerId: 1, id: fresh, quantities: {ingredient.id: 14});
    await counts.review(managerId: 1, id: fresh, approve: true);
    await db.rawUpdate('UPDATE raw_ingredients SET current_stock=current_stock-2 WHERE id=?', [ingredient.id]);
    await expectLater(counts.post(managerId: 1, id: fresh), throwsStateError);
    expect((await catalog.getRawIngredient(ingredient.id)).currentStock, 13);
    expect((await counts.lines(1, fresh)).single['movement_id'], isNull);
  });

  test('changing storage unit invalidates a count even without a balance movement', () async {
    final ingredient = await catalog.createRawIngredient(name: 'Flour', storageUnit: StorageUnit.kg, currentStock: 10);
    final id = await counts.start(managerId: 1, ingredientIds: [ingredient.id], reason: 'Shelf');
    await db.update('raw_ingredients', {'storage_unit': 'g'}, where: 'id=?', whereArgs: [ingredient.id]);
    await expectLater(counts.submit(managerId: 1, id: id, quantities: {ingredient.id: 8}), throwsStateError);
    expect((await catalog.getRawIngredient(ingredient.id)).currentStock, 10);
  });

  test('scoped discount uses integer paisa, min spend, cap, dates, overnight window and role', () {
    final lines = [CartItem(menuItem: const MenuItem(id: 1, categoryId: 1, name: 'Burger', basePrice: 100.05)),
      CartItem(menuItem: const MenuItem(id: 2, categoryId: 2, name: 'Drink', basePrice: 100))];
    final discount = DiscountPreset(id: 1, name: 'Night', type: DiscountType.percentage, value: 50, isActive: true,
      rules: DiscountRules(minimumSpendPaisa: 20000, maximumDiscountPaisa: 4500,
        startsAt: DateTime(2026, 1, 1), endsAt: DateTime(2027, 1, 1), startMinute: 22 * 60, endMinute: 2 * 60,
        diningModes: ['TAKEAWAY'], categoryIds: [1], cashierIds: [2]));
    double price({String mode = 'TAKEAWAY', int cashier = 2, DateTime? time, double subtotal = 200.05}) =>
      discount.calculateDiscount(subtotal, items: lines, diningMode: mode, cashierId: cashier, now: time ?? DateTime(2026, 10, 27, 23));
    expect(price(), 45);
    expect(price(time: DateTime(2026, 10, 28, 1)), 45);
    expect(price(time: DateTime(2026, 10, 28, 12)), 0);
    expect(price(mode: 'DINE_IN'), 0);
    expect(price(cashier: 3), 0);
    expect(price(subtotal: 199), 0);
    expect(price(time: DateTime(2027, 1, 1)), 0);
    expect(discount.copyWith(rules: const DiscountRules(categoryIds: [1])).calculateDiscount(200.05, items: lines), 50.03);
  });

  test('checkout rejects changed terms, enforces daily capacity atomically, audits Manager changes', () async {
    final category = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Meal', basePrice: 100);
    await publishFixtures(catalog);
    final preset = DiscountPreset(id: 0, name: 'Lunch', type: DiscountType.flat, value: 10, isActive: true,
      rules: DiscountRules(categoryIds: [category.id], dailyLimit: 1));
    await expectLater(catalog.saveManagedDiscount(managerId: 2, preset: preset, create: true), throwsStateError);
    await catalog.saveManagedDiscount(managerId: 1, preset: preset, create: true);
    final saved = (await catalog.getDiscountPresets()).single;
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final orders = OrderAndCheckoutController(database: db);
    Future<CheckoutResult> pay(DiscountPreset discount, {String? commandId}) => orders.checkoutOrder(
      businessDayId: day.id, shiftId: shift.id, cashierId: 2, diningType: DiningType.dineIn,
      items: [CartItem(menuItem: menu)], discount: discount, commandId: commandId,
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 90)]);
    await catalog.saveManagedDiscount(managerId: 1, preset: saved.copyWith(name: 'Revised lunch'));
    await expectLater(pay(saved), throwsStateError);
    expect(await db.query('orders'), isEmpty);
    final current = (await catalog.getDiscountPresets()).single;
    await pay(current, commandId: 'once');
    await pay(current, commandId: 'once');
    await expectLater(pay(current), throwsStateError);
    expect(await db.query('orders'), hasLength(1));
    expect(await db.query('configuration_audit'), hasLength(2));
  });

  test('shortcuts persist, reject conflicts/reserved keys/Cashier writes, restore previous map', () async {
    var shortcuts = KeyboardShortcutController(db);
    final original = await shortcuts.load();
    final changed = Map<String, String>.of(original)..['category1'] = 'Shift+F1';
    await expectLater(shortcuts.save(managerId: 2, bindings: changed, expected: original), throwsStateError);
    final duplicate = Map<String, String>.of(original)..['hold'] = 'F1';
    await expectLater(shortcuts.save(managerId: 1, bindings: duplicate, expected: original), throwsArgumentError);
    final reserved = Map<String, String>.of(original)..['hold'] = 'Alt+F4';
    await expectLater(shortcuts.save(managerId: 1, bindings: reserved, expected: original), throwsArgumentError);
    await shortcuts.save(managerId: 1, bindings: changed, expected: original);
    await expectLater(shortcuts.save(managerId: 1, bindings: original, expected: original), throwsStateError);
    expect(await shortcuts.prior(1), original);
    await pos.close(); db = await pos.initialize(); shortcuts = KeyboardShortcutController(db);
    expect(await shortcuts.load(), changed);
    await shortcuts.save(managerId: 1, bindings: await shortcuts.prior(1), expected: changed);
    expect(await shortcuts.load(), original);
  });

  test('upgrade from v19 preserves records and supplies unrestricted legacy discount rules', () async {
    await catalog.createDiscountPreset(name: 'Legacy', type: DiscountType.percentage, value: 10);
    await db.execute('DROP TABLE stock_count_lines');
    await db.execute('DROP TABLE stock_counts');
    await db.execute('DROP TABLE configuration_audit');
    await db.execute('ALTER TABLE discount_presets DROP COLUMN rules_json');
    await db.execute('PRAGMA user_version=19');
    await pos.close(); db = await pos.initialize();
    final preset = (await CatalogAndRecipeController(database: db).getDiscountPresets()).single;
    expect(preset.calculateDiscount(100), 10);
    expect(await db.query('stock_counts'), isEmpty);
  });
}
