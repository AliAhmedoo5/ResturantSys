import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CatalogAndRecipeController Integration Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late CatalogAndRecipeController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('catalog_controller_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_catalog.db';
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

    test('Menu Categories CRUD with custom display order and color coding', () async {
      final cat1 = await controller.createCategory(
        name: 'Beverages',
        displayOrder: 2,
        colorHex: '#00897B',
      );
      final cat2 = await controller.createCategory(
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#E53935',
      );
      final cat3 = await controller.createCategory(
        name: 'Desserts',
        displayOrder: 3,
        colorHex: '#8E24AA',
      );

      final categories = await controller.getCategories();
      expect(categories.length, equals(3));
      // Ordered by display_order ASC
      expect(categories[0].name, equals('Burgers'));
      expect(categories[1].name, equals('Beverages'));
      expect(categories[2].name, equals('Desserts'));
      expect(categories[0].colorHex, equals('#E53935'));

      // Update category
      final updatedCat2 = cat2.copyWith(name: 'Gourmet Burgers', displayOrder: 0);
      await controller.updateCategory(updatedCat2);

      final updatedList = await controller.getCategories();
      expect(updatedList.first.name, equals('Gourmet Burgers'));
      expect(updatedList.first.displayOrder, equals(0));

      // Delete category
      await controller.deleteCategory(cat1.id);
      final afterDelete = await controller.getCategories();
      expect(afterDelete.length, equals(2));
      expect(afterDelete.any((c) => c.id == cat1.id), isFalse);
    });

    test('Menu Items CRUD with tax-inclusive pricing, tax rate %, and active toggle', () async {
      final category = await controller.createCategory(
        name: 'Fast Food',
        displayOrder: 1,
        colorHex: '#FB8C00',
      );

      // Tax inclusive retail price Rs 1160 with 16% tax rate
      final item = await controller.createMenuItem(
        categoryId: category.id,
        name: 'Zinger Deluxe',
        basePrice: 1160.0,
        taxRate: 16.0,
        isTaxInclusive: true,
        isActive: true,
      );

      expect(item.name, equals('Zinger Deluxe'));
      expect(item.categoryName, equals('Fast Food'));
      expect(item.basePrice, equals(1160.0));
      expect(item.taxRate, equals(16.0));
      expect(item.isTaxInclusive, isTrue);
      expect(item.isActive, isTrue);

      // Verify tax-inclusive back calculations:
      // net = 1160 / 1.16 = 1000.0
      // tax = 1160 - 1000 = 160.0
      expect(item.netPrice, closeTo(1000.0, 0.001));
      expect(item.taxAmount, closeTo(160.0, 0.001));
      expect(item.grossPrice, equals(1160.0));

      // Toggle inactive
      await controller.toggleMenuItemActive(item.id, false);
      final inactiveItem = await controller.getMenuItem(item.id);
      expect(inactiveItem.isActive, isFalse);

      final activeList = await controller.getMenuItems(activeOnly: true);
      expect(activeList, isEmpty);

      final allList = await controller.getMenuItems(activeOnly: false);
      expect(allList.length, equals(1));

      // Update item
      final updatedItem = item.copyWith(
        name: 'Zinger Deluxe Extra',
        basePrice: 1200.0,
        isActive: true,
      );
      await controller.updateMenuItem(updatedItem);

      final fetched = await controller.getMenuItem(item.id);
      expect(fetched.name, equals('Zinger Deluxe Extra'));
      expect(fetched.basePrice, equals(1200.0));

      // Delete item
      await controller.deleteMenuItem(item.id);
      final emptyList = await controller.getMenuItems();
      expect(emptyList, isEmpty);
    });

    test('Raw Ingredients CRUD with base storage units and low-stock alert thresholds', () async {
      final patty = await controller.createRawIngredient(
        name: 'Beef Patty 150g',
        storageUnit: StorageUnit.count,
        currentStock: 10.0,
        lowStockThreshold: 15.0,
        costPerRecipeUnit: 220.0,
      );

      final sauce = await controller.createRawIngredient(
        name: 'Garlic Mayo',
        storageUnit: StorageUnit.g,
        currentStock: 1500.0,
        lowStockThreshold: 500.0,
        costPerRecipeUnit: 0.65,
      );

      final syrup = await controller.createRawIngredient(
        name: 'Cola Concentrate',
        storageUnit: StorageUnit.ml,
        currentStock: 5000.0,
        lowStockThreshold: 1000.0,
        costPerRecipeUnit: 0.12,
      );

      final flour = await controller.createRawIngredient(
        name: 'Breading Flour',
        storageUnit: StorageUnit.kg,
        currentStock: 25.0,
        lowStockThreshold: 5.0,
        costPerRecipeUnit: 180.0,
      );

      // Verify low-stock warning logic
      expect(patty.isLowStock, isTrue); // 10 <= 15
      expect(sauce.isLowStock, isFalse); // 1500 > 500
      expect(syrup.isLowStock, isFalse);
      expect(flour.isLowStock, isFalse);

      final lowStockList = await controller.getRawIngredients(lowStockOnly: true);
      expect(lowStockList.length, equals(1));
      expect(lowStockList.first.name, equals('Beef Patty 150g'));

      // Stock adjustment
      await controller.adjustStock(patty.id, 10.0); // 10 + 10 = 20
      final updatedPatty = await controller.getRawIngredient(patty.id);
      expect(updatedPatty.currentStock, equals(20.0));
      expect(updatedPatty.isLowStock, isFalse); // 20 > 15
    });

    test('Bill of Materials (BOM) recipe builder linking items to ingredients with fractional quantities', () async {
      final category = await controller.createCategory(
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#E53935',
      );

      final burger = await controller.createMenuItem(
        categoryId: category.id,
        name: 'Classic Smash',
        basePrice: 650.0,
      );

      final bun = await controller.createRawIngredient(
        name: 'Brioche Bun',
        storageUnit: StorageUnit.count,
        currentStock: 200.0,
        lowStockThreshold: 50.0,
        costPerRecipeUnit: 35.0,
      );

      final patty = await controller.createRawIngredient(
        name: 'Smash Patty Ground Beef',
        storageUnit: StorageUnit.g,
        currentStock: 20000.0,
        lowStockThreshold: 3000.0,
        costPerRecipeUnit: 1.20, // Rs 1.20 per gram
      );

      final sauce = await controller.createRawIngredient(
        name: 'Smash Sauce',
        storageUnit: StorageUnit.g,
        currentStock: 5000.0,
        lowStockThreshold: 800.0,
        costPerRecipeUnit: 0.75, // Rs 0.75 per gram
      );

      final wrapper = await controller.createRawIngredient(
        name: 'Butter Paper Wrapper',
        storageUnit: StorageUnit.count,
        currentStock: 500.0,
        lowStockThreshold: 100.0,
        costPerRecipeUnit: 4.50,
      );

      // Recipe: 1 Bun, 150g Patty, 20g Sauce, 1 Wrapper
      await controller.setRecipeForMenuItem(
        menuItemId: burger.id,
        items: [
          (rawIngredientId: bun.id, quantity: 1.0),
          (rawIngredientId: patty.id, quantity: 150.0),
          (rawIngredientId: sauce.id, quantity: 20.0),
          (rawIngredientId: wrapper.id, quantity: 1.0),
        ],
      );

      final recipe = await controller.getRecipeForMenuItem(burger.id);
      expect(recipe.length, equals(4));

      final pattyComponent = recipe.firstWhere((r) => r.rawIngredientId == patty.id);
      expect(pattyComponent.quantityPerRecipeUnit, equals(150.0));
      expect(pattyComponent.rawIngredientName, equals('Smash Patty Ground Beef'));
      expect(pattyComponent.storageUnit, equals(StorageUnit.g));
      expect(pattyComponent.totalIngredientCost, closeTo(150.0 * 1.20, 0.001)); // 180.0

      // Calculate total food cost
      // 1 Bun (35) + 150g Patty (180) + 20g Sauce (15) + 1 Wrapper (4.50) = 234.50
      final totalCost = await controller.calculateItemIngredientCost(burger.id);
      expect(totalCost, closeTo(234.50, 0.001));

      // Remove single recipe item
      await controller.removeRecipeItem(
        menuItemId: burger.id,
        rawIngredientId: wrapper.id,
      );
      final recipeAfterRemove = await controller.getRecipeForMenuItem(burger.id);
      expect(recipeAfterRemove.length, equals(3));
      expect(recipeAfterRemove.any((r) => r.rawIngredientId == wrapper.id), isFalse);
    });

    test('Modifiers CRUD with price deltas and ingredient quantity deltas', () async {
      final category = await controller.createCategory(
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#E53935',
      );

      final burger = await controller.createMenuItem(
        categoryId: category.id,
        name: 'Cheese Burger',
        basePrice: 550.0,
      );

      final cheese = await controller.createRawIngredient(
        name: 'Cheddar Cheese Slice',
        storageUnit: StorageUnit.count,
        currentStock: 300.0,
        lowStockThreshold: 50.0,
        costPerRecipeUnit: 40.0,
      );

      final mayo = await controller.createRawIngredient(
        name: 'Regular Mayo',
        storageUnit: StorageUnit.g,
        currentStock: 4000.0,
        lowStockThreshold: 500.0,
        costPerRecipeUnit: 0.50,
      );

      // +Extra Cheese: adding Rs. 80 and 1 cheese slice
      final mod1 = await controller.createModifier(
        menuItemId: burger.id,
        name: '+Extra Cheese',
        priceDelta: 80.0,
        rawIngredientId: cheese.id,
        ingredientQtyDelta: 1.0,
        isActive: true,
      );

      // No Mayo: deducting 0g sauce at Rs. 0
      final mod2 = await controller.createModifier(
        menuItemId: burger.id,
        name: 'No Mayo',
        priceDelta: 0.0,
        rawIngredientId: mayo.id,
        ingredientQtyDelta: 0.0,
        isActive: true,
      );

      expect(mod1.name, equals('+Extra Cheese'));
      expect(mod1.priceDelta, equals(80.0));
      expect(mod1.ingredientQtyDelta, equals(1.0));
      expect(mod1.rawIngredientName, equals('Cheddar Cheese Slice'));

      expect(mod2.name, equals('No Mayo'));
      expect(mod2.priceDelta, equals(0.0));
      expect(mod2.ingredientQtyDelta, equals(0.0));

      final modifiers = await controller.getModifiers(menuItemId: burger.id);
      expect(modifiers.length, equals(2));

      // Toggle active
      await controller.toggleModifierActive(mod1.id, false);
      final activeModifiers = await controller.getModifiers(menuItemId: burger.id, activeOnly: true);
      expect(activeModifiers.length, equals(1));
      expect(activeModifiers.first.name, equals('No Mayo'));

      // Delete modifier
      await controller.deleteModifier(mod2.id);
      final remaining = await controller.getModifiers(menuItemId: burger.id);
      expect(remaining.length, equals(1));
    });

    test('Pre-approved discount presets CRUD with percentage and flat rupee calculations', () async {
      final staffDiscount = await controller.createDiscountPreset(
        name: 'Staff Meal 20%',
        type: DiscountType.percentage,
        value: 20.0,
        isActive: true,
      );

      final promoDiscount = await controller.createDiscountPreset(
        name: 'Summer Promo Rs 150',
        type: DiscountType.flat,
        value: 150.0,
        isActive: true,
      );

      final presets = await controller.getDiscountPresets();
      expect(presets.length, equals(2));

      // Calculate discount on Rs 1000 order:
      // 20% on 1000 = 200.0
      expect(staffDiscount.calculateDiscount(1000.0), closeTo(200.0, 0.001));

      // Flat Rs 150 on 1000 = 150.0
      expect(promoDiscount.calculateDiscount(1000.0), equals(150.0));

      // Flat discount capped at subtotal if order is smaller than discount
      expect(promoDiscount.calculateDiscount(100.0), equals(100.0));

      // Toggle active
      await controller.toggleDiscountPresetActive(staffDiscount.id, false);
      final activePresets = await controller.getDiscountPresets(activeOnly: true);
      expect(activePresets.length, equals(1));
      expect(activePresets.first.name, equals('Summer Promo Rs 150'));

      // Update preset
      final updatedPromo = promoDiscount.copyWith(value: 200.0, name: 'Summer Promo Rs 200');
      await controller.updateDiscountPreset(updatedPromo);

      final fetched = (await controller.getDiscountPresets()).firstWhere((p) => p.id == promoDiscount.id);
      expect(fetched.value, equals(200.0));
      expect(fetched.name, equals('Summer Promo Rs 200'));

      // Delete preset
      await controller.deleteDiscountPreset(promoDiscount.id);
      final remaining = await controller.getDiscountPresets();
      expect(remaining.length, equals(1));
    });
  });
}
