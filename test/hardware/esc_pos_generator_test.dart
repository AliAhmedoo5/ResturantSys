import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/hardware/esc_pos_constants.dart';
import 'package:resturant_sys/core/hardware/esc_pos_generator.dart';
import 'package:resturant_sys/core/hardware/paper_width.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_item.dart';
import 'package:resturant_sys/core/orders/order_payment.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';

void main() {
  group('EscPosGenerator Hardware Byte Stream Tests', () {
    const generator = EscPosGenerator();

    late Order sampleOrder;

    setUp(() {
      final now = DateTime(2026, 10, 12, 14, 30, 0);

      final item1 = OrderItem(
        id: 101,
        orderId: 1,
        menuItemId: 10,
        name: 'Zinger Burger',
        quantity: 2,
        unitPrice: 550.0,
        totalPrice: 1100.0,
        modifiersJson: jsonEncode([
          {'name': 'Extra Cheese', 'price_delta': 60.0},
          {'name': 'No Mayo', 'price_delta': 0.0},
        ]),
        createdAt: now,
      );

      final item2 = OrderItem(
        id: 102,
        orderId: 1,
        dealId: 5,
        name: 'Family Deal 1',
        quantity: 1,
        unitPrice: 1500.0,
        totalPrice: 1500.0,
        dealChoicesJson: jsonEncode([
          {'menu_item_name': 'Spicy Burger', 'upgrade_price': 0.0},
          {'menu_item_name': 'Large Fries', 'upgrade_price': 50.0},
          {'menu_item_name': '1.5L Coke', 'upgrade_price': 0.0},
        ]),
        createdAt: now,
      );

      sampleOrder = Order(
        id: 42,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 7,
        diningType: DiningType.takeaway,
        subtotal: 2600.0,
        discountAmount: 200.0,
        taxAmount: 360.0,
        grandTotal: 2400.0,
        paymentStatus: 'SETTLED',
        createdAt: now,
        items: [item1, item2],
        payments: const [
          OrderPayment(
            id: 1,
            orderId: 42,
            paymentMethod: PaymentMethod.cash,
            amountTendered: 3000.0,
            changeReturned: 600.0,
          ),
        ],
        cashierName: 'Ali Cashier',
      );
    });

    test('ESC/POS Command Constants match official thermal specifications', () {
      // Paper Auto-Cutter GS V 0
      expect(EscPosConstants.cutPaperFull, equals([0x1D, 0x56, 0x00]));

      // RJ11 Cash Drawer Kick Pulse ESC p 0 25 250
      expect(EscPosConstants.kickDrawerPulse, equals([0x1B, 0x70, 0x00, 25, 250]));

      // Printer Initialization ESC @
      expect(EscPosConstants.initPrinter, equals([0x1B, 0x40]));

      // Large bold character sizing GS ! 0x11
      expect(EscPosConstants.sizeLargeBold, equals([0x1D, 0x21, 0x11]));

      // Inverted alert banner GS B 1
      expect(EscPosConstants.inverseOn, equals([0x1D, 0x42, 0x01]));
      expect(EscPosConstants.inverseOff, equals([0x1D, 0x42, 0x00]));
    });

    test('generateCustomerTaxReceipt emits correct branding, items, taxes, and cut command', () {
      final bytes = generator.generateCustomerTaxReceipt(
        order: sampleOrder,
        paperWidth: PaperWidth.mm80,
        storeName: 'WARM GRILL POS',
      );

      // 1. Starts with Init Printer (ESC @)
      expect(bytes.sublist(0, 2), equals(EscPosConstants.initPrinter));

      // 2. Ends with Paper Cut (GS V 0)
      expect(bytes.sublist(bytes.length - 3), equals(EscPosConstants.cutPaperFull));

      final decoded = latin1.decode(bytes);

      // Branding
      expect(decoded, contains('WARM GRILL POS'));
      expect(decoded, contains('CUSTOMER RECEIPT'));

      // Order metadata
      expect(decoded, contains('Order #: #42'));
      expect(decoded, contains('Token: #07'));
      expect(decoded, contains('Dining: Takeaway'));
      expect(decoded, contains('Cashier: Ali Cashier'));

      // Line items & modifiers
      expect(decoded, contains('2x Zinger Burger'));
      expect(decoded, contains('Extra Cheese'));
      expect(decoded, contains('No Mayo'));
      expect(decoded, contains('Family Deal 1'));
      expect(decoded, contains('Spicy Burger'));
      expect(decoded, contains('Large Fries'));

      // Financials
      expect(decoded, contains('Subtotal:'));
      expect(decoded, contains('2,600.00'));
      expect(decoded, contains('Discount:'));
      expect(decoded, contains('-Rs 200.00'));
      expect(decoded, contains('Tax:'));
      expect(decoded, contains('360.00'));
      expect(decoded, contains('GRAND TOTAL:'));
      expect(decoded, contains('2,400.00'));

      // Tender breakdown
      expect(decoded, contains('Cash'));
      expect(decoded, contains('3,000.00'));
      expect(decoded, contains('Change Returned:'));
      expect(decoded, contains('600.00'));
    });

    test('generateCustomerTaxReceipt supports 58mm compact layout toggle', () {
      final bytes58 = generator.generateCustomerTaxReceipt(
        order: sampleOrder,
        paperWidth: PaperWidth.mm58,
      );

      final decoded58 = latin1.decode(bytes58);
      expect(decoded58, contains('Token: #07'));
      expect(decoded58, contains('GRAND TOTAL:'));
      // Divider length in 58mm should be 32 columns
      expect(decoded58, contains('--------------------------------'));
    });

    test('generateKitchenOrderTicket formats large bold token, dining type, and strictly ZERO prices', () {
      final bytes = generator.generateKitchenOrderTicket(
        order: sampleOrder,
        paperWidth: PaperWidth.mm80,
      );

      // Starts with Init Printer and ends with Cut
      expect(bytes.sublist(0, 2), equals(EscPosConstants.initPrinter));
      expect(bytes.sublist(bytes.length - 3), equals(EscPosConstants.cutPaperFull));

      // Contains GS ! 0x11 for Large Bold Token Header
      expect(
        bytes.contains(0x1D) && bytes.contains(0x21) && bytes.contains(0x11),
        isTrue,
      );

      final decoded = latin1.decode(bytes);

      // Kitchen header
      expect(decoded, contains('TOKEN #07'));
      expect(decoded, contains('*** TAKEAWAY ***'));
      expect(decoded, contains('Order #: #42'));
      expect(decoded, contains('Cashier: Ali Cashier'));

      // Items & cooking modifiers
      expect(decoded, contains('2x ZINGER BURGER'));
      expect(decoded, contains('[+] EXTRA CHEESE'));
      expect(decoded, contains('*** NO MAYO ***'));
      expect(decoded, contains('1x FAMILY DEAL 1'));
      expect(decoded, contains('- SPICY BURGER'));
      expect(decoded, contains('- LARGE FRIES'));

      // CRITICAL ACCEPTANCE CRITERIA: ZERO PRICES ON KOT
      // Must not contain price currency 'Rs', decimal pricing, or subtotal/tax/total amounts
      expect(decoded, isNot(contains('Rs')));
      expect(decoded, isNot(contains('2,400.00')));
      expect(decoded, isNot(contains('2,600.00')));
      expect(decoded, isNot(contains('550.00')));
      expect(decoded, isNot(contains('Subtotal')));
      expect(decoded, isNot(contains('GRAND TOTAL')));
      expect(decoded, isNot(contains('Discount')));
    });

    test('generateKitchenVoidSlip emits inverted banner, token, and supervisor cancellation reason', () {
      final bytes = generator.generateKitchenVoidSlip(
        order: sampleOrder,
        reason: 'Customer cancelled takeaway order',
        supervisorName: 'Manager Asad',
      );

      // Inverted banner codes present
      expect(
        bytes.contains(0x1D) && bytes.contains(0x42) && bytes.contains(0x01),
        isTrue,
      );
      // Ends with Auto-cutter
      expect(bytes.sublist(bytes.length - 3), equals(EscPosConstants.cutPaperFull));

      final decoded = latin1.decode(bytes);
      expect(decoded, contains('*** ORDER CANCELLED / VOID ***'));
      expect(decoded, contains('TOKEN #07'));
      expect(decoded, contains('Reason: Customer cancelled takeaway order'));
      expect(decoded, contains('Authorized By: Manager Asad'));
      expect(decoded, contains('HALT PREPARATION OF ITEMS:'));
      expect(decoded, contains('2x Zinger Burger'));
      expect(decoded, contains('1x Family Deal 1'));
      expect(decoded, contains('DO NOT PREPARE - DISCARD PREP'));
    });

    test('generateCashDrawerPulse emits exact RJ11 ESC p 0 25 250 command', () {
      final pulseBytes = generator.generateCashDrawerPulse();
      expect(pulseBytes, equals([0x1B, 0x70, 0x00, 25, 250]));
    });
  });
}
