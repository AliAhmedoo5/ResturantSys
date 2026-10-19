import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/pos_database_constants.dart';
import 'discount_preset.dart';
import 'menu_category.dart';
import 'menu_item.dart';
import 'modifier.dart';
import 'raw_ingredient.dart';
import 'recipe_item.dart';
import 'storage_unit.dart';

/// Domain controller managing Menu Categories, Menu Items with tax-inclusive pricing,
/// Raw Ingredients, Recipe Bill of Materials (BOM), Modifiers, and Pre-Approved Discounts.
class CatalogAndRecipeController {
  CatalogAndRecipeController({required this.database});

  final Database database;

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  // ---------------------------------------------------------------------------
  // Categories CRUD
  // ---------------------------------------------------------------------------

  Future<List<MenuCategory>> getCategories() async {
    final rows = await database.query(
      PosDatabaseConstants.tableCategories,
      orderBy: 'display_order ASC, name ASC',
    );
    return rows.map((r) => MenuCategory.fromMap(r)).toList();
  }

  Future<MenuCategory> createCategory({
    required String name,
    required int displayOrder,
    required String colorHex,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableCategories,
      {
        'name': name.trim(),
        'display_order': displayOrder,
        'color_hex': colorHex.trim(),
        'created_at': now,
      },
    );

    return MenuCategory(
      id: id,
      name: name.trim(),
      displayOrder: displayOrder,
      colorHex: colorHex.trim(),
      createdAt: DateTime.parse(now),
    );
  }

  Future<MenuCategory> updateCategory(MenuCategory category) async {
    await database.update(
      PosDatabaseConstants.tableCategories,
      {
        'name': category.name.trim(),
        'display_order': category.displayOrder,
        'color_hex': category.colorHex.trim(),
      },
      where: 'id = ?',
      whereArgs: [category.id],
    );
    return category;
  }

