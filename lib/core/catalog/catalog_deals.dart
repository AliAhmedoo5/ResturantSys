part of 'catalog_and_recipe_controller.dart';

/// Deal definitions and Recipe Gate share the catalog's SQLite implementation.
mixin _DealCatalog {
  Database get database;
  Future<void> validateRecipe(int menuItemId, {DatabaseExecutor? executor});

  Future<Deal> createDeal({
    required String name,
    required double basePrice,
    bool isActive = true,
    List<DealItemDraft> items = const [],
  }) async {
    final now = CatalogAndRecipeController._formatTimestamp(DateTime.now());

    return await database.transaction((txn) async {
      final dealId = await txn.insert(
        PosDatabaseConstants.tableDeals,
        {
          'name': name.trim(),
          'base_price': basePrice,
          'is_active': isActive ? 1 : 0,
          'created_at': now,
        },
      );

      final createdDealItems = <DealItem>[];

      for (final itemDraft in items) {
        final itemId = await txn.insert(
          PosDatabaseConstants.tableDealItems,
          {
            'deal_id': dealId,
            'group_name': itemDraft.groupName.trim(),
            'category_id': itemDraft.categoryId,
            'default_menu_item_id': itemDraft.defaultMenuItemId,
            'is_upgradeable': itemDraft.isUpgradeable ? 1 : 0,
            'upgrade_price': itemDraft.upgradePrice,
          },
        );

        final createdOptions = <DealItemOption>[];
        for (final optDraft in itemDraft.options) {
          final optId = await txn.insert(
            PosDatabaseConstants.tableDealItemOptions,
            {
              'deal_item_id': itemId,
              'menu_item_id': optDraft.menuItemId,
              'is_default': optDraft.isDefault ? 1 : 0,
              'upgrade_price': optDraft.upgradePrice,
            },
          );

          createdOptions.add(DealItemOption(
            id: optId,
            dealItemId: itemId,
            menuItemId: optDraft.menuItemId,
            isDefault: optDraft.isDefault,
            upgradePrice: optDraft.upgradePrice,
          ));
        }

        createdDealItems.add(DealItem(
          id: itemId,
          dealId: dealId,
          groupName: itemDraft.groupName.trim(),
          categoryId: itemDraft.categoryId,
          defaultMenuItemId: itemDraft.defaultMenuItemId,
          isUpgradeable: itemDraft.isUpgradeable,
          upgradePrice: itemDraft.upgradePrice,
          options: createdOptions,
        ));
      }

      if (isActive) await validateDealRecipe(dealId, executor: txn);
      return Deal(
        id: dealId,
        name: name.trim(),
        basePrice: basePrice,
        isActive: isActive,
        createdAt: DateTime.parse(now),
        items: createdDealItems,
      );
    });
  }

  /// Atomic edit preserves the deal identity and committed order snapshots.
  Future<void> saveDeal({required int managerId, int? id, required String name,
    required double basePrice, required bool isActive, required List<DealItemDraft> items}) async {
    await database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      if (name.trim().isEmpty || !basePrice.isFinite || basePrice < 0 ||
          (basePrice * 100 - (basePrice * 100).round()).abs() > 0.000001) {
        throw ArgumentError('Enter a name and non-negative price with at most two decimal places.');
      }
      for (final slot in items) {
        if (slot.groupName.trim().isEmpty || slot.options.isEmpty ||
            slot.options.map((o) => o.menuItemId).toSet().length != slot.options.length ||
            slot.options.where((o) => o.isDefault).length != 1 ||
            slot.options.any((o) => !o.upgradePrice.isFinite || o.upgradePrice < 0 ||
              (o.upgradePrice * 100 - (o.upgradePrice * 100).round()).abs() > 0.000001)) {
          throw ArgumentError('Each component needs a name, unique choices, one default and valid upgrade prices.');
        }
      }
      final values = {'name': name.trim(), 'base_price': basePrice, 'is_active': isActive ? 1 : 0};
      final int dealId;
      if (id == null) {
        dealId = await txn.insert('deals', {...values, 'created_at': CatalogAndRecipeController._formatTimestamp(DateTime.now())});
      } else {
        if (await txn.update('deals', values, where: 'id = ?', whereArgs: [id]) != 1) throw StateError('Deal no longer exists.');
        dealId = id;
      }
      final existingSlots = await txn.query('deal_items', where: 'deal_id = ?', whereArgs: [dealId]);
      final existingIds = existingSlots.map((row) => row['id'] as int).toSet();
      final retainedIds = items.where((slot) => slot.id != null).map((slot) => slot.id!).toSet();
      if (!existingIds.containsAll(retainedIds) || items.where((slot) => slot.id != null).length != retainedIds.length) {
        throw StateError('Deal components changed. Reopen the deal editor.');
      }
      for (final removed in existingIds.difference(retainedIds)) {
        await txn.delete('deal_items', where: 'id = ?', whereArgs: [removed]);
      }
      for (final slot in items) {
        final slotValues = {'deal_id': dealId, 'group_name': slot.groupName.trim(), 'category_id': null,
          'default_menu_item_id': slot.options.singleWhere((o) => o.isDefault).menuItemId,
          'is_upgradeable': slot.options.any((o) => o.upgradePrice > 0) ? 1 : 0, 'upgrade_price': 0};
        final int slotId;
        if (slot.id == null) {
          slotId = await txn.insert('deal_items', slotValues);
        } else {
          slotId = slot.id!;
          await txn.update('deal_items', slotValues, where: 'id = ?', whereArgs: [slotId]);
          await txn.delete('deal_item_options', where: 'deal_item_id = ?', whereArgs: [slotId]);
        }
        for (final option in slot.options) {
          await txn.insert('deal_item_options', {'deal_item_id': slotId, 'menu_item_id': option.menuItemId,
            'is_default': option.isDefault ? 1 : 0, 'upgrade_price': option.upgradePrice});
        }
      }
      if (isActive) await validateDealRecipe(dealId, executor: txn);
    });
  }

  Future<List<Deal>> getDeals({bool? activeOnly}) async {
    String? where;
    if (activeOnly == true) {
      where = 'is_active = 1';
    }

    final dealRows = await database.query(
      PosDatabaseConstants.tableDeals,
      where: where,
      orderBy: 'name ASC',
    );

    final deals = <Deal>[];
    for (final row in dealRows) {
      final dealId = row['id'] as int;
      if (activeOnly == true) {
        try { await validateDealRecipe(dealId); } on StateError { continue; }
      }
      final dealItems = await _getDealItemsForDeal(dealId, database);
      deals.add(Deal.fromMap(row, items: dealItems));
    }
    return deals;
  }

  Future<void> validateDealRecipe(int dealId, {DatabaseExecutor? executor}) async {
    final db = executor ?? database;
    final slots = await _getDealItemsForDeal(dealId, db);
    if (slots.isEmpty) throw StateError('A published deal must contain at least one component.');
    for (final slot in slots) {
      final ids = {if (slot.defaultMenuItemId != null) slot.defaultMenuItemId!, ...slot.options.map((option) => option.menuItemId)};
      if (slot.categoryId != null) {
        final candidates = await db.query('menu_items', where: 'category_id = ? AND is_active = 1', whereArgs: [slot.categoryId]);
        ids.addAll(candidates.map((row) => row['id'] as int));
      }
      if (ids.isEmpty) throw StateError('Every deal component needs a recipe-backed menu item.');
      for (final id in ids) {
        final rows = await db.query('menu_items', where: 'id = ? AND is_active = 1', whereArgs: [id]);
        if (rows.isEmpty) throw StateError('Deal components must be active menu items.');
        await validateRecipe(id, executor: db);
      }
    }
  }

  Future<void> toggleDealActive(int id, bool active) async {
    await database.transaction((txn) async {
      if (active) await validateDealRecipe(id, executor: txn);
      await txn.update('deals', {'is_active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Deal> getDeal(int id) async {
    final dealRows = await database.query(
      PosDatabaseConstants.tableDeals,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (dealRows.isEmpty) {
      throw StateError('Deal with id $id not found.');
    }

    final dealItems = await _getDealItemsForDeal(id, database);
    return Deal.fromMap(dealRows.first, items: dealItems);
  }

  Future<List<DealItem>> _getDealItemsForDeal(int dealId, DatabaseExecutor executor) async {
    final itemRows = await executor.rawQuery('''
      SELECT di.*, mi.name as default_menu_item_name
      FROM ${PosDatabaseConstants.tableDealItems} di
      LEFT JOIN ${PosDatabaseConstants.tableMenuItems} mi ON di.default_menu_item_id = mi.id
      WHERE di.deal_id = ?
      ORDER BY di.id ASC;
    ''', [dealId]);

    final items = <DealItem>[];
    for (final row in itemRows) {
      final itemId = row['id'] as int;
      final optRows = await executor.rawQuery('''
        SELECT dio.*, mi.name as menu_item_name
        FROM ${PosDatabaseConstants.tableDealItemOptions} dio
        JOIN ${PosDatabaseConstants.tableMenuItems} mi ON dio.menu_item_id = mi.id
        WHERE dio.deal_item_id = ?
        ORDER BY dio.id ASC;
      ''', [itemId]);

      final options = optRows.map((o) => DealItemOption.fromMap(o)).toList();
      items.add(DealItem.fromMap(row, options: options));
    }
    return items;
  }

  Future<void> deleteDeal(int id) async {
    await database.delete(
      PosDatabaseConstants.tableDeals,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Revalidates the complete selection within the enclosing checkout transaction.
  Future<List<int>> validateDealSelection(int dealId, List<SelectedDealChoice> choices,
      {required DatabaseExecutor executor}) async {
    final componentIds = <int>[];
    final deals = await executor.query('deals', where: 'id = ? AND is_active = 1', whereArgs: [dealId]);
    if (deals.isEmpty) throw StateError('This deal is no longer active.');
    await validateDealRecipe(dealId, executor: executor);
    final slots = await _getDealItemsForDeal(dealId, executor);
    if (choices.length != slots.length || choices.map((c) => c.dealItemId).toSet().length != slots.length) throw StateError('Select exactly one option for each deal component.');
    for (final slot in slots) {
      final selected = choices.where((c) => c.dealItemId == slot.id);
      if (selected.length != 1) throw StateError('Missing deal component.');
      final choice = selected.single;
      final allowed = {if (slot.defaultMenuItemId != null) slot.defaultMenuItemId!, ...slot.options.map((o) => o.menuItemId)};
      if (slot.categoryId != null && slot.options.isEmpty) {
        final rows = await executor.query('menu_items', where: 'category_id = ? AND is_active = 1', whereArgs: [slot.categoryId]);
        allowed.addAll(rows.map((r) => r['id'] as int));
      }
      if (!allowed.contains(choice.menuItemId)) throw StateError('This menu item is not an allowed deal choice.');
      componentIds.add(choice.menuItemId);
    }
    return componentIds;
  }
}
