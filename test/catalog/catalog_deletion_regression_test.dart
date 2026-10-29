import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
  for (final target in ['category', 'menu item', 'deal']) {
    test('deletes $target after day close without changing order history', () async {
      final directory = await Directory.systemTemp.createTemp('catalog_delete_');
      final pos = PosDatabase(factory: databaseFactoryFfi, customPath: '${directory.path}/pos.db');
      addTearDown(() async {
        await pos.close();
        await directory.delete(recursive: true);
      });
      final db = await pos.initialize();
      final catalog = CatalogAndRecipeController(database: db);
      final shifts = ShiftAndCashController(database: db);
      final orders = OrderAndCheckoutController(database: db);
      final category = await catalog.createCategory(name: 'Pizza', displayOrder: 0, colorHex: '#FFFFFF');
      final item = await catalog.createMenuItem(categoryId: category.id, name: 'Pizza slice', basePrice: 100);
      final ingredient = await catalog.createRawIngredient(name: 'Dough', storageUnit: StorageUnit.count, currentStock: 10);
      await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
      await catalog.toggleMenuItemActive(item.id, true);
      final deal = await catalog.createDeal(name: 'Pizza meal', basePrice: 100,
        items: [DealItemDraft(groupName: 'Slice', defaultMenuItemId: item.id)]);
      final day = await shifts.openBusinessDay(openedByStaffId: 1);
      final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
      await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
        diningType: DiningType.dineIn, items: [target == 'deal'
          ? CartItem(deal: deal, selectedDealChoices: [SelectedDealChoice(
              dealItemId: deal.items.single.id, groupName: 'Slice', menuItemId: item.id, menuItemName: item.name)])
          : CartItem(menuItem: item)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
      await shifts.closeBusinessDay(closedByStaffId: 1, autoLockActiveShifts: true);
      final history = await db.query('order_items');
      final reports = await db.query('report_runs');
      if (target == 'category') {
        await catalog.deleteCategory(category.id);
        expect(await catalog.getCategories(), isEmpty);
      } else if (target == 'menu item') {
        await catalog.deleteMenuItem(item.id);
      } else {
        await catalog.deleteDeal(deal.id);
        expect(await catalog.getDeals(), isEmpty);
      }
      if (target != 'deal') {
        expect(await catalog.getMenuItems(), isEmpty);
        expect(await catalog.getMenuItems(activeOnly: true), isEmpty);
      }
      // Nullable catalog references detach; every saved sale field stays intact.
      final reference = target == 'deal' ? 'deal_id' : 'menu_item_id';
      expect(await db.query('order_items'), [for (final row in history) {...row, reference: null}]);
      expect(await db.query('report_runs'), reports);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}
