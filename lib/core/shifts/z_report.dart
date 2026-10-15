import 'package:intl/intl.dart';
import 'shift.dart';

/// Summarizes an overarching Business Day across all cashier shifts, payment tenders,
/// voids, inventory wastage, and cash drawer reconciliations for End-of-Day Z-Report audit.
class ZReport {
  ZReport({
    required this.businessDayId,
    required this.openedAt,
    this.closedAt,
    required this.generatedAt,
    required this.openedByStaffName,
    this.closedByStaffName,
    required this.totalShiftsCount,
    this.shifts = const [],
    this.grossSales = 0.0,
    this.netSales = 0.0,
    this.totalTax = 0.0,
    this.totalDiscounts = 0.0,
    this.cashSales = 0.0,
    this.cardSales = 0.0,
    this.raastSales = 0.0,
    this.totalOpeningFloat = 0.0,
    this.totalPayIn = 0.0,
    this.totalPayOut = 0.0,
    this.totalExpectedDrawerCash = 0.0,
    this.totalCountedCash = 0.0,
    this.netCashVariance = 0.0,
    this.totalOrdersCount = 0,
    this.totalVoidCount = 0,
    this.totalVoidAmount = 0.0,
    this.totalWastageCount = 0,
    this.totalWastageCost = 0.0,
    this.totalMandiPurchasesCost = 0.0,
    this.totalVendorDeliveriesCount = 0,
    this.totalVendorSettlementsAmount = 0.0,
  });

  final int businessDayId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final DateTime generatedAt;
  final String openedByStaffName;
  final String? closedByStaffName;

  final int totalShiftsCount;
  final List<Shift> shifts;

  final double grossSales;
  final double netSales;
  final double totalTax;
  final double totalDiscounts;

  final double cashSales;
  final double cardSales;
  final double raastSales;

  final double totalOpeningFloat;
  final double totalPayIn;
  final double totalPayOut;
  final double totalExpectedDrawerCash;
  final double totalCountedCash;
  final double netCashVariance;

  final int totalOrdersCount;
  final int totalVoidCount;
  final double totalVoidAmount;

  final int totalWastageCount;
  final double totalWastageCost;

  final double totalMandiPurchasesCost;
  final int totalVendorDeliveriesCount;
  final double totalVendorSettlementsAmount;

  double get totalTenderSales => cashSales + cardSales + raastSales;

  static final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// Formats the Z-Report as a clean 42-column monospace thermal slip suitable for ESC/POS printing.
  String toPrintableString() {
    final buffer = StringBuffer();
    const divider = '==========================================';
    const subDivider = '------------------------------------------';

    void line(String left, String right) {
      const totalWidth = 42;
      final spaceCount = totalWidth - left.length - right.length;
      if (spaceCount > 0) {
        buffer.writeln('$left${' ' * spaceCount}$right');
      } else {
        buffer.writeln('$left $right');
      }
    }

    void center(String text) {
      const totalWidth = 42;
      final leftPadding = ((totalWidth - text.length) / 2).floor();
      final pad = leftPadding > 0 ? ' ' * leftPadding : '';
      buffer.writeln('$pad$text');
    }

    buffer.writeln(divider);
    center('RESTURANT OPERATIONS POS');
    center('*** MASTER END-OF-DAY Z-REPORT ***');
    buffer.writeln(divider);

    line('Business Day:', '#$businessDayId');
    line('Opened At:', _dateFormat.format(openedAt));
    if (closedAt != null) {
      line('Closed At:', _dateFormat.format(closedAt!));
    }
    line('Generated At:', _dateFormat.format(generatedAt));
    line('Opened By:', openedByStaffName);
    if (closedByStaffName != null) {
      line('Closed By:', closedByStaffName!);
    }
    line('Total Shifts:', '$totalShiftsCount');
    line('Total Orders:', '$totalOrdersCount');
    buffer.writeln(subDivider);

    center('-- REVENUE SUMMARY --');
    line('Gross Sales:', 'Rs ${_currencyFormat.format(grossSales)}');
    line('Discounts:', 'Rs ${_currencyFormat.format(totalDiscounts)}');
    line('Taxes:', 'Rs ${_currencyFormat.format(totalTax)}');
    line('Net Sales:', 'Rs ${_currencyFormat.format(netSales)}');
    buffer.writeln(subDivider);

    center('-- PAYMENT TENDER BREAKDOWN --');
    line('Cash Sales:', 'Rs ${_currencyFormat.format(cashSales)}');
    line('Card Sales:', 'Rs ${_currencyFormat.format(cardSales)}');
    line('Raast Sales:', 'Rs ${_currencyFormat.format(raastSales)}');
    line('Total Tenders:', 'Rs ${_currencyFormat.format(totalTenderSales)}');
    buffer.writeln(subDivider);

    center('-- CASH DRAWER AUDIT & VARIANCE --');
    line('Opening Floats:', 'Rs ${_currencyFormat.format(totalOpeningFloat)}');
    line('(+) Cash Sales:', 'Rs ${_currencyFormat.format(cashSales)}');
    line('(+) Total Pay-Ins:', 'Rs ${_currencyFormat.format(totalPayIn)}');
    line('(-) Total Pay-Outs:', 'Rs ${_currencyFormat.format(totalPayOut)}');
    line('Expected Drawer:', 'Rs ${_currencyFormat.format(totalExpectedDrawerCash)}');
    line('Counted Drawer:', 'Rs ${_currencyFormat.format(totalCountedCash)}');
    line('Net Variance:', 'Rs ${_currencyFormat.format(netCashVariance)}');
    buffer.writeln(subDivider);

    center('-- AUDIT & OPERATIONS LOG --');
    line('Total Voids:', '$totalVoidCount (Rs ${_currencyFormat.format(totalVoidAmount)})');
    line('Kitchen Wastage:', '$totalWastageCount logs (Rs ${_currencyFormat.format(totalWastageCost)})');
    line('Mandi Purchases:', 'Rs ${_currencyFormat.format(totalMandiPurchasesCost)}');
    line('Khata Deliveries:', '$totalVendorDeliveriesCount');
    line('Khata Settled:', 'Rs ${_currencyFormat.format(totalVendorSettlementsAmount)}');

    if (shifts.isNotEmpty) {
      buffer.writeln(subDivider);
      center('-- SHIFTS BREAKDOWN --');
      for (final sh in shifts) {
        final shiftVariance = sh.discrepancy ?? 0.0;
        final cashier = sh.staffName ?? 'Staff #${sh.staffId}';
        line('Shift #${sh.id} ($cashier):', 'Var: Rs ${_currencyFormat.format(shiftVariance)}');
      }
    }

    buffer.writeln(divider);
    center('OFFICIAL BUSINESS DAY CLOSING AUDIT');
    center('ALL CASHIER SESSIONS ARCHIVED');
    buffer.writeln(divider);

    return buffer.toString();
  }
}
