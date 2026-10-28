import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/orders/customer_controller.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'order_and_checkout_controller_test.dart' show publishFixtures;

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory temp;
  late PosDatabase pos;
  late Database db;
  late CatalogAndRecipeController catalog;
  late OrderAndCheckoutController orders;
  late CustomerController customers;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('backlog_workflows_');
    pos = PosDatabase(factory: databaseFactoryFfi, customPath: '${temp.path}/test.db');
    db = await pos.initialize();
    catalog = CatalogAndRecipeController(database: db);
    orders = OrderAndCheckoutController(database: db);
    customers = CustomerController(db);
  });
  tearDown(() async { await pos.close(); await temp.delete(recursive: true); });

  Future<CartItem> item() async {
    final category = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 100);
    await publishFixtures(catalog);
    return CartItem(menuItem: await catalog.getMenuItem(menu.id));
  }

  test('Manager creates and atomically edits selectable deal components', () async {
    final line = await item();
    final slots = [DealItemDraft(groupName: 'Main', options: [DealOptionDraft(menuItemId: line.menuItem!.id, isDefault: true)])];
    await catalog.saveDeal(managerId: 1, name: 'Lunch', basePrice: 90, isActive: true, items: slots);
    final deal = (await catalog.getDeals()).single;
    await catalog.saveDeal(managerId: 1, id: deal.id, name: 'Lunch revised', basePrice: 95, isActive: true,
      items: [DealItemDraft(id: deal.items.single.id, groupName: 'Main', options: slots.single.options)]);
    expect((await catalog.getDeal(deal.id)).basePrice, 95);
    expect((await catalog.getDeal(deal.id)).items.single.options.single.menuItemId, line.menuItem!.id);
    expect((await catalog.getDeal(deal.id)).items.single.id, deal.items.single.id);
    await expectLater(catalog.saveDeal(managerId: 1, id: deal.id, name: 'Invalid', basePrice: 1,
      isActive: true, items: []), throwsStateError);
    expect((await catalog.getDeal(deal.id)).name, 'Lunch revised');
    await expectLater(catalog.saveDeal(managerId: 2, name: 'Forbidden', basePrice: 1, isActive: false, items: []), throwsStateError);
  });

  test('multiple holds survive reopening without tokens, payments or stock movement', () async {
    final line = await item();
    final before = await db.query('raw_ingredients');
    await orders.holdCart(cashierId: 2, label: 'Table 1', items: [line], diningType: DiningType.dineIn);
    await orders.holdCart(cashierId: 2, label: 'Table 2', items: [line.copyWith(quantity: 2)], diningType: DiningType.takeaway);
    await pos.close(); db = await pos.initialize();
    orders = OrderAndCheckoutController(database: db);
    final holds = await orders.getHolds(2);
    expect(holds.length, 2);
    final payload = jsonDecode(holds.first['payload'] as String) as Map<String, dynamic>;
    expect((await orders.restoreDraftLines(payload['items'] as List)).single.quantity, 2);
    expect(await db.query('checkout_tokens'), isEmpty);
    expect(await db.query('order_payments'), isEmpty);
    expect(await db.query('raw_ingredients'), before);
    await expectLater(orders.getHolds(1), throwsStateError);
  });

  test('recall reprices and rejects unavailable items while retaining the hold', () async {
    final line = await item();
    await orders.holdCart(cashierId: 2, label: 'Lunch', items: [line], diningType: DiningType.takeaway);
    final payload = jsonDecode((await orders.getHolds(2)).single['payload'] as String) as Map<String, dynamic>;
    await db.update('menu_items', {'base_price': 125}, where: 'id = ?', whereArgs: [line.menuItem!.id]);
    expect((await orders.restoreDraftLines(payload['items'] as List)).single.unitPrice, 125);
    await catalog.toggleMenuItemActive(line.menuItem!.id, false);
    await expectLater(orders.restoreDraftLines(payload['items'] as List), throwsStateError);
    expect((await orders.getHolds(2)).length, 1);
  });

  test('hold is consumed only by successful checkout, inside the same transaction', () async {
    final line = await item();
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final hold = await orders.holdCart(cashierId: 2, label: 'Counter', items: [line], diningType: DiningType.dineIn);
    final customer = await customers.save(staffId: 2, name: 'Test Person', phone: '03001234567');
    await expectLater(orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
      diningType: DiningType.dineIn, items: [line], customerId: -1, heldCartId: hold,
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]), throwsStateError);
    expect(await orders.getHolds(2), hasLength(1));
    await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
      diningType: DiningType.dineIn, items: [line], customerId: customer.id, heldCartId: hold,
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    expect(await orders.getHolds(2), isEmpty);
    final history = await customers.history(customer.id);
    expect(history.length, 1);
    await db.update('menu_items', {'base_price': 140}, where: 'id = ?', whereArgs: [line.menuItem!.id]);
    final repeat = await orders.repeatOrder(cashierId: 2, orderId: history.single['id'] as int);
    expect(repeat.single.menuItem!.id, line.menuItem!.id);
    expect(repeat.single.unitPrice, 140);
    expect(await db.query('orders'), hasLength(1));
    final target = await customers.save(staffId: 1, name: 'Canonical Person', phone: '03007654321');
    final snapshot = await db.query('orders');
    await customers.merge(managerId: 1, sourceId: customer.id, targetId: target.id, reason: 'Confirmed duplicate');
    expect(await db.query('orders'), snapshot);
    expect(await customers.history(target.id), hasLength(1));
  });

  test('normalized duplicate detection and audited transitive merges preserve phone aliases', () async {
    final first = await customers.save(staffId: 2, name: 'First', phone: '03001234567');
    await expectLater(customers.save(staffId: 2, name: 'Duplicate', phone: '+923001234567'), throwsStateError);
    final second = await customers.save(staffId: 2, name: 'Second', phone: '03007654321');
    final third = await customers.save(staffId: 2, name: 'Third', phone: '03117654321');
    await expectLater(customers.merge(managerId: 2, sourceId: first.id, targetId: second.id, reason: 'Duplicate'), throwsStateError);
    await customers.merge(managerId: 1, sourceId: first.id, targetId: second.id, reason: 'Confirmed duplicate');
    await customers.merge(managerId: 1, sourceId: second.id, targetId: third.id, reason: 'Confirmed duplicate');
    expect((await customers.search('+923001234567')).single.id, third.id);
    expect(await db.query('customer_merges'), hasLength(2));
    await expectLater(db.delete('customer_merges'), throwsA(isA<DatabaseException>()));
  });

  test('v17 upgrade links closed legacy orders without changing their snapshots', () async {
    final line = await item();
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final area = await DeliveryController(database: db).saveArea(staffId: 1, name: 'Garden', code: 'G', deliveryFeePaisa: 0);
    await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2, diningType: DiningType.delivery,
      items: [line], delivery: DeliveryDetails(areaId: area.id, quotedFeePaisa: 0, phone: '+92 300 1234567', customerName: 'Legacy Person', fullAddress: 'House 7'),
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    // Restore the exact pre-directory schema shape and exercise real onUpgrade.
    await db.execute('DROP INDEX orders_customer');
    await db.execute('ALTER TABLE orders DROP COLUMN customer_id');
    await db.execute('DROP TABLE customer_order_links');
    await db.execute('DROP TABLE customer_merges');
    await db.execute('DROP TABLE customers');
    await db.execute('DROP TABLE held_carts');
    await db.update('business_days', {'status': 'CLOSED'}, where: 'id = ?', whereArgs: [day.id]);
    final original = (await db.query('orders')).single;
    await db.execute('PRAGMA user_version = 17');
    await pos.close(); db = await pos.initialize();
    customers = CustomerController(db);
    final customer = (await customers.search('03001234567')).single;
    expect(await customers.history(customer.id), hasLength(1));
    final after = Map<String, Object?>.from((await db.query('orders')).single)..remove('customer_id');
    expect(after, original);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
