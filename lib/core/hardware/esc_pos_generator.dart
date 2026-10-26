import 'dart:convert';
import 'package:intl/intl.dart';
import '../orders/order.dart';
import '../orders/payment_method.dart';
import '../shifts/z_report.dart';
import 'esc_pos_constants.dart';
import 'paper_width.dart';

/// Generates raw ESC/POS byte streams for thermal receipt printers and RJ11 cash drawers.
class EscPosGenerator {
  const EscPosGenerator();

  static final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// Generates the raw ESC/POS byte sequence for a Customer Tax Receipt.
  List<int> generateCustomerTaxReceipt({
    required Order order,
    PaperWidth paperWidth = PaperWidth.mm80,
    String storeName = 'RESTURANT POS',
    String storeTagline = 'Fast Food & Kitchen Operations',
    String storeAddress = 'Main Commercial Avenue',
    String storePhone = '+92 300 1234567',
    String? storeTaxId = 'STRN/NTN: 9876543-2',
  }) {
    final bytes = <int>[];
    final cols = paperWidth.columns;

    void addText(String text) {
      bytes.addAll(_encodeText(text));
    }

    void addLine(String text) {
      addText('$text\n');
    }

    void addDivider({String char = '-'}) {
      addLine(char * cols);
    }

    // 1. Initialize printer
    bytes.addAll(EscPosConstants.initPrinter);

    // 2. Header Branding (Centered)
    bytes.addAll(EscPosConstants.alignCenter);
    bytes.addAll(EscPosConstants.boldOn);
    bytes.addAll(EscPosConstants.sizeLargeBold);
    addLine(storeName);

    bytes.addAll(EscPosConstants.sizeNormal);
    bytes.addAll(EscPosConstants.boldOff);
    if (storeTagline.isNotEmpty) addLine(storeTagline);
    if (storeAddress.isNotEmpty) addLine(storeAddress);
    if (storePhone.isNotEmpty) addLine('Tel: $storePhone');
    if (storeTaxId != null && storeTaxId.isNotEmpty) addLine(storeTaxId);

    // 3. Receipt Title Banner
    addDivider(char: '=');
    bytes.addAll(EscPosConstants.boldOn);
    addLine('CUSTOMER RECEIPT');
    bytes.addAll(EscPosConstants.boldOff);
    addDivider(char: '=');

    // 4. Metadata (Left aligned)
    bytes.addAll(EscPosConstants.alignLeft);
    addLine(_formatTwoColumns('Order #: #${order.id}', 'Token: ${order.tokenDisplay}', cols));
    addLine('Date: ${_dateTimeFormat.format(order.createdAt)}');
    addLine(_formatTwoColumns(
      'Dining: ${order.diningType.displayName}',
      'Cashier: ${order.cashierName ?? 'Counter Cashier'}',
      cols,
    ));
    addDivider();

    // 5. Line Items Header
    bytes.addAll(EscPosConstants.boldOn);
    addLine(_formatLineItemHeader(cols));
    bytes.addAll(EscPosConstants.boldOff);
    addDivider();

    // 6. Line Items
    for (final item in order.items) {
      final linePrice = 'Rs ${_currencyFormat.format(item.totalPrice)}';
      final itemHeader = '${item.quantity}x ${item.name}';
      addLine(_formatTwoColumns(itemHeader, linePrice, cols));

      // Deal combo choices
      final dealChoices = item.decodedDealChoices;
      if (dealChoices.isNotEmpty) {
        for (final choice in dealChoices) {
          final choiceName = choice['menu_item_name'] ?? '';
          final upgrade = (choice['upgrade_price'] as num?)?.toDouble() ?? 0.0;
          final upgradeText = upgrade > 0 ? ' (+Rs ${_currencyFormat.format(upgrade)})' : '';
          addLine('   - $choiceName$upgradeText');
        }
      }

      // Modifiers
      final modifiers = item.decodedModifiers;
      if (modifiers.isNotEmpty) {
        for (final mod in modifiers) {
          final modName = mod['name'] ?? '';
          final delta = (mod['price_delta'] as num?)?.toDouble() ?? 0.0;
          final deltaText = delta > 0 ? ' (+Rs ${_currencyFormat.format(delta)})' : '';
          addLine('   + $modName$deltaText');
        }
      }
    }

    addDivider();

    // 7. Totals & Tax Breakdown
    addLine(_formatTwoColumns('Subtotal:', 'Rs ${_currencyFormat.format(order.subtotal)}', cols));

    if (order.discountAmount > 0) {
      addLine(_formatTwoColumns(
        'Discount:',
        '-Rs ${_currencyFormat.format(order.discountAmount)}',
        cols,
      ));
    }

    if (order.taxAmount > 0) {
      addLine(_formatTwoColumns(
        'Tax:',
        'Rs ${_currencyFormat.format(order.taxAmount)}',
        cols,
      ));
    }

    addDivider();
    bytes.addAll(EscPosConstants.boldOn);
    bytes.addAll(EscPosConstants.sizeDoubleHeight);
    addLine(_formatTwoColumns(
      'GRAND TOTAL:',
      'Rs ${_currencyFormat.format(order.grandTotal)}',
      cols,
    ));
    bytes.addAll(EscPosConstants.sizeNormal);
    bytes.addAll(EscPosConstants.boldOff);
    addDivider();

    // 8. Payment Tender Breakdown
    bytes.addAll(EscPosConstants.boldOn);
    addLine('PAYMENT TENDER:');
    bytes.addAll(EscPosConstants.boldOff);

    for (final payment in order.payments) {
      final tenderName = payment.paymentMethod.displayName;
      addLine(_formatTwoColumns(
        tenderName,
        'Rs ${_currencyFormat.format(payment.amountTendered)}',
        cols,
      ));

      if (payment.paymentMethod == PaymentMethod.cash && payment.changeReturned > 0) {
        addLine(_formatTwoColumns(
          'Change Returned:',
          'Rs ${_currencyFormat.format(payment.changeReturned)}',
          cols,
        ));
      }

      if (payment.referenceCode != null && payment.referenceCode!.isNotEmpty) {
        addLine('  Ref Code: ${payment.referenceCode}');
      }
    }

    addDivider();

    // 9. Footer (Centered)
    bytes.addAll(EscPosConstants.alignCenter);
    addLine('Thank you for dining with us!');
    addLine('Please keep this receipt for order pickup.');
    addLine('Powered by ResturantPOS');

    // 10. Feed & Full Cut
    bytes.addAll([EscPosConstants.lf, EscPosConstants.lf, EscPosConstants.lf]);
    bytes.addAll(EscPosConstants.cutPaperFull);

    return bytes;
  }

