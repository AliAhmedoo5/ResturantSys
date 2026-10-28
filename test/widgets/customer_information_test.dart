import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/supervisor/customer_information_panel.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    if (Platform.environment['CAPTURE_DESKTOP'] != 'true') return;
    final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (!await file.exists()) return;
    final font = FontLoader(WarmCounterTypography.fontFamily)
      ..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
    await font.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
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
    auth.session.lock();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Ayesha', skipOffstage: false), findsNothing);
    expect(find.text('03001234567', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  CustomerReportProfile profile(String name, String phone, {int orders = 1}) => CustomerReportProfile(
    name: name, phone: phone, notes: 'Call at the gate', orders: [
      for (var id = 1; id <= orders; id++) CustomerReportOrder(id: id, token: id, totalPaisa: 105000,
        createdAt: '2026-10-28 13:00:00', diningType: 'DELIVERY', paymentStatus: 'SETTLED',
        recordedName: name, address: 'Synthetic Street 10', area: 'North', items: ['2 × Synthetic Burger']),
    ]);

  for (final width in [1366.0, 390.0]) {
    testWidgets('Customer information is searchable and readable at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(width < 600 ? 1.3 : 1)), child: child!),
        home: Scaffold(body: RepaintBoundary(key: const ValueKey('customer_contact_preview'),
          child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: CustomerInformationPanel(
            snapshotToken: 1, load: () async => [profile('Synthetic Ayesha', '03001234567'),
              profile('Synthetic Bilal', '03111234567')]))))));
      await tester.pumpAndSettle();
      expect(find.text('Customer information'), findsOneWidget);
      expect(find.text('03001234567'), findsWidgets);
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('customer_contact_preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory('build/desktop-previews').create(recursive: true);
          await File('${directory.path}/customer-information-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.enterText(find.byKey(const ValueKey('customer_information_search')), '+92 300 1234567');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 phone records'), findsOneWidget);
      expect(find.text('Synthetic Bilal'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('customer_information_search')), 'Bilal');
      await tester.pumpAndSettle();
      expect(find.text('03111234567'), findsWidgets);
      expect(find.text('Synthetic Ayesha'), findsNothing);
    });
  }

  testWidgets('Customer history pagination preserves all recorded orders', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CustomerInformationPanel(snapshotToken: 1,
        load: () async => [profile('Synthetic Ayesha', '03001234567', orders: 12)])))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Next customer orders'));
    await tester.tap(find.byTooltip('Next customer orders'));
    await tester.pumpAndSettle();
    expect(find.text('11–12 of 12 orders'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_history_order_11')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_history_order_1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customer reload hides old contacts and discards stale responses', (tester) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    final delayed = Completer<List<CustomerReportProfile>>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ValueListenableBuilder<int>(valueListenable: revision, builder: (context, value, _) =>
        CustomerInformationPanel(snapshotToken: value, load: () => value == 1 ? delayed.future :
          Future.value([profile(value == 0 ? 'Initial name' : 'Newest name', '03001234567')])))))));
    await tester.pumpAndSettle();
    expect(find.text('Initial name'), findsWidgets);
    revision.value = 1;
    await tester.pump();
    expect(find.text('Initial name', skipOffstage: false), findsNothing);
    revision.value = 2;
    await tester.pumpAndSettle();
    delayed.complete([profile('Stale name', '03111234567')]);
    await tester.pumpAndSettle();
    expect(find.text('Newest name'), findsWidgets);
    expect(find.text('Stale name', skipOffstage: false), findsNothing);
  });

  testWidgets('Failed customer information read can be retried', (tester) async {
    var fail = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CustomerInformationPanel(snapshotToken: 1, load: () async {
        if (fail) throw StateError('Synthetic failure');
        return [profile('Recovered customer', '03001234567')];
      })))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load customer information'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry customer information'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered customer'), findsWidgets);
  });
}
