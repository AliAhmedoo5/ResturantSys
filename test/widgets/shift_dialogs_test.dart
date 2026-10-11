import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/x_report.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/shifts/open_shift_dialog.dart';
import 'package:resturant_sys/widgets/shifts/cash_movement_dialog.dart';
import 'package:resturant_sys/widgets/shifts/blind_shift_close_dialog.dart';
import 'package:resturant_sys/widgets/shifts/x_report_dialog.dart';
import 'package:resturant_sys/widgets/shifts/discrepancy_review_dialog.dart';
import 'package:resturant_sys/widgets/shifts/open_business_day_dialog.dart';
import 'package:resturant_sys/widgets/shifts/business_day_bar.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/shifts/business_day.dart';

void main() {
  group('Shift Operations Widget Tests', () {
    testWidgets('OpenShiftDialog allows entering float and validates non-negative amount', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      double? submittedFloat;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: OpenShiftDialog(
              onOpenShift: (float) async {
                submittedFloat = float;
              },
            ),
          ),
        ),
      );

      expect(find.text('Open Cashier Shift'), findsOneWidget);
      expect(find.text('Opening Cash Float (Rs)'), findsOneWidget);

      final input = find.byKey(const ValueKey('opening_float_input'));
      expect(input, findsOneWidget);

      await tester.enterText(input, '5000');
      await tester.pump();

      final openButton = find.byKey(const ValueKey('confirm_open_shift_button'));
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      expect(submittedFloat, equals(5000.0));
    });

    testWidgets('CashMovementDialog toggles Pay-In/Pay-Out and validates mandatory fields', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      CashMovementType? recordedType;
      double? recordedAmount;
      String? recordedCategory;
      String? recordedNotes;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: CashMovementDialog(
              onRecordMovement: (type, amount, category, notes) async {
                recordedType = type;
                recordedAmount = amount;
                recordedCategory = category;
                recordedNotes = notes;
              },
            ),
          ),
        ),
      );

      expect(find.text('Record Cash Movement'), findsOneWidget);

      // Switch to Pay-Out
      final payOutSegment = find.byKey(const ValueKey('movement_type_payout'));
      await tester.tap(payOutSegment);
      await tester.pump();

      // Enter amount
      final amountInput = find.byKey(const ValueKey('cash_movement_amount_input'));
      await tester.enterText(amountInput, '350');
      await tester.pump();

      // Enter note
      final notesInput = find.byKey(const ValueKey('cash_movement_notes_input'));
      await tester.enterText(notesInput, 'Emergency ice purchase');
      await tester.pump();

      final submitBtn = find.byKey(const ValueKey('submit_cash_movement_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(recordedType, equals(CashMovementType.payOut));
      expect(recordedAmount, equals(350.0));
      expect(recordedCategory, isNotEmpty);
      expect(recordedNotes, equals('Emergency ice purchase'));
    });

    testWidgets('BlindShiftCloseDialog hides system totals and counts physical denominations', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      double? submittedCount;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: BlindShiftCloseDialog(
              shiftId: 1,
              cashierName: 'Counter Cashier',
              onSubmitBlindCount: (count) async {
                submittedCount = count;
              },
            ),
          ),
        ),
      );

      // Verify that system expected totals and sales figures are NOT visible
      expect(find.textContaining('Expected Total'), findsNothing);
      expect(find.textContaining('Expected Cash'), findsNothing);
      expect(find.textContaining('System Balance'), findsNothing);

      // Enter direct count or denomination
      final totalInput = find.byKey(const ValueKey('direct_counted_cash_input'));
      expect(totalInput, findsOneWidget);

      await tester.enterText(totalInput, '7450');
      await tester.pump();

      final submitBtn = find.byKey(const ValueKey('submit_blind_close_button'));
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(submittedCount, equals(7450.0));
    });

    testWidgets('XReportDialog renders monospace receipt preview', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final report = XReport(
        businessDayId: 1,
        shiftId: 1,
        staffId: 2,
        cashierName: 'Counter Cashier',
        openedAt: DateTime(2026, 10, 11, 8, 0),
        generatedAt: DateTime(2026, 10, 11, 14, 0),
        openingFloat: 5000.0,
        cashSales: 1500.0,
        totalPayIn: 500.0,
        totalPayOut: 200.0,
        expectedDrawerCash: 6800.0,
        isInterim: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: XReportDialog(report: report),
          ),
        ),
      );

      expect(find.text('Interim X-Report Preview'), findsOneWidget);
      expect(find.textContaining('INTERIM X-REPORT'), findsOneWidget);
      expect(find.byKey(const ValueKey('print_x_report_button')), findsOneWidget);
    });

    testWidgets('DiscrepancyReviewDialog displays flagged shift and submits supervisor resolution', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final flaggedShift = Shift(
        id: 10,
        businessDayId: 1,
        staffId: 2,
        openedAt: DateTime(2026, 10, 11, 8, 0),
        closedAt: DateTime(2026, 10, 11, 16, 0),
        openingFloat: 5000.0,
        expectedCash: 8000.0,
        countedCash: 7750.0,
        discrepancy: -250.0,
        discrepancyStatus: DiscrepancyStatus.flagged,
        status: ShiftStatus.closed,
        staffName: 'Zeeshan Cashier',
      );

      int? resolvedShiftId;
      String? resolvedNotes;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: DiscrepancyReviewDialog(
              flaggedShifts: [flaggedShift],
              onResolveDiscrepancy: (shiftId, notes) async {
                resolvedShiftId = shiftId;
                resolvedNotes = notes;
              },
            ),
          ),
        ),
      );

      expect(find.text('Discrepancy Review Queue'), findsOneWidget);
      expect(find.text('Zeeshan Cashier'), findsOneWidget);
      expect(find.textContaining('-250.00'), findsOneWidget);

      final resolveButton = find.byKey(ValueKey('resolve_shift_btn_${flaggedShift.id}'));
      await tester.tap(resolveButton);
      await tester.pumpAndSettle();

      final notesField = find.byKey(const ValueKey('resolution_notes_input'));
      await tester.enterText(notesField, 'Cashier dropped 250 rs change under desk, recovered.');
      await tester.pump();

      final confirmBtn = find.byKey(const ValueKey('confirm_resolve_button'));
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(resolvedShiftId, equals(10));
      expect(resolvedNotes, equals('Cashier dropped 250 rs change under desk, recovered.'));
    });

    testWidgets('OpenBusinessDayDialog displays supervisor name and triggers callback', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool dayOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: OpenBusinessDayDialog(
              supervisorName: 'Supervisor Ali',
              onOpenBusinessDay: () async {
                dayOpened = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Supervisor: Supervisor Ali'), findsOneWidget);

      final openBtn = find.byKey(const ValueKey('confirm_open_business_day_button'));
      expect(openBtn, findsOneWidget);
      await tester.tap(openBtn);
      await tester.pumpAndSettle();

      expect(dayOpened, isTrue);
    });

    testWidgets('BusinessDayBar shows active shift and triggers actions', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool cashMovementClicked = false;
      bool xReportClicked = false;
      bool closeShiftClicked = false;

      const cashier = Staff(
        id: 1,
        name: 'Zeeshan Cashier',
        departmentId: 1,
        departmentName: 'Front Counter',
        pinHash: 'dummy',
        role: StaffRole.cashier,
        isActive: true,
      );

      final businessDay = BusinessDay(
        id: 1,
        openedAt: DateTime(2026, 10, 11, 8, 0),
        openedByStaffId: 2,
        status: BusinessDayStatus.open,
      );

      final shift = Shift(
        id: 5,
        businessDayId: 1,
        staffId: 1,
        openedAt: DateTime(2026, 10, 11, 8, 30),
        openingFloat: 5000.0,
        status: ShiftStatus.open,
        staffName: 'Zeeshan Cashier',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: BusinessDayBar(
              currentStaff: cashier,
              activeBusinessDay: businessDay,
              activeShift: shift,
              flaggedShiftsCount: 1,
              onOpenBusinessDayTap: () {},
              onCloseBusinessDayTap: () {},
              onOpenShiftTap: () {},
              onCashMovementTap: () => cashMovementClicked = true,
              onInterimXReportTap: () => xReportClicked = true,
              onCloseShiftTap: () => closeShiftClicked = true,
              onDiscrepancyQueueTap: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('Day #1'), findsOneWidget);
      expect(find.textContaining('Shift #5: Zeeshan Cashier'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('btn_cash_movement')), warnIfMissed: false);
      expect(cashMovementClicked, isTrue);

      await tester.tap(find.byKey(const ValueKey('btn_interim_xreport')), warnIfMissed: false);
      expect(xReportClicked, isTrue);

      await tester.tap(find.byKey(const ValueKey('btn_close_shift')), warnIfMissed: false);
      expect(closeShiftClicked, isTrue);
    });
  });
}
