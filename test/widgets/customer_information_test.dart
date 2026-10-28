import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  testWidgets('Customers report shows recorded customer identity and contact information', (tester) async {
    tester.view.physicalSize = const Size(1366, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final auth = (await tester.runAsync(() async {
      final db = await store.initialize();
      final people = await db.query('staff');
      final manager = people.firstWhere((r) => r['role'] != 'CASHIER');
      final cashier = people.firstWhere((r) => r['role'] == 'CASHIER');
      final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
      final customer = await db.insert('customers', {'name': 'Synthetic Ayesha', 'phone': '03001234567',
        'notes': 'Call at the gate', 'created_at': '2026-10-28 12:00:00'});
      final day = await db.insert('business_days', {'opened_at': '2026-10-28 12:00:00',
        'status': 'OPEN', 'opened_by_staff_id': manager['id']});
      final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': cashier['id'],
        'opened_at': '2026-10-28 12:00:00', 'opening_float': 0, 'status': 'OPEN'});
      await db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': cashier['id'],
        'customer_id': customer, 'customer_name': 'Synthetic Ayesha', 'customer_phone': '03001234567',
        'delivery_address_snapshot': 'Synthetic Street 10', 'delivery_area_name_snapshot': 'North',
        'token_number': 1, 'dining_type': 'DELIVERY', 'subtotal': 1050, 'grand_total': 1050,
        'payment_status': 'SETTLED', 'created_at': '2026-10-28 13:00:00'});
      return auth;
    }))!;
    addTearDown(() async { await tester.runAsync(store.close); });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
      service: AnalyticsService(database: auth.database, authService: auth), session: auth.session))));
    tester.widget<DropdownButtonFormField<AnalyticsFamily>>(
      find.byKey(const ValueKey('analytics_family'))).onChanged!(AnalyticsFamily.customers);
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 400; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('Synthetic Ayesha').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer_information')), findsOneWidget);
    expect(find.text('Synthetic Ayesha'), findsWidgets);
    expect(find.text('03001234567'), findsWidgets);
    expect(find.text('Call at the gate'), findsOneWidget);
    expect(find.text('Synthetic Street 10'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
