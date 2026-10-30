import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('order_item_allocations schema & immutability triggers', () {
    test('table and triggers are created, and modifications are strictly rejected', () async {
      final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      final db = await store.initialize();
      addTearDown(store.close);

      // Verify table exists
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [PosDatabaseConstants.tableOrderItemAllocations],
      );
      expect(tables, isNotEmpty, reason: 'order_item_allocations table must exist');

      // Create a test business day, shift, and order to satisfy foreign keys
      final staff = (await db.query('staff')).first;
      final dayId = await db.insert('business_days', {
        'opened_at': '2026-10-30 10:00:00',
        'status': 'OPEN',
        'opened_by_staff_id': staff['id'],
      });
      final shiftId = await db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': staff['id'],
        'opened_at': '2026-10-30 10:00:00',
        'opening_float': 1000,
        'status': 'OPEN',
      });
      final orderId = await db.insert('orders', {
        'business_day_id': dayId,
        'shift_id': shiftId,
        'cashier_id': staff['id'],
        'token_number': 1,
        'dining_type': 'TAKEAWAY',
        'subtotal': 100,
        'grand_total': 100,
        'payment_status': 'SETTLED',
        'created_at': '2026-10-30 10:30:00',
      });

      // Insert an allocation record
      final allocId = await db.insert(PosDatabaseConstants.tableOrderItemAllocations, {
        'order_id': orderId,
        'order_item_id': null,
        'revision': 0,
        'line_kind': 'ITEM',
        'entry_type': 'SALE',
        'menu_item_id': null,
        'deal_id': null,
        'component_menu_item_id': null,
        'item_name_snapshot': 'Test Burger',
        'quantity': 1,
        'gross_sales_paisa': 65000,
        'allocated_discount_paisa': 5000,
        'net_sales_paisa': 60000,
        'tax_carve_out_paisa': 0,
        'bom_recipe_cost_paisa': 25000,
        'contribution_margin_paisa': 35000,
        'recorded_at': '2026-10-30 10:30:00',
      });
      expect(allocId, isPositive);

      // Attempting to UPDATE the allocation record MUST fail
      expect(
        () => db.update(
          PosDatabaseConstants.tableOrderItemAllocations,
          {'net_sales_paisa': 50000},
          where: 'id = ?',
          whereArgs: [allocId],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('Order item allocations are immutable'),
        )),
      );

      // Attempting to DELETE the allocation record MUST fail
      expect(
        () => db.delete(
          PosDatabaseConstants.tableOrderItemAllocations,
          where: 'id = ?',
          whereArgs: [allocId],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('Order item allocations are immutable'),
        )),
      );
    });
  });
}
