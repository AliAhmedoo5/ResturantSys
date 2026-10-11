import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PosCatalogDatabase Schema & Relational Integrity Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_catalog_db_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_pos_catalog.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initializes schema version 3 with all catalog, BOM, modifier, and discount tables', () async {
      final db = await posDb.initialize();

      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tablesResult.map((row) => row['name'] as String).toList();

      expect(tableNames, contains(PosDatabaseConstants.tableCategories));
      expect(tableNames, contains(PosDatabaseConstants.tableMenuItems));
      expect(tableNames, contains(PosDatabaseConstants.tableRawIngredients));
      expect(tableNames, contains(PosDatabaseConstants.tableRecipes));
      expect(tableNames, contains(PosDatabaseConstants.tableModifiers));
      expect(tableNames, contains(PosDatabaseConstants.tableDiscountPresets));
    });

    test('enforces UNIQUE constraints on category and ingredient names', () async {
      final db = await posDb.initialize();

      await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Burgers',
        'display_order': 1,
        'color_hex': '#E53935',
        'created_at': '2026-10-11 12:00:00',
      });

      expect(
        () => db.insert(PosDatabaseConstants.tableCategories, {
          'name': 'Burgers',
          'display_order': 2,
          'color_hex': '#1E88E5',
          'created_at': '2026-10-11 12:00:00',
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Beef Patty 150g',
        'storage_unit': 'count',
        'current_stock': 100.0,
        'low_stock_threshold': 20.0,
        'cost_per_recipe_unit': 220.0,
        'created_at': '2026-10-11 12:00:00',
      });

      expect(
        () => db.insert(PosDatabaseConstants.tableRawIngredients, {
          'name': 'Beef Patty 150g',
          'storage_unit': 'count',
          'current_stock': 50.0,
          'low_stock_threshold': 10.0,
          'cost_per_recipe_unit': 210.0,
          'created_at': '2026-10-11 12:00:00',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('cascades delete from category to menu items, recipes, and modifiers', () async {
      final db = await posDb.initialize();

      final categoryId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Beverages',
        'display_order': 2,
        'color_hex': '#00897B',
        'created_at': '2026-10-11 12:00:00',
      });

      final ingredientId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Mint Syrup',
        'storage_unit': 'ml',
        'current_stock': 2000.0,
        'low_stock_threshold': 500.0,
        'cost_per_recipe_unit': 0.85,
        'created_at': '2026-10-11 12:00:00',
      });

      final menuItemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': categoryId,
        'name': 'Mint Lemonade',
        'base_price': 350.0,
        'tax_rate': 16.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': '2026-10-11 12:00:00',
      });

      await db.insert(PosDatabaseConstants.tableRecipes, {
        'menu_item_id': menuItemId,
        'raw_ingredient_id': ingredientId,
        'quantity_per_recipe_unit': 30.0,
        'created_at': '2026-10-11 12:00:00',
      });

      await db.insert(PosDatabaseConstants.tableModifiers, {
        'menu_item_id': menuItemId,
        'name': 'Extra Mint',
        'price_delta': 50.0,
        'raw_ingredient_id': ingredientId,
        'ingredient_qty_delta': 15.0,
        'is_active': 1,
        'created_at': '2026-10-11 12:00:00',
      });

      // Delete the category
      await db.delete(
        PosDatabaseConstants.tableCategories,
        where: 'id = ?',
        whereArgs: [categoryId],
      );

      // Verify category deleted
      final categories = await db.query(PosDatabaseConstants.tableCategories);
      expect(categories, isEmpty);

      // Verify cascade: menu_items, recipes, modifiers deleted
      final items = await db.query(PosDatabaseConstants.tableMenuItems);
      expect(items, isEmpty);

      final recipes = await db.query(PosDatabaseConstants.tableRecipes);
      expect(recipes, isEmpty);

      final modifiers = await db.query(PosDatabaseConstants.tableModifiers);
      expect(modifiers, isEmpty);

      // Ingredient itself is preserved
      final ingredients = await db.query(PosDatabaseConstants.tableRawIngredients);
      expect(ingredients.length, equals(1));
    });

    test('restricts deleting raw ingredient if referenced in an active recipe', () async {
      final db = await posDb.initialize();

      final categoryId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Sides',
        'display_order': 3,
        'color_hex': '#F4511E',
        'created_at': '2026-10-11 12:00:00',
      });

      final ingredientId = await db.insert(PosDatabaseConstants.tableRawIngredients, {
        'name': 'Potato Fries Cut',
        'storage_unit': 'g',
        'current_stock': 5000.0,
        'low_stock_threshold': 1000.0,
        'cost_per_recipe_unit': 0.40,
        'created_at': '2026-10-11 12:00:00',
      });

      final menuItemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': categoryId,
        'name': 'Regular Fries',
        'base_price': 250.0,
        'tax_rate': 16.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': '2026-10-11 12:00:00',
      });

      await db.insert(PosDatabaseConstants.tableRecipes, {
        'menu_item_id': menuItemId,
        'raw_ingredient_id': ingredientId,
        'quantity_per_recipe_unit': 200.0,
        'created_at': '2026-10-11 12:00:00',
      });

      // Deleting the ingredient directly must fail due to ON DELETE RESTRICT
      expect(
        () => db.delete(
          PosDatabaseConstants.tableRawIngredients,
          where: 'id = ?',
          whereArgs: [ingredientId],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('supports pre-approved discount presets table with percentage and flat types', () async {
      final db = await posDb.initialize();

      final discount1 = await db.insert(PosDatabaseConstants.tableDiscountPresets, {
        'name': 'Staff Meal 50%',
        'type': 'PERCENTAGE',
        'value': 50.0,
        'is_active': 1,
        'created_at': '2026-10-11 12:00:00',
      });

      final discount2 = await db.insert(PosDatabaseConstants.tableDiscountPresets, {
        'name': 'Promo Rs 100 Off',
        'type': 'FLAT',
        'value': 100.0,
        'is_active': 1,
        'created_at': '2026-10-11 12:00:00',
      });

      expect(discount1, isPositive);
      expect(discount2, isPositive);

      final presets = await db.query(PosDatabaseConstants.tableDiscountPresets);
      expect(presets.length, equals(2));
    });
  });
}
