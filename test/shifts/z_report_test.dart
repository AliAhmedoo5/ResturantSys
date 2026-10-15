import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/order_void.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/procurement/desi_unit.dart';
import 'package:resturant_sys/core/procurement/wastage_reason.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Z-Report Aggregation, Multi-Shift Math, and Day Locking Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late ProcurementAndWastageController procurementController;
    late VendorKhataController khataController;
    late int supervisorId;
    late int cashierId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_zreport_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}zreport_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      procurementController = ProcurementAndWastageController(database: db);
      khataController = VendorKhataController(database: db);

      final supervisor = await db.query(PosDatabaseConstants.tableStaff, where: "role = 'SUPERVISOR'", limit: 1);
      supervisorId = supervisor.first['id'] as int;
      final cashier = await db.query(PosDatabaseConstants.tableStaff, where: "role = 'CASHIER'", limit: 1);
      cashierId = cashier.first['id'] as int;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('correctly aggregates multi-shift totals, tenders, voids, wastage, and variance', () async {
      // 1. Open Business Day
      final day = await shiftController.openBusinessDay(openedByStaffId: supervisorId);

      // Create dummy menu items & raw ingredient for checkout & wastage
      final catId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Burgers',
        'display_order': 1,
        'color_hex': '#FF5722',
        'created_at': DateTime.now().toIso8601String(),
      });
      final ingredientId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Chicken Fillet',
        'storage_unit': 'kg',
        'current_stock': 50.0,
        'low_stock_threshold': 5.0,
        'cost_per_recipe_unit': 150.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final menuItemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': catId,
        'name': 'Zinger Burger',
        'base_price': 500.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert(PosDatabaseConstants.tableRecipes, {
        'menu_item_id': menuItemId,
        'raw_ingredient_id': ingredientId,
        'quantity_per_recipe_unit': 0.15,
        'created_at': DateTime.now().toIso8601String(),
      });

      final burgerItem = MenuItem(
        id: menuItemId,
        categoryId: catId,
        name: 'Zinger Burger',
        basePrice: 500.0,
      );

      // --- SHIFT 1 ---
      final shift1 = await shiftController.openShift(staffId: cashierId, openingFloat: 5000.0);

      // Cash Order: 500
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift1.id,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(
            menuItem: burgerItem,
            quantity: 1,
          ),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0),
        ],
      );

      // Card Order: 1000
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift1.id,
        cashierId: cashierId,
        diningType: DiningType.takeaway,
        items: [
          CartItem(
            menuItem: burgerItem,
            quantity: 2,
          ),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.card, amountTendered: 1000.0),
        ],
      );

      // Pay-In: 200
      await shiftController.recordCashMovement(
        shiftId: shift1.id,
        staffId: cashierId,
        type: CashMovementType.payIn,
        amount: 200.0,
        category: 'Cash Added',
        notes: 'Change added',
      );

      // Shift 1 Close: Expected Cash = 5000 (float) + 500 (cash) + 200 (pay-in) = 5700.0
      // Cashier counts 5680.0 (Variance: -20.0)
      await shiftController.closeShift(shiftId: shift1.id, countedCash: 5680.0);

      // --- SHIFT 2 ---
      final shift2 = await shiftController.openShift(staffId: cashierId, openingFloat: 3000.0);

      // Raast QR Order: 500
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift2.id,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(
            menuItem: burgerItem,
            quantity: 1,
          ),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.raast, amountTendered: 500.0),
        ],
      );

      // Order to be voided: 500 Cash
      final checkoutToVoid = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift2.id,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(
            menuItem: burgerItem,
            quantity: 1,
          ),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 500.0),
        ],
      );
      // Supervisor voids order
      await orderController.voidOrder(
        orderId: checkoutToVoid.order.id,
        supervisorStaffId: supervisorId,
        cashierStaffId: cashierId,
        reason: VoidReason.customerCancelled,
      );

      // Shift 2 Pay-Out: 100
      await shiftController.recordCashMovement(
        shiftId: shift2.id,
        staffId: cashierId,
        type: CashMovementType.payOut,
        amount: 100.0,
        category: 'Supplies',
        notes: 'Cleaning soap',
      );

      // Shift 2 Close: Expected Cash = 3000 (float) + 0 (cash sales, voided order is not settled) - 100 (pay-out) = 2900.0
      // Cashier counts 2900.0 (clean variance: 0.0)
      await shiftController.closeShift(shiftId: shift2.id, countedCash: 2900.0);

      // Kitchen wastage log:
      await procurementController.recordKitchenWastage(
        staffPin: '1111',
        rawIngredientId: ingredientId,
        quantity: 2.0,
        reason: WastageReason.burned,
        notes: 'Burned in fryer',
      );

      // Mandi procurement:
      await procurementController.recordMandiPurchase(
        rawIngredientId: ingredientId,
        unit: DesiUnit.dharri,
        quantity: 2.0,
        totalCost: 1500.0,
        notes: 'Wholesale chicken',
      );

      // Vendor Khata delivery and settlement:
      final vendor = await khataController.createVendor(name: 'Al-Madina Poultry', phone: '03001234567');
      await khataController.recordCreditDelivery(
        vendorId: vendor.id,
        amount: 5000.0,
        referenceSlip: 'INV-101',
      );
      await khataController.recordSettlementPayment(
        vendorId: vendor.id,
        amount: 2000.0,
        paymentSource: VendorPaymentSource.paidOutsideDrawer,
        notes: 'Bank transfer',
      );

      // 2. Generate Z-Report for the Business Day
      final zReport = await shiftController.generateZReport(day.id);

      expect(zReport.businessDayId, equals(day.id));
      expect(zReport.totalShiftsCount, equals(2));
      expect(zReport.cashSales, equals(500.0));
      expect(zReport.cardSales, equals(1000.0));
      expect(zReport.raastSales, equals(500.0));
      expect(zReport.netSales, equals(2000.0)); // Settled orders only: 500 + 1000 + 500
      expect(zReport.totalOpeningFloat, equals(8000.0)); // 5000 + 3000
      expect(zReport.totalPayIn, equals(200.0));
      expect(zReport.totalPayOut, equals(100.0));
      expect(zReport.totalExpectedDrawerCash, equals(8600.0)); // 8000 + 500 + 200 - 100
      expect(zReport.totalCountedCash, equals(8580.0)); // 5680 + 2900
      expect(zReport.netCashVariance, equals(-20.0)); // 8580 - 8600
      expect(zReport.totalVoidCount, equals(1));
      expect(zReport.totalVoidAmount, equals(500.0));
      expect(zReport.totalWastageCount, equals(1));
      expect(zReport.totalWastageCost, equals(300.0));
      expect(zReport.totalMandiPurchasesCost, equals(1500.0));
      expect(zReport.totalVendorDeliveriesCount, equals(1));
      expect(zReport.totalVendorSettlementsAmount, equals(2000.0));

      final printable = zReport.toPrintableString();
      expect(printable, contains('MASTER END-OF-DAY Z-REPORT'));
      expect(printable, contains('Business Day:'));
      expect(printable, contains('#${day.id}'));
      expect(printable, contains('Net Sales:'));
      expect(printable, contains('2,000.00'));
      expect(printable, contains('Cash Sales:'));
      expect(printable, contains('500.00'));
      expect(printable, contains('Card Sales:'));
      expect(printable, contains('1,000.00'));
      expect(printable, contains('Raast Sales:'));
      expect(printable, contains('500.00'));
      expect(printable, contains('Net Variance:'));
      expect(printable, contains('-20.00'));
      expect(printable, contains('Total Voids:'));
    });

    test('finalizes business day, locks day, and resets token sequence to #01 on next day', () async {
      final day1 = await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      final shift = await shiftController.openShift(staffId: cashierId, openingFloat: 1000.0);

      final catId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Snacks',
        'display_order': 1,
        'color_hex': '#FF5722',
        'created_at': DateTime.now().toIso8601String(),
      });
      final snackItemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': catId,
        'name': 'Quick Snack',
        'base_price': 200.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      final snackItem = MenuItem(
        id: snackItemId,
        categoryId: catId,
        name: 'Quick Snack',
        basePrice: 200.0,
      );

      // Create an order in Day 1: token will be #01
      final res1 = await orderController.checkoutOrder(
        businessDayId: day1.id,
        shiftId: shift.id,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: snackItem, quantity: 1),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 200.0),
        ],
      );
      expect(res1.order.tokenNumber, equals(1));

      // Second order in Day 1: token will be #02
      final res2 = await orderController.checkoutOrder(
        businessDayId: day1.id,
        shiftId: shift.id,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(menuItem: snackItem, quantity: 1),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 200.0),
        ],
      );
      expect(res2.order.tokenNumber, equals(2));

      // Close shift
      await shiftController.closeShift(shiftId: shift.id, countedCash: 1400.0);

      // Finalize Day 1 with Z-Report
      final closedDay = await shiftController.finalizeBusinessDayWithZReport(
        closedByStaffId: supervisorId,
      );
      expect(closedDay.isClosed, isTrue);

      // Now open Day 2
      final day2 = await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      final nextTokenDay2 = await orderController.getNextTokenNumber(day2.id);

      // Verify token resets to #01 for the fresh Business Day!
      expect(nextTokenDay2, equals(1));
    });
  });
}
