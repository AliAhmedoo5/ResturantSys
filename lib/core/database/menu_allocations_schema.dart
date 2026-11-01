import 'package:sqflite_common/sqlite_api.dart';
import 'pos_database_constants.dart';

/// Database schema migration for Ticket #88 governed by ADR-0021.
///
/// Creates table `order_item_allocations` and enforces append-only immutability.
Future<void> createMenuAllocationsSchema(DatabaseExecutor db) async {
  final existing = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
    [PosDatabaseConstants.tableOrderItemAllocations],
  );
  if (existing.isNotEmpty) {
    final sql = (existing.first['sql'] as String?) ?? '';
    if (sql.contains('REFERENCES ${PosDatabaseConstants.tableMenuItems}') ||
        sql.contains('REFERENCES menu_items') ||
        sql.contains('REFERENCES ${PosDatabaseConstants.tableDeals}') ||
        sql.contains('REFERENCES deals')) {
      await db.execute('''
        CREATE TABLE order_item_allocations_migration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
          order_item_id INTEGER,
          revision INTEGER NOT NULL DEFAULT 0,
          line_kind TEXT NOT NULL CHECK(line_kind IN ('ITEM', 'DEAL_PARENT', 'DEAL_COMPONENT')),
          entry_type TEXT NOT NULL CHECK(entry_type IN ('SALE', 'CONTRA')),
          menu_item_id INTEGER,
          deal_id INTEGER,
          component_menu_item_id INTEGER,
          item_name_snapshot TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          gross_sales_paisa INTEGER NOT NULL,
          allocated_discount_paisa INTEGER NOT NULL,
          net_sales_paisa INTEGER NOT NULL,
          tax_carve_out_paisa INTEGER NOT NULL,
          bom_recipe_cost_paisa INTEGER,
          contribution_margin_paisa INTEGER,
          recorded_at TEXT NOT NULL
        );
      ''');
      await db.execute('INSERT INTO order_item_allocations_migration SELECT * FROM ${PosDatabaseConstants.tableOrderItemAllocations};');
      await db.execute('DROP TABLE ${PosDatabaseConstants.tableOrderItemAllocations};');
      await db.execute('ALTER TABLE order_item_allocations_migration RENAME TO ${PosDatabaseConstants.tableOrderItemAllocations};');
    }
  }

  await db.execute('''
    CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrderItemAllocations} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
      order_item_id INTEGER,
      revision INTEGER NOT NULL DEFAULT 0,
      line_kind TEXT NOT NULL CHECK(line_kind IN ('ITEM', 'DEAL_PARENT', 'DEAL_COMPONENT')),
      entry_type TEXT NOT NULL CHECK(entry_type IN ('SALE', 'CONTRA')),
      menu_item_id INTEGER,
      deal_id INTEGER,
      component_menu_item_id INTEGER,
      item_name_snapshot TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      gross_sales_paisa INTEGER NOT NULL,
      allocated_discount_paisa INTEGER NOT NULL,
      net_sales_paisa INTEGER NOT NULL,
      tax_carve_out_paisa INTEGER NOT NULL,
      bom_recipe_cost_paisa INTEGER,
      contribution_margin_paisa INTEGER,
      recorded_at TEXT NOT NULL
    );
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_order_item_allocations_order 
    ON ${PosDatabaseConstants.tableOrderItemAllocations}(order_id);
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_order_item_allocations_item 
    ON ${PosDatabaseConstants.tableOrderItemAllocations}(menu_item_id);
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_order_item_allocations_deal 
    ON ${PosDatabaseConstants.tableOrderItemAllocations}(deal_id);
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_order_item_allocations_comp 
    ON ${PosDatabaseConstants.tableOrderItemAllocations}(component_menu_item_id);
  ''');

  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_order_item_allocations_kind 
    ON ${PosDatabaseConstants.tableOrderItemAllocations}(line_kind, entry_type);
  ''');

  // Enforce append-only immutability: No UPDATE or DELETE allowed
  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ${PosDatabaseConstants.tableOrderItemAllocations}_no_$operation
      BEFORE $operation ON ${PosDatabaseConstants.tableOrderItemAllocations}
      BEGIN
        SELECT RAISE(ABORT, 'Order item allocations are immutable');
      END;
    ''');
  }
}
