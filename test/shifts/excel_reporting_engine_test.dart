import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/procurement/desi_unit.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/procurement/wastage_reason.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/shifts/excel_reporting_engine.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ExcelReportingEngine 6-Sheet Workbook Generation Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late ProcurementAndWastageController procurementController;
    late VendorKhataController khataController;
    late CatalogAndRecipeController catalogController;
    late ExcelReportingEngine excelEngine;
    late int supervisorId;
    late int cashierId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_excel_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}excel_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      catalogController = CatalogAndRecipeController(database: db);
      procurementController = ProcurementAndWastageController(database: db);
      khataController = VendorKhataController(database: db);
      excelEngine = ExcelReportingEngine(database: db);

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

    test('generates valid 6-sheet .xlsx workbook with ISO audit timestamps', () async {
      // 1. Setup Day, Shifts, Catalog, Orders, Wastage, Vendor
      final day = await shiftController.openBusinessDay(openedByStaffId: supervisorId);

      final catId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Crispy Chicken',
        'display_order': 1,
        'color_hex': '#FF9800',
        'created_at': DateTime.now().toIso8601String(),
      });
      final ingId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Chicken Drumsticks',
        'storage_unit': 'kg',
        'current_stock': 40.0,
        'low_stock_threshold': 5.0,
        'cost_per_recipe_unit': 200.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final menuItemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': catId,
        'name': 'Hot Crispy Drumsticks',
        'base_price': 650.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert(PosDatabaseConstants.tableRecipes, {
        'menu_item_id': menuItemId,
        'raw_ingredient_id': ingId,
        'quantity_per_recipe_unit': 0.25,
        'created_at': DateTime.now().toIso8601String(),
      });

      final drumstickItem = MenuItem(
        id: menuItemId,
        categoryId: catId,
        name: 'Hot Crispy Drumsticks',
        basePrice: 650.0,
      );

      final shift = await shiftController.openShift(staffId: cashierId, openingFloat: 5000.0);

      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: cashierId,
        diningType: DiningType.takeaway,
        items: [
          CartItem(
            menuItem: drumstickItem,
            quantity: 2,
          ),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 1300.0),
        ],
      );

      await shiftController.closeShift(shiftId: shift.id, staffId: shift.staffId, countedCash: 6300.0);

      await procurementController.recordKitchenWastage(
        staffPin: '1111',
        rawIngredientId: ingId,
        quantity: 1.5,
        reason: WastageReason.dropped,
        notes: 'Dropped during rush hour',
      );

      await procurementController.recordMandiPurchase(
        rawIngredientId: ingId,
        unit: DesiUnit.dharri,
        quantity: 4.0,
        totalCost: 3800.0,
        notes: 'Morning fresh poultry mandi',
      );

      final vendor = await khataController.createVendor(name: 'Punjab Broilers', phone: '03215551234');
      await khataController.recordCreditDelivery(vendorId: vendor.id, amount: 8000.0, referenceSlip: 'DEL-88');
      await khataController.recordSettlementPayment(
        vendorId: vendor.id,
        amount: 3000.0,
        paymentSource: VendorPaymentSource.paidOutsideDrawer,
        staffId: supervisorId,
        notes: 'Interbank wire transfer',
      );

      final zReport = await shiftController.generateZReport(day.id);

      // 2. Generate 6-Sheet Excel Workbook
      final bytes = await excelEngine.generateDailyWorkbookBytes(
        businessDayId: day.id,
        zReport: zReport,
      );

      expect(bytes, isNotEmpty);

      // 3. Inspect ZIP structure (OpenXML .xlsx)
      final archive = ZipDecoder().decodeBytes(bytes);
      final fileNames = archive.files.map((f) => f.name).toSet();

      expect(fileNames.contains('[Content_Types].xml'), isTrue);
      expect(fileNames.contains('xl/workbook.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet1.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet2.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet3.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet4.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet5.xml'), isTrue);
      expect(fileNames.contains('xl/worksheets/sheet6.xml'), isTrue);

      // Verify workbook.xml defines all 6 required sheet names
      final workbookFile = archive.findFile('xl/workbook.xml')!;
      final workbookXml = utf8.decode(workbookFile.content as List<int>);
      expect(workbookXml, contains('Executive Summary'));
      expect(workbookXml, contains('Sales by Item'));
      expect(workbookXml, contains('Stock &amp; BOM Consumption'));
      expect(workbookXml, contains('Kitchen Wastage Log'));
      expect(workbookXml, contains('Shift Handover Audits'));
      expect(workbookXml, contains('Vendor Khata Ledger'));

      // Verify Sheet 1 contains Executive Summary data & ISO timestamp
      final sheet1File = archive.findFile('xl/worksheets/sheet1.xml')!;
      final sheet1Xml = utf8.decode(sheet1File.content as List<int>);
      expect(sheet1Xml, contains('Executive Daily Summary'));
      expect(sheet1Xml, contains('Net Sales'));
      expect(sheet1Xml, contains('1300'));
      expect(sheet1Xml, contains('Cash Sales'));
      expect(sheet1Xml, contains('SHIFT DISCREPANCIES AUDIT'));
      // Verify ISO timestamp format (e.g. 2026-10-15)
      expect(sheet1Xml, contains(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')));

      // Verify Sheet 2 contains Item Sales
      final sheet2File = archive.findFile('xl/worksheets/sheet2.xml')!;
      final sheet2Xml = utf8.decode(sheet2File.content as List<int>);
      expect(sheet2Xml, contains('Hot Crispy Drumsticks'));
      expect(sheet2Xml, contains('Crispy Chicken'));

      // Verify Sheet 3 contains Stock & BOM Consumption with Recipe Usage
      final sheet3File = archive.findFile('xl/worksheets/sheet3.xml')!;
      final sheet3Xml = utf8.decode(sheet3File.content as List<int>);
      expect(sheet3Xml, contains('Chicken Drumsticks'));
      expect(sheet3Xml, contains('Recipe Usage'));
      expect(sheet3Xml, contains('Mandi Purchases'));

      // Verify Sheet 4 contains Kitchen Wastage log
      final sheet4File = archive.findFile('xl/worksheets/sheet4.xml')!;
      final sheet4Xml = utf8.decode(sheet4File.content as List<int>);
      expect(sheet4Xml, contains('Chicken Drumsticks'));
      expect(sheet4Xml, contains('Dropped during rush hour'));

      // Verify Sheet 5 contains Shift Handover with Pay-Ins, Pay-Outs, and Voids
      final sheet5File = archive.findFile('xl/worksheets/sheet5.xml')!;
      final sheet5Xml = utf8.decode(sheet5File.content as List<int>);
      expect(sheet5Xml, contains('Shift Handover'));
      expect(sheet5Xml, contains('5000')); // Opening float
      expect(sheet5Xml, contains('Pay-Ins'));
      expect(sheet5Xml, contains('Pay-Outs'));
      expect(sheet5Xml, contains('Voids'));

      // Verify Sheet 6 contains Vendor Khata Ledger
      final sheet6File = archive.findFile('xl/worksheets/sheet6.xml')!;
      final sheet6Xml = utf8.decode(sheet6File.content as List<int>);
      expect(sheet6Xml, contains('Punjab Broilers'));
      expect(sheet6Xml, contains('8000'));
      expect(sheet6Xml, contains('3000'));

      // 4. Test file export on disk
      final reportPath = '${tempDir.path}${Platform.pathSeparator}z_report_day_${day.id}.xlsx';
      final savedFile = await excelEngine.saveWorkbookToFile(bytes: bytes, filePath: reportPath);
      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.length(), equals(bytes.length));
    });

    test('Sheet 3 Stock & BOM captures recipe usage from Deals and Modifiers', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      final shift = await shiftController.openShift(staffId: cashierId, openingFloat: 2000.0);

      final catId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Burgers',
        'display_order': 1,
        'color_hex': '#E65100',
        'created_at': DateTime.now().toIso8601String(),
      });

      final bunIngId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Burger Bun',
        'storage_unit': 'count',
        'current_stock': 100.0,
        'low_stock_threshold': 10.0,
        'cost_per_recipe_unit': 20.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final pattyIngId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Beef Patty',
        'storage_unit': 'count',
        'current_stock': 50.0,
        'low_stock_threshold': 5.0,
        'cost_per_recipe_unit': 150.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final cheeseIngId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Cheddar Slice',
        'storage_unit': 'count',
        'current_stock': 80.0,
        'low_stock_threshold': 10.0,
        'cost_per_recipe_unit': 30.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      final burgerItemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': catId,
        'name': 'Classic Burger',
        'base_price': 500.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert(PosDatabaseConstants.tableRecipes, {
        'menu_item_id': burgerItemId,
        'raw_ingredient_id': bunIngId,
        'quantity_per_recipe_unit': 1.0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert(PosDatabaseConstants.tableRecipes, {
        'menu_item_id': burgerItemId,
        'raw_ingredient_id': pattyIngId,
        'quantity_per_recipe_unit': 1.0,
        'created_at': DateTime.now().toIso8601String(),
      });

      final deal = await orderController.createDeal(
        name: 'Solo Burger Combo',
        basePrice: 650.0,
        items: [
          DealItemDraft(
            groupName: 'Burger',
            defaultMenuItemId: burgerItemId,
          ),
        ],
      );

      final extraCheeseMod = await catalogController.createModifier(
        menuItemId: burgerItemId,
        name: '+Extra Cheese',
        priceDelta: 50.0,
        rawIngredientId: cheeseIngId,
        ingredientQtyDelta: 1.0,
      );

      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [
          CartItem(
            deal: deal,
            quantity: 2,
            selectedDealChoices: [
              SelectedDealChoice(
                dealItemId: deal.items[0].id,
                groupName: 'Burger',
                menuItemId: burgerItemId,
                menuItemName: 'Classic Burger',
              ),
            ],
            selectedModifiers: [extraCheeseMod],
          ),
        ],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 1500.0, changeReturned: 100.0),
        ],
      );

      final zReport = await shiftController.generateZReport(day.id);
      final bytes = await excelEngine.generateDailyWorkbookBytes(
        businessDayId: day.id,
        zReport: zReport,
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      final sheet3File = archive.findFile('xl/worksheets/sheet3.xml')!;
      final sheet3Xml = utf8.decode(sheet3File.content as List<int>);

      expect(sheet3Xml, contains('<is><t>Beef Patty</t></is></c>'));
      expect(sheet3Xml, contains('<is><t>Cheddar Slice</t></is></c>'));

      final pattyIndex = sheet3Xml.indexOf('<is><t>Beef Patty</t></is>');
      expect(pattyIndex, isNonNegative);
      final pattyRowEnd = sheet3Xml.indexOf('</row>', pattyIndex);
      final pattyRowXml = sheet3Xml.substring(pattyIndex, pattyRowEnd);
      expect(pattyRowXml, contains('<v>2.0</v>'));

      final cheeseIndex = sheet3Xml.indexOf('<is><t>Cheddar Slice</t></is>');
      expect(cheeseIndex, isNonNegative);
      final cheeseRowEnd = sheet3Xml.indexOf('</row>', cheeseIndex);
      final cheeseRowXml = sheet3Xml.substring(cheeseIndex, cheeseRowEnd);
      expect(cheeseRowXml, contains('<v>2.0</v>'));
    });
  });
}
