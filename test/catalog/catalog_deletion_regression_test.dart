import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  for (final target in ['category', 'menu item', 'deal', 'category upgrade']) {
    test('deletes $target after day close without changing order history', () async {
      final directory = await Directory.systemTemp.createTemp('catalog_delete_');
      final pos = PosDatabase(factory: databaseFactoryFfi, customPath: '${directory.path}/pos.db');
      addTearDown(() async {
        await pos.close();
        await directory.delete(recursive: true);
      });
      var db = await pos.initialize();
      if (target == 'category upgrade') {
        // Restore the actual v21 guard before exercising the versioned upgrade.
        await db.execute('DROP TRIGGER IF EXISTS menu_item_delete_modifiers');
        await db.execute('DROP TRIGGER closed_order_items_UPDATE');
        await db.execute('''CREATE TRIGGER closed_order_items_UPDATE BEFORE UPDATE ON order_items
          WHEN EXISTS(SELECT 1 FROM orders o JOIN business_days b ON b.id=o.business_day_id
            WHERE o.id=OLD.order_id AND b.status='CLOSED')
          BEGIN SELECT RAISE(ABORT,'Business Day is permanently closed'); END''');
        await db.setVersion(21);
        await pos.close();
        db = await pos.initialize();
        expect(await db.getVersion(), PosDatabaseConstants.schemaVersion);
      }
      final catalog = CatalogAndRecipeController(database: db);
      final shifts = ShiftAndCashController(database: db);
      final orders = OrderAndCheckoutController(database: db);
      final category = await catalog.createCategory(name: 'Pizza', displayOrder: 0, colorHex: '#FFFFFF');
      final item = await catalog.createMenuItem(categoryId: category.id, name: 'Pizza slice', basePrice: 100);
      final ingredient = await catalog.createRawIngredient(name: 'Dough', storageUnit: StorageUnit.count, currentStock: 10);
      await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
      await catalog.toggleMenuItemActive(item.id, true);
      final group = await catalog.createModifierGroup(menuItemId: item.id, name: 'Toppings');
      await catalog.createModifier(menuItemId: item.id, groupId: group.id, name: 'Extra cheese');
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
      final lineId = history.single['id'];
      if (target == 'category') {
        // Each receipt column stays immutable, including nullable snapshots.
        for (final entry in history.single.entries) {
          final changedValue = entry.value is num
              ? (entry.value as num) + 1
              : '${entry.value ?? ''}changed';
          await expectLater(db.update('order_items', {
            entry.key: changedValue,
          }, where: 'id = ?', whereArgs: [lineId]),
            throwsA(predicate((error) => error.toString().contains('Business Day is permanently closed'))),
            reason: '${entry.key} must remain protected while its catalog record exists');
        }
      }
      if (target.startsWith('category')) {
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
        expect(await catalog.getModifiers(), isEmpty);
        expect(await catalog.getModifierGroups(), isEmpty);
      }
      // Nullable catalog references detach; every saved sale field stays intact.
      final reference = target == 'deal' ? 'deal_id' : 'menu_item_id';
      expect(await db.query('order_items'), [for (final row in history) {...row, reference: null}]);
      expect(await db.query('report_runs'), reports);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(db.update('order_items', {'quantity': 2}, where: 'id = ?', whereArgs: [lineId]),
        throwsA(predicate((error) => error.toString().contains('Business Day is permanently closed'))));
      await expectLater(db.delete('order_items', where: 'id = ?', whereArgs: [lineId]), throwsA(isA<DatabaseException>()));
    });
  }
}
