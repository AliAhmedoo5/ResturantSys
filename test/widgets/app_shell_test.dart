import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/app_header.dart';
import 'package:resturant_sys/widgets/app_shell.dart';
import 'package:resturant_sys/widgets/onboarding/onboarding_wizard.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AppHeader & AppShell Widget Tests', () {
    testWidgets('AppHeader displays Locked status when unauthenticated', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(64),
              child: AppHeader(
                activeStaff: null,
                onLock: null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('ResturantPOS'), findsOneWidget);
      expect(find.text('Register Locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('lock_register_button')), findsNothing);
    });

    testWidgets('AppHeader displays active user name and department with 1-tap lock button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool lockClicked = false;
      const staff = Staff(
        id: 1,
        name: 'Zeeshan Khan',
        departmentId: 1,
        departmentName: 'Front Counter',
        pinHash: 'hash',
        role: StaffRole.cashier,
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: AppHeader(
                activeStaff: staff,
                onLock: () => lockClicked = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Zeeshan Khan'), findsOneWidget);
      expect(find.text('Front Counter • Front Counter Cashier'), findsOneWidget);

      final lockButton = find.byKey(const ValueKey('lock_register_button'));
      expect(lockButton, findsOneWidget);

      await tester.tap(lockButton);
      await tester.pump();

      expect(lockClicked, isTrue);
    });

    testWidgets('AppShell shows lock screen when locked and switches to workspace on login', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = SessionState();

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: AppShell(
            session: session,
            onAuthenticatePin: (pin) async {
              if (pin == '123456') {
                return const Staff(
                  id: 2,
                  name: 'Manager Ali',
                  departmentId: 3,
                  departmentName: 'Management',
                  pinHash: 'hash',
                  role: StaffRole.supervisor,
                  isActive: true,
                );
              }
              return null;
            },
          ),
        ),
      );

      // Initially locked
      expect(find.text('Register Locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('pin_lock_screen')), findsOneWidget);

      // Tap 1, 2, 3, 4
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('unlock_pin_button')));
      await tester.pumpAndSettle();

      // Should now be unlocked
      expect(find.text('Manager Ali'), findsOneWidget);
      expect(find.text('Management • Manager'), findsOneWidget);
      expect(find.byKey(const ValueKey('lock_register_button')), findsOneWidget);

      // 1-tap lock register action
      await tester.tap(find.byKey(const ValueKey('lock_register_button')));
      await tester.pumpAndSettle();

      // Back to locked
      expect(find.text('Register Locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('pin_lock_screen')), findsOneWidget);
    });

    testWidgets('AppShell renders child workspace when authenticated', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = SessionState();
      const supervisor = Staff(
        id: 1,
        name: 'Supervisor Ali',
        departmentId: 3,
        departmentName: 'Management',
        pinHash: 'dummy',
        role: StaffRole.supervisor,
        isActive: true,
      );
      session.login(supervisor);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: AppShell(
            session: session,
            onAuthenticatePin: (_) async => null,
            child: const Center(child: Text('Custom Workspace Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Workspace Content'), findsOneWidget);
      expect(find.text('Supervisor Ali'), findsOneWidget);
    });

    testWidgets('AppShell shows workspace switcher for supervisor and switches to Catalog & BOM workspace', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = SessionState();
      const supervisor = Staff(
        id: 1,
        name: 'Supervisor Ali',
        departmentId: 3,
        departmentName: 'Management',
        pinHash: 'dummy',
        role: StaffRole.supervisor,
        isActive: true,
      );
      session.login(supervisor);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: AppShell(
            session: session,
            onAuthenticatePin: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify workspace tab buttons are present
      expect(find.byKey(const ValueKey('workspace_tab_register')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_riderTrips')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_catalog')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_khata')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_supervisor')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_mandi')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_wastage')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace_tab_tokenQueue')), findsNothing);

      // Tap Catalog & BOM tab
      await tester.ensureVisible(find.byKey(const ValueKey('workspace_tab_catalog')));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_catalog')));
      await tester.pumpAndSettle();

      // Tap Khata tab
      await tester.ensureVisible(find.byKey(const ValueKey('workspace_tab_khata')));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_khata')));
      await tester.pumpAndSettle();

      // Tap Supervisor Portal tab
      await tester.ensureVisible(find.byKey(const ValueKey('workspace_tab_supervisor')));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_supervisor')));
      await tester.pumpAndSettle();

      // Tap Token Queue tab
      await tester.pumpAndSettle();

      // Tap Mandi Purchase tab
      await tester.ensureVisible(find.byKey(const ValueKey('workspace_tab_mandi')));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_mandi')));
      await tester.pumpAndSettle();

      // Tap Kitchen Wastage tab
      await tester.ensureVisible(find.byKey(const ValueKey('workspace_tab_wastage')));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_wastage')));
      await tester.pumpAndSettle();

      // Switches back to Register tab
      await tester.ensureVisible(find.byKey(const ValueKey('workspace_tab_register')));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_register')));
      await tester.pumpAndSettle();
    });

    testWidgets('AppShell shows OnboardingWizard on first launch when onboarding is required', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
        seedDefaultStaff: false,
      );
      final db = (await tester.runAsync(posDb.initialize))!;
      addTearDown(() async {
        await tester.runAsync(posDb.close);
      });

      final authService = AuthService(database: db);
      final shiftController = ShiftAndCashController(database: db);
      final catalogController = CatalogAndRecipeController(database: db);

      await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: AppShell(
            session: authService.session,
            onAuthenticatePin: authService.authenticateWithPin,
            authService: authService,
            shiftController: shiftController,
            catalogController: catalogController,
          ),
        ),
      );
            for (var attempt = 0; attempt < 500; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byType(OnboardingWizard).evaluate().isNotEmpty) break;
      }
      });
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingWizard), findsOneWidget);
      expect(find.textContaining('First-Run Setup Wizard'), findsOneWidget);
    });
  });
}
