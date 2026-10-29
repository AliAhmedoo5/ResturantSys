import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('cashier receipt retries retain independent receiving attribution', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final now = DateTime.now().toUtc();
    final opened = now.subtract(const Duration(hours: 1)).toIso8601String();
    final day = await db.insert('business_days', {'opened_at': opened, 'status': 'OPEN', 'opened_by_staff_id': 1});
    final origin = await db.insert('shifts', {'business_day_id': day, 'staff_id': 2, 'opened_at': opened, 'status': 'CLOSED', 'opening_float': 0});
    final receiving = await db.insert('shifts', {'business_day_id': day, 'staff_id': 2, 'opened_at': opened, 'status': 'OPEN', 'opening_float': 0});
    final order = await db.insert('orders', {'business_day_id': day, 'shift_id': origin, 'cashier_id': 2, 'token_number': 1, 'dining_type': 'TAKEAWAY', 'subtotal': 200, 'grand_total': 200, 'payment_status': 'COLLECTION_DUE', 'created_at': opened});
    final controller = OrderAndCheckoutController(database: db);
    final actual = now.subtract(const Duration(minutes: 30));
    Future<int> collect() => controller.recordCashierReceipt(orderId: order, shiftId: receiving, cashierId: 2, amountPaisa: 10000, method: PaymentMethod.cash, commandId: 'receipt-1', actualAt: actual);
    expect(await collect(), await collect());
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    final snapshot = await AnalyticsService(database: db, authService: auth).load(AnalyticsQuery(startDate: now, endDateExclusive: now.add(const Duration(days: 1)), live: true));
    final row = snapshot.section(AnalyticsFamily.cash).rows.singleWhere((r) => r.sourceType == 'payment_events');
    expect(row.cells['amount_paisa'], 10000);
    expect(row.cells['originating_shift_id'], origin);
    expect(row.cells['receiving_shift_id'], receiving);
    expect(row.cells['actual_at_source'] ?? row.cells['actual_at'], actual.toIso8601String());
    expect(row.cells['recorded_at'], isNotNull);
    expect(DateTime.parse((row.cells['recorded_at_source'] ?? row.cells['recorded_at']) as String).isAfter(actual), isTrue);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.cash);
    expect(csv, contains('receiving shift id'));
    expect(csv, contains('originating shift id'));
    expect(csv, contains('receipt-receipt-1'));
    final localActual = actual.add(const Duration(hours: 5));
    for (final live in [false, true]) {
      final calendar = snapshot.query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime, live: live, startDate: localActual, endDateExclusive: localActual.add(const Duration(minutes: 1)));
      final included = await AnalyticsService(database: db, authService: auth).load(calendar);
      expect(included.section(AnalyticsFamily.cash).rows.where((r) => r.sourceType == 'payment_events').length, 1);
      final excluded = await AnalyticsService(database: db, authService: auth).load(calendar.copyWith(startDate: localActual.subtract(const Duration(minutes: 1)), endDateExclusive: localActual));
      expect(excluded.section(AnalyticsFamily.cash).rows.where((r) => r.sourceType == 'payment_events'), isEmpty, reason: 'Actual end boundary is exclusive, including in live mode');
    }
    expect((await controller.getOrderPayments(order)).length, 1);
    expect(snapshot.section(AnalyticsFamily.delivery).metrics.singleWhere((m) => m.id == 'collection_due').value, 10000);
    final shifts = ShiftAndCashController(database: db);
    expect(await shifts.calculateCashSales(origin), 0);
    expect(await shifts.calculateCashSales(receiving), 100);

    Future<RefundResult> refund() => controller.recordCashierRefund(orderId: order, shiftId: receiving, cashierId: 2, amountPaisa: 5000, method: PaymentMethod.cash, reason: 'Partial return', commandId: 'refund-1');
    final refunded = await refund();
    expect((await refund()).cashMovementId, refunded.cashMovementId);
    expect((await controller.getOrderPayments(order)).length, 2);
    final afterRefund = await AnalyticsService(database: db, authService: auth).load(snapshot.query);
    expect(afterRefund.section(AnalyticsFamily.cash).rows.where((r) => r.sourceType == 'payment_events').map((r) => r.cells['amount_paisa']), unorderedEquals([10000, -5000]));

    await expectLater(controller.recordCashierReceipt(orderId: order, shiftId: receiving, cashierId: 2, amountPaisa: 1000, method: PaymentMethod.cash, commandId: 'invalid-time', actualAt: now.subtract(const Duration(days: 1))), throwsStateError);
    expect((await controller.getOrderPayments(order)).length, 2, reason: 'Failed event validation must roll back its tender');
    await expectLater(controller.recordCashierRefund(orderId: order, shiftId: receiving, cashierId: 2, amountPaisa: 1000, method: PaymentMethod.cash, reason: 'Invalid historical entry', commandId: 'invalid-refund-time', actualAt: now.subtract(const Duration(days: 1))), throwsStateError);
    expect((await controller.getOrderPayments(order)).length, 2);
    expect((await shifts.getCashMovements(receiving)).length, 1, reason: 'Failed refund must roll back both its tender and linked PAY_OUT');
  });
}
