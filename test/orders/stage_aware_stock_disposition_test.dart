import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Stage-Aware Stock Disposition Tests (RESTOCK_RAW vs WASTED_COOKED)', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogAndRecipeController catalogController;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;

    late int businessDayId;
    late int shiftId;
    const cashierId = 2;
    late MenuItem burger;
    late RawIngredient patty;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage_stock_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}stage_stock.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      catalogController = CatalogAndRecipeController(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);

      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      businessDayId = day.id;
      final shift = await shiftController.openShift(staffId: cashierId, openingFloat: 5000.0);
      shiftId = shift.id;

      final cat = await catalogController.createCategory(name: 'Main', displayOrder: 1, colorHex: '#123456');
      burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 500.0);
      patty = await catalogController.createRawIngredient(
        name: 'Beef Patty',
        storageUnit: StorageUnit.count,
        currentStock: 100.0,
        costPerRecipeUnit: 150.0,
      );

      await catalogController.setRecipeForMenuItem(
        menuItemId: burger.id,
        items: [(rawIngredientId: patty.id, quantity: 1.0)],
      );
      await catalogController.toggleMenuItemActive(burger.id, true);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Confirmed stage (unstarted prep): canceled items restore raw inventory with RESTOCK_RAW', () async {
      final initialStock = (await catalogController.getRawIngredient(patty.id)).currentStock;
      expect(initialStock, equals(100.0));

      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 2)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000.0)],
      );

      // Stock was deducted by 2 (100 -> 98)
      expect((await catalogController.getRawIngredient(patty.id)).currentStock, equals(98.0));

      // Mark order as CONFIRMED (food preparation has not commenced)
      await db.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': TokenStatus.confirmed.code},
        where: 'id = ?',
        whereArgs: [checkout.order.id],
      );

      final revision = await orderController.cancelOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer cancelled before kitchen started',
        commandId: 'cmd-cancel-unstarted',
      );

      expect(revision.lines.first.bomDisposition, equals('RESTOCK_RAW'));

      // Raw inventory is restored to 100.0
      final restoredStock = (await catalogController.getRawIngredient(patty.id)).currentStock;
      expect(restoredStock, equals(100.0));

      // No entry created in kitchen_wastage
      final wastageRows = await db.query(PosDatabaseConstants.tableKitchenWastage);
      expect(wastageRows.isEmpty, isTrue);
    });

    test('Preparing stage: removed items cannot return to bulk inventory and post to WASTED_COOKED', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 2)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000.0)],
      );

      expect((await catalogController.getRawIngredient(patty.id)).currentStock, equals(98.0));

      // Order is in PREPARING stage (kitchen has started cooking)
      await db.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': TokenStatus.preparing.code},
        where: 'id = ?',
        whereArgs: [checkout.order.id],
      );

      // Cashier cancels the order during preparation
      final revision = await orderController.cancelOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer walked out during frying',
        commandId: 'cmd-cancel-during-prep',
      );

      expect(revision.lines.first.bomDisposition, equals('WASTED_COOKED'));

      // Bulk inventory MUST NOT be restored: remains at 98.0
      final stockAfter = (await catalogController.getRawIngredient(patty.id)).currentStock;
      expect(stockAfter, equals(98.0));

      // Posted to kitchen wastage ledger
      final wastageRows = await db.query(
        PosDatabaseConstants.tableKitchenWastage,
        where: 'raw_ingredient_id = ?',
        whereArgs: [patty.id],
      );
      expect(wastageRows.length, equals(1));
      final wastage = wastageRows.first;
      expect(wastage['reason'], equals('WASTED_COOKED'));
      expect(wastage['quantity'], equals(2.0));
      expect(wastage['cost_loss'], equals(300.0)); // 2 * 150.0
      expect(wastage['staff_id'], equals(cashierId));
    });

    test('Ready and Out for Delivery stages also post removals to WASTED_COOKED', () async {
      for (final stage in [TokenStatus.ready, TokenStatus.outForDelivery]) {
        final checkout = await orderController.checkoutOrder(
          businessDayId: businessDayId,
          shiftId: shiftId,
          cashierId: cashierId,
          diningType: DiningType.takeaway,
          items: [CartItem(menuItem: burger, quantity: 1)],
          payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0)],
        );

        await db.update(
          PosDatabaseConstants.tableOrders,
          {'token_status': stage.code},
          where: 'id = ?',
          whereArgs: [checkout.order.id],
        );

        final revision = await orderController.cancelOrder(
          orderId: checkout.order.id,
          cashierId: cashierId,
          reason: 'Customer rejected at ${stage.displayName}',
          commandId: 'cmd-cancel-${stage.code}',
        );

        expect(revision.lines.first.bomDisposition, equals('WASTED_COOKED'));
      }
    });
  });
}
