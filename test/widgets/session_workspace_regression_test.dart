import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/app_header.dart';
import 'package:resturant_sys/widgets/app_shell.dart';
import 'package:resturant_sys/widgets/procurement/kitchen_wastage_workspace.dart';

void main() {
  for (final nextRole in StaffRole.values) {
    testWidgets('new ${nextRole.name} session resets manager wastage screen', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionState();
      addTearDown(session.dispose);
      const manager = Staff(id: 1, name: 'Manager', departmentId: 1,
          pinHash: 'unused', role: StaffRole.manager, isActive: true);
      final nextStaff = Staff(id: 2, name: 'Next user', departmentId: 1,
          pinHash: 'unused', role: nextRole, isActive: true);
      session.login(manager);
      await tester.pumpWidget(MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: AppShell(session: session, onAuthenticatePin: (_) async => nextStaff),
      ));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_wastage')));
      await tester.pumpAndSettle();
      expect(find.byType(KitchenWastageWorkspace), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lock_register_button')));
      await tester.pumpAndSettle();
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('unlock_pin_button')));
      await tester.pumpAndSettle();
      expect(session.currentStaff, nextStaff);
      expect(find.byType(KitchenWastageWorkspace), findsNothing);
      expect(tester.widget<AppHeader>(find.byType(AppHeader)).selectedWorkspace,
          AppWorkspaceTab.register);
    });
  }
}
