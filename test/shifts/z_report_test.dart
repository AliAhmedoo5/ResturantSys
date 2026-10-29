import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:resturant_sys/core/shifts/report_export_service.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/shifts/report_delivery_service.dart';
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

    test('failed Business Day seal rolls back every shift closure', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      final shift = await shiftController.openShift(staffId: cashierId, openingFloat: 100);
      await db.execute("CREATE TRIGGER reject_close BEFORE UPDATE OF status ON business_days WHEN NEW.status = 'CLOSED' BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END");
      await expectLater(
        shiftController.finalizeBusinessDayWithZReport(closedByStaffId: supervisorId),
        throwsA(anything),
      );
      expect((await shiftController.getActiveBusinessDay())?.id, day.id);
      expect((await shiftController.getShift(shift.id)).isOpen, isTrue);
    });
    test('Z-close saves immutable PDF and Excel artifacts beside the local database', () async {
      await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      await shiftController.openShift(staffId: cashierId, openingFloat: 100);
      await shiftController.finalizeBusinessDayWithZReport(closedByStaffId: supervisorId);
      final files = await Directory('${tempDir.path}/reports').list(recursive: true).where((f) => f is File).toList();
      final pdf = File(files.singleWhere((f) => f.path.endsWith('.pdf')).path);
      final xlsx = File(files.singleWhere((f) => f.path.endsWith('.xlsx')).path);
      expect(String.fromCharCodes((await pdf.readAsBytes()).take(5)), '%PDF-');
      expect((await xlsx.readAsBytes()).take(2), [80, 75]);
    });

    test('offline delivery retries persist independently of a sealed Business Day', () async {
      final delivery = ReportDeliveryService(database: db, transport: (_) async => throw const SocketException('offline'));
      await delivery.configure(managerStaffId: supervisorId, endpoint: 'https://reports.example.test/send',
        recipients: [const ReportRecipient(channel:'EMAIL',address:'owner@example.test',approved:true)]);
      await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      await shiftController.openShift(staffId: cashierId, openingFloat: 100);
      await shiftController.finalizeBusinessDayWithZReport(closedByStaffId: supervisorId);
      final queued = await delivery.history(managerStaffId:supervisorId);
      expect(queued.single['status'],'PENDING');
      await delivery.processPending(now: DateTime.now().toUtc().add(const Duration(minutes:1)));
      final failed = (await delivery.history(managerStaffId:supervisorId)).single;
      expect(failed['status'],'PENDING');
      expect(failed['retry_count'],1);
      expect(failed['error_message'],'Connection unavailable; retry scheduled.');
      expect(await shiftController.getActiveBusinessDay(),isNull);
      await posDb.close();
      db = await posDb.initialize();
      final restarted = ReportDeliveryService(database:db,transport: (_) async => 'provider-message-42');
      expect((await restarted.history(managerStaffId:supervisorId)).single['retry_count'],1);
      await restarted.processPending(now:DateTime.parse(failed['next_attempt_at'] as String).add(const Duration(seconds:1)));
      expect((await restarted.history(managerStaffId:supervisorId)).single['status'],'ACCEPTED');
    });

    test('recovers synthetic report snapshot after disk failure and later catalog edits', () async {
      final delivery=ReportDeliveryService(database:db,transport:(_) async=>'synthetic-provider');
      await delivery.configure(managerStaffId:supervisorId,endpoint:'https://reports.example.test/send',
        recipients:[const ReportRecipient(channel:'EMAIL',address:'fixture@example.invalid',approved:true)]);
      final day=await shiftController.openBusinessDay(openedByStaffId:supervisorId);
      final shift=await shiftController.openShift(staffId:cashierId,openingFloat:100);
      final now=DateTime.now().toIso8601String();
      final category=await db.insert('categories',{'name':'Synthetic category','display_order':1,'color_hex':'#FFC400','created_at':now});
      final ingredient=await db.insert('raw_ingredients',{'name':'Synthetic Flour','storage_unit':'kg','current_stock':10.0,'low_stock_threshold':0.0,'cost_per_recipe_unit':1.0,'created_at':now});
      final item=await db.insert('menu_items',{'category_id':category,'name':'Synthetic Burger','base_price':123.45,'tax_rate':0.0,'is_tax_inclusive':1,'is_active':1,'created_at':now});
      await db.insert('recipes',{'menu_item_id':item,'raw_ingredient_id':ingredient,'quantity_per_recipe_unit':0.25,'created_at':now});
      final menu=MenuItem(id:item,categoryId:category,name:'Synthetic Burger',basePrice:123.45);
      for(final tender in [const PaymentTender(method:PaymentMethod.cash,amountTendered:123),const PaymentTender(method:PaymentMethod.jazzCash,amountTendered:123.45)]) {
        await orderController.checkoutOrder(businessDayId:day.id,shiftId:shift.id,cashierId:cashierId,
          diningType:DiningType.dineIn,items:[CartItem(menuItem:menu,quantity:1)],payments:[tender]);
      }
      await shiftController.closeBusinessDay(closedByStaffId:supervisorId,autoLockActiveShifts:true);
      final blocked=File('${tempDir.path}/blocked');
      await blocked.writeAsString('synthetic file occupying report directory');
      final exporter=ReportExportService(database:db,directory:blocked.path);
      await exporter.exportPending();
      expect(await shiftController.getActiveBusinessDay(),isNull);
      expect((await shiftController.getShift(shift.id)).countedCash,isNull);
      expect((await exporter.history()).single['status'],'PENDING');
      final catalog=CatalogAndRecipeController(database:db);
      final raw=await catalog.getRawIngredient(ingredient);
      await catalog.updateRawIngredient(raw.copyWith(name:'Changed after close',currentStock:500));
      final recovered=ReportExportService(database:db,directory:'${tempDir.path}/recovered');
      await recovered.exportPending();
      final run=(await recovered.history()).single;
      final snapshot=jsonDecode(run['snapshot_json'] as String) as Map<String,dynamic>;
      final sections=snapshot['sections'] as List;
      final summary=Map<String,dynamic>.fromEntries((sections[0]['rows'] as List).map((r)=>MapEntry(r[0] as String,r[1])));
      expect(summary['Net sales incl. Collection Due'],24690);
      expect(summary['Tender CASH (collected)'],12300);
      expect(summary['Tender JAZZCASH (collected)'],12345);
      expect(summary['Cash rounding'],-45);
      expect((sections[2]['rows'] as List).single,['Synthetic Flour','kg',0,9.5,9.5]);
      final artifacts=jsonDecode(run['artifacts_json'] as String) as List;
      final workbook=File(artifacts.singleWhere((a)=>a['kind']=='xlsx')['path'] as String);
      final archive=ZipDecoder().decodeBytes(await workbook.readAsBytes());
      final salesXml=utf8.decode(archive.findFile('xl/worksheets/sheet2.xml')!.content as List<int>);
      final inventoryXml=utf8.decode(archive.findFile('xl/worksheets/sheet3.xml')!.content as List<int>);
      expect(salesXml,contains('Synthetic Burger'));
      expect(salesXml,contains('<v>12345</v>'));
      expect(inventoryXml,contains('Synthetic Flour'));
      expect(inventoryXml,isNot(contains('Changed after close')));
      expect(inventoryXml,contains('<v>9.5</v>'));
      expect(inventoryXml,contains('Recorded inventory movements'));
      expect(inventoryXml,contains('<v>10.0</v>')); 
      await recovered.exportPending();
      await delivery.enqueueReadyReports();
      await delivery.enqueueReadyReports();
      expect((await delivery.history(managerStaffId:supervisorId)).length,1);
      expect(await Directory('${tempDir.path}/recovered').list().length,2);
      final sample=Platform.environment['SYNTHETIC_Z_CLOSE_FIXTURE'];
      if(sample!=null) {
        await Directory(sample).create(recursive:true);
        for(final artifact in artifacts) {
          await File(artifact['path'] as String).copy('$sample/synthetic-z-close.${artifact['kind']}');
        }
      }
    });

    test('concurrent export recovery persists one immutable artifact pair', () async {
      await shiftController.openBusinessDay(openedByStaffId:supervisorId);
      await shiftController.closeBusinessDay(closedByStaffId:supervisorId);
      final first=ReportExportService(database:db,directory:'${tempDir.path}/first-recovery');
      final second=ReportExportService(database:db,directory:'${tempDir.path}/second-recovery');
      await Future.wait([first.exportPending(),second.exportPending()]);
      final files=await tempDir.list(recursive:true).where((file)=>file.path.endsWith('.pdf') || file.path.endsWith('.xlsx')).toList();
      expect(files.length,2);
      expect((await first.history()).single['status'],'READY');
    });

    for (final scenario in [
      {'name':'partial reduction','refund':2000,'balance':80.0},
      {'name':'full cancellation','refund':10000,'balance':0.0},
    ]) {
      test('Z drawer reconciliation counts ${scenario['name']} cash refund once', () async {
        final day=await shiftController.openBusinessDay(openedByStaffId:supervisorId);
        final shift=await shiftController.openShift(staffId:cashierId,openingFloat:0);
        final now=DateTime.now().toIso8601String();
        final category=await db.insert('categories',{'name':'Refund fixture','display_order':1,'color_hex':'#FFC400','created_at':now});
        final ingredient=await db.insert('raw_ingredients',{'name':'Refund portion','storage_unit':'count','current_stock':10,'created_at':now});
        final item=await db.insert('menu_items',{'category_id':category,'name':'Refund snack','base_price':20.0,'tax_rate':0.0,'is_tax_inclusive':1,'is_active':1,'created_at':now});
        await db.insert('recipes',{'menu_item_id':item,'raw_ingredient_id':ingredient,'quantity_per_recipe_unit':1,'created_at':now});
        final menu=MenuItem(id:item,categoryId:category,name:'Refund snack',basePrice:20);
        final sale=await orderController.checkoutOrder(businessDayId:day.id,shiftId:shift.id,cashierId:cashierId,
          diningType:DiningType.dineIn,items:[CartItem(menuItem:menu,quantity:5)],
          payments:[const PaymentTender(method:PaymentMethod.cash,amountTendered:100)]);
        if(scenario['name']=='full cancellation') {
          await orderController.cancelOrder(orderId:sale.order.id,cashierId:cashierId,
            reason:'Customer cancelled',commandId:'refund-full-cancel');
        } else {
          await orderController.reviseOrder(orderId:sale.order.id,cashierId:cashierId,
            reason:'Remove one snack',commandId:'refund-partial-revise',newItems:[CartItem(menuItem:menu,quantity:4)]);
        }
        await orderController.recordCashierRefund(orderId:sale.order.id,shiftId:shift.id,cashierId:cashierId,
          amountPaisa:scenario['refund'] as int,method:PaymentMethod.cash,reason:'Cash returned to customer',commandId:'explicit-refund');
        final expected=scenario['balance'] as double;
        expect(await shiftController.calculateExpectedCash(shift.id),expected);
        final preview=await shiftController.generateZReport(day.id);
        expect(preview.cashSales,expected,reason:'Collected tender is net of the explicit refund');
        expect(preview.totalExpectedDrawerCash,expected,reason:'Drawer payout must not be deducted a second time');
        expect(preview.toPrintableString(),contains(RegExp(r'Expected Drawer:\s+Rs '+RegExp.escape(expected.toStringAsFixed(2)))));
        final frozenShift=await shiftController.closeShift(shiftId:shift.id,staffId:cashierId,countedCash:expected);
        expect(frozenShift.expectedCash,expected);
        expect(frozenShift.discrepancy,0);
        await shiftController.finalizeBusinessDayWithZReport(closedByStaffId:supervisorId);
        final closed=await shiftController.generateZReport(day.id);
        expect(closed.totalExpectedDrawerCash,expected);
        expect(closed.totalCountedCash,expected);
        expect(closed.netCashVariance,0);
        final run=(await ReportExportService(database:db).history()).single;
        final sections=(jsonDecode(run['snapshot_json'] as String) as Map)['sections'] as List;
        final frozenRows=sections[4]['rows'] as List;
        expect(frozenRows.single[3],scenario['name']=='full cancellation'?0:8000);
        expect(frozenRows.single[4],scenario['name']=='full cancellation'?0:8000);
        expect(frozenRows.single[5],0);
      });
    }

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
      await shiftController.closeShift(shiftId: shift1.id, staffId: shift1.staffId, countedCash: 5680.0);

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
      await shiftController.closeShift(shiftId: shift2.id, staffId: shift2.staffId, countedCash: 2900.0);

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
        staffId: supervisorId,
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
      expect(printable, contains('Net Discrepancy:'));
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
      final portionId = await db.insert('raw_ingredients', {
        'name': 'Prepared portion', 'storage_unit': 'count', 'current_stock': 100,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('recipes', {
        'menu_item_id': snackItemId, 'raw_ingredient_id': portionId,
        'quantity_per_recipe_unit': 1, 'created_at': DateTime.now().toIso8601String(),
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
      await shiftController.closeShift(shiftId: shift.id, staffId: shift.staffId, countedCash: 1400.0);

      // Finalize Day 1 with Z-Report
      final closedDay = await shiftController.finalizeBusinessDayWithZReport(
        closedByStaffId: supervisorId,
      );
      expect(closedDay.isClosed, isTrue);
      await expectLater(orderController.cancelOrder(orderId:res1.order.id,cashierId:cashierId,
        reason:'Attempt after seal',commandId:'closed-day-cancel'),throwsStateError);
      await expectLater(orderController.checkoutOrder(businessDayId:day1.id,shiftId:shift.id,
        cashierId:cashierId,diningType:DiningType.dineIn,items:[CartItem(menuItem:snackItem,quantity:1)],
        payments:[const PaymentTender(method:PaymentMethod.cash,amountTendered:200)]),throwsStateError);
      expect((await orderController.getOrder(res1.order.id)).tokenNumber,1);

      // Now open Day 2
      final day2 = await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      final nextTokenDay2 = await orderController.getNextTokenNumber(day2.id);

      // Verify token resets to #01 for the fresh Business Day!
      expect(nextTokenDay2, equals(1));
      final nextShift=await shiftController.openShift(staffId:cashierId,openingFloat:100);
      final nextOrder=await orderController.checkoutOrder(businessDayId:day2.id,shiftId:nextShift.id,
        cashierId:cashierId,diningType:DiningType.dineIn,items:[CartItem(menuItem:snackItem,quantity:1)],
        payments:[const PaymentTender(method:PaymentMethod.cash,amountTendered:200)]);
      expect(nextOrder.order.tokenNumber,1);
      expect((await orderController.getOrder(res2.order.id)).tokenNumber,2);
    });

    test('finalizeBusinessDayWithZReport auto-locks open shifts and concludes day when shift is active', () async {
      await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      final shift = await shiftController.openShift(staffId: cashierId, openingFloat: 500.0);
      expect(shift.isOpen, isTrue);

      // Finalize Business Day with Z-Report while shift is still active
      final closedDay = await shiftController.finalizeBusinessDayWithZReport(
        closedByStaffId: supervisorId,
      );

      expect(closedDay.isClosed, isTrue);
      final activeShift = await shiftController.getActiveShift();
      expect(activeShift, isNull);

      final reloadedShiftRows = await db.query(
        PosDatabaseConstants.tableShifts,
        where: 'id = ?',
        whereArgs: [shift.id],
      );
      expect(reloadedShiftRows.first['status'], equals('CLOSED'));
    });
  });
}


