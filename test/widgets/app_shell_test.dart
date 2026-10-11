import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/widgets/app_header.dart';
import 'package:resturant_sys/widgets/app_shell.dart';

void main() {
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
              if (pin == '1234') {
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
      await tester.pumpAndSettle();

      // Should now be unlocked
      expect(find.text('Manager Ali'), findsOneWidget);
      expect(find.text('Management • Supervisor'), findsOneWidget);
      expect(find.byKey(const ValueKey('lock_register_button')), findsOneWidget);

      // 1-tap lock register action
      await tester.tap(find.byKey(const ValueKey('lock_register_button')));
      await tester.pumpAndSettle();

      // Back to locked
      expect(find.text('Register Locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('pin_lock_screen')), findsOneWidget);
    });

    testWidgets('AppShell renders RegisterShiftWorkspace when shiftController is provided', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final posDb = PosDatabase(customPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
      final db = await posDb.initialize();
      addTearDown(posDb.close);

      final controller = ShiftAndCashController(database: db);
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
            shiftController: controller,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Business Day Closed'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_open_business_day')), findsOneWidget);
    });
  });
}
