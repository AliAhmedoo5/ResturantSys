import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Catalog deletion may detach nullable references from a saved receipt. It
/// cannot change the receipt itself or bypass the closed Business Day boundary.
Future<void> createCatalogDeletionGuard(DatabaseExecutor db) async {
  // Group ownership cascades from menu_items, but modifiers.group_id uses
  // RESTRICT. Remove owned options first so cascade ordering cannot block a
  // menu item (or its category) from being deleted. A failed parent deletion
  // rolls this trigger's work back with the same SQLite statement.
  await db.execute('''CREATE TRIGGER IF NOT EXISTS menu_item_delete_modifiers
    BEFORE DELETE ON menu_items
    BEGIN DELETE FROM modifiers WHERE menu_item_id=OLD.id; END''');
  final columns = await db.rawQuery('PRAGMA table_info(order_items)');
  final unchanged = columns
      .map((column) => column['name'] as String)
      .where((name) => name != 'menu_item_id' && name != 'deal_id')
      .map((name) => 'NEW."$name" IS OLD."$name"')
      .join(' AND ');
  // Recreate this guard after any future migration that adds receipt columns.
  await db.execute('DROP TRIGGER IF EXISTS closed_order_items_UPDATE');
  await db.execute('''CREATE TRIGGER closed_order_items_UPDATE
    BEFORE UPDATE ON order_items
    WHEN EXISTS (SELECT 1 FROM orders o JOIN business_days b ON b.id=o.business_day_id
                 WHERE o.id=OLD.order_id AND b.status='CLOSED')
      OR EXISTS (SELECT 1 FROM orders o JOIN business_days b ON b.id=o.business_day_id
                 WHERE o.id=NEW.order_id AND b.status='CLOSED')
    BEGIN
      SELECT CASE WHEN NOT (
        $unchanged
        AND (NEW.menu_item_id IS OLD.menu_item_id OR
          (NEW.menu_item_id IS NULL AND NOT EXISTS
            (SELECT 1 FROM menu_items WHERE id=OLD.menu_item_id)))
        AND (NEW.deal_id IS OLD.deal_id OR
          (NEW.deal_id IS NULL AND NOT EXISTS
            (SELECT 1 FROM deals WHERE id=OLD.deal_id)))
      ) THEN RAISE(ABORT, 'Business Day is permanently closed') END;
    END''');
}
