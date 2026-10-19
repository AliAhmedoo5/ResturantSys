import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/widgets/onboarding/onboarding_wizard.dart';

Future<void> tapAndWait(WidgetTester tester, Finder button) async {
  await tester.runAsync(() async {
    await tester.ensureVisible(button);
    await tester.tap(button);
    for (var attempt = 0; attempt < 500; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
    fail('Onboarding action did not finish within five seconds.');
  });
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Seam 3: Compulsory 5-Step First-Run Onboarding Wizard', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;
    late ShiftAndCashController shiftController;
    late CatalogAndRecipeController catalogController;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_onboarding_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}onboard_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
        seedDefaultStaff: false, // clean, empty database!
      );
      db = await posDb.initialize();
      authService = AuthService(database: db);
      shiftController = ShiftAndCashController(database: db);
      catalogController = CatalogAndRecipeController(database: db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('Wizard renders 5 steps and enforces strict sequential completion with Manager and Cashier', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Staff? completedCashier;

      Future<void> mountWizard() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: OnboardingWizard(
              authService: authService,
              shiftController: shiftController,
              catalogController: catalogController,
              onCompleted: (cashier) {
                completedCashier = cashier;
              },
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }
      await mountWizard();

      // --- STEP 1: Restaurant Identity ---
      expect(find.text('Step 1: Restaurant Identity'), findsOneWidget);
      expect(find.byKey(const ValueKey('restaurant_name_input')), findsOneWidget);
      expect(find.textContaining('PKR'), findsWidgets);

      // Tap Next Step 1 -> advances to Step 2
      final step1NextBtn = find.byKey(const ValueKey('step_1_next_button'));
      expect(step1NextBtn, findsOneWidget);
      await tapAndWait(tester, step1NextBtn);

      // --- STEP 2: Create First Manager Account ---
      expect(find.text('Step 2: Create Manager Account'), findsOneWidget);
      final managerNameInput = find.byKey(const ValueKey('manager_name_input'));
      final managerPinInput = find.byKey(const ValueKey('manager_pin_input'));
      final managerConfirmPinInput = find.byKey(const ValueKey('manager_confirm_pin_input'));
      final step2NextBtn = find.byKey(const ValueKey('step_2_next_button'));

      // Attempt submit without PIN -> validation fails
      await tapAndWait(tester, step2NextBtn);
      expect(find.text('Step 3: Create Primary Cashier'), findsNothing);

      // Enter valid Manager details (4-digit PIN)
      await tester.enterText(managerNameInput, 'Owner Asad');
      await tester.enterText(managerPinInput, '1234');
      await tester.enterText(managerConfirmPinInput, '1234');
      await tester.pumpAndSettle();

      await tapAndWait(tester, step2NextBtn);

      // --- STEP 3: MANDATORY: Create Primary Cashier ---
      expect(find.text('Step 3: Create Primary Cashier'), findsOneWidget);
      final cashierNameInput = find.byKey(const ValueKey('cashier_name_input'));
      final cashierPinInput = find.byKey(const ValueKey('cashier_pin_input'));
      final cashierConfirmPinInput = find.byKey(const ValueKey('cashier_confirm_pin_input'));
      final step3NextBtn = find.byKey(const ValueKey('step_3_next_button'));

      // Try using the SAME PIN as Manager -> must be rejected
      await tester.enterText(cashierNameInput, 'Bilal Cashier');
      await tester.enterText(cashierPinInput, '1234');
      await tester.enterText(cashierConfirmPinInput, '1234');
      await tester.pumpAndSettle();

      await tapAndWait(tester, step3NextBtn);
      expect(find.textContaining('Cashier PIN must be different from Manager PIN'), findsOneWidget);

      // Try 3-digit PIN for cashier -> rejected (must be 4 digits)
      await tester.enterText(cashierPinInput, '987');
      await tester.enterText(cashierConfirmPinInput, '987');
      await tester.pumpAndSettle();

      await tapAndWait(tester, step3NextBtn);
      expect(find.textContaining('Cashier PIN must be exactly 4 numeric digits'), findsOneWidget);

      // Enter distinct 4-digit Cashier PIN
      await tester.enterText(cashierPinInput, '9876');
      await tester.enterText(cashierConfirmPinInput, '9876');
      await tester.pumpAndSettle();

      await tapAndWait(tester, step3NextBtn);

      // --- STEP 4: Guided First Recipe Creator ---
      expect(find.text('Step 4: Create First Recipe'), findsOneWidget);
      expect(find.textContaining('requires a recipe with linked raw ingredients'), findsOneWidget);

      final menuItemNameInput = find.byKey(const ValueKey('menu_item_name_input'));
      final categoryNameInput = find.byKey(const ValueKey('category_name_input'));
      final menuItemPriceInput = find.byKey(const ValueKey('menu_item_price_input'));
      final ingredientNameInput = find.byKey(const ValueKey('ingredient_name_input'));
      final ingredientStockInput = find.byKey(const ValueKey('ingredient_stock_input'));
      final ingredientCostInput = find.byKey(const ValueKey('ingredient_cost_input'));
      final recipeQtyInput = find.byKey(const ValueKey('recipe_qty_input'));
      final step4NextBtn = find.byKey(const ValueKey('step_4_next_button'));

      await tester.enterText(menuItemNameInput, 'Mafia Special Burger');
      await tester.enterText(categoryNameInput, 'Burgers');
      await tester.enterText(menuItemPriceInput, '450.00');
      await tester.enterText(ingredientNameInput, 'Beef Patty');
      await tester.enterText(ingredientStockInput, '10000');
      await tester.enterText(ingredientCostInput, '1.20');
      await tester.enterText(recipeQtyInput, '150');
      await tester.pumpAndSettle();

      await tapAndWait(tester, step4NextBtn);

      // --- STEP 5: Manager Opens First Business Day & Switch to Cashier ---
      expect(find.text('Step 5: Open First Business Day'), findsOneWidget);
      final openDayBtn = find.byKey(const ValueKey('open_first_business_day_button'));
      expect(openDayBtn, findsOneWidget);

      await tapAndWait(tester, openDayBtn);

      // Simulate restarting after the recipe and Business Day were persisted.
      final originalDay = await tester.runAsync(shiftController.getActiveBusinessDay);
      await tester.pumpWidget(const SizedBox.shrink());
      await mountWizard();
      await tapAndWait(tester, step1NextBtn);
      await tester.enterText(managerPinInput, '1234');
      await tester.enterText(managerConfirmPinInput, '1234');
      await tapAndWait(tester, step2NextBtn);
      await tester.enterText(cashierPinInput, '9876');
      await tester.enterText(cashierConfirmPinInput, '9876');
      await tapAndWait(tester, step3NextBtn);
      await tester.enterText(menuItemNameInput, 'Mafia Special Burger');
      await tapAndWait(tester, step4NextBtn);
      await tapAndWait(tester, openDayBtn);
      expect((await tester.runAsync(catalogController.getMenuItems))!.length, 1);
      expect((await tester.runAsync(authService.getAllStaff))!.length, 2);
      expect((await tester.runAsync(shiftController.getActiveBusinessDay))!.id, originalDay!.id);

      // Should render the Switch to Cashier prompt
      expect(find.textContaining('Switch to Cashier'), findsWidgets);
      final switchCashierBtn = find.byKey(const ValueKey('switch_to_cashier_button'));
      expect(switchCashierBtn, findsOneWidget);

      await tapAndWait(tester, switchCashierBtn);

      // Wizard completes and returns the created cashier
      expect(completedCashier, isNotNull);
      expect(completedCashier!.role, equals(StaffRole.cashier));
      expect(completedCashier!.name, equals('Bilal Cashier'));

      // Verify DB settings mark onboarding completed
      final onboardingSetting = await tester.runAsync(() => db.query(
        PosDatabaseConstants.tableSystemSettings,
        where: 'key = ?',
        whereArgs: [PosDatabaseConstants.settingOnboardingCompleted],
      ));
      expect(onboardingSetting!.first['value'], equals('true'));

      // Verify active business day exists
      final activeDay = await tester.runAsync(shiftController.getActiveBusinessDay);
      expect(activeDay, isNotNull);
      final cashier = await tester.runAsync(() => authService.authenticateAndLogin('9876'));
      final shift = await tester.runAsync(() => shiftController.openShift(
        staffId: cashier!.id, openingFloat: 1000,
      ));
      expect(shift!.businessDayId, activeDay!.id);
    });
  });
}