  /// Generates the raw RJ11 cash drawer kick pulse command bytes (`ESC p 0 25 250`).
  List<int> generateCashDrawerPulse() {
    return List<int>.from(EscPosConstants.kickDrawerPulse);
  }

  /// Generates the raw ESC/POS byte sequence for an End-of-Day Z-Report.
  List<int> generateZReportSlip({
    required ZReport report,
    PaperWidth paperWidth = PaperWidth.mm80,
  }) {
    final bytes = <int>[];
    bytes.addAll(EscPosConstants.initPrinter);
    bytes.addAll(EscPosConstants.alignLeft);
    bytes.addAll(_encodeText(report.toPrintableString()));
    bytes.addAll([EscPosConstants.lf, EscPosConstants.lf, EscPosConstants.lf]);
    bytes.addAll(EscPosConstants.cutPaperFull);
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Format Helper Methods
  // ---------------------------------------------------------------------------

  static List<int> _encodeText(String text) {
    final sanitized = text
        .replaceAll('•', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");

    final buffer = StringBuffer();
    for (final rune in sanitized.runes) {
      if (rune <= 255) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write('?');
      }
    }
    return latin1.encode(buffer.toString());
  }

  static String _formatLineItemHeader(int cols) {
    if (cols <= 32) {
      // 58mm compact layout
      return _formatTwoColumns('ITEM (QTY)', 'TOTAL', cols);
    }
    // 80mm standard layout
    return _formatTwoColumns('ITEM DESCRIPTION', 'TOTAL', cols);
  }

  static String _formatTwoColumns(String left, String right, int totalWidth) {
    final availableSpace = totalWidth - right.length;
    if (availableSpace <= 0) {
      return '$left $right';
    }

    if (left.length > availableSpace - 1) {
      final truncatedLeft = left.substring(0, availableSpace - 1);
      return '$truncatedLeft $right';
    }

    final spacesCount = totalWidth - left.length - right.length;
    final spaces = ' ' * (spacesCount > 0 ? spacesCount : 1);
    return '$left$spaces$right';
  }
}
