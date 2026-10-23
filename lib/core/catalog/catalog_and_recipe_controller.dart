import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/pos_database_constants.dart';
import 'catalog_media_service.dart';
import 'catalog_photo_change.dart';
import 'discount_preset.dart';
import 'menu_category.dart';
import 'menu_item.dart';
import 'modifier.dart';
import 'modifier_group.dart';
import 'raw_ingredient.dart';
import 'recipe_item.dart';
import 'storage_unit.dart';

/// Domain controller managing Menu Categories, Menu Items with tax-inclusive pricing,
/// Raw Ingredients, Recipe Bill of Materials (BOM), Modifiers, Pre-Approved Discounts,
/// and Catalog Media Storage.
class CatalogAndRecipeController {
  CatalogAndRecipeController({
    required this.database,
    CatalogMediaService? mediaService,
  }) : mediaService = mediaService ?? CatalogMediaService(database: database);

  final Database database;
  final CatalogMediaService mediaService;

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

    final items = <MenuItem>[];
    for (final row in rows) {
      if (activeOnly == true) {
        try { await validateRecipe(row['id'] as int); } on StateError { continue; }
      }
      items.add(MenuItem.fromMap(row, categoryName: row['category_name'] as String?));
    }
    return items;
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
    bool isActive = false,
    CatalogPhotoChange? photoChange,
  }) async {
    if (isActive) throw StateError("Save a draft and configure its recipe before activation.");
    final now = _formatTimestamp(DateTime.now());
    final id = await mediaService.saveEntityWithPhoto(
      entityType: 'menu_item',
      photoChange: photoChange,
      saveEntity: (executor) => executor.insert(
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
      ),
    );

    return getMenuItem(id);
  }

  Future<MenuItem> updateMenuItem(MenuItem item, {CatalogPhotoChange? photoChange}) async {
    await mediaService.saveEntityWithPhoto(
      entityType: 'menu_item',
      photoChange: photoChange,
      saveEntity: (txn) async {
        if (item.isActive) await validateRecipe(item.id, executor: txn);
        await txn.update(
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
        return item.id;
      },
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
    final rows = await (executor ?? database).rawQuery('SELECT r.*, i.id AS ingredient_exists FROM recipes r LEFT JOIN raw_ingredients i ON i.id = r.raw_ingredient_id WHERE r.menu_item_id = ?', [menuItemId]);
    if (rows.isEmpty || rows.any((row) {
      final qty = (row['quantity_per_recipe_unit'] as num).toDouble();
      return row['ingredient_exists'] == null || !qty.isFinite || qty <= 0;
    })) {
      throw StateError('Recipe required: configure a complete positive BOM before activation.');
    }
  }

  Future<void> toggleMenuItemActive(int id, bool isActive) async {
    await database.transaction((txn) async {
      if (isActive) await validateRecipe(id, executor: txn);
      await txn.update(PosDatabaseConstants.tableMenuItems, {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    });
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
    if (!quantity.isFinite || quantity <= 0) throw ArgumentError("Recipe quantities must be positive and finite.");
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
    await database.transaction((txn) async {
      await txn.delete('recipes', where: 'menu_item_id = ? AND raw_ingredient_id = ?', whereArgs: [menuItemId, rawIngredientId]);
      final remaining = await txn.query('recipes', where: 'menu_item_id = ?', whereArgs: [menuItemId]);
      if (remaining.isEmpty) await txn.update('menu_items', {'is_active': 0}, where: 'id = ?', whereArgs: [menuItemId]);
    });
  }

  Future<void> setRecipeForMenuItem({
    required int menuItemId,
    required List<({int rawIngredientId, double quantity})> items,
  }) async {
    for (final item in items) {
      if (!item.quantity.isFinite || item.quantity <= 0) throw ArgumentError('Recipe quantities must be positive and finite.');
    }
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
      if (items.isEmpty) await txn.update('menu_items', {'is_active': 0}, where: 'id = ?', whereArgs: [menuItemId]);
    });
  }

  Future<double> calculateItemIngredientCost(int menuItemId) async {
    final recipe = await getRecipeForMenuItem(menuItemId);
    return recipe.fold<double>(0.0, (sum, item) => sum + item.totalIngredientCost);
  }

  // ---------------------------------------------------------------------------
  // Modifiers CRUD
  // ---------------------------------------------------------------------------

  Future<List<ModifierGroup>> getModifierGroups({int? menuItemId, DatabaseExecutor? executor}) async {
    final rows = await (executor ?? database).query('modifier_groups', where: menuItemId == null ? null : 'menu_item_id = ?', whereArgs: menuItemId == null ? null : [menuItemId], orderBy: 'id');
    return rows.map(ModifierGroup.fromMap).toList();
  }

  Future<ModifierGroup> createModifierGroup({required int menuItemId, required String name, String selectionMode = 'SINGLE', int minSelected = 0, int maxSelected = 1, bool isRequired = false}) async {
    final group = ModifierGroup(id: 0, menuItemId: menuItemId, name: name, selectionMode: selectionMode, minSelected: minSelected, maxSelected: maxSelected, isRequired: isRequired);
    group.validate();
    final id = await database.insert('modifier_groups', group.toMap());
    return ModifierGroup.fromMap({'id': id, ...group.toMap()});
  }

  Future<void> updateModifierGroup(ModifierGroup group) async {
    group.validate();
    await database.transaction((txn) async {
      final options = await txn.query('modifiers', where: 'group_id = ? AND menu_item_id != ?', whereArgs: [group.id, group.menuItemId]);
      if (options.isNotEmpty) throw StateError('A group cannot move away from its modifier menu item.');
      await txn.update('modifier_groups', group.toMap(), where: 'id = ?', whereArgs: [group.id]);
    });
  }

  Future<void> _validateModifier({required DatabaseExecutor executor, int? menuItemId, int? groupId, int? rawIngredientId, required double quantity, required double price}) async {
    if (!quantity.isFinite || !price.isFinite || (rawIngredientId == null && quantity != 0)) throw ArgumentError('Modifier deltas must be finite and reference an ingredient.');
    if (groupId != null) {
      final rows = await executor.query('modifier_groups', where: 'id = ? AND menu_item_id = ?', whereArgs: [groupId, menuItemId]);
      if (rows.isEmpty) throw StateError('The modifier group must belong to the same menu item.');
    }
  }

  Future<Modifier> _modifierFromRow(Map<String, Object?> row, DatabaseExecutor executor) async {
    ModifierGroup? group;
    if (row['group_id'] != null) {
      final groups = await executor.query('modifier_groups', where: 'id = ?', whereArgs: [row['group_id']]);
      if (groups.isNotEmpty) group = ModifierGroup.fromMap(groups.first);
    }
    return Modifier.fromMap(row, group: group);
  }

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

    return Future.wait(rows.map((r) => _modifierFromRow(r, database)));
  }

  Future<Modifier> createModifier({
    int? menuItemId,
    int? groupId,
    required String name,
    double priceDelta = 0.0,
    int? rawIngredientId,
    double ingredientQtyDelta = 0.0,
    bool isActive = true,
  }) async {
    await _validateModifier(executor: database, menuItemId: menuItemId, groupId: groupId, rawIngredientId: rawIngredientId, quantity: ingredientQtyDelta, price: priceDelta);
    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableModifiers,
      {
        'menu_item_id': menuItemId,
        'group_id': groupId,
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

    return _modifierFromRow(rows.first, database);
  }

  Future<Modifier> updateModifier(Modifier modifier) async {
    await _validateModifier(executor: database, menuItemId: modifier.menuItemId, groupId: modifier.groupId, rawIngredientId: modifier.rawIngredientId, quantity: modifier.ingredientQtyDelta, price: modifier.priceDelta);
    await database.update(
      PosDatabaseConstants.tableModifiers,
      {
        'menu_item_id': modifier.menuItemId,
        'group_id': modifier.groupId,
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

    return _modifierFromRow(rows.first, database);
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
