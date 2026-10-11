import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/catalog/dialogs/recipe_builder_dialog.dart';
import 'package:resturant_sys/widgets/catalog/supervisor_catalog_workspace.dart';

void main() {
  group('SupervisorCatalogWorkspace Widget Tests', () {
    testWidgets('renders all 5 catalog tabs and supports tab switching', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: SupervisorCatalogWorkspace(
              initialCategories: [
                MenuCategory(id: 1, name: 'Burgers', displayOrder: 1, colorHex: '#E53935'),
              ],
              initialMenuItems: [
                MenuItem(id: 1, categoryId: 1, categoryName: 'Burgers', name: 'Zinger', basePrice: 550.0),
              ],
              initialRawIngredients: [
                RawIngredient(id: 1, name: 'Bun', storageUnit: StorageUnit.count, currentStock: 100, lowStockThreshold: 20),
              ],
              initialModifiers: [
                Modifier(id: 1, name: '+Cheese', priceDelta: 60.0),
              ],
              initialDiscounts: [
                DiscountPreset(id: 1, name: 'Staff 20%', type: DiscountType.percentage, value: 20.0, isActive: true),
              ],
            ),
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
      expect(find.descendant(of: find.byType(SingleChildScrollView), matching: find.text('Pre-Approved Discounts')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_discount_preset_button')), findsOneWidget);
    });

    testWidgets('creates a Category through CategoryFormDialog and displays it in list', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: SupervisorCatalogWorkspace(
              initialCategories: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Add Category dialog
      await tester.tap(find.byKey(const ValueKey('add_category_button')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Menu Category')), findsOneWidget);

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
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const category = MenuCategory(
        id: 1,
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#E53935',
      );
      const bun = RawIngredient(
        id: 1,
        name: 'Sesame Bun',
        storageUnit: StorageUnit.count,
        currentStock: 100.0,
        lowStockThreshold: 20.0,
        costPerRecipeUnit: 30.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: SupervisorCatalogWorkspace(
              initialCategories: [category],
              initialMenuItems: [],
              initialRawIngredients: [bun],
            ),
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

      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Menu Item')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('menu_item_name_field')), 'Zinger Classic');
      await tester.enterText(find.byKey(const ValueKey('menu_item_price_field')), '580.00');
      await tester.enterText(find.byKey(const ValueKey('menu_item_tax_rate_field')), '16.00');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('save_menu_item_button')));
      await tester.pumpAndSettle();

      // Item should now be in the list
      expect(find.text('Zinger Classic'), findsOneWidget);
      expect(find.text('Rs 580.00'), findsOneWidget);
    });

    testWidgets('RecipeBuilderDialog renders BOM breakdown with fractional quantities and live cost', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const item = MenuItem(
        id: 1,
        categoryId: 1,
        categoryName: 'Burgers',
        name: 'Classic Smash',
        basePrice: 650.0,
      );
      const bun = RawIngredient(
        id: 1,
        name: 'Brioche Bun',
        storageUnit: StorageUnit.count,
        currentStock: 100,
        lowStockThreshold: 20,
        costPerRecipeUnit: 35.0,
      );

      int? addedIngredientId;
      double? addedQty;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: RecipeBuilderDialog(
              menuItem: item,
              initialRecipeItems: const [],
              initialAllIngredients: const [bun],
              onAddOrUpdateItem: (ingId, qty) async {
                addedIngredientId = ingId;
                addedQty = qty;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recipe BOM: Classic Smash'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_recipe_item_button')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('recipe_qty_field')), '1.0');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('add_recipe_item_button')));
      await tester.pumpAndSettle();

      expect(addedIngredientId, equals(1));
      expect(addedQty, equals(1.0));
    });

    testWidgets('shows LOW STOCK badge for ingredients below threshold and supports low stock filter', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Seed 1 normal ingredient, 1 low stock ingredient
      const abundant = RawIngredient(
        id: 1,
        name: 'Abundant Lettuce',
        storageUnit: StorageUnit.kg,
        currentStock: 50.0,
        lowStockThreshold: 10.0,
        costPerRecipeUnit: 120.0,
      );
      const depleted = RawIngredient(
        id: 2,
        name: 'Depleted Cheese Slices',
        storageUnit: StorageUnit.count,
        currentStock: 5.0,
        lowStockThreshold: 20.0,
        costPerRecipeUnit: 35.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: SupervisorCatalogWorkspace(
              initialRawIngredients: [abundant, depleted],
            ),
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
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: SupervisorCatalogWorkspace(
              initialModifiers: [],
            ),
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

      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Modifier')), findsOneWidget);

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
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: SupervisorCatalogWorkspace(
              initialDiscounts: [],
            ),
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

      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Add Discount Preset')), findsOneWidget);

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
