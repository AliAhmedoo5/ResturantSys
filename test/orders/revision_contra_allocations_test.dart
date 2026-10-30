import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

  group('Order Revisions, Contra-Allocations & Sale-Time BOM Costing (ADR-0021 §5)', () {
    late PosDatabase store;
    late Database db;
    late CatalogAndRecipeController catalog;
    late OrderAndCheckoutController orders;
    late ShiftAndCashController shifts;
    late Staff cashier;
    late Staff supervisor;
    late int bDayId;
    late int shiftId;

    setUp(() async {
      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await store.initialize();
      catalog = CatalogAndRecipeController(database: db);
      orders = OrderAndCheckoutController(database: db);
      shifts = ShiftAndCashController(database: db);

      final staffRows = await db.query('staff');
      cashier = Staff.fromMap(staffRows.firstWhere((r) => r['role'] == 'CASHIER'));
      supervisor = Staff.fromMap(staffRows.firstWhere((r) => r['role'] == 'SUPERVISOR'));

      final auth = AuthService(database: db);
      auth.session.login(cashier);

      bDayId = (await shifts.openBusinessDay(openedByStaffId: supervisor.id)).id;
      shiftId = (await shifts.openShift(staffId: cashier.id, openingFloat: 500)).id;
    });

    tearDown(() => store.close());

    test('revising an order keeps unmodified allocations, contras removed lines, and adds new independent allocations', () async {
      final cat = await catalog.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FFFFFF');
      final burger = await catalog.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 400);
      final fries = await catalog.createMenuItem(categoryId: cat.id, name: 'Fries', basePrice: 200);
      final drink = await catalog.createMenuItem(categoryId: cat.id, name: 'Drink', basePrice: 100);

      final meat = await catalog.createRawIngredient(name: 'Meat', storageUnit: StorageUnit.count, currentStock: 100, costPerRecipeUnit: 150);
      final potato = await catalog.createRawIngredient(name: 'Potato', storageUnit: StorageUnit.count, currentStock: 100, costPerRecipeUnit: 50);
      final syrup = await catalog.createRawIngredient(name: 'Syrup', storageUnit: StorageUnit.count, currentStock: 100, costPerRecipeUnit: 30);

      await catalog.addOrUpdateRecipeItem(menuItemId: burger.id, rawIngredientId: meat.id, quantity: 1.0);
      await catalog.addOrUpdateRecipeItem(menuItemId: fries.id, rawIngredientId: potato.id, quantity: 1.0);
      await catalog.addOrUpdateRecipeItem(menuItemId: drink.id, rawIngredientId: syrup.id, quantity: 1.0);

      // Checkout initial order: 2x Burger (PKR 800) + 1x Fries (PKR 200) = PKR 1000
      final checkout = await orders.checkoutOrder(
        businessDayId: bDayId,
        shiftId: shiftId,
        cashierId: cashier.id,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: burger, quantity: 2),
          CartItem(menuItem: fries, quantity: 1),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000.0),
        ],
      );
      final orderId = checkout.order.id;

      // Check initial allocations (Revision 0 / initial checkout)
      final initAllocs = await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [orderId]);
      expect(initAllocs, hasLength(2));
      final burgerInit = initAllocs.firstWhere((a) => a['menu_item_id'] == burger.id);
      final friesInit = initAllocs.firstWhere((a) => a['menu_item_id'] == fries.id);
      expect(burgerInit['quantity'], 2);
      expect(burgerInit['entry_type'], 'SALE');
      expect(burgerInit['gross_sales_paisa'], 80000);
      expect(friesInit['quantity'], 1);
      expect(friesInit['entry_type'], 'SALE');
      expect(friesInit['gross_sales_paisa'], 20000);

      // Revision 1: Remove Fries, keep 2x Burger unmodified, add 1x Drink (PKR 100)
      // Per ADR-0021 §5:
      // - Unmodified Burger keeps original locked allocation
      // - Removed Fries receives explicit contra-allocation
      // - Newly added Drink receives independent line allocation
      await orders.reviseOrder(
        orderId: orderId,
        cashierId: cashier.id,
        reason: 'Swap fries for drink',
        commandId: 'rev-cmd-1',
        newItems: [
          CartItem(menuItem: burger, quantity: 2),
          CartItem(menuItem: drink, quantity: 1),
        ],
      );

      final rev1Allocs = await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id ASC');
      // Should have:
      // 1. Initial Burger (+2) [Locked, not re-allocated]
      // 2. Initial Fries (+1)
      // 3. Fries CONTRA (-1)
      // 4. Drink SALE (+1)
      expect(rev1Allocs, hasLength(4));

      final friesContra = rev1Allocs.firstWhere((a) => a['menu_item_id'] == fries.id && a['entry_type'] == 'CONTRA');
      expect(friesContra['quantity'], -1);
      expect(friesContra['gross_sales_paisa'], -20000);
      expect(friesContra['revision'], 2);

      final drinkSale = rev1Allocs.firstWhere((a) => a['menu_item_id'] == drink.id && a['entry_type'] == 'SALE');
      expect(drinkSale['quantity'], 1);
      expect(drinkSale['gross_sales_paisa'], 10000);
      expect(drinkSale['revision'], 2);

      // Only ONE Burger row exists (unmodified items keep original locked allocation!)
      final burgerRows = rev1Allocs.where((a) => a['menu_item_id'] == burger.id).toList();
      expect(burgerRows, hasLength(1));
      expect(burgerRows.single['id'], burgerInit['id'], reason: 'Unmodified burger must preserve its original locked allocation');

      // Revision 2: Reduce Burger from 2 to 1
      await orders.reviseOrder(
        orderId: orderId,
        cashierId: cashier.id,
        reason: 'Customer wants only 1 burger',
        commandId: 'rev-cmd-2',
        newItems: [
          CartItem(menuItem: burger, quantity: 1),
          CartItem(menuItem: drink, quantity: 1),
        ],
      );

      final rev2Allocs = await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id ASC');
      // Should now have:
      // Initial Burger (+2)
      // Initial Fries (+1)
      // Fries CONTRA (-1)
      // Drink SALE (+1)
      // Burger partial CONTRA (-1)
      expect(rev2Allocs, hasLength(5));
      final burgerContra = rev2Allocs.lastWhere((a) => a['menu_item_id'] == burger.id && a['entry_type'] == 'CONTRA');
      expect(burgerContra['quantity'], -1);
      expect(burgerContra['gross_sales_paisa'], -40000);

      // Now CANCEL the order:
      // Only active net allocations (Burger x1, Drink x1) should be contra-allocated!
      // Fries (already net 0) must NOT be double-reversed!
      await orders.cancelOrder(
        orderId: orderId,
        cashierId: cashier.id,
        reason: 'Customer cancelled completely',
        commandId: 'cancel-cmd-1',
      );

      final cancelAllocs = await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id ASC');
      // Should add:
      // Burger contra (-1) for the remaining 1
      // Drink contra (-1)
      // NO new Fries contra!
      final friesTotalContra = cancelAllocs.where((a) => a['menu_item_id'] == fries.id && a['entry_type'] == 'CONTRA').toList();
      expect(friesTotalContra, hasLength(1), reason: 'Fries was already contra-allocated; must not be double-reversed');

      // Every line must balance to exactly net 0
      int totalNetQty = 0;
      int totalNetGross = 0;
      int totalNetSales = 0;
      for (final a in cancelAllocs) {
        totalNetQty += a['quantity'] as int;
        totalNetGross += a['gross_sales_paisa'] as int;
        totalNetSales += a['net_sales_paisa'] as int;
      }
      expect(totalNetQty, 0, reason: 'Total net quantity for cancelled order must reconcile to zero');
      expect(totalNetGross, 0, reason: 'Total gross for cancelled order must reconcile to zero');
      expect(totalNetSales, 0, reason: 'Total net sales for cancelled order must reconcile to zero');
    });

    test('sale-time BOM costing resolves ingredient unit cost from ingredient_cost_history at order creation time', () async {
      final cat = await catalog.createCategory(name: 'Meals', displayOrder: 1, colorHex: '#FFFFFF');
      final meal = await catalog.createMenuItem(categoryId: cat.id, name: 'Special Meal', basePrice: 500);

      // Create ingredient with initial rate 50 PKR (5,000 paisa)
      final ingredient = await catalog.createRawIngredient(
        name: 'Special Ingredient',
        storageUnit: StorageUnit.count,
        currentStock: 100,
        costPerRecipeUnit: 50.0,
      );
      await catalog.addOrUpdateRecipeItem(menuItemId: meal.id, rawIngredientId: ingredient.id, quantity: 1.0);

      // Historic entry in ingredient_cost_history was recorded by trigger
      final historyBefore = await db.query('ingredient_cost_history', where: 'ingredient_id = ?', whereArgs: [ingredient.id]);
      expect(historyBefore, isNotEmpty);
      expect(historyBefore.first['unit_cost_rupees'], 50.0);

      // Checkout order when rate is 50.0
      final checkout = await orders.checkoutOrder(
        businessDayId: bDayId,
        shiftId: shiftId,
        cashierId: cashier.id,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: meal, quantity: 1),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0),
        ],
      );

      final alloc = (await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [checkout.order.id])).first;
      // 50 PKR * 100 = 5000 paisa
      expect(alloc['bom_recipe_cost_paisa'], 5000);
      expect(alloc['contribution_margin_paisa'], 50000 - 5000);

      // Later, supplier prices increase: ingredient updated to 90 PKR
      await catalog.updateRawIngredient(
        ingredient.copyWith(costPerRecipeUnit: 90.0),
      );

      // Future rate is recorded in history
      final historyAfter = await db.query('ingredient_cost_history', where: 'ingredient_id = ?', whereArgs: [ingredient.id], orderBy: 'id ASC');
      expect(historyAfter, hasLength(2));
      expect(historyAfter.last['unit_cost_rupees'], 90.0);

      // New order created after rate change gets 90 PKR rate
      final checkout2 = await orders.checkoutOrder(
        businessDayId: bDayId,
        shiftId: shiftId,
        cashierId: cashier.id,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: meal, quantity: 1),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0),
        ],
      );

      final alloc2 = (await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [checkout2.order.id])).first;
      expect(alloc2['bom_recipe_cost_paisa'], 9000); // 9000 paisa for the new order
      // Original order allocation remains locked at 5000 paisa
      final originalAlloc = (await db.query('order_item_allocations', where: 'order_id = ?', whereArgs: [checkout.order.id])).first;
      expect(originalAlloc['bom_recipe_cost_paisa'], 5000);
    });
  });
}
