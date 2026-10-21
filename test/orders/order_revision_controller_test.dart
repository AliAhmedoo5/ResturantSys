import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
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

  group('Autonomous Cashier Order Revisions & Idempotency Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogAndRecipeController catalogController;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;

    late int businessDayId;
    late int shiftId;
    const cashierId = 2; // Front counter cashier
    late MenuItem burger;
    late MenuItem fries;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('order_rev_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_order_rev.db';
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

      final cat = await catalogController.createCategory(name: 'Food', displayOrder: 1, colorHex: '#FFAA00');
      burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 500.0);
      fries = await catalogController.createMenuItem(categoryId: cat.id, name: 'Fries', basePrice: 200.0);

      final patty = await catalogController.createRawIngredient(name: 'Patty', storageUnit: StorageUnit.count, currentStock: 100);
      final potato = await catalogController.createRawIngredient(name: 'Potato', storageUnit: StorageUnit.kg, currentStock: 50);

      await catalogController.setRecipeForMenuItem(menuItemId: burger.id, items: [(rawIngredientId: patty.id, quantity: 1.0)]);
      await catalogController.setRecipeForMenuItem(menuItemId: fries.id, items: [(rawIngredientId: potato.id, quantity: 0.2)]);

      await catalogController.toggleMenuItemActive(burger.id, true);
      await catalogController.toggleMenuItemActive(fries.id, true);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Cashier can cancel confirmed order without a Manager PIN', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 2)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000.0)],
      );

      // Cashier cancels order autonomously with mandatory reason
      final rev = await orderController.cancelOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer changed mind before preparation',
        commandId: 'cmd-cancel-101',
      );

      expect(rev.id, greaterThan(0));
      expect(rev.orderId, equals(checkout.order.id));
      expect(rev.action, equals('CANCEL'));
      expect(rev.reason, equals('Customer changed mind before preparation'));
      expect(rev.cashierId, equals(cashierId));
      expect(rev.newTotalPaisa, equals(0));
      expect(rev.moneyDeltaPaisa, equals(-100000));
      expect(rev.lines.length, equals(1));
      expect(rev.lines.first.newQtyDecimal, equals('0'));

      final updatedOrder = await orderController.getOrder(checkout.order.id);
      expect(updatedOrder.grandTotal, equals(0.0));
      expect(updatedOrder.currentRevision, equals(2));
      expect(updatedOrder.isRefundPending, isTrue); // Paid order flagged as refund pending
    });

    test('Canceling or revising requires a mandatory non-empty reason', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.takeaway,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0)],
      );

      expect(
        () => orderController.cancelOrder(
          orderId: checkout.order.id,
          cashierId: cashierId,
          reason: '   ',
          commandId: 'cmd-empty-reason',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => orderController.reviseOrder(
          orderId: checkout.order.id,
          cashierId: cashierId,
          reason: '',
          commandId: 'cmd-empty-reason-2',
          newItems: [CartItem(menuItem: burger, quantity: 2)],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Cashier can revise quantities and add items autonomously without Manager PIN', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0)],
      );

      // Cashier revises: burger quantity from 1 to 2, and adds fries
      final revision = await orderController.reviseOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer added fries and an extra burger',
        commandId: 'cmd-rev-add-items',
        newItems: [
          CartItem(menuItem: burger, quantity: 2),
          CartItem(menuItem: fries, quantity: 1),
        ],
      );

      expect(revision.orderId, equals(checkout.order.id));
      expect(revision.revisionNo, equals(2));
      expect(revision.oldTotalPaisa, equals(50000));
      expect(revision.newTotalPaisa, equals(120000)); // 2*500 + 200 = 1200.0
      expect(revision.moneyDeltaPaisa, equals(70000));
      expect(revision.cashierId, equals(cashierId));

      final updatedOrder = await orderController.getOrder(checkout.order.id);
      expect(updatedOrder.grandTotal, equals(1200.0));
      expect(updatedOrder.currentRevision, equals(2));
      expect(updatedOrder.items.length, equals(2));

      final allRevisions = await orderController.getOrderRevisions(checkout.order.id);
      expect(allRevisions.length, equals(1));
      expect(allRevisions.first.commandId, equals('cmd-rev-add-items'));
    });

    test('Idempotency: concurrent revision attempts with identical commandId do not double-book', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0)],
      );

      final rev1 = await orderController.reviseOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer altered order',
        commandId: 'idempotent-rev-key-99',
        newItems: [CartItem(menuItem: burger, quantity: 2)],
      );

      // Retry with identical idempotency commandId
      final rev2 = await orderController.reviseOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer altered order duplicate retry',
        commandId: 'idempotent-rev-key-99',
        newItems: [CartItem(menuItem: burger, quantity: 2)],
      );

      expect(rev1.id, equals(rev2.id));
      expect(rev1.newTotalPaisa, equals(rev2.newTotalPaisa));

      final revs = await orderController.getOrderRevisions(checkout.order.id);
      expect(revs.length, equals(1)); // Only one record in order_revisions

      final updatedOrder = await orderController.getOrder(checkout.order.id);
      expect(updatedOrder.currentRevision, equals(2)); // Not incremented twice
    });
  });
}
