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
import 'package:resturant_sys/core/finance/operations_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  for (final example in [(due:1250, partial:0, finalCash:1300, delta:50, method:PaymentMethod.cash), (due:1249, partial:0, finalCash:1200, delta:-49, method:PaymentMethod.cash), (due:2250, partial:1000, finalCash:1300, delta:50, method:PaymentMethod.cash), (due:49, partial:0, finalCash:0, delta:-49, method:PaymentMethod.cash), (due:1249, partial:0, finalCash:1249, delta:0, method:PaymentMethod.card)]) {
    test('final manual receipt settles ${example.due} paisa with retained delta ${example.delta}', () async {
      final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      final db = await store.initialize();
      addTearDown(store.close);
      final shifts = ShiftAndCashController(database: db);
      final day = await shifts.openBusinessDay(openedByStaffId: 1);
      final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
      final order = await db.insert('orders', {'business_day_id':day.id,'shift_id':shift.id,'cashier_id':2,'token_number':1,'dining_type':'TAKEAWAY','subtotal':example.due/100,'grand_total':example.due/100,'payment_status':'COLLECTION_DUE','created_at':DateTime.now().toUtc().toIso8601String()});
      final controller = OrderAndCheckoutController(database: db);
      if (example.partial > 0) await controller.recordCashierReceipt(orderId:order,shiftId:shift.id,cashierId:2,amountPaisa:example.partial,method:PaymentMethod.cash,commandId:'partial');
      Future<int> finish() => controller.recordCashierReceipt(orderId:order,shiftId:shift.id,cashierId:2,amountPaisa:example.finalCash,method:example.method,commandId:'final');
      expect(await finish(), await finish());
      final saved = await controller.getOrder(order);
      expect(saved.paymentStatus,'SETTLED');
      expect(saved.grandTotal,example.due/100);
      final auth = AuthService(database:db)..session.login(Staff.fromMap((await db.query('staff',where:'id=1')).single));
      final snapshot = await AnalyticsService(database:db,authService:auth).load(AnalyticsQuery(startDate:DateTime(2020),endDateExclusive:DateTime(2100),live:true));
      final event = snapshot.section(AnalyticsFamily.cash).rows.singleWhere((r)=>r.cells['event_key']=='receipt-final');
      expect(event.cells['amount_paisa'],example.finalCash);
      expect(event.cells['rounding_paisa'],example.delta);
      expect(event.cells['change_paisa'],0);
      final ledger = snapshot.section(AnalyticsFamily.audit).rows.where((r)=>r.sourceType=='rounding_variance_ledger').toList();
      expect(ledger.length,example.delta == 0 ? 0 : 1,reason:'Digital stays exact; retries must not duplicate the rounding ledger');
      expect(AnalyticsExportService().csv(snapshot,AnalyticsFamily.cash),contains('rounding paisa'));
    });
  }
  test('calendar event-only snapshot retains receiving context without broadening drawer scope', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1, openedAt: DateTime(2026,10,27,18));
    final shift = await shifts.openShift(staffId: 2, openingFloat: 1000, openedAt: DateTime(2026,10,27,18));
    final order = await db.insert('orders', {'business_day_id': day.id, 'shift_id': shift.id, 'cashier_id': 2, 'token_number': 1, 'dining_type': 'TAKEAWAY', 'subtotal': 200, 'grand_total': 200, 'payment_status': 'COLLECTION_DUE', 'created_at': '2026-10-27 18:15:00'});
    await OrderAndCheckoutController(database: db).recordCashierReceipt(orderId: order, shiftId: shift.id, cashierId: 2, amountPaisa: 10000, method: PaymentMethod.cash, commandId: 'old-order-new-receipt', actualAt: DateTime.parse('2026-10-28T10:30:00+05:00'));
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: 1, name: 'Utilities');
    await operations.postExpense(managerId: 1, categoryId: category, amountPaisa: 2000, description: 'Bank bill', source: FundingSource.bank, businessDayId: day.id, reason: 'Paid', requestKey: 'event-only-bank', actualAt: DateTime.parse('2026-10-28T11:00:00+05:00'));
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    final snapshot = await AnalyticsService(database: db, authService: auth).load(AnalyticsQuery(startDate: DateTime(2026,10,28,10), endDateExclusive: DateTime(2026,10,28,12), timeBasis: AnalyticsTimeBasis.calendarTime));
    expect(snapshot.businessDayIds, [day.id]);
    expect(snapshot.section(AnalyticsFamily.orders).rows.where((r) => r.sourceType == 'orders'), isEmpty);
    final receipt = snapshot.section(AnalyticsFamily.cash).rows.singleWhere((r) => r.sourceType == 'payment_events');
    expect(receipt.cells['shift_owner_id'], 2);
    expect(receipt.cells['shift_start_source'], '2026-10-27 18:00:00');
    expect(receipt.cells['business_day_start_source'], '2026-10-27 18:00:00');
    final finance = snapshot.section(AnalyticsFamily.expenses).rows.singleWhere((r) => r.cells['kind'] == 'Finance payment');
    expect(finance.cells['business_day_start_source'], '2026-10-27 18:00:00');
    expect(finance.cells['shift_id'], isNull);
    expect(snapshot.section(AnalyticsFamily.cash).metrics.singleWhere((m) => m.id == 'opening_float').value, 0);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.cash);
    expect(csv, contains('query_start_inclusive,2026-10-28T10:00:00.000+05:00'));
    expect(csv, contains('query_end_exclusive,2026-10-28T12:00:00.000+05:00'));
  });

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
    final selected = await AnalyticsService(database: db, authService: auth).load(snapshot.query.copyWith(shiftId: receiving, diningType: 'DELIVERY', paymentMethod: 'CARD'));
    final bridge = selected.section(AnalyticsFamily.cash);
    expect(bridge.metrics.singleWhere((m) => m.id == 'expected_drawer').value, 5000);
    expect(bridge.metrics.singleWhere((m) => m.id == 'cash_refunds').value, 5000);
    expect(bridge.rows.where((r) => r.cells['kind'] == 'Physical cash effect'), hasLength(2));
    expect(bridge.metrics.singleWhere((m) => m.id == 'variance').value, isNull);

    await expectLater(controller.recordCashierReceipt(orderId: order, shiftId: receiving, cashierId: 2, amountPaisa: 1000, method: PaymentMethod.cash, commandId: 'invalid-time', actualAt: now.subtract(const Duration(days: 1))), throwsStateError);
    expect((await controller.getOrderPayments(order)).length, 2, reason: 'Failed event validation must roll back its tender');
    await expectLater(controller.recordCashierRefund(orderId: order, shiftId: receiving, cashierId: 2, amountPaisa: 1000, method: PaymentMethod.cash, reason: 'Invalid historical entry', commandId: 'invalid-refund-time', actualAt: now.subtract(const Duration(days: 1))), throwsStateError);
    expect((await controller.getOrderPayments(order)).length, 2);
    expect((await shifts.getCashMovements(receiving)).length, 1, reason: 'Failed refund must roll back both its tender and linked PAY_OUT');
  });
}
