import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/z_report.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/app_shell.dart';
import 'package:resturant_sys/widgets/supervisor/supervisor_portal_workspace.dart';

class _StockController extends OrderAndCheckoutController {
  _StockController(Database database) : super(database: database);
  int requests = 0;
  bool fail = false;
  Completer<List<LowStockWarning>>? pending;
  List<LowStockWarning> alerts = const [LowStockWarning(ingredientId: 1,
      ingredientName: 'burger bun', currentStock: -5, threshold: 0, storageUnit: 'count')];

  @override
  Future<List<LowStockWarning>> getManagerStockAlerts() async {
    requests++;
    if (fail) throw StateError('Storage unavailable');
    if (pending != null) return pending!.future;
    return alerts;
  }
}

Future<_StockController> _pumpManager(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = (await tester.runAsync(() => databaseFactoryFfi.openDatabase(inMemoryDatabasePath)))!;
  addTearDown(() => tester.runAsync(db.close));
  final orders = _StockController(db);
  final session = SessionState()..login(const Staff(id: 1, name: 'Manager',
      departmentId: 1, pinHash: 'unused', role: StaffRole.manager, isActive: true));
  addTearDown(session.dispose);
  await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme, home: AppShell(
    session: session, onAuthenticatePin: (_) async => null,
    child: SupervisorPortalWorkspace(orderController: orders,
      initialDepartments: const [], initialStaff: const [],
      initialCashierVoidEnabled: true,
      initialDiscrepancies: const [],
      initialZReport: ZReport(businessDayId: 1, openedAt: DateTime(2026),
          generatedAt: DateTime(2026), openedByStaffName: 'Manager', totalShiftsCount: 0),
    ),
  )));
  await tester.pumpAndSettle();
  return orders;
}

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('Feature Toggles scrolls to Update Threshold with stock banner at 150 percent scaling', (tester) async {
    await _pumpManager(tester);
    await tester.tap(find.byKey(const ValueKey('portal_tab_toggles')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Settings must scroll instead of overflowing the viewport.');
    await tester.drag(find.text('Operational Feature Toggles'), const Offset(0, -500));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('save_discrepancy_threshold_button'));
    expect(save.hitTestable(), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('discrepancy_threshold_input')), '250');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Discrepancy threshold updated to PKR 250.00'), findsOneWidget);
  });

  testWidgets('Refresh stock confirms unchanged counts and clears a replenished alert', (tester) async {
    final orders = await _pumpManager(tester);
    expect(find.textContaining('burger bun: -5.0 count'), findsOneWidget);
    await tester.tap(find.text('Refresh stock'));
    await tester.pumpAndSettle();
    expect(orders.requests, 2);
    expect(find.textContaining('Stock refreshed'), findsOneWidget);
    expect(find.textContaining('burger bun: -5.0 count'), findsOneWidget);
    orders.alerts = [];
    await tester.tap(find.text('Refresh stock'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manager_stock_alert')), findsNothing);
    expect(find.textContaining('No low-stock alerts remain'), findsOneWidget);
  });

  testWidgets('stock refresh disables repeated clicks and recovers from a read failure', (tester) async {
    final orders = await _pumpManager(tester);
    orders.pending = Completer<List<LowStockWarning>>();
    final refresh = find.byKey(const ValueKey('refresh_manager_stock'));
    await tester.tap(refresh);
    await tester.pump();
    expect(find.text('Refreshing...'), findsOneWidget);
    expect(tester.widget<TextButton>(refresh).onPressed, isNull);
    await tester.tap(refresh);
    expect(orders.requests, 2);
    orders.pending!.complete(orders.alerts);
    orders.pending = null;
    await tester.pumpAndSettle();
    orders.fail = true;
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh stock alerts'), findsOneWidget);
    expect(tester.widget<TextButton>(refresh).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('portal_tab_toggles')));
    await tester.pumpAndSettle();
    expect(find.text('Operational Feature Toggles'), findsOneWidget);
    orders.fail = false;
    orders.alerts = [];
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manager_stock_alert')), findsNothing);
  });
}