  Future<void> deleteCategory(int id) async {
    await database.delete(
      PosDatabaseConstants.tableCategories,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Menu Items CRUD
  // ---------------------------------------------------------------------------

  Future<List<MenuItem>> getMenuItems({
    int? categoryId,
    bool? activeOnly,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (categoryId != null) {
      conditions.add('m.category_id = ?');
      args.add(categoryId);
    }
    if (activeOnly == true) {
      conditions.add('m.is_active = 1');
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final rows = await database.rawQuery('''
      SELECT 
        m.*,
        c.name AS category_name
      FROM ${PosDatabaseConstants.tableMenuItems} m
      JOIN ${PosDatabaseConstants.tableCategories} c ON m.category_id = c.id
      $whereClause
      ORDER BY c.display_order ASC, m.name ASC;
    ''', args);

    return rows.map((r) => MenuItem.fromMap(r, categoryName: r['category_name'] as String?)).toList();
  }

  Future<MenuItem> getMenuItem(int id) async {
    final rows = await database.rawQuery('''
      SELECT 
        m.*,
        c.name AS category_name
      FROM ${PosDatabaseConstants.tableMenuItems} m
      JOIN ${PosDatabaseConstants.tableCategories} c ON m.category_id = c.id
      WHERE m.id = ?;
    ''', [id]);

    if (rows.isEmpty) {
      throw StateError('Menu item with id $id not found.');
    }
    final r = rows.first;
    return MenuItem.fromMap(r, categoryName: r['category_name'] as String?);
  }

  Future<MenuItem> createMenuItem({
    required int categoryId,
    required String name,
    required double basePrice,
    double taxRate = 0.0,
    bool isTaxInclusive = true,
    bool isActive = true,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableMenuItems,
      {
        'category_id': categoryId,
        'name': name.trim(),
        'base_price': basePrice,
        'tax_rate': taxRate,
        'is_tax_inclusive': isTaxInclusive ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
      },
    );

    return getMenuItem(id);
  }

  Future<MenuItem> updateMenuItem(MenuItem item) async {
    await database.update(
      PosDatabaseConstants.tableMenuItems,
      {
        'category_id': item.categoryId,
        'name': item.name.trim(),
        'base_price': item.basePrice,
        'tax_rate': item.taxRate,
        'is_tax_inclusive': item.isTaxInclusive ? 1 : 0,
        'is_active': item.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
    return getMenuItem(item.id);
  }

  Future<void> deleteMenuItem(int id) async {
    await database.delete(
      PosDatabaseConstants.tableMenuItems,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> validateRecipe(int menuItemId, {DatabaseExecutor? executor}) async {
    final rows = await (executor ?? database).query('recipes', where: 'menu_item_id = ?', whereArgs: [menuItemId]);
    if (rows.isEmpty || rows.any((row) {
      final qty = (row['quantity_per_recipe_unit'] as num).toDouble();
      return !qty.isFinite || qty <= 0;
    })) {
      throw StateError('Recipe required: configure a complete positive BOM before activation.');
    }
  }

  Future<void> toggleMenuItemActive(int id, bool isActive) async {
    if (isActive) await validateRecipe(id);
    await database.update(
      PosDatabaseConstants.tableMenuItems,
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Raw Ingredients CRUD
  // ---------------------------------------------------------------------------

  Future<List<RawIngredient>> getRawIngredients({bool? lowStockOnly}) async {
    String? where;
    List<Object?>? args;
    if (lowStockOnly == true) {
      where = 'current_stock <= low_stock_threshold';
    }

    final rows = await database.query(
      PosDatabaseConstants.tableRawIngredients,
      where: where,
      whereArgs: args,
      orderBy: 'name ASC',
    );
    return rows.map((r) => RawIngredient.fromMap(r)).toList();
  }

  Future<RawIngredient> getRawIngredient(int id) async {
    final rows = await database.query(
      PosDatabaseConstants.tableRawIngredients,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      throw StateError('Raw ingredient with id $id not found.');
    }
    return RawIngredient.fromMap(rows.first);
  }

  Future<RawIngredient> createRawIngredient({
    required String name,
    required StorageUnit storageUnit,
    double currentStock = 0.0,
    double lowStockThreshold = 0.0,
    double costPerRecipeUnit = 0.0,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableRawIngredients,
      {
        'name': name.trim(),
        'storage_unit': storageUnit.code,
        'current_stock': currentStock,
        'low_stock_threshold': lowStockThreshold,
        'cost_per_recipe_unit': costPerRecipeUnit,
        'created_at': now,
      },
    );

    return RawIngredient(
      id: id,
      name: name.trim(),
      storageUnit: storageUnit,
      currentStock: currentStock,
      lowStockThreshold: lowStockThreshold,
      costPerRecipeUnit: costPerRecipeUnit,
      createdAt: DateTime.parse(now),
    );
  }

  Future<RawIngredient> updateRawIngredient(RawIngredient ingredient) async {
    await database.update(
      PosDatabaseConstants.tableRawIngredients,
      {
        'name': ingredient.name.trim(),
        'storage_unit': ingredient.storageUnit.code,
        'current_stock': ingredient.currentStock,
        'low_stock_threshold': ingredient.lowStockThreshold,
        'cost_per_recipe_unit': ingredient.costPerRecipeUnit,
      },
      where: 'id = ?',
      whereArgs: [ingredient.id],
    );
    return ingredient;
  }

  Future<void> deleteRawIngredient(int id) async {
    await database.delete(
      PosDatabaseConstants.tableRawIngredients,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> adjustStock(int id, double quantityDelta) async {
    await database.rawUpdate('''
      UPDATE ${PosDatabaseConstants.tableRawIngredients}
      SET current_stock = current_stock + ?
      WHERE id = ?;
    ''', [quantityDelta, id]);
  }

  // ---------------------------------------------------------------------------
  // Bill of Materials (BOM) Recipe Engine
  // ---------------------------------------------------------------------------

  Future<List<RecipeItem>> getRecipeForMenuItem(int menuItemId) async {
    final rows = await database.rawQuery('''
      SELECT 
        r.*,
        i.name AS raw_ingredient_name,
        i.storage_unit,
        i.cost_per_recipe_unit
      FROM ${PosDatabaseConstants.tableRecipes} r
      JOIN ${PosDatabaseConstants.tableRawIngredients} i ON r.raw_ingredient_id = i.id
      WHERE r.menu_item_id = ?
      ORDER BY i.name ASC;
    ''', [menuItemId]);

    return rows.map((r) => RecipeItem.fromMap(r)).toList();
  }

  Future<RecipeItem> addOrUpdateRecipeItem({
    required int menuItemId,
    required int rawIngredientId,
    required double quantity,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    await database.rawInsert('''
      INSERT INTO ${PosDatabaseConstants.tableRecipes} 
        (menu_item_id, raw_ingredient_id, quantity_per_recipe_unit, created_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(menu_item_id, raw_ingredient_id) 
      DO UPDATE SET quantity_per_recipe_unit = excluded.quantity_per_recipe_unit;
    ''', [menuItemId, rawIngredientId, quantity, now]);

    final items = await getRecipeForMenuItem(menuItemId);
    return items.firstWhere((item) => item.rawIngredientId == rawIngredientId);
  }

  Future<void> removeRecipeItem({
    required int menuItemId,
    required int rawIngredientId,
  }) async {
    await database.delete(
      PosDatabaseConstants.tableRecipes,
      where: 'menu_item_id = ? AND raw_ingredient_id = ?',
      whereArgs: [menuItemId, rawIngredientId],
    );
  }

  Future<void> setRecipeForMenuItem({
    required int menuItemId,
    required List<({int rawIngredientId, double quantity})> items,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    await database.transaction((txn) async {
      await txn.delete(
        PosDatabaseConstants.tableRecipes,
        where: 'menu_item_id = ?',
        whereArgs: [menuItemId],
      );

      final batch = txn.batch();
      for (final item in items) {
        batch.insert(PosDatabaseConstants.tableRecipes, {
          'menu_item_id': menuItemId,
          'raw_ingredient_id': item.rawIngredientId,
          'quantity_per_recipe_unit': item.quantity,
          'created_at': now,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<double> calculateItemIngredientCost(int menuItemId) async {
    final recipe = await getRecipeForMenuItem(menuItemId);
    return recipe.fold<double>(0.0, (sum, item) => sum + item.totalIngredientCost);
  }

  // ---------------------------------------------------------------------------
  // Modifiers CRUD
  // ---------------------------------------------------------------------------

  Future<List<Modifier>> getModifiers({
    int? menuItemId,
    bool? activeOnly,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (menuItemId != null) {
      conditions.add('m.menu_item_id = ?');
      args.add(menuItemId);
    }
    if (activeOnly == true) {
      conditions.add('m.is_active = 1');
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final rows = await database.rawQuery('''
      SELECT 
        m.*,
        mi.name AS menu_item_name,
        i.name AS raw_ingredient_name,
        i.storage_unit
      FROM ${PosDatabaseConstants.tableModifiers} m
      LEFT JOIN ${PosDatabaseConstants.tableMenuItems} mi ON m.menu_item_id = mi.id
      LEFT JOIN ${PosDatabaseConstants.tableRawIngredients} i ON m.raw_ingredient_id = i.id
      $whereClause
      ORDER BY m.name ASC;
    ''', args);

    return rows.map((r) => Modifier.fromMap(r)).toList();
  }

  Future<Modifier> createModifier({
    int? menuItemId,
    required String name,
    double priceDelta = 0.0,
    int? rawIngredientId,
    double ingredientQtyDelta = 0.0,
    bool isActive = true,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableModifiers,
      {
        'menu_item_id': menuItemId,
        'name': name.trim(),
        'price_delta': priceDelta,
        'raw_ingredient_id': rawIngredientId,
        'ingredient_qty_delta': ingredientQtyDelta,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
      },
    );

    final rows = await database.rawQuery('''
      SELECT 
        m.*,
        mi.name AS menu_item_name,
        i.name AS raw_ingredient_name,
        i.storage_unit
      FROM ${PosDatabaseConstants.tableModifiers} m
      LEFT JOIN ${PosDatabaseConstants.tableMenuItems} mi ON m.menu_item_id = mi.id
      LEFT JOIN ${PosDatabaseConstants.tableRawIngredients} i ON m.raw_ingredient_id = i.id
      WHERE m.id = ?;
    ''', [id]);

    return Modifier.fromMap(rows.first);
  }

  Future<Modifier> updateModifier(Modifier modifier) async {
    await database.update(
      PosDatabaseConstants.tableModifiers,
      {
        'menu_item_id': modifier.menuItemId,
        'name': modifier.name.trim(),
        'price_delta': modifier.priceDelta,
        'raw_ingredient_id': modifier.rawIngredientId,
        'ingredient_qty_delta': modifier.ingredientQtyDelta,
        'is_active': modifier.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [modifier.id],
    );

    final rows = await database.rawQuery('''
      SELECT 
        m.*,
        mi.name AS menu_item_name,
        i.name AS raw_ingredient_name,
        i.storage_unit
      FROM ${PosDatabaseConstants.tableModifiers} m
      LEFT JOIN ${PosDatabaseConstants.tableMenuItems} mi ON m.menu_item_id = mi.id
      LEFT JOIN ${PosDatabaseConstants.tableRawIngredients} i ON m.raw_ingredient_id = i.id
      WHERE m.id = ?;
    ''', [modifier.id]);

    return Modifier.fromMap(rows.first);
  }

  Future<void> deleteModifier(int id) async {
    await database.delete(
      PosDatabaseConstants.tableModifiers,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleModifierActive(int id, bool isActive) async {
    await database.update(
      PosDatabaseConstants.tableModifiers,
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Pre-Approved Discount Presets CRUD
  // ---------------------------------------------------------------------------

  Future<List<DiscountPreset>> getDiscountPresets({bool? activeOnly}) async {
    String? where;
    List<Object?>? args;
    if (activeOnly == true) {
      where = 'is_active = 1';
    }

    final rows = await database.query(
      PosDatabaseConstants.tableDiscountPresets,
      where: where,
      whereArgs: args,
      orderBy: 'name ASC',
    );
    return rows.map((r) => DiscountPreset.fromMap(r)).toList();
  }

  Future<DiscountPreset> createDiscountPreset({
    required String name,
    required DiscountType type,
    required double value,
    bool isActive = true,
  }) async {
    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableDiscountPresets,
      {
        'name': name.trim(),
        'type': type.code,
        'value': value,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
      },
    );

    return DiscountPreset(
      id: id,
      name: name.trim(),
      type: type,
      value: value,
      isActive: isActive,
      createdAt: DateTime.parse(now),
    );
  }

  Future<DiscountPreset> updateDiscountPreset(DiscountPreset preset) async {
    await database.update(
      PosDatabaseConstants.tableDiscountPresets,
      {
        'name': preset.name.trim(),
        'type': preset.type.code,
        'value': preset.value,
        'is_active': preset.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [preset.id],
    );
    return preset;
  }

  Future<void> deleteDiscountPreset(int id) async {
    await database.delete(
      PosDatabaseConstants.tableDiscountPresets,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleDiscountPresetActive(int id, bool isActive) async {
    await database.update(
      PosDatabaseConstants.tableDiscountPresets,
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
