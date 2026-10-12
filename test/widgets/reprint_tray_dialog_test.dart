import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/print_job.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/reprint_tray_dialog.dart';

void main() {
  group('ReprintTrayDialog Widget Tests', () {
    late InMemoryHardwareAdapter adapter;
    late ReprintTrayController controller;

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
      expect(find.text('No tickets printed in this session.'), findsOneWidget);
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
  });
}
