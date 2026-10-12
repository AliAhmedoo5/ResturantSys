import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/paper_width.dart';
import 'package:resturant_sys/core/hardware/print_job.dart';
import 'package:resturant_sys/core/hardware/printer_topology.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_item.dart';
import 'package:resturant_sys/core/orders/order_payment.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';

void main() {
  group('ReprintTrayController & Decoupled Hardware Printing Tests', () {
    late InMemoryHardwareAdapter adapter;
    late ReprintTrayController controller;
    late Order cashOrder;
    late Order cardOrder;

    setUp(() {
      adapter = InMemoryHardwareAdapter();
      controller = ReprintTrayController(
        hardwareAdapter: adapter,
        topology: PrinterTopology.single,
        paperWidth: PaperWidth.mm80,
      );

      final now = DateTime(2026, 10, 12, 12, 0, 0);

      final item = OrderItem(
        id: 1,
        orderId: 10,
        name: 'Crispy Chicken Burger',
        quantity: 1,
        unitPrice: 650.0,
        totalPrice: 650.0,
        createdAt: now,
      );

      cashOrder = Order(
        id: 10,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 3,
        diningType: DiningType.dineIn,
        subtotal: 650.0,
        grandTotal: 650.0,
        paymentStatus: 'SETTLED',
        createdAt: now,
        items: [item],
        payments: const [
          OrderPayment(
            id: 1,
            orderId: 10,
            paymentMethod: PaymentMethod.cash,
            amountTendered: 1000.0,
            changeReturned: 350.0,
          ),
        ],
      );

      cardOrder = Order(
        id: 11,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 4,
        diningType: DiningType.takeaway,
        subtotal: 650.0,
        grandTotal: 650.0,
        paymentStatus: 'SETTLED',
        createdAt: now,
        items: [item],
        payments: const [
          OrderPayment(
            id: 2,
            orderId: 11,
            paymentMethod: PaymentMethod.card,
            amountTendered: 650.0,
            changeReturned: 0.0,
            referenceCode: 'TXN-987123',
          ),
        ],
      );
    });

    test('Single Printer Topology sends sequential dual cuts (Receipt + KOT) to counter printer', () async {
      controller.topology = PrinterTopology.single;

      await controller.dispatchOrderPrinting(
        order: cashOrder,
        isCashPaid: true,
      );

      // Both tickets routed to counter printer sequentially
      expect(adapter.counterPrintedBytes.length, equals(2));
      expect(adapter.kitchenPrintedBytes, isEmpty);

      // Drawer kicked on Cash payment
      expect(adapter.drawerKickCount, equals(1));

      // Recent jobs records both successful tickets
      expect(controller.recentJobs.length, equals(2));
      expect(controller.failedCount, equals(0));
    });

    test('Dual Printer Topology routes receipt to Counter and KOT to Kitchen printer', () async {
      controller.topology = PrinterTopology.dual;

      await controller.dispatchOrderPrinting(
        order: cashOrder,
        isCashPaid: true,
      );

      // Receipt routed to counter, KOT routed to kitchen
      expect(adapter.counterPrintedBytes.length, equals(1));
      expect(adapter.kitchenPrintedBytes.length, equals(1));
      expect(adapter.drawerKickCount, equals(1));
    });

    test('Cash payment strictly triggers drawer kick; Card payment leaves drawer closed', () async {
      // 1. Cash order
      await controller.dispatchOrderPrinting(order: cashOrder, isCashPaid: true);
      expect(adapter.drawerKickCount, equals(1));

      // 2. Card order
      await controller.dispatchOrderPrinting(order: cardOrder, isCashPaid: false);
      expect(adapter.drawerKickCount, equals(1)); // Unchanged!
    });

    test('Manual unpluggable cash drawer setting suppresses solenoid pulse without error', () async {
      controller.cashDrawerEnabled = false;

      await controller.dispatchOrderPrinting(order: cashOrder, isCashPaid: true);

      expect(adapter.drawerKickCount, equals(0));
      expect(adapter.counterPrintedBytes.length, equals(2));
    });

    test('Hardware printer failures decouple from checkout and enqueue to Reprint Tray with 1-tap retry', () async {
      // Simulate counter printer failure (e.g. paper roll finished)
      adapter.shouldFailCounterPrint = true;

      // Must NOT throw exception to caller
      await controller.dispatchOrderPrinting(order: cashOrder, isCashPaid: true);

      // Print jobs enqueued into failedJobs
      expect(controller.hasFailures, isTrue);
      expect(controller.failedCount, equals(2)); // Both receipt & KOT failed
      expect(controller.failedJobs.first.type, equals(PrintJobType.customerReceipt));
      expect(controller.failedJobs.first.isFailed, isTrue);

      // Simulate cashier replacing paper roll
      adapter.shouldFailCounterPrint = false;

      // 1-tap retry of first failed job
      final retrySuccess = await controller.retryJob(controller.failedJobs.first.id);
      expect(retrySuccess, isTrue);
      expect(controller.failedCount, equals(1));

      // 1-tap retry all remaining
      final retriedCount = await controller.retryAllFailed();
      expect(retriedCount, equals(1));
      expect(controller.failedCount, equals(0));
      expect(controller.hasFailures, isFalse);
    });

    test('Supervisor manual drawer override sends kick pulse', () async {
      final overrideSuccess = await controller.triggerSupervisorDrawerOverride();

      expect(overrideSuccess, isTrue);
      expect(adapter.drawerKickCount, equals(1));
    });

    test('dispatchKitchenVoidSlip formats and emits void ticket to kitchen target', () async {
      controller.topology = PrinterTopology.dual;

      await controller.dispatchKitchenVoidSlip(
        order: cashOrder,
        reason: 'Burned food / remake required',
        supervisorName: 'Supervisor Tariq',
      );

      expect(adapter.kitchenPrintedBytes.length, equals(1));
      expect(controller.recentJobs.first.type, equals(PrintJobType.kitchenVoidSlip));
    });
  });
}
