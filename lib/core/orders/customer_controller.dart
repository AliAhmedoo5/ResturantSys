import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../delivery/delivery_controller.dart';

class Customer {
  Customer.fromMap(Map<String, Object?> row)
      : id = row['id'] as int, name = row['name'] as String,
        phone = row['phone'] as String, notes = row['notes'] as String;
  final int id;
  final String name, phone, notes;
}

/// Customer identity is independent of immutable order and address snapshots.
class CustomerController {
  CustomerController(this.database);
  final Database database;

  static Future<void> requireRole(DatabaseExecutor db, int staffId, {bool manager = false}) async {
    final rows = await db.query('staff', where: 'id = ? AND is_active = 1 AND login_enabled = 1', whereArgs: [staffId]);
    if (rows.isEmpty || (manager && rows.single['role'] != 'MANAGER') ||
        (!manager && !['MANAGER', 'CASHIER'].contains(rows.single['role']))) {
      throw StateError('An active ${manager ? 'Manager' : 'POS staff member'} is required.');
    }
  }

  Future<List<Customer>> search(String query) async {
    final phone = DeliveryController.normalizePhone(query);
    final rows = await database.rawQuery('''SELECT DISTINCT c.* FROM customers c
      LEFT JOIN customers alias ON alias.merged_into = c.id
      WHERE c.merged_into IS NULL AND (c.name LIKE ? OR c.phone LIKE ? OR alias.phone LIKE ?)
      ORDER BY c.name COLLATE NOCASE LIMIT 100''',
      ['%${query.trim()}%', phone.isEmpty ? '' : '%$phone%', phone.isEmpty ? '' : '%$phone%']);
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer> save({required int staffId, int? id, required String name,
    required String phone, String notes = ''}) async {
    return database.transaction((txn) async {
      await requireRole(txn, staffId);
      final normalized = DeliveryController.normalizePhone(phone);
      if (name.trim().isEmpty || normalized.length < 7) throw ArgumentError('Enter a name and valid phone.');
      final duplicates = await txn.query('customers', where: 'phone = ? AND id != ?', whereArgs: [normalized, id ?? -1]);
      if (duplicates.isNotEmpty) throw StateError('Phone already belongs to an existing customer. Select that record.');
      final values = {'name': name.trim(), 'phone': normalized, 'notes': notes.trim()};
      final int savedId;
      if (id == null) {
        savedId = await txn.insert('customers', {...values, 'created_at': DateTime.now().toIso8601String()});
      } else {
        if (await txn.update('customers', values, where: 'id = ? AND merged_into IS NULL', whereArgs: [id]) != 1) {
          throw StateError('Customer was merged or removed. Refresh the directory.');
        }
        savedId = id;
      }
      return Customer.fromMap((await txn.query('customers', where: 'id = ?', whereArgs: [savedId])).single);
    });
  }

  Future<void> merge({required int managerId, required int sourceId, required int targetId, required String reason}) async {
    await database.transaction((txn) async {
      await requireRole(txn, managerId, manager: true);
      if (sourceId == targetId || reason.trim().isEmpty) throw ArgumentError('Select different customers and enter a merge reason.');
      final rows = await txn.query('customers', where: 'id IN (?, ?) AND merged_into IS NULL', whereArgs: [sourceId, targetId]);
      if (rows.length != 2) throw StateError('Both customers must be active. Refresh the directory.');
      // Flatten aliases so repeated merges stay searchable without rewriting orders.
      await txn.update('customers', {'merged_into': targetId}, where: 'id = ? OR merged_into = ?', whereArgs: [sourceId, sourceId]);
      await txn.insert('customer_merges', {'source_id': sourceId, 'target_id': targetId,
        'manager_id': managerId, 'reason': reason.trim(), 'created_at': DateTime.now().toIso8601String()});
    });
  }

  Future<List<Map<String, Object?>>> history(int customerId) => database.rawQuery('''
    SELECT o.* FROM orders o WHERE o.customer_id IN
      (SELECT id FROM customers WHERE id = ? OR merged_into = ?)
      OR o.id IN (SELECT order_id FROM customer_order_links WHERE customer_id IN
        (SELECT id FROM customers WHERE id = ? OR merged_into = ?))
    ORDER BY o.id DESC LIMIT 100''', [customerId, customerId, customerId, customerId]);
}
