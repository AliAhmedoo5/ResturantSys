import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late PosDatabase store;
  late Database db;
  late AuthService auth;
  late AnalyticsService service;
  late int day, shift;
  final query = AnalyticsQuery(startDate: DateTime(2026, 10, 28), endDateExclusive: DateTime(2026, 10, 29));

  setUp(() async {
    store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath, seedDefaultStaff: false);
    db = await store.initialize();
    for (final entry in [(1, 'SUPERVISOR', 3), (2, 'CASHIER', 1)]) {
      await db.insert('staff', {'id': entry.$1, 'name': 'Synthetic staff ${entry.$1}',
        'department_id': entry.$3, 'role': entry.$2, 'pin_hash': 'fixture-${entry.$1}',
        'created_at': '2026-10-28 12:00:00', 'is_active': 1});
    }
    auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    service = AnalyticsService(database: db, authService: auth);
    day = await db.insert('business_days', {'opened_at': '2026-10-28 12:00:00', 'status': 'OPEN', 'opened_by_staff_id': 1});
    shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': 2,
      'opened_at': '2026-10-28 12:00:00', 'opening_float': 0, 'status': 'OPEN'});
  });
  tearDown(() => store.close());

  Future<int> person(String name, String phone, {String notes = ''}) => db.insert('customers', {
    'name': name, 'phone': phone, 'notes': notes, 'created_at': '2026-10-28 12:00:00'});
  Future<int> order(int token, String phone, {int? customerId, String name = 'Recorded name',
    String status = 'SETTLED', String dining = 'DELIVERY'}) => db.insert('orders', {
      'business_day_id': day, 'shift_id': shift, 'cashier_id': 2, 'token_number': token,
      'customer_id': customerId, 'customer_phone': phone, 'customer_name': name,
      'delivery_address_snapshot': 'Synthetic Street $token', 'delivery_area_name_snapshot': 'North',
      'dining_type': dining, 'payment_status': status, 'subtotal': 1050, 'grand_total': 1050,
      'created_at': '2026-10-28 13:00:00'});

  test('Full contact details and current profile notes remain outside analytics snapshots and exports', () async {
    final id = await person('Synthetic Ayesha', '03001234567', notes: 'Call at gate');
    await order(1, '+92 300 1234567', customerId: id, name: 'Older recorded name');
    final details = (await service.loadCustomerDetails(query)).single;
    expect(details.name, 'Synthetic Ayesha');
    expect(details.phone, '03001234567');
    expect(details.notes, 'Call at gate');
    expect(details.addresses, ['Synthetic Street 1']);
    expect(details.orders.single.recordedName, 'Older recorded name');
    expect(details.recordedValuePaisa, 105000);
    final snapshot = await service.load(query);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.customers);
    for (final raw in ['Synthetic Ayesha', '03001234567', 'Synthetic Street 1', 'Call at gate']) {
      expect(csv, isNot(contains(raw)));
      expect(snapshot.section(AnalyticsFamily.customers).rows.map((r) => r.cells).toString(), isNot(contains(raw)));
    }
  });

  test('Identical masked phone suffixes never combine separate customers or notes', () async {
    final first = await person('Synthetic Ayesha', '03001234567', notes: 'First person');
    final second = await person('Synthetic Bilal', '03111234567', notes: 'Second person');
    await order(1, '03001234567', customerId: first);
    await order(2, '03111234567', customerId: second);
    final result = await service.loadCustomerDetails(query);
    expect(result, hasLength(2));
    expect(result.first.phone, '03001234567');
    expect(result.first.notes, 'First person');
    expect(result.last.phone, '03111234567');
    expect(result.last.notes, 'Second person');
  });

  test('Merged and legacy customer links resolve current profile without rewriting order snapshots', () async {
    final old = await person('Previous profile', '03001234567');
    final current = await person('Current profile', '03111234567', notes: 'Current notes');
    final id = await order(1, '03001234567', name: 'Original order name');
    await db.insert('customer_order_links', {'order_id': id, 'customer_id': old});
    await db.update('customers', {'merged_into': current}, where: 'id=?', whereArgs: [old]);
    final before = (await db.query('orders', where: 'id=?', whereArgs: [id])).single;
    final result = (await service.loadCustomerDetails(query)).single;
    expect(result.name, 'Current profile');
    expect(result.phone, '03001234567');
    expect(result.primaryPhone, '03111234567');
    expect(result.notes, 'Current notes');
    expect(result.orders.single.recordedName, 'Original order name');
    expect((await db.query('orders', where: 'id=?', whereArgs: [id])).single, before);
  });

  test('Order-only legacy contacts retain recorded names, and unknown names are not invented', () async {
    await order(1, '03001234567', name: 'Legacy recorded customer');
    await order(2, '03111234567', name: '');
    final result = await service.loadCustomerDetails(query);
    expect(result.map((p) => p.name), containsAll(['Legacy recorded customer', 'Name not recorded']));
  });

  test('Customer history follows period, cashier, shift, Dining Type and payment filters', () async {
    final id = await person('Synthetic Ayesha', '03001234567');
    final delivery = await order(1, '03001234567', customerId: id);
    await order(2, '03001234567', customerId: id, dining: 'TAKEAWAY');
    await order(3, '03001234567', customerId: id, status: 'CANCELLED');
    await order(4, '', name: 'Guest');
    await db.insert('order_payments', {'order_id': delivery, 'payment_method': 'CASH',
      'amount_tendered': 1050, 'change_returned': 0});
    final result = await service.loadCustomerDetails(query.copyWith(cashierId: 2,
      shiftId: shift, diningType: 'DELIVERY', paymentMethod: 'CASH'));
    expect(result.single.orders.single.id, delivery);
    expect(await service.loadCustomerDetails(query.copyWith(cashierId: 9999)), isEmpty);
    expect(await service.loadCustomerDetails(query.copyWith(shiftId: 9999)), isEmpty);
    expect(await service.loadCustomerDetails(AnalyticsQuery(startDate: DateTime(2026, 10, 27),
      endDateExclusive: DateTime(2026, 10, 28))), isEmpty);
  });

  test('Contact reads reject cashier access and persisted Manager revocation', () async {
    auth.session.login(Staff.fromMap((await db.query('staff', where: 'id=2')).single));
    await expectLater(service.loadCustomerDetails(query), throwsStateError);
    auth.session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    await db.update('staff', {'login_enabled': 0}, where: 'id=1');
    await expectLater(service.loadCustomerDetails(query), throwsStateError);
  });

  test('An in-flight contact read cannot publish after the session locks', () async {
    await order(1, '03001234567');
    final pending = service.loadCustomerDetails(query);
    auth.session.lock();
    await expectLater(pending, throwsStateError);
  });
}
