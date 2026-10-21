import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/widgets/orders/cashier_order_revision_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CashierOrderRevisionDialog Widget Tests', () {
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
    late Order order;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('widget_rev_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}widget_rev.db';
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

      final cat = await catalogController.createCategory(name: 'Cat', displayOrder: 1, colorHex: '#FFAA00');
      burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Zinger Burger', basePrice: 500.0);
      final ing = await catalogController.createRawIngredient(name: 'Chicken', storageUnit: StorageUnit.kg, currentStock: 50);
      await catalogController.setRecipeForMenuItem(menuItemId: burger.id, items: [(rawIngredientId: ing.id, quantity: 0.2)]);
      await catalogController.toggleMenuItemActive(burger.id, true);

      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 2)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000.0)],
      );
      order = checkout.order;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('renders dialog with order details and stage notice without requiring PIN', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierOrderRevisionDialog(
              order: order,
              cashierId: cashierId,
              shiftId: shiftId,
              orderController: orderController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cashier_order_revision_dialog')), findsOneWidget);
      expect(find.text('#01'), findsOneWidget);
      expect(find.textContaining('Order #${order.id} Revision'), findsOneWidget);
      expect(find.textContaining('Cashier Autonomy (No PIN)'), findsOneWidget);

      // Buttons present
      expect(find.byKey(const ValueKey('apply_revision_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel_entire_order_button')), findsOneWidget);
    });

    testWidgets('canceling order autonomously updates order and shows refund prompt', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool callbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierOrderRevisionDialog(
              order: order,
              cashierId: cashierId,
              shiftId: shiftId,
              orderController: orderController,
              onRevisionCompleted: () => callbackCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Cancel Entire Order
      await tester.tap(find.byKey(const ValueKey('cancel_entire_order_button')));
      await tester.pumpAndSettle();

      expect(callbackCalled, isTrue);

      // Pending refund banner should now appear since order was paid with cash
      expect(find.byKey(const ValueKey('pending_refund_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('disburse_cash_refund_button')), findsOneWidget);

      // Tap Cash Payout
      await tester.tap(find.byKey(const ValueKey('disburse_cash_refund_button')));
      await tester.pumpAndSettle();

      final updated = await orderController.getOrder(order.id);
      expect(updated.isCancelled, isTrue);
    });
  });
}
