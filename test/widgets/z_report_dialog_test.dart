import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/shifts/z_report.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/widgets/shifts/z_report_dialog.dart';

void main() {
  group('ZReportDialog Widget Tests', () {
    late ZReport dummyZReport;

    setUp(() {
      dummyZReport = ZReport(
        businessDayId: 42,
        openedAt: DateTime(2026, 10, 15, 8, 0, 0),
        closedAt: DateTime(2026, 10, 15, 23, 30, 0),
        generatedAt: DateTime(2026, 10, 15, 23, 35, 0),
        openedByStaffName: 'Supervisor Alice',
        closedByStaffName: 'Supervisor Alice',
        totalShiftsCount: 2,
        shifts: [
          Shift(
            id: 1,
            businessDayId: 42,
            staffId: 2,
            staffName: 'Cashier Bob',
            openedAt: DateTime(2026, 10, 15, 8, 0, 0),
            closedAt: DateTime(2026, 10, 15, 16, 0, 0),
            openingFloat: 5000.0,
            countedCash: 7500.0,
            expectedCash: 7500.0,
            discrepancy: 0.0,
            discrepancyStatus: DiscrepancyStatus.clean,
            status: ShiftStatus.closed,
          ),
          Shift(
            id: 2,
            businessDayId: 42,
            staffId: 3,
            staffName: 'Cashier Charlie',
            openedAt: DateTime(2026, 10, 15, 16, 0, 0),
            closedAt: DateTime(2026, 10, 15, 23, 30, 0),
            openingFloat: 4000.0,
            countedCash: 6850.0,
            expectedCash: 6900.0,
            discrepancy: -50.0,
            discrepancyStatus: DiscrepancyStatus.flagged,
            status: ShiftStatus.closed,
          ),
        ],
        grossSales: 15400.0,
        netSales: 14800.0,
        totalTax: 0.0,
        totalDiscounts: 600.0,
        cashSales: 9400.0,
        cardSales: 3400.0,
        raastSales: 2000.0,
        totalOpeningFloat: 9000.0,
        totalPayIn: 500.0,
        totalPayOut: 200.0,
        totalExpectedDrawerCash: 18700.0,
        totalCountedCash: 18650.0,
        netCashVariance: -50.0,
        totalOrdersCount: 28,
        totalVoidCount: 2,
        totalVoidAmount: 1100.0,
        totalWastageCount: 3,
        totalWastageCost: 450.0,
        totalMandiPurchasesCost: 6500.0,
        totalVendorDeliveriesCount: 2,
        totalVendorSettlementsAmount: 4000.0,
      );
    });

    testWidgets('renders all summary metrics, tender breakdown, and variance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZReportDialog(
              report: dummyZReport,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Day #42'), findsWidgets);
      expect(find.textContaining('Supervisor Alice'), findsWidgets);
      expect(find.text('Net Sales'), findsWidgets);
      expect(find.textContaining('14,800.00'), findsWidgets);

      // Tender breakdowns
      expect(find.textContaining('Cash'), findsWidgets);
      expect(find.textContaining('9,400.00'), findsWidgets);
      expect(find.textContaining('Card'), findsWidgets);
      expect(find.textContaining('3,400.00'), findsWidgets);
      expect(find.textContaining('Raast'), findsWidgets);
      expect(find.textContaining('2,000.00'), findsWidgets);

      // Net variance
      expect(find.textContaining('-50.00'), findsWidgets);

      // Buttons
      expect(find.byKey(const ValueKey('export_excel_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('print_z_report_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('finalize_day_button')), findsOneWidget);
    });

    testWidgets('triggers export excel callback when export button tapped', (tester) async {
      bool excelExported = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZReportDialog(
              report: dummyZReport,
              onExportExcel: () async {
                excelExported = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('export_excel_button')));
      await tester.pumpAndSettle();

      expect(excelExported, isTrue);
    });

    testWidgets('triggers finalize day callback when lock button tapped', (tester) async {
      bool finalized = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZReportDialog(
              report: dummyZReport,
              onFinalizeBusinessDay: () async {
                finalized = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('finalize_day_button')));
      await tester.pumpAndSettle();

      expect(finalized, isTrue);
    });
  });
}
