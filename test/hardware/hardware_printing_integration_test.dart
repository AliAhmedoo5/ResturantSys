import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/hardware/esc_pos_constants.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/paper_width.dart';
import 'package:resturant_sys/core/hardware/printer_topology.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Decoupled Hardware Printing & Database Commit Integration Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogAndRecipeController catalogController;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late InMemoryHardwareAdapter hardwareAdapter;
    late ReprintTrayController reprintTrayController;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hardware_integration_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_hardware.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      catalogController = CatalogAndRecipeController(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);

      hardwareAdapter = InMemoryHardwareAdapter();
      reprintTrayController = ReprintTrayController(
        hardwareAdapter: hardwareAdapter,
        topology: PrinterTopology.single,
        paperWidth: PaperWidth.mm80,
      );
      await reprintTrayController.loadSettings(db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Checkout commits to SQLite, emits dual tickets with auto-cuts, and kicks drawer on cash', () async {
      // 1. Open Business Day and Shift
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      // 2. Create catalog items
      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final burger = await catalogController.createMenuItem(
        categoryId: cat.id,
        name: 'Zinger Burger',
        basePrice: 500.0,
      );

      // 3. Commit order transaction to SQLite
      final checkoutResult = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.takeaway,
        items: [
          CartItem(menuItem: burger, quantity: 2),
        ],
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 1000.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(checkoutResult.order.id, isPositive);
      expect(checkoutResult.order.tokenDisplay, equals('#01'));

      // 4. Decoupled printing execution
      await reprintTrayController.dispatchOrderPrinting(
        order: checkoutResult.order,
        isCashPaid: true,
      );

      // Verify cash drawer kicked with exact pulse
      expect(hardwareAdapter.drawerKickCount, equals(1));
      expect(hardwareAdapter.drawerPulses.first, equals(EscPosConstants.kickDrawerPulse));

      // Verify two sequential tickets emitted on counter printer (Receipt + KOT)
      expect(hardwareAdapter.counterPrintedBytes.length, equals(2));

      // Customer Tax Receipt
      final receiptBytes = hardwareAdapter.counterPrintedBytes[0];
      expect(receiptBytes.sublist(0, 2), equals(EscPosConstants.initPrinter));
      expect(receiptBytes.sublist(receiptBytes.length - 3), equals(EscPosConstants.cutPaperFull));
      final decodedReceipt = latin1.decode(receiptBytes);
      expect(decodedReceipt, contains('CUSTOMER RECEIPT'));
      expect(decodedReceipt, contains('2x Zinger Burger'));
      expect(decodedReceipt, contains('GRAND TOTAL:'));
      expect(decodedReceipt, contains('1,000.00'));

      // Kitchen Order Ticket (KOT)
      final kotBytes = hardwareAdapter.counterPrintedBytes[1];
      expect(kotBytes.sublist(0, 2), equals(EscPosConstants.initPrinter));
      expect(kotBytes.sublist(kotBytes.length - 3), equals(EscPosConstants.cutPaperFull));
      final decodedKot = latin1.decode(kotBytes);
      expect(decodedKot, contains('TOKEN #01'));
      expect(decodedKot, contains('*** TAKEAWAY ***'));
      expect(decodedKot, contains('2x ZINGER BURGER'));
      // KOT strictly zero prices
      expect(decodedKot, isNot(contains('Rs')));
      expect(decodedKot, isNot(contains('1,000.00')));
    });

    test('Printer hardware failure leaves SQLite commit intact and enqueues to Reprint Tray', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);
      final cat = await catalogController.createCategory(name: 'Sides', displayOrder: 1, colorHex: '#00FF00');
      final fries = await catalogController.createMenuItem(
        categoryId: cat.id,
        name: 'French Fries',
        basePrice: 200.0,
      );

      // Simulate hardware failure (e.g. paper roll depleted)
      hardwareAdapter.shouldFailCounterPrint = true;

      // Checkout commits to SQLite successfully
      final checkoutResult = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: fries, quantity: 1),
        ],
        payments: [
          const PaymentTender(
            method: PaymentMethod.card,
            amountTendered: 200.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(checkoutResult.order.id, isPositive);

      // Decoupled printing handles failure gracefully without throwing exception
      await reprintTrayController.dispatchOrderPrinting(
        order: checkoutResult.order,
        isCashPaid: false,
      );

      // SQLite order exists and is valid
      final orderInDb = await orderController.getOrder(checkoutResult.order.id);
      expect(orderInDb.id, equals(checkoutResult.order.id));

      // Reprint tray captured the failure
      expect(reprintTrayController.hasFailures, isTrue);
      expect(reprintTrayController.failedCount, equals(2));

      // Simulate printer repaired and paper replaced
      hardwareAdapter.shouldFailCounterPrint = false;

      // 1-tap retry all failed jobs
      final retriedCount = await reprintTrayController.retryAllFailed();
      expect(retriedCount, equals(2));
      expect(reprintTrayController.hasFailures, isFalse);
      expect(reprintTrayController.failedCount, equals(0));
      expect(hardwareAdapter.counterPrintedBytes.length, equals(2));
    });
  });
}
