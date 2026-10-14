import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/token_queue_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/supervisor/supervisor_portal_workspace.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SupervisorPortalWorkspace Widget Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late AuthService authService;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late TokenQueueController tokenQueueController;
    late Staff supervisorStaff;
    late int businessDayId;
    late int shiftId;
    late MenuItem burger;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_portal_widget_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}portal_widget.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      final db = await posDb.initialize();

      authService = AuthService(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      tokenQueueController = TokenQueueController(
        database: db,
        authService: authService,
      );

      // Create dummy menu item
      final catId = await db.insert('categories', {
        'name': 'Burgers',
        'display_order': 1,
        'color_hex': '#FF0000',
        'created_at': DateTime.now().toIso8601String(),
      });
      final burgerId = await db.insert('menu_items', {
        'category_id': catId,
        'name': 'Zinger Burger',
        'base_price': 500.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      burger = MenuItem(
        id: burgerId,
        categoryId: catId,
        name: 'Zinger Burger',
        basePrice: 500.0,
      );

      supervisorStaff = (await authService.authenticateWithPin('1234'))!;
      final bDay = await shiftController.openBusinessDay(openedByStaffId: supervisorStaff.id);
      businessDayId = bDay.id;

      final cashier = (await authService.authenticateWithPin('1111'))!;
      final shift = await shiftController.openShift(
        staffId: cashier.id,
        openingFloat: 5000.0,
      );
      shiftId = shift.id;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Widget createTestApp() {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(
          body: SupervisorPortalWorkspace(
            authService: authService,
            shiftController: shiftController,
            orderController: orderController,
            tokenQueueController: tokenQueueController,
            currentStaff: supervisorStaff,
          ),
        ),
      );
    }

    testWidgets('renders all tabs and allows department creation and staff registration', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Verify portal tab buttons
      expect(find.byKey(const ValueKey('portal_tab_staff')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_toggles')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_discrepancies')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_tokenQueue')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_kitchenStation')), findsOneWidget);

      // Verify default Staff & Departments tab
      expect(find.textContaining('Departments'), findsOneWidget);
      expect(find.textContaining('Staff Directory'), findsOneWidget);
      expect(find.text('Supervisor'), findsWidgets);
      expect(find.text('Counter Cashier'), findsOneWidget);
      expect(find.text('Kitchen Cook'), findsOneWidget);

      // Create new Custom Department
      final addDeptBtn = find.byKey(const ValueKey('add_department_button'));
      expect(addDeptBtn, findsOneWidget);
      await tester.tap(addDeptBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Custom Department'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('department_name_input')), 'Riders');
      await tester.tap(find.byKey(const ValueKey('department_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Riders'), findsOneWidget);

      // Register new staff member
      final registerStaffBtn = find.byKey(const ValueKey('register_staff_button'));
      expect(registerStaffBtn, findsOneWidget);
      await tester.tap(registerStaffBtn);
      await tester.pumpAndSettle();

      expect(find.text('Register New Staff Member'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('staff_name_input')), 'Kamran Rider');
      await tester.enterText(find.byKey(const ValueKey('staff_pin_input')), '9876');
      await tester.tap(find.byKey(const ValueKey('staff_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Kamran Rider'), findsOneWidget);
    });

    testWidgets('feature toggles switch operational settings on and off', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Switch to Feature Toggles tab
      await tester.tap(find.byKey(const ValueKey('portal_tab_toggles')));
      await tester.pumpAndSettle();

      expect(find.text('Operational Feature Toggles'), findsOneWidget);
      expect(find.text('Interactive Token Queue Tray'), findsOneWidget);
      expect(find.text('Cashier Void Requests'), findsOneWidget);

      final tokenTraySwitch = find.byKey(const ValueKey('toggle_token_tray_switch'));
      final voidSwitch = find.byKey(const ValueKey('toggle_cashier_void_switch'));

      expect(tokenTraySwitch, findsOneWidget);
      expect(voidSwitch, findsOneWidget);

      // Toggle Token Tray Off
      await tester.tap(tokenTraySwitch);
      await tester.pumpAndSettle();
      expect(await orderController.isTokenTrayEnabled(), isFalse);

      // Toggle Cashier Void Off
      await tester.tap(voidSwitch);
      await tester.pumpAndSettle();
      expect(await orderController.isCashierVoidEnabled(), isFalse);

      // Toggle Token Tray back On
      await tester.tap(tokenTraySwitch);
      await tester.pumpAndSettle();
      expect(await orderController.isTokenTrayEnabled(), isTrue);
    });

    testWidgets('discrepancy audit review displays flagged shift and allows resolution', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Close shift with a discrepancy to generate a flagged shift
      await shiftController.closeShift(
        shiftId: shiftId,
        countedCash: 4500.0, // Expected 5000, variance = -500
      );

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Switch to Discrepancy Review tab
      await tester.tap(find.byKey(const ValueKey('portal_tab_discrepancies')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Discrepancy Audit Review'), findsOneWidget);
      expect(find.text('FLAGGED'), findsOneWidget);
      expect(find.textContaining('500.00'), findsOneWidget);

      // Tap Resolve
      final resolveBtn = find.byKey(ValueKey('resolve_discrepancy_$shiftId'));
      expect(resolveBtn, findsOneWidget);
      await tester.tap(resolveBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Resolve Shift #$shiftId Discrepancy'), findsOneWidget);

      // Submit resolution notes
      await tester.enterText(find.byType(TextField), 'Audited: short drawer verified by supervisor');
      await tester.tap(find.byKey(const ValueKey('submit_resolution_button')));
      await tester.pumpAndSettle();

      expect(find.text('RESOLVED'), findsOneWidget);
      expect(find.textContaining('Audited: short drawer'), findsOneWidget);
    });

    testWidgets('token queue tray shows active tokens with 1-tap progression and kitchen station marks ready', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Create an order
      final checkout = await orderController.checkoutOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: supervisorStaff.id,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 1000.0,
            changeReturned: 500.0,
          ),
        ],
      );
      final order = checkout.order;

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Switch to Token Queue Tray
      await tester.tap(find.byKey(const ValueKey('portal_tab_tokenQueue')));
      await tester.pumpAndSettle();

      expect(find.text('#01'), findsOneWidget);
      expect(find.text('PREPARING'), findsOneWidget);

      // 1-Tap Advance: Preparing -> Ready
      final markReadyBtn = find.byKey(ValueKey('advance_token_${order.id}'));
      expect(markReadyBtn, findsOneWidget);
      await tester.tap(markReadyBtn);
      await tester.pumpAndSettle();

      expect(find.text('READY ON PASS'), findsOneWidget);

      // 1-Tap Advance: Ready -> Delivered
      final markDeliveredBtn = find.byKey(ValueKey('advance_token_${order.id}'));
      expect(markDeliveredBtn, findsOneWidget);
      await tester.tap(markDeliveredBtn);
      await tester.pumpAndSettle();

      // Token is now Delivered, so active count is 0
      expect(find.text('Active (0)'), findsOneWidget);
    });
  });
}
