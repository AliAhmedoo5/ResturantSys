import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/widgets/app_shell.dart';

void main() {
  testWidgets('Manager can open Dashboard directly from the main sidebar', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionState();
    session.login(const Staff(id: 1, name: 'Manager', pinHash: 'fixture',
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
    session.login(const Staff(id: 2, name: 'Cashier', pinHash: 'fixture',
      role: StaffRole.cashier, isActive: true));
    await tester.pumpAndSettle();
    expect(dashboard, findsNothing);
  });
}
