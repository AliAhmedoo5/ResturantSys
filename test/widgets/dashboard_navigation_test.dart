import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/app_shell.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  testWidgets('Manager can open Dashboard directly from the main sidebar', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionState();
    session.login(const Staff(id: 1, departmentId: 1, name: 'Manager', pinHash: 'fixture',
      role: StaffRole.manager, isActive: true));
    await tester.pumpWidget(MaterialApp(home: AppShell(
      session: session, onAuthenticatePin: (_) async => null,
    )));
    await tester.pumpAndSettle();
    final dashboard = find.byKey(const ValueKey('workspace_tab_dashboard'));
    expect(dashboard, findsOneWidget);
    await tester.tap(dashboard);
    await tester.pumpAndSettle();
    expect(find.text('Analytics unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    session.lock();
    await tester.pumpAndSettle();
    session.login(const Staff(id: 2, departmentId: 1, name: 'Cashier', pinHash: 'fixture',
      role: StaffRole.cashier, isActive: true));
    await tester.pumpAndSettle();
    expect(dashboard, findsNothing);
  });

  testWidgets('Sidebar Dashboard loads the authorized database snapshot and exports', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final auth = (await tester.runAsync(() async {
      final db = await store.initialize();
      final people = await db.query('staff');
      final manager = people.firstWhere((row) => row['role'] == 'MANAGER');
      final cashier = people.firstWhere((row) => row['role'] == 'CASHIER');
      final service = AuthService(database: db)..session.login(Staff.fromMap(manager));
      await service.completeOnboarding();
      final now = DateTime.now().toUtc().add(const Duration(hours: 5));
      for (var i = 0; i < 7; i++) {
        final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i));
        final day = await db.insert('business_days', {'opened_at': date.toIso8601String(),
          'status': i == 6 ? 'OPEN' : 'CLOSED', 'opened_by_staff_id': manager['id']});
        final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': cashier['id'],
          'opened_at': date.toIso8601String(), 'opening_float': 1000, 'status': 'OPEN'});
        for (var token = 1; token <= 12 + i * 3; token++) {
          final value = 550 + i * 75.0;
          await db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': cashier['id'],
            'token_number': token, 'dining_type': 'TAKEAWAY', 'subtotal': value, 'grand_total': value,
            'payment_status': 'SETTLED', 'created_at': date.toIso8601String()});
        }
      }
      return service;
    }))!;
    addTearDown(() async { await tester.runAsync(store.close); });

    if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
      final font = FontLoader(WarmCounterTypography.fontFamily);
      font.addFont(Future.value(ByteData.sublistView(await File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf').readAsBytes())));
      await font.load();
      final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }

    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: RepaintBoundary(key: const ValueKey('dashboard_shell_preview'), child: AppShell(
        session: auth.session, authService: auth, onAuthenticatePin: (_) async => null))));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 400; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byKey(const ValueKey('workspace_tab_dashboard')).evaluate().isNotEmpty) break;
      }
    });
    await tester.tap(find.byKey(const ValueKey('workspace_tab_dashboard')));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 400; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('CSV (this report)').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Business intelligence'), findsOneWidget);
    expect(find.text('CSV (this report)'), findsOneWidget);
    expect(find.text('Analytics unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('dashboard_shell_preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory('build/desktop-previews').create(recursive: true);
        await File('${directory.path}/dashboard-sidebar-synthetic-1366.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
