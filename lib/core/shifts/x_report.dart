import 'package:intl/intl.dart';
import 'cash_movement.dart';
import 'shift.dart';

/// Summarizes an interim or finalized cashier shift for thermal X-Report printout and audit.
class XReport {
  XReport({
    required this.businessDayId,
    required this.shiftId,
    required this.staffId,
    required this.cashierName,
    required this.openedAt,
    required this.generatedAt,
    this.closedAt,
    required this.openingFloat,
    this.cashSales = 0.0,
    this.cardSales = 0.0,
    this.raastSales = 0.0,
    required this.totalPayIn,
    required this.totalPayOut,
    required this.expectedDrawerCash,
    this.countedCash,
    this.discrepancy,
    this.discrepancyStatus = DiscrepancyStatus.clean,
    this.cashMovements = const [],
    this.isInterim = true,
  });

  final int businessDayId;
  final int shiftId;
  final int staffId;
  final String cashierName;
  final DateTime openedAt;
  final DateTime generatedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final double cashSales;
  final double cardSales;
  final double raastSales;
  final double totalPayIn;
  final double totalPayOut;
  final double expectedDrawerCash;
  final double? countedCash;
  final double? discrepancy;
  final DiscrepancyStatus discrepancyStatus;
  final List<CashMovement> cashMovements;
  final bool isInterim;

  double get totalSales => cashSales + cardSales + raastSales;

  static final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// Formats the report as a clean 42-column monospace thermal slip suitable for ESC/POS printing.
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
    center('RESTURANT POS');
    center(isInterim ? '*** INTERIM X-REPORT ***' : '*** SHIFT CLOSING X-REPORT ***');
    buffer.writeln(divider);

    line('Business Day:', '#$businessDayId');
    line('Shift ID:', '#$shiftId');
    line('Cashier:', cashierName);
    line('Opened At:', _dateFormat.format(openedAt));
    if (closedAt != null) {
      line('Closed At:', _dateFormat.format(closedAt!));
    }
    line('Generated At:', _dateFormat.format(generatedAt));
    line('Mode:', isInterim ? 'Interim (Active)' : 'Closed Handover');
    buffer.writeln(subDivider);

    center('-- REVENUE & TENDERS --');
    line('Cash Sales:', 'Rs ${_currencyFormat.format(cashSales)}');
    line('Card Sales:', 'Rs ${_currencyFormat.format(cardSales)}');
    line('Raast Sales:', 'Rs ${_currencyFormat.format(raastSales)}');
    line('Total Sales:', 'Rs ${_currencyFormat.format(totalSales)}');
    buffer.writeln(subDivider);

    center('-- DRAWER CASH ACCOUNTING --');
    line('Opening Float:', 'Rs ${_currencyFormat.format(openingFloat)}');
    line('(+) Cash Sales:', 'Rs ${_currencyFormat.format(cashSales)}');
    line('(+) Total Pay-Ins:', 'Rs ${_currencyFormat.format(totalPayIn)}');
    line('(-) Total Pay-Outs:', 'Rs ${_currencyFormat.format(totalPayOut)}');
    buffer.writeln(subDivider);

    line('Expected Drawer:', 'Rs ${_currencyFormat.format(expectedDrawerCash)}');
    if (countedCash != null) {
      line('Counted Cash:', 'Rs ${_currencyFormat.format(countedCash!)}');
      line('Variance:', 'Rs ${_currencyFormat.format(discrepancy ?? 0.0)}');
      line('Discrepancy Status:', discrepancyStatus.dbValue);
    } else {
      line('Counted Cash:', 'N/A (Active Shift)');
      line('Variance:', 'N/A');
    }

    if (cashMovements.isNotEmpty) {
      buffer.writeln(subDivider);
      center('-- MID-SHIFT MOVEMENTS --');
      for (final m in cashMovements) {
        final prefix = m.isPayIn ? '[+IN]' : '[-OUT]';
        line('$prefix ${m.category}:', 'Rs ${_currencyFormat.format(m.amount)}');
      }
    }

    buffer.writeln(divider);
    center(isInterim ? 'INTERIM AUDIT TICKET ONLY' : 'OFFICIAL SHIFT HANDOVER RECORD');
    buffer.writeln(divider);

    return buffer.toString();
  }
}
