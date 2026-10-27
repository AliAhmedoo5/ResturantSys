import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/khata/vendor_transaction.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('VendorKhataController Domain Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late VendorKhataController khataController;
    late ShiftAndCashController shiftController;
    late int testStaffId;
    late int testSupervisorId;
    late int testCashierId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('khata_controller_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_khata.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      shiftController = ShiftAndCashController(database: db);
      khataController = VendorKhataController(
        database: db,
        shiftController: shiftController,
      );

      final supervisorRows = await db.query(
        PosDatabaseConstants.tableStaff,
        where: "role IN ('SUPERVISOR', 'MANAGER')",
        limit: 1,
      );
      testSupervisorId = supervisorRows.first['id'] as int;

      final cashierRows = await db.query(
        PosDatabaseConstants.tableStaff,
        where: "role = 'CASHIER'",
        limit: 1,
      );
      testCashierId = cashierRows.first['id'] as int;
      testStaffId = testSupervisorId;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<int> insertTestIngredient({
      required String name,
      required String unit,
      double initialStock = 0.0,
    }) async {
      return await db.insert(
        PosDatabaseConstants.tableRawIngredients,
        {
          'name': name,
          'storage_unit': unit,
          'current_stock': initialStock,
          'low_stock_threshold': 100.0,
          'cost_per_recipe_unit': 1.0,
          'created_at': '2026-10-14 12:00:00',
        },
      );
    }

    test('Vendor directory CRUD: creates, reads, updates, and deletes vendor with opening balance', () async {
      // 1. Create vendor
      final vendor = await khataController.createVendor(
        name: 'Al-Madina Poultry Farm',
        phone: '03001234567',
        suppliedIngredients: 'Chicken Breast, Wings',
        openingBalance: 12500.0,
      );

      expect(vendor.id, isPositive);
      expect(vendor.name, equals('Al-Madina Poultry Farm'));
      expect(vendor.phone, equals('03001234567'));
      expect(vendor.suppliedIngredients, equals('Chicken Breast, Wings'));
      expect(vendor.openingBalance, equals(12500.0));
      expect(vendor.currentBalance, equals(12500.0));

      // 2. Read vendors
      final list = await khataController.getVendors();
      expect(list.length, equals(1));
      expect(list.first.name, equals('Al-Madina Poultry Farm'));

      // Search query
      final searchHits = await khataController.getVendors(searchQuery: 'Madina');
      expect(searchHits.length, equals(1));
      final searchMisses = await khataController.getVendors(searchQuery: 'Beef');
      expect(searchMisses, isEmpty);

      // 3. Update vendor
      final updated = await khataController.updateVendor(
        id: vendor.id,
        name: 'Al-Madina Broiler & Poultry',
        phone: '03009998877',
        suppliedIngredients: 'Chicken Breast, Wings, Boneless',
      );

      expect(updated.name, equals('Al-Madina Broiler & Poultry'));
      expect(updated.phone, equals('03009998877'));
      expect(updated.currentBalance, equals(12500.0)); // Balance unchanged by edit

      // 4. Delete vendor
      await khataController.deleteVendor(vendor.id);
      final afterDelete = await khataController.getVendors();
      expect(afterDelete, isEmpty);
    });

    test('Credit Delivery entry logs stock shipment, links slip number, and increments payable balance', () async {
      final ingredientId = await insertTestIngredient(
        name: 'Fresh Chicken',
        unit: 'kg',
        initialStock: 10.0,
      );

      final vendor = await khataController.createVendor(
        name: 'Punjab Broilers',
        phone: '03211112222',
        suppliedIngredients: 'Fresh Chicken',
        openingBalance: 0.0,
      );

      await khataController.setSuppliedItems(managerId: testSupervisorId,
          vendorId: vendor.id, ingredientIds: {ingredientId});
      // Record credit delivery of 40 kg for Rs. 24,000 with slip number DS-8921
      final txn = await khataController.recordCreditDelivery(
        vendorId: vendor.id,
        amount: 24000.0,
        referenceSlip: 'DS-8921',
        rawIngredientId: ingredientId,
        quantity: 40.0,
        notes: 'Delivered in good condition to cold storage',
        staffId: testStaffId,
      );

      expect(txn.type, equals(VendorTransactionType.purchaseCredit));
      expect(txn.amount, equals(24000.0));
      expect(txn.referenceSlip, equals('DS-8921'));
      expect(txn.rawIngredientId, equals(ingredientId));
      expect(txn.quantity, equals(40.0));

      // Check vendor payable balance updated: 0 + 24000 = 24000
      final refreshedVendor = await khataController.getVendorById(vendor.id);
      expect(refreshedVendor?.currentBalance, equals(24000.0));

      // Check stock balance incremented: 10 + 40 = 50 kg
      final ingredientRow = (await db.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [ingredientId],
      )).first;
      expect(ingredientRow['current_stock'], equals(50.0));
    });

    test('Multi-source settlement: Paid from Active Drawer auto-generates Pay-Out cash movement', () async {
      // 1. Setup Business Day & Shift
      await shiftController.openBusinessDay(openedByStaffId: testSupervisorId);
      final shift = await shiftController.openShift(staffId: testCashierId, openingFloat: 5000.0);

      // 2. Create Vendor with payable balance
      final vendor = await khataController.createVendor(
        name: 'Haji Dairy',
        phone: '03334445555',
        openingBalance: 10000.0,
      );

      // 3. Settle Rs. 3,500 from active cash drawer
      final txn = await khataController.recordSettlementPayment(
        vendorId: vendor.id,
        amount: 3500.0,
        paymentSource: VendorPaymentSource.paidFromActiveDrawer,
        shiftId: shift.id,
        staffId: testSupervisorId,
        referenceSlip: 'PAY-HD-01',
        notes: 'Paid cash from till to supplier driver',
      );

      expect(txn.type, equals(VendorTransactionType.paymentDrawer));
      expect(txn.amount, equals(3500.0));

      // Check vendor balance decreased: 10000 - 3500 = 6500
      final refreshedVendor = await khataController.getVendorById(vendor.id);
      expect(refreshedVendor?.currentBalance, equals(6500.0));

      // Verify Cash Pay-Out movement was created in active shift
      final movements = await shiftController.getCashMovements(shift.id);
      expect(movements.length, equals(1));
      final movement = movements.first;
      expect(movement.type, equals(CashMovementType.payOut));
      expect(movement.amount, equals(3500.0));
      expect(movement.category, equals('Vendor Khata'));
      expect(movement.notes, contains('Haji Dairy'));
      expect(movement.notes, contains('PAY-HD-01'));
    });

    test('Multi-source settlement: Paid Outside Drawer updates balance without touching drawer float', () async {
      // 1. Setup Business Day & Shift
      await shiftController.openBusinessDay(openedByStaffId: testSupervisorId);
      final shift = await shiftController.openShift(staffId: testCashierId, openingFloat: 5000.0);

      // 2. Create Vendor with payable balance
      final vendor = await khataController.createVendor(
        name: 'Ittifaq Oil Mills',
        phone: '03456789012',
        openingBalance: 50000.0,
      );

      // 3. Settle Rs. 20,000 via Bank Transfer (outside drawer)
      final txn = await khataController.recordSettlementPayment(
        vendorId: vendor.id,
        amount: 20000.0,
        paymentSource: VendorPaymentSource.paidOutsideDrawer,
        staffId: testStaffId,
        referenceSlip: 'FT-994821',
        notes: 'Paid via Meezan Bank online transfer',
      );

      expect(txn.type, equals(VendorTransactionType.paymentExternal));
      expect(txn.amount, equals(20000.0));

      // Check vendor balance decreased: 50000 - 20000 = 30000
      final refreshedVendor = await khataController.getVendorById(vendor.id);
      expect(refreshedVendor?.currentBalance, equals(30000.0));

      // Verify ZERO cash movements were created in active shift
      final movements = await shiftController.getCashMovements(shift.id);
      expect(movements, isEmpty);
    });

    test('Paid from Active Drawer throws ArgumentError when no active shiftId is provided', () async {
      final vendor = await khataController.createVendor(
        name: 'Lahore Spices',
        phone: '03000000000',
        openingBalance: 5000.0,
      );

      expect(
        () => khataController.recordSettlementPayment(
          vendorId: vendor.id,
          amount: 1000.0,
          paymentSource: VendorPaymentSource.paidFromActiveDrawer,
          // shiftId and staffId missing!
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Paid from Active Drawer rejects payment when shift is closed', () async {
      await shiftController.openBusinessDay(openedByStaffId: testSupervisorId);
      final shift = await shiftController.openShift(staffId: testCashierId, openingFloat: 5000.0);
      await shiftController.closeShift(
        shiftId: shift.id, staffId: shift.staffId,
        countedCash: 5000.0,
      );

      final vendor = await khataController.createVendor(
        name: 'Rawalpindi Meat Mart',
        phone: '03011112222',
        openingBalance: 4000.0,
      );

      expect(
        () => khataController.recordSettlementPayment(
          vendorId: vendor.id,
          amount: 1000.0,
          paymentSource: VendorPaymentSource.paidFromActiveDrawer,
          shiftId: shift.id,
          staffId: testStaffId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Updating vendor opening balance adjusts current balance by delta', () async {
      final vendor = await khataController.createVendor(
        name: 'Faisalabad Flour Mills',
        phone: '03099998888',
        openingBalance: 10000.0,
      );

      // Add a delivery (+5,000) -> current balance becomes 15,000
      await khataController.recordCreditDelivery(
        vendorId: vendor.id,
        amount: 5000.0,
        staffId: testStaffId,
      );

      // Correct opening balance from 10,000 to 12,000 (+2,000 delta)
      final updated = await khataController.updateVendor(
        id: vendor.id,
        name: 'Faisalabad Flour Mills (Pvt) Ltd',
        phone: '03099998888',
        openingBalance: 12000.0,
      );

      expect(updated.openingBalance, equals(12000.0));
      // Current balance: 15,000 + 2,000 = 17,000
      expect(updated.currentBalance, equals(17000.0));
    });

    test('Vendor statement view displays chronological delivery receipts, settlements, and running balances', () async {
      // Vendor with initial opening balance Rs. 5,000
      final vendor = await khataController.createVendor(
        name: 'Kisan Veggies',
        phone: '03112223334',
        openingBalance: 5000.0,
      );

      // 1. Delivery 1: Rs. 8,000 (Payable becomes 13,000)
      await khataController.recordCreditDelivery(
        vendorId: vendor.id,
        amount: 8000.0,
        referenceSlip: 'KV-01',
        notes: 'Potatoes and Tomatoes delivery',
        staffId: testStaffId,
      );

      // 2. Settlement 1: Rs. 6,000 Outside Drawer (Payable becomes 7,000)
      await khataController.recordSettlementPayment(
        vendorId: vendor.id,
        amount: 6000.0,
        paymentSource: VendorPaymentSource.paidOutsideDrawer,
        referenceSlip: 'BANK-CHQ-10',
        notes: 'Cheque payment',
        staffId: testStaffId,
      );

      // 3. Delivery 2: Rs. 4,000 (Payable becomes 11,000)
      await khataController.recordCreditDelivery(
        vendorId: vendor.id,
        amount: 4000.0,
        referenceSlip: 'KV-02',
        notes: 'Onions delivery',
        staffId: testStaffId,
      );

      // Retrieve full statement
      final statement = await khataController.getVendorStatement(vendor.id);

      expect(statement.vendor.id, equals(vendor.id));
      expect(statement.openingBalance, equals(5000.0));
      expect(statement.currentBalance, equals(11000.0));
      expect(statement.entries.length, equals(3));

      // Entry 1: Delivery +8,000 -> Running balance: 13,000
      expect(statement.entries[0].transaction.referenceSlip, equals('KV-01'));
      expect(statement.entries[0].transaction.type, equals(VendorTransactionType.purchaseCredit));
      expect(statement.entries[0].creditAmount, equals(8000.0));
      expect(statement.entries[0].debitAmount, equals(0.0));
      expect(statement.entries[0].runningBalance, equals(13000.0));

      // Entry 2: Payment -6,000 -> Running balance: 7,000
      expect(statement.entries[1].transaction.referenceSlip, equals('BANK-CHQ-10'));
      expect(statement.entries[1].transaction.type, equals(VendorTransactionType.paymentExternal));
      expect(statement.entries[1].creditAmount, equals(0.0));
      expect(statement.entries[1].debitAmount, equals(6000.0));
      expect(statement.entries[1].runningBalance, equals(7000.0));

      // Entry 3: Delivery +4,000 -> Running balance: 11,000
      expect(statement.entries[2].transaction.referenceSlip, equals('KV-02'));
      expect(statement.entries[2].transaction.type, equals(VendorTransactionType.purchaseCredit));
      expect(statement.entries[2].creditAmount, equals(4000.0));
      expect(statement.entries[2].debitAmount, equals(0.0));
      expect(statement.entries[2].runningBalance, equals(11000.0));
    });
  });
}
