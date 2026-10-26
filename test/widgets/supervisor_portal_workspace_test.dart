import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/department.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/shifts/z_report.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';

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
        role: StaffRole.manager,
        isActive: true,
      ),
    ];

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
      bool? initialCashierVoidEnabled,
      List<Shift>? initialDiscrepancies,
      ZReport? initialZReport,
      Future<void> Function()? onFinalizeBusinessDay,
      ReprintTrayController? reprintTrayController,
      ShiftAndCashController? shiftController,
      double? initialDiscrepancyThreshold,
    }) {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(
          body: SupervisorPortalWorkspace(
            currentStaff: testStaffList.first,
            shiftController: shiftController,
            initialDepartments: initialDepartments ?? List.of(testDepartments),
            initialStaff: initialStaff ?? List.of(testStaffList),
            initialCashierVoidEnabled: initialCashierVoidEnabled ?? true,
            initialDiscrepancies: initialDiscrepancies,
            initialZReport: initialZReport,
            onFinalizeBusinessDay: onFinalizeBusinessDay,
            reprintTrayController: reprintTrayController,
            initialDiscrepancyThreshold: initialDiscrepancyThreshold,
          ),
        ),
      );
    }

    testWidgets('Dashboard reports missing dependencies and staff management remains accessible', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portal_tab_dashboard')));
      await tester.pumpAndSettle();
      expect(find.text('Analytics unavailable. A Manager session and database are required.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('portal_tab_staff')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('add_department_button')), findsOneWidget);
    });

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
      expect(find.byKey(const ValueKey('portal_tab_tokenQueue')), findsNothing);
      expect(find.byKey(const ValueKey('portal_tab_kitchenStation')), findsNothing);

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
      await tester.tap(find.byKey(const ValueKey('staff_role_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Front Counter Cashier').last);
      await tester.pumpAndSettle();
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
      expect(find.text('Cashier Void Requests'), findsOneWidget);

      final voidFinder = find.byKey(const ValueKey('toggle_cashier_void_switch'));

      expect(voidFinder, findsOneWidget);

      // Verify initial states
      expect(tester.widget<SwitchListTile>(voidFinder).value, isTrue);


      // Toggle Cashier Void Off
      await tester.tap(voidFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(voidFinder).value, isFalse);

    });

    testWidgets('allows manager to view and configure discrepancy threshold in operational settings', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Switch to Feature Toggles tab
      await tester.tap(find.byKey(const ValueKey('portal_tab_toggles')));
      await tester.pumpAndSettle();

      expect(find.text('Shift Cash Discrepancy Threshold (PKR)'), findsOneWidget);
      final thresholdInput = find.byKey(const ValueKey('discrepancy_threshold_input'));
      final saveBtn = find.byKey(const ValueKey('save_discrepancy_threshold_button'));
      expect(thresholdInput, findsOneWidget);
      expect(saveBtn, findsOneWidget);

      // Verify default threshold 100.00 via threshold input field
      final thresholdField = tester.widget<TextField>(thresholdInput);
      expect(thresholdField.controller?.text, equals('100.00'));

      // Update threshold to 250.00
      await tester.enterText(thresholdInput, '250.00');
      await tester.pump();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Discrepancy threshold updated to PKR 250.00'), findsOneWidget);

      // Verify Discrepancy Audit Review shows active threshold
      await tester.tap(find.byKey(const ValueKey('portal_tab_discrepancies')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Active Threshold: PKR 250.00'), findsOneWidget);
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
      expect(find.text('Net Drawer Discrepancy'), findsOneWidget);

      // Verify button hierarchy: portal_export_excel_btn is secondary OutlinedButton
      final exportExcelBtn = find.byKey(const ValueKey('portal_export_excel_btn'));
      expect(exportExcelBtn, findsOneWidget);
      expect(find.byType(OutlinedButton), findsWidgets);

      // Verify touch target for save_usb_path_btn
      final saveUsbBtn = find.byKey(const ValueKey('save_usb_path_btn'));
      expect(saveUsbBtn, findsOneWidget);
      expect(tester.getSize(saveUsbBtn).height, greaterThanOrEqualTo(48.0));

      final viewZReportBtn = find.byKey(const ValueKey('portal_view_z_report_btn'));
      expect(viewZReportBtn, findsOneWidget);

      // Verify touch target height is at least 48px
      final btnSize = tester.getSize(viewZReportBtn);
      expect(btnSize.height, greaterThanOrEqualTo(48.0));

      // Open full Z-Report
      await tester.tap(viewZReportBtn);
      await tester.pumpAndSettle();

      expect(find.text('Master End-of-Day Z-Report'), findsOneWidget);

      // Native print dispatch is covered by z_report_native_print_test.dart.

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
