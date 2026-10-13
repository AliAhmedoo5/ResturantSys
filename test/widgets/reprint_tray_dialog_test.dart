import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/print_job.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/reprint_tray_dialog.dart';
import 'package:resturant_sys/widgets/orders/supervisor_void_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReprintTrayDialog Widget Tests', () {
    late InMemoryHardwareAdapter adapter;
    late ReprintTrayController controller;
    Directory? tempDir;
    PosDatabase? posDb;
    Database? db;
    OrderAndCheckoutController? orderController;
    AuthService? authService;

    const testStaff = Staff(
      id: 1,
      name: 'Supervisor Tariq',
      departmentId: 3,
      pinHash: 'hash',
      role: StaffRole.supervisor,
      isActive: true,
      departmentName: 'Management',
    );

    setUp(() {
      adapter = InMemoryHardwareAdapter();
      controller = ReprintTrayController(
        hardwareAdapter: adapter,
      );
    });

    Widget createTestApp(Widget child) {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(body: child),
      );
    }

    testWidgets('Renders empty recent tickets when no print jobs executed', (tester) async {
      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: testStaff,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Hardware & Reprint Tray'), findsOneWidget);
      expect(find.text('No receipts or KOTs printed in this session.'), findsOneWidget);
      expect(find.byKey(const ValueKey('kick_drawer_button')), findsOneWidget);
    });

    testWidgets('Kick Drawer button triggers cash drawer pulse and shows SnackBar', (tester) async {
      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: testStaff,
        ),
      ));
      await tester.pumpAndSettle();

      expect(adapter.drawerKickCount, equals(0));

      final kickButton = find.byKey(const ValueKey('kick_drawer_button'));
      await tester.tap(kickButton);
      await tester.pumpAndSettle();

      expect(adapter.drawerKickCount, equals(1));
      expect(find.text('Cash drawer pulse emitted.'), findsOneWidget);
    });

    testWidgets('Kick Drawer button rejects non-supervisor cashier', (tester) async {
      const cashierStaff = Staff(
        id: 2,
        name: 'Cashier Bilal',
        departmentId: 1,
        pinHash: 'hash',
        role: StaffRole.cashier,
        isActive: true,
        departmentName: 'Front Counter',
      );

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: cashierStaff,
        ),
      ));
      await tester.pumpAndSettle();

      final kickButton = find.byKey(const ValueKey('kick_drawer_button'));
      await tester.tap(kickButton);
      await tester.pumpAndSettle();

      expect(adapter.drawerKickCount, equals(0));
      expect(find.text('Supervisor authorization required for manual drawer kick.'), findsOneWidget);
    });

    testWidgets('Displays failed print jobs with error text and 1-tap retry button', (tester) async {
      final now = DateTime(2026, 10, 12, 12, 0, 0);
      final fakeOrder = Order(
        id: 5,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 5,
        diningType: DiningType.dineIn,
        subtotal: 500.0,
        grandTotal: 500.0,
        paymentStatus: 'SETTLED',
        createdAt: now,
      );

      adapter.shouldFailCounterPrint = true;
      await controller.dispatchOrderPrinting(order: fakeOrder, isCashPaid: false);
      expect(controller.failedCount, equals(2));

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: testStaff,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Failed Print Jobs (2)'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry_all_failed_button')), findsOneWidget);
      expect(find.text('#05'), findsWidgets);
      expect(find.text(PrintJobType.customerReceipt.label), findsOneWidget);
      expect(find.text(PrintJobType.kitchenOrderTicket.label), findsOneWidget);
    });

    testWidgets('1-tap Retry on failed job re-emits bytes and moves job out of failed list', (tester) async {
      final now = DateTime(2026, 10, 12, 12, 0, 0);
      final fakeOrder = Order(
        id: 12,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 12,
        diningType: DiningType.takeaway,
        subtotal: 700.0,
        grandTotal: 700.0,
        paymentStatus: 'SETTLED',
        createdAt: now,
      );

      // Simulate failure
      adapter.shouldFailCounterPrint = true;
      await controller.dispatchOrderPrinting(order: fakeOrder, isCashPaid: false);
      expect(controller.failedCount, equals(2));

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: testStaff,
        ),
      ));
      await tester.pumpAndSettle();

      // Printer recovered
      adapter.shouldFailCounterPrint = false;

      // Tap 1-tap retry for the first job
      final firstFailedJobId = controller.failedJobs.first.id;
      final retryBtn = find.byKey(ValueKey('retry_job_$firstFailedJobId'));
      expect(retryBtn, findsOneWidget);

      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      // Failed count decremented from 2 to 1
      expect(controller.failedCount, equals(1));
    });

    tearDown(() async {
      await db?.close();
      if (tempDir != null && await tempDir!.exists()) {
        await tempDir!.delete(recursive: true);
      }
    });

    Future<void> initDatabase() async {
      tempDir = await Directory.systemTemp.createTemp('reprint_tray_test_');
      final path = '${tempDir!.path}${Platform.pathSeparator}test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: path);
      db = await posDb!.initialize();
      orderController = OrderAndCheckoutController(database: db!);
      authService = AuthService(database: db!);
    }

    testWidgets('Supervisor can view and toggle cashier void requests feature switch', (tester) async {
      await initDatabase();

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: testStaff,
          orderController: orderController,
          authService: authService,
        ),
      ));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const ValueKey('toggle_cashier_void_switch'));
      expect(switchFinder, findsOneWidget);
      expect(find.text('Cashier Void Requests: Enabled'), findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(find.text('Cashier Void Requests: Disabled'), findsOneWidget);
      final enabled = await orderController!.isCashierVoidEnabled();
      expect(enabled, isFalse);
    });

    testWidgets('Recent settled job displays Void button and opens SupervisorVoidDialog', (tester) async {
      await initDatabase();

      final now = DateTime(2026, 10, 12, 12, 0, 0);
      await db!.insert('orders', {
        'id': 7,
        'business_day_id': 1,
        'shift_id': 1,
        'cashier_id': 2,
        'token_number': 7,
        'dining_type': 'dineIn',
        'subtotal': 450.0,
        'discount_amount': 0.0,
        'tax_amount': 0.0,
        'delivery_fee': 0.0,
        'grand_total': 450.0,
        'payment_status': 'SETTLED',
        'created_at': now.toIso8601String(),
      });

      final fakeOrder = Order(
        id: 7,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 7,
        diningType: DiningType.dineIn,
        subtotal: 450.0,
        grandTotal: 450.0,
        paymentStatus: 'SETTLED',
        createdAt: now,
      );

      await controller.dispatchOrderPrinting(order: fakeOrder, isCashPaid: true);

      await tester.pumpWidget(createTestApp(
        ReprintTrayDialog(
          controller: controller,
          currentStaff: testStaff,
          orderController: orderController,
          authService: authService,
        ),
      ));
      await tester.pumpAndSettle();

      final voidBtn = find.byKey(ValueKey('void_job_${controller.recentJobs.first.id}'));
      expect(voidBtn, findsOneWidget);

      await tester.tap(voidBtn);
      await tester.pumpAndSettle();

      expect(find.byType(SupervisorVoidDialog), findsOneWidget);
      expect(find.text('Supervisor Void Authorization'), findsOneWidget);
    });
  });
}
