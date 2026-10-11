import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/catalog/supervisor_catalog_workspace.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SupervisorCatalogWorkspace Widget Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late CatalogAndRecipeController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('catalog_widget_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_widget_pos.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      final db = await posDb.initialize();
      controller = CatalogAndRecipeController(database: db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('renders all 5 catalog tabs and supports tab switching', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tab_categories')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_menu_items')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_raw_ingredients')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_modifiers')), findsOneWidget);
      expect(find.byKey(const ValueKey('tab_discounts')), findsOneWidget);

      // Categories tab is active initially
      expect(find.text('Menu Categories'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_category_button')), findsOneWidget);

      // Switch to Menu Items tab
      await tester.tap(find.byKey(const ValueKey('tab_menu_items')));
      await tester.pumpAndSettle();
      expect(find.text('Menu Items & Recipe BOM'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_menu_item_button')), findsOneWidget);

      // Switch to Raw Ingredients tab
      await tester.tap(find.byKey(const ValueKey('tab_raw_ingredients')));
      await tester.pumpAndSettle();
      expect(find.text('Raw Ingredients Inventory'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_ingredient_button')), findsOneWidget);

      // Switch to Modifiers tab
      await tester.tap(find.byKey(const ValueKey('tab_modifiers')));
      await tester.pumpAndSettle();
      expect(find.text('Modifiers & Add-ons'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_modifier_button')), findsOneWidget);

      // Switch to Discounts tab
      await tester.tap(find.byKey(const ValueKey('tab_discounts')));
      await tester.pumpAndSettle();
      expect(find.text('Pre-Approved Discounts'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_discount_preset_button')), findsOneWidget);
    });

    testWidgets('creates a Category through CategoryFormDialog and displays it in list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Add Category dialog
      await tester.tap(find.byKey(const ValueKey('add_category_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add Menu Category'), findsOneWidget);

      // Fill in category name and order
      await tester.enterText(find.byKey(const ValueKey('category_name_field')), 'Crispy Chicken');
      await tester.enterText(find.byKey(const ValueKey('category_order_field')), '1');
      await tester.pump();

      // Save category
      await tester.tap(find.byKey(const ValueKey('save_category_button')));
      await tester.pumpAndSettle();

      // Verify category appeared in list
      expect(find.text('Crispy Chicken'), findsOneWidget);
      expect(find.text('Order: #1'), findsOneWidget);
    });

    testWidgets('creates Menu Item and opens BOM Recipe Builder dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Seed a category and ingredient
      final category = await controller.createCategory(
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#E53935',
      );
      final bun = await controller.createRawIngredient(
        name: 'Sesame Bun',
        storageUnit: StorageUnit.count,
        currentStock: 100.0,
        lowStockThreshold: 20.0,
        costPerRecipeUnit: 30.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Menu Items tab
      await tester.tap(find.byKey(const ValueKey('tab_menu_items')));
      await tester.pumpAndSettle();

      // Open Add Menu Item dialog
      await tester.tap(find.byKey(const ValueKey('add_menu_item_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add Menu Item'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('menu_item_name_field')), 'Zinger Classic');
      await tester.enterText(find.byKey(const ValueKey('menu_item_price_field')), '580.00');
      await tester.enterText(find.byKey(const ValueKey('menu_item_tax_rate_field')), '16.00');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save_menu_item_button')));
      await tester.pumpAndSettle();

      // Item should now be in the list
      expect(find.text('Zinger Classic'), findsOneWidget);
      expect(find.text('Rs 580.00'), findsOneWidget);

      // Open BOM Recipe Builder
      final items = await controller.getMenuItems();
      final zinger = items.firstWhere((i) => i.name == 'Zinger Classic');

      final bomButton = find.byKey(ValueKey('edit_bom_button_${zinger.id}'));
      expect(bomButton, findsOneWidget);
      await tester.tap(bomButton);
      await tester.pumpAndSettle();

      expect(find.text('Recipe BOM: Zinger Classic'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_recipe_item_button')), findsOneWidget);

      // Enter fractional quantity 1 count bun
      await tester.enterText(find.byKey(const ValueKey('recipe_qty_field')), '1.0');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add_recipe_item_button')));
      await tester.pumpAndSettle();

      expect(find.text('Sesame Bun'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('shows LOW STOCK badge for ingredients below threshold and supports low stock filter', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Seed 1 normal ingredient, 1 low stock ingredient
      await controller.createRawIngredient(
        name: 'Abundant Lettuce',
        storageUnit: StorageUnit.kg,
        currentStock: 50.0,
        lowStockThreshold: 10.0,
        costPerRecipeUnit: 120.0,
      );
      await controller.createRawIngredient(
        name: 'Depleted Cheese Slices',
        storageUnit: StorageUnit.count,
        currentStock: 5.0,
        lowStockThreshold: 20.0,
        costPerRecipeUnit: 35.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Go to Raw Ingredients tab
      await tester.tap(find.byKey(const ValueKey('tab_raw_ingredients')));
      await tester.pumpAndSettle();

      expect(find.text('Abundant Lettuce'), findsOneWidget);
      expect(find.text('Depleted Cheese Slices'), findsOneWidget);
      expect(find.text('LOW STOCK'), findsOneWidget);

      // Filter to show low stock only
      await tester.tap(find.byKey(const ValueKey('low_stock_filter_chip')));
      await tester.pumpAndSettle();

      expect(find.text('Depleted Cheese Slices'), findsOneWidget);
      expect(find.text('Abundant Lettuce'), findsNothing);
    });

    testWidgets('creates a modifier with price delta and ingredient quantity delta', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Go to Modifiers tab
      await tester.tap(find.byKey(const ValueKey('tab_modifiers')));
      await tester.pumpAndSettle();

      // Open Add Modifier dialog
      await tester.tap(find.byKey(const ValueKey('add_modifier_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add Modifier'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('modifier_name_field')), '+Extra Jalapenos');
      await tester.enterText(find.byKey(const ValueKey('modifier_price_delta_field')), '60.00');
      await tester.enterText(find.byKey(const ValueKey('modifier_qty_delta_field')), '15.0');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save_modifier_button')));
      await tester.pumpAndSettle();

      expect(find.text('+Extra Jalapenos'), findsOneWidget);
      expect(find.text('+Rs 60.00'), findsOneWidget);
    });

    testWidgets('creates Pre-Approved Discount presets and displays them', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: SupervisorCatalogWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Go to Discounts tab
      await tester.tap(find.byKey(const ValueKey('tab_discounts')));
      await tester.pumpAndSettle();

      // Open Add Discount dialog
      await tester.tap(find.byKey(const ValueKey('add_discount_preset_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add Discount Preset'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('discount_name_field')), 'Staff Courtesy 25%');
      await tester.enterText(find.byKey(const ValueKey('discount_value_field')), '25');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save_discount_button')));
      await tester.pumpAndSettle();

      expect(find.text('Staff Courtesy 25%'), findsOneWidget);
      expect(find.text('25% Off'), findsOneWidget);
    });
  });
}
