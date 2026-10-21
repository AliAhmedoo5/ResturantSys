import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Decoupled Refunds & Explicit Cashier Disbursement Tests', () {
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
    late MenuItem drink;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('refund_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}refund.db';
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

      final cat = await catalogController.createCategory(name: 'Menu', displayOrder: 1, colorHex: '#FFAA00');
      burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 600.0);
      drink = await catalogController.createMenuItem(categoryId: cat.id, name: 'Drink', basePrice: 150.0);

      final ing = await catalogController.createRawIngredient(name: 'Item Ing', storageUnit: StorageUnit.count, currentStock: 100);
      await catalogController.setRecipeForMenuItem(menuItemId: burger.id, items: [(rawIngredientId: ing.id, quantity: 1.0)]);
      await catalogController.setRecipeForMenuItem(menuItemId: drink.id, items: [(rawIngredientId: ing.id, quantity: 0.5)]);

      await catalogController.toggleMenuItemActive(burger.id, true);
      await catalogController.toggleMenuItemActive(drink.id, true);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Canceling a paid order marks balance as Refund Owed/Pending without opening till', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600.0)],
      );

      // Verify initial cash movement table is empty (checkout doesn't create mid-shift movement)
      final initialMovements = await shiftController.getCashMovements(shiftId);
      expect(initialMovements.isEmpty, isTrue);

      // Cashier cancels the order
      await orderController.cancelOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer left',
        commandId: 'cmd-cancel-prepaid',
      );

      final updatedOrder = await orderController.getOrder(checkout.order.id);
      expect(updatedOrder.paymentStatus, equals('REFUND_PENDING'));
      expect(updatedOrder.isRefundPending, isTrue);

      // Cash drawer was NOT opened and no cash movement was automatically created!
      final movementsAfterCancel = await shiftController.getCashMovements(shiftId);
      expect(movementsAfterCancel.isEmpty, isTrue);

      // Pending refund amount is exactly Rs 600 (60,000 paisa)
      final pendingPaisa = await orderController.getOrderPendingRefundPaisa(checkout.order.id);
      expect(pendingPaisa, equals(60000));
    });

    test('Explicit Cashier cash refund records PAY_OUT and preserves cash drawer variance integrity', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600.0)],
      );

      await orderController.cancelOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Order cancelled by customer',
        commandId: 'cmd-cancel-prepaid-drawer',
      );

      // Before refund disbursement: expected drawer cash = opening (5000) + cash sales (600) = 5600
      final expectedBeforeRefund = await shiftController.calculateExpectedCash(shiftId);
      expect(expectedBeforeRefund, equals(5600.0));

      // Separate explicit Cashier refund disbursement action (cash payout from drawer)
      final refundResult = await orderController.recordCashierRefund(
        orderId: checkout.order.id,
        shiftId: shiftId,
        cashierId: cashierId,
        amountPaisa: 60000,
        method: PaymentMethod.cash,
        reason: 'Customer returned cash for canceled order',
        commandId: 'cmd-disburse-cash-600',
      );

      expect(refundResult.isCashPayout, isTrue);
      expect(refundResult.cashMovementId, isNotNull);
      expect(refundResult.paymentStatus, equals('CANCELLED')); // Fully refunded

      // Verified drawer movements: 1 PAY_OUT of 600.0
      final movements = await shiftController.getCashMovements(shiftId);
      expect(movements.length, equals(1));
      expect(movements.first.type, equals(CashMovementType.payOut));
      expect(movements.first.amount, equals(600.0));
      expect(movements.first.category, equals('REFUND'));

      // After refund disbursement: expected drawer cash = 5000 + 600 - 600 = 5000.0
      final expectedAfterRefund = await shiftController.calculateExpectedCash(shiftId);
      expect(expectedAfterRefund, equals(5000.0));

      // Order has 0 pending refund remaining
      final remainingPending = await orderController.getOrderPendingRefundPaisa(checkout.order.id);
      expect(remainingPending, equals(0));
    });

    test('Explicit Cashier digital refund (JazzCash/Easypaisa) does not alter drawer cash', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.takeaway,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [
          const PaymentTender(
            method: PaymentMethod.jazzCash,
            amountTendered: 600.0,
            referenceCode: 'TXN-JAZZ-1234',
          ),
        ],
      );

      await orderController.cancelOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer changed mind',
        commandId: 'cmd-cancel-jazzcash',
      );

      // Explicit digital refund confirmation
      final refundResult = await orderController.recordCashierRefund(
        orderId: checkout.order.id,
        shiftId: shiftId,
        cashierId: cashierId,
        amountPaisa: 60000,
        method: PaymentMethod.jazzCash,
        referenceCode: 'REF-JAZZ-9876',
        reason: 'Reversed digital transfer in JazzCash portal',
      );

      expect(refundResult.isCashPayout, isFalse);
      expect(refundResult.cashMovementId, isNull); // No physical cash drawer movement
      expect(refundResult.paymentStatus, equals('CANCELLED'));

      // Cash drawer remains at opening float 5000.0
      final expectedCash = await shiftController.calculateExpectedCash(shiftId);
      expect(expectedCash, equals(5000.0));
    });

    test('Revising order downwards flags exact delta as Refund Pending', () async {
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: burger, quantity: 1), // 600
          CartItem(menuItem: drink, quantity: 1),  // 150
        ], // Total = 750
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 750.0)],
      );

      // Customer removes drink: new total 600.0, delta -150.0
      await orderController.reviseOrder(
        orderId: checkout.order.id,
        cashierId: cashierId,
        reason: 'Customer decided not to take drink',
        commandId: 'cmd-remove-drink',
        newItems: [CartItem(menuItem: burger, quantity: 1)],
      );

      final updatedOrder = await orderController.getOrder(checkout.order.id);
      expect(updatedOrder.paymentStatus, equals('REFUND_PENDING'));
      expect(updatedOrder.grandTotal, equals(600.0));

      // Exact pending refund is 150.0 (15,000 paisa)
      final pendingPaisa = await orderController.getOrderPendingRefundPaisa(checkout.order.id);
      expect(pendingPaisa, equals(15000));

      // Cashier disburses Rs 150 cash refund
      final refundResult = await orderController.recordCashierRefund(
        orderId: checkout.order.id,
        shiftId: shiftId,
        cashierId: cashierId,
        amountPaisa: 15000,
        method: PaymentMethod.cash,
        reason: 'Cash refund for removed drink',
      );

      expect(refundResult.paymentStatus, equals('SETTLED')); // Restored to SETTLED since order has remaining items
      final finalOrder = await orderController.getOrder(checkout.order.id);
      expect(finalOrder.paymentStatus, equals('SETTLED'));
      expect(await orderController.getOrderPendingRefundPaisa(checkout.order.id), equals(0));
    });
  });
}
