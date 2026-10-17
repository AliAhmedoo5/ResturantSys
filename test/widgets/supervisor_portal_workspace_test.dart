import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/department.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_item.dart';
import 'package:resturant_sys/core/orders/token_queue_controller.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/shifts/z_report.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/pin_numpad.dart';
import 'package:resturant_sys/widgets/supervisor/supervisor_portal_workspace.dart';

void main() {
  group('SupervisorPortalWorkspace Widget Tests', () {
    final testDepartments = [
      Department(id: 1, name: 'Front Counter', createdAt: DateTime(2026, 1, 1)),
      Department(id: 2, name: 'Kitchen', createdAt: DateTime(2026, 1, 1)),
      Department(id: 3, name: 'Management', createdAt: DateTime(2026, 1, 1)),
    ];

    final testStaffList = [
      const Staff(
        id: 1,
        name: 'Supervisor',
        departmentId: 3,
        departmentName: 'Management',
        pinHash: '1234',
        role: StaffRole.supervisor,
        isActive: true,
      ),
      const Staff(
        id: 2,
        name: 'Counter Cashier',
        departmentId: 1,
        departmentName: 'Front Counter',
        pinHash: '1111',
        role: StaffRole.cashier,
        isActive: true,
      ),
      const Staff(
        id: 3,
        name: 'Kitchen Cook',
        departmentId: 2,
        departmentName: 'Kitchen',
        pinHash: '2222',
        role: StaffRole.kitchen,
        isActive: true,
      ),
    ];

    final testOrder = Order(
      id: 101,
      businessDayId: 1,
      shiftId: 1,
      cashierId: 1,
      cashierName: 'Supervisor',
      tokenNumber: 1,
      diningType: DiningType.dineIn,
      subtotal: 500.0,
      discountAmount: 0.0,
      taxAmount: 0.0,
      grandTotal: 500.0,
      paymentStatus: 'SETTLED',
      createdAt: DateTime(2026, 1, 1, 12, 0),
      tokenStatus: TokenStatus.preparing,
      items: [
        OrderItem(
          id: 1,
          orderId: 101,
          menuItemId: 1,
          name: 'Zinger Burger',
          quantity: 1,
          unitPrice: 500.0,
          totalPrice: 500.0,
          createdAt: DateTime(2026, 1, 1, 12, 0),
        ),
      ],
    );

    final testDiscrepancyShift = Shift(
      id: 10,
      businessDayId: 1,
      staffId: 2,
      staffName: 'Counter Cashier',
      openedAt: DateTime(2026, 1, 1, 9, 0),
      closedAt: DateTime(2026, 1, 1, 17, 0),
      openingFloat: 5000.0,
      countedCash: 4500.0,
      expectedCash: 5000.0,
      discrepancy: -500.0,
      discrepancyStatus: DiscrepancyStatus.flagged,
      status: ShiftStatus.closed,
    );

    Widget createTestApp({
      List<Department>? initialDepartments,
      List<Staff>? initialStaff,
      bool? initialTokenTrayEnabled,
      bool? initialCashierVoidEnabled,
      List<Shift>? initialDiscrepancies,
      ZReport? initialZReport,
      Future<void> Function()? onFinalizeBusinessDay,
      TokenQueueController? tokenQueueController,
      ShiftAndCashController? shiftController,
    }) {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(
          body: SupervisorPortalWorkspace(
            currentStaff: testStaffList.first,
            shiftController: shiftController,
            initialDepartments: initialDepartments ?? List.of(testDepartments),
            initialStaff: initialStaff ?? List.of(testStaffList),
            initialTokenTrayEnabled: initialTokenTrayEnabled ?? true,
            initialCashierVoidEnabled: initialCashierVoidEnabled ?? true,
            initialDiscrepancies: initialDiscrepancies,
            initialZReport: initialZReport,
            onFinalizeBusinessDay: onFinalizeBusinessDay,
            tokenQueueController: tokenQueueController,
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

      // Verify portal tab navigation buttons
      expect(find.byKey(const ValueKey('portal_tab_staff')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_toggles')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_discrepancies')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_reports')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_tokenQueue')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal_tab_kitchenStation')), findsOneWidget);

      // Verify default Staff & Departments tab content
      expect(find.text('Staff & Departments'), findsOneWidget);
      expect(find.textContaining('Departments ('), findsOneWidget);
      expect(find.textContaining('Staff Directory'), findsOneWidget);
      expect(find.text('Supervisor'), findsWidgets);
      expect(find.text('Counter Cashier'), findsOneWidget);
      expect(find.text('Kitchen Cook'), findsWidgets);

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

      final tokenTrayFinder = find.byKey(const ValueKey('toggle_token_tray_switch'));
      final voidFinder = find.byKey(const ValueKey('toggle_cashier_void_switch'));

      expect(tokenTrayFinder, findsOneWidget);
      expect(voidFinder, findsOneWidget);

      // Verify initial states
      expect(tester.widget<SwitchListTile>(tokenTrayFinder).value, isTrue);
      expect(tester.widget<SwitchListTile>(voidFinder).value, isTrue);

      // Toggle Token Tray Off
      await tester.tap(tokenTrayFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tokenTrayFinder).value, isFalse);

      // Toggle Cashier Void Off
      await tester.tap(voidFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(voidFinder).value, isFalse);

      // Toggle Token Tray back On
      await tester.tap(tokenTrayFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tokenTrayFinder).value, isTrue);
    });

    testWidgets('discrepancy audit review displays flagged shift and allows resolution', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(
        initialDiscrepancies: [testDiscrepancyShift],
      ));
      await tester.pumpAndSettle();

      // Switch to Discrepancy Review tab
      await tester.tap(find.byKey(const ValueKey('portal_tab_discrepancies')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Discrepancy Audit Review'), findsOneWidget);
      expect(find.text('FLAGGED'), findsOneWidget);
      expect(find.textContaining('500.00'), findsOneWidget);

      // Tap Resolve
      final resolveBtn = find.byKey(const ValueKey('resolve_discrepancy_10'));
      expect(resolveBtn, findsOneWidget);
      await tester.tap(resolveBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Resolve Shift #10 Discrepancy'), findsOneWidget);

      // Submit resolution notes
      await tester.enterText(find.byType(TextField), 'Audited: short drawer verified by supervisor');
      await tester.tap(find.byKey(const ValueKey('submit_resolution_button')));
      await tester.pumpAndSettle();

      expect(find.text('RESOLVED'), findsOneWidget);
      expect(find.textContaining('Audited: short drawer'), findsOneWidget);
    });

    testWidgets('token queue tray shows active tokens with 1-tap progression', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tokenController = TokenQueueController(initialOrders: [testOrder]);

      await tester.pumpWidget(createTestApp(tokenQueueController: tokenController));
      await tester.pumpAndSettle();

      // Switch to Token Queue Tray
      await tester.tap(find.byKey(const ValueKey('portal_tab_tokenQueue')));
      await tester.pumpAndSettle();

      expect(find.text('#01'), findsOneWidget);
      expect(find.text('PREPARING'), findsOneWidget);

      // 1-Tap Advance: Preparing -> Ready
      final advanceBtn = find.byKey(const ValueKey('advance_token_101'));
      expect(advanceBtn, findsOneWidget);
      await tester.tap(advanceBtn);
      await tester.pumpAndSettle();

      expect(find.text('READY ON PASS'), findsOneWidget);

      // 1-Tap Advance: Ready -> Delivered
      await tester.tap(advanceBtn);
      await tester.pumpAndSettle();

      // Token is now Delivered, so active count is 0
      expect(find.text('Active (0)'), findsOneWidget);
    });

    testWidgets('kitchen station PIN authentication and mark ready on pass', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tokenController = TokenQueueController(initialOrders: [testOrder]);

      await tester.pumpWidget(createTestApp(tokenQueueController: tokenController));
      await tester.pumpAndSettle();

      // Switch to Kitchen Station tab
      await tester.tap(find.byKey(const ValueKey('portal_tab_kitchenStation')));
      await tester.pumpAndSettle();

      expect(find.text('Kitchen Token Station'), findsOneWidget);
      expect(find.textContaining('Enter Kitchen Cook 4-Digit PIN'), findsOneWidget);

      // Enter Cook PIN 2222 on PinNumpad
      final twoButton = find.descendant(
        of: find.byType(PinNumpad),
        matching: find.text('2'),
      );
      expect(twoButton, findsOneWidget);

      await tester.tap(twoButton);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(twoButton);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(twoButton);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(twoButton);
      await tester.pumpAndSettle();

      // Station unlocked
      expect(find.text('Kitchen Token Station (The Pass)'), findsOneWidget);
      expect(find.textContaining('Unlocked by Kitchen Cook'), findsOneWidget);
      expect(find.text('#01'), findsOneWidget);

      // 1-Tap Mark Ready
      final markReadyBtn = find.byKey(const ValueKey('kitchen_mark_ready_101'));
      expect(markReadyBtn, findsOneWidget);
      await tester.tap(markReadyBtn);
      await tester.pumpAndSettle();

      // Pass is now clear
      expect(find.text('All orders plated! The pass is clear.'), findsOneWidget);
      expect(tokenController.readyTokens.length, 1);
    });

    testWidgets('reports and backups tab opens Z-Report dialog with wired day finalization', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testZReport = ZReport(
        businessDayId: 1,
        openedAt: DateTime(2026, 1, 1, 8, 0),
        closedAt: DateTime(2026, 1, 1, 23, 0),
        generatedAt: DateTime(2026, 1, 1, 23, 5),
        openedByStaffName: 'Supervisor',
        closedByStaffName: 'Supervisor',
        totalShiftsCount: 1,
        shifts: [testDiscrepancyShift],
        grossSales: 15000.0,
        netSales: 15000.0,
        totalTax: 0.0,
        totalDiscounts: 0.0,
        cashSales: 10000.0,
        cardSales: 5000.0,
        raastSales: 0.0,
        totalOpeningFloat: 5000.0,
        totalPayIn: 0.0,
        totalPayOut: 0.0,
        totalExpectedDrawerCash: 15000.0,
        totalCountedCash: 14500.0,
        netCashVariance: -500.0,
        totalOrdersCount: 20,
        totalVoidCount: 0,
        totalVoidAmount: 0.0,
        totalWastageCount: 0,
        totalWastageCost: 0.0,
        totalMandiPurchasesCost: 0.0,
        totalVendorDeliveriesCount: 0,
        totalVendorSettlementsAmount: 0.0,
      );

      bool finalizedCalled = false;

      await tester.pumpWidget(createTestApp(
        initialZReport: testZReport,
        onFinalizeBusinessDay: () async {
          finalizedCalled = true;
        },
      ));
      await tester.pumpAndSettle();

      // Switch to Reports & Backups tab
      await tester.tap(find.byKey(const ValueKey('portal_tab_reports')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Active Business Day #1'), findsOneWidget);
      expect(find.textContaining('1 Shifts Finalized'), findsOneWidget);

      final viewZReportBtn = find.byKey(const ValueKey('portal_view_z_report_btn'));
      expect(viewZReportBtn, findsOneWidget);

      // Verify touch target height is at least 48px
      final btnSize = tester.getSize(viewZReportBtn);
      expect(btnSize.height, greaterThanOrEqualTo(48.0));

      // Open full Z-Report
      await tester.tap(viewZReportBtn);
      await tester.pumpAndSettle();

      expect(find.text('Master End-of-Day Z-Report'), findsOneWidget);
      final finalizeBtn = find.byKey(const ValueKey('finalize_day_button'));
      expect(finalizeBtn, findsOneWidget);

      // Tap Finalize button -> Confirmation dialog appears
      await tester.tap(finalizeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Finalize Business Day'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel_finalize_dialog_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm_finalize_dialog_btn')), findsOneWidget);

      // Confirm
      await tester.tap(find.byKey(const ValueKey('confirm_finalize_dialog_btn')));
      await tester.pumpAndSettle();

      expect(finalizedCalled, isTrue);

      // Day finalized and closed; Active Business Day #1 card is reset
      expect(find.textContaining('Active Business Day #1'), findsNothing);
    });
  });
}
