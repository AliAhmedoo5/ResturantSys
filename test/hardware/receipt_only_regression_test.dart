import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';

void main() {
  test('checkout prints one customer receipt and no kitchen ticket', () async {
    final adapter = InMemoryHardwareAdapter();
    final controller = ReprintTrayController(hardwareAdapter: adapter);
    addTearDown(controller.dispose);
    await controller.dispatchOrderPrinting(order: Order(id: 1, businessDayId: 1,
      shiftId: 1, cashierId: 2, tokenNumber: 1, diningType: DiningType.dineIn,
      subtotal: 333, grandTotal: 333, paymentStatus: 'SETTLED', createdAt: DateTime(2026)),
      isCashPaid: false);
    expect(adapter.counterPrintedBytes, hasLength(1), reason: 'KOT printing was discarded.');
    expect(controller.recentJobs, hasLength(1));
  });
}
