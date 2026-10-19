import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/modifier_group.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  test('Required SINGLE group replaces the previous option and consumes explicit recipe deltas', () async {
    sqfliteFfiInit();
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final catalog = CatalogAndRecipeController(database: db);
    final orders = OrderAndCheckoutController(database: db);
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final cat = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#000000');
    final item = await catalog.createMenuItem(categoryId: cat.id, name: 'Mayo burger', basePrice: 300);
    final mayo = await catalog.createRawIngredient(name: 'Mayo', storageUnit: StorageUnit.g, currentStock: 200);
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: mayo.id, quantity: 20.0)]);
    await catalog.toggleMenuItemActive(item.id, true);
    final group = await catalog.createModifierGroup(menuItemId: item.id, name: 'Sauce', isRequired: true);
    final normal = await catalog.createModifier(menuItemId: item.id, groupId: group.id, name: 'Normal', rawIngredientId: mayo.id);
    final none = await catalog.createModifier(menuItemId: item.id, groupId: group.id, name: 'Without sauce', rawIngredientId: mayo.id, ingredientQtyDelta: -20);
    final extra = await catalog.createModifier(menuItemId: item.id, groupId: group.id, name: 'Extra', priceDelta: 30, rawIngredientId: mayo.id, ingredientQtyDelta: 30);
    final selection = ModifierSelection.select([none], extra);
    expect(selection.map((option) => option.id), [extra.id]);
    expect(() => ModifierSelection.validate([], [group]), throwsStateError);
    expect(() => ModifierSelection.validate([none, extra], [group]), throwsStateError);
    Future<void> sell(List<CartItem> items) async {
      await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2, diningType: DiningType.dineIn, items: items, payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000)]);
    }
    await expectLater(sell([CartItem(menuItem: item)]), throwsStateError);
    await expectLater(sell([CartItem(menuItem: item, selectedModifiers: [none, extra])]), throwsStateError);
    await sell([CartItem(menuItem: item, selectedModifiers: selection)]);
    expect((await catalog.getRawIngredient(mayo.id)).currentStock, 150);
    await sell([CartItem(menuItem: item, selectedModifiers: [none])]);
    expect((await catalog.getRawIngredient(mayo.id)).currentStock, 150);
    await sell([CartItem(menuItem: item, selectedModifiers: [normal])]);
    expect((await catalog.getRawIngredient(mayo.id)).currentStock, 130);
    await catalog.toggleMenuItemActive(item.id, false);
    await expectLater(sell([CartItem(menuItem: item, selectedModifiers: [normal])]), throwsStateError);
    expect((await orders.getOrders()).length, 3);
  });
}
