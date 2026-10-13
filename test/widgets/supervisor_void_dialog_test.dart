import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/print_job.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/order_void.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/orders/reprint_tray_dialog.dart';
import 'package:resturant_sys/widgets/orders/supervisor_void_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SupervisorVoidDialog Widget Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;
    late ShiftAndCashController shiftController;
    late CatalogAndRecipeController catalogController;
    late OrderAndCheckoutController orderController;
    late InMemoryHardwareAdapter hardwareAdapter;
    late ReprintTrayController reprintTrayController;
    late Order testOrder;

    const cashierStaff = Staff(
      id: 2,
      name: 'Counter Cashier',
      departmentId: 1,
      pinHash: 'hash',
      role: StaffRole.cashier,
      isActive: true,
      departmentName: 'Front Counter',
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('void_dialog_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_void.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();

      authService = AuthService(database: db);
      shiftController = ShiftAndCashController(database: db);
      catalogController = CatalogAndRecipeController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      hardwareAdapter = InMemoryHardwareAdapter();
      reprintTrayController = ReprintTrayController(hardwareAdapter: hardwareAdapter);

      // Create Day & Shift
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      // Create catalog and ingredients
      final meat = await catalogController.createRawIngredient(
        name: 'Chicken Patty',
        storageUnit: StorageUnit.count,
        currentStock: 20.0,
      );
      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Zinger', basePrice: 500.0);
      await catalogController.addOrUpdateRecipeItem(menuItemId: burger.id, rawIngredientId: meat.id, quantity: 1.0);

      // Checkout an order
      final result = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 2)],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000.0),
        ],
      );
      testOrder = result.order;

      // Verify stock was reduced
      final stockPostCheckout = await catalogController.getRawIngredient(meat.id);
      expect(stockPostCheckout.currentStock, equals(18.0));
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget createTestApp(Widget child) {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(body: child),
      );
    }

    testWidgets('renders order summary, mandatory reasons, and supervisor pin numpad without logging cashier out', (tester) async {
      authService.session.login(cashierStaff);
      expect(authService.session.isAuthenticated, isTrue);
      expect(authService.session.currentStaff?.name, equals('Counter Cashier'));

      await tester.pumpWidget(createTestApp(
        SupervisorVoidDialog(
          order: testOrder,
          cashierId: cashierStaff.id,
          orderController: orderController,
          authService: authService,
          reprintTrayController: reprintTrayController,
        ),
      ));
      await tester.pumpAndSettle();

      // Header details
      expect(find.text('Supervisor Void Authorization'), findsOneWidget);
      expect(find.textContaining('Order #${testOrder.id}'), findsOneWidget);
      expect(find.textContaining('Token ${testOrder.tokenDisplay}'), findsOneWidget);

      // Mandatory void reasons
      expect(find.text('Void Reason (Mandatory):'), findsOneWidget);
      expect(find.text(VoidReason.customerCancelled), findsOneWidget);
      expect(find.text(VoidReason.cashierMistake), findsOneWidget);
      expect(find.text(VoidReason.paymentDeclined), findsOneWidget);

      // Pin Numpad
      expect(find.text('Enter Supervisor 4-Digit PIN'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);

      // Cashier remains logged in
      expect(authService.session.isAuthenticated, isTrue);
      expect(authService.session.currentStaff?.id, equals(cashierStaff.id));
    });

    testWidgets('rejects invalid or non-supervisor PIN, shows error message, and keeps cashier logged in', (tester) async {
      authService.session.login(cashierStaff);

      await tester.pumpWidget(createTestApp(
        SupervisorVoidDialog(
          order: testOrder,
          cashierId: cashierStaff.id,
          orderController: orderController,
          authService: authService,
          reprintTrayController: reprintTrayController,
        ),
      ));
      await tester.pumpAndSettle();

      // Enter cashier PIN (1111) which has no supervisor permissions
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pumpAndSettle();

      // Error message displayed
      expect(find.text('Invalid Supervisor PIN or insufficient privileges.'), findsOneWidget);

      // Order is NOT voided
      final orderInDb = await orderController.getOrder(testOrder.id);
      expect(orderInDb.isVoided, isFalse);

      // Cashier is still logged in
      expect(authService.session.currentStaff?.id, equals(cashierStaff.id));
    });

    testWidgets('authorizes with valid supervisor PIN (1234), voids order, restores stock, emits void slip, and pops', (tester) async {
      authService.session.login(cashierStaff);
      bool voidSuccessCallbackCalled = false;

      await tester.pumpWidget(createTestApp(
        SupervisorVoidDialog(
          order: testOrder,
          cashierId: cashierStaff.id,
          orderController: orderController,
          authService: authService,
          reprintTrayController: reprintTrayController,
          onVoidSuccess: () => voidSuccessCallbackCalled = true,
        ),
      ));
      await tester.pumpAndSettle();

      // Select 'Cashier Mistake' reason
      await tester.tap(find.byKey(const ValueKey('void_reason_cashier_mistake')));
      await tester.pumpAndSettle();

      // Enter supervisor PIN 1234
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '3'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '4'));
      await tester.pumpAndSettle();

      expect(voidSuccessCallbackCalled, isTrue);

      // Order is VOIDED in database
      final orderInDb = await orderController.getOrder(testOrder.id);
      expect(orderInDb.isVoided, isTrue);
      expect(orderInDb.paymentStatus, equals('VOIDED'));

      // Audit record was logged
      final audit = await orderController.getOrderVoid(testOrder.id);
      expect(audit, isNotNull);
      expect(audit!.reason, equals(VoidReason.cashierMistake));
      expect(audit.supervisorName, equals('Supervisor'));

      // Inventory was restored: 18 -> 20
      final ingList = await catalogController.getRawIngredients();
      final patty = ingList.firstWhere((i) => i.name == 'Chicken Patty');
      expect(patty.currentStock, equals(20.0));

      // ESC/POS Kitchen Void Slip was automatically dispatched!
      expect(reprintTrayController.recentJobs.length, equals(1));
      final voidJob = reprintTrayController.recentJobs.first;
      expect(voidJob.type, equals(PrintJobType.kitchenVoidSlip));
      expect(hardwareAdapter.kitchenPrintedBytes.length, equals(1));

      // Cashier remains logged in throughout the entire flow
      expect(authService.session.currentStaff?.id, equals(cashierStaff.id));
    });

    testWidgets('ReprintTrayDialog allows supervisor to view and toggle cashier void requests switch', (tester) async {
      const supervisorStaff = Staff(
        id: 1,
        name: 'Supervisor',
        departmentId: 1,
        pinHash: 'hash',
        role: StaffRole.supervisor,
        isActive: true,
      );

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: reprintTrayController,
          currentStaff: supervisorStaff,
          orderController: orderController,
          authService: authService,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final switchFinder = find.byKey(const ValueKey('toggle_cashier_void_switch'));
      expect(switchFinder, findsOneWidget);
      expect(find.text('Cashier Void Requests: Enabled'), findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Cashier Void Requests: Disabled'), findsOneWidget);
      final enabled = await orderController.isCashierVoidEnabled();
      expect(enabled, isFalse);
    });

    testWidgets('ReprintTrayDialog recent settled job displays Void button and launches SupervisorVoidDialog', (tester) async {
      const supervisorStaff = Staff(
        id: 1,
        name: 'Supervisor',
        departmentId: 1,
        pinHash: 'hash',
        role: StaffRole.supervisor,
        isActive: true,
      );

      await reprintTrayController.dispatchOrderPrinting(order: testOrder, isCashPaid: true);

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: reprintTrayController,
          currentStaff: supervisorStaff,
          orderController: orderController,
          authService: authService,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final voidBtn = find.byKey(ValueKey('void_job_${reprintTrayController.recentJobs.first.id}'));
      expect(voidBtn, findsOneWidget);

      await tester.tap(voidBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SupervisorVoidDialog), findsOneWidget);
      expect(find.text('Supervisor Void Authorization'), findsOneWidget);
    });

    testWidgets('CounterBillingWorkspace alerts when cashier void requests are disabled', (tester) async {
      await orderController.setCashierVoidEnabled(false);

      await tester.pumpWidget(createTestApp(
        CounterBillingWorkspace(
          currentStaff: cashierStaff,
          businessDayId: 1,
          shiftId: 1,
          orderController: orderController,
          authService: authService,
          reprintTrayController: reprintTrayController,
          initialCategories: const [],
          initialMenuItems: const [],
          initialDeals: const [],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final voidButtonFinder = find.byKey(const ValueKey('open_void_order_button'));
      expect(voidButtonFinder, findsOneWidget);

      await tester.tap(voidButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Cashier void requests are disabled by management.'), findsOneWidget);
    });
  });
}
