import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/staff_role.dart';

class DeliveryArea {
  DeliveryArea.fromMap(Map<String, Object?> row)
      : id = row['id'] as int,
        name = row['name'] as String,
        code = row['code'] as String? ?? '',
        coverageDescription = row['coverage_description'] as String? ?? '',
        deliveryFeePaisa = row['delivery_fee_paisa'] as int,
        minOrderPaisa = row['min_order_paisa'] as int,
        isActive = row['is_active'] == 1,
        isArchived = row['archived_at'] != null;
  final int id, deliveryFeePaisa, minOrderPaisa;
  final String name, code, coverageDescription;
  final bool isActive, isArchived;
}

/// Manager configuration and the counter's read-only delivery area directory.
class DeliveryController {
  DeliveryController({required this.database});
  final Database database;

  Future<void> _requireManager(DatabaseExecutor db, int staffId) async {
    final rows = await db.query('staff', where: 'id = ? AND is_active = 1', whereArgs: [staffId]);
    if (rows.isEmpty || StaffRole.fromCode(rows.single['role'] as String) != StaffRole.manager) {
      throw StateError('Only an active Manager can configure delivery areas and fees.');
    }
  }

  Future<List<DeliveryArea>> getAreas({bool activeOnly = false, bool includeArchived = false}) async {
    final rows = await database.query('delivery_areas',
      where: [if (!includeArchived || activeOnly) 'archived_at IS NULL', if (activeOnly) 'is_active = 1'].join(' AND ').isEmpty
          ? null : [if (!includeArchived || activeOnly) 'archived_at IS NULL', if (activeOnly) 'is_active = 1'].join(' AND '),
      orderBy: 'name COLLATE NOCASE, id');
    return rows.map(DeliveryArea.fromMap).toList();
  }

  Future<DeliveryArea> saveArea({required int staffId, int? id, required String name, required String code,
    String coverageDescription = '', required int deliveryFeePaisa, int minOrderPaisa = 0, bool isActive = true}) async {
    return database.transaction((txn) async {
      await _requireManager(txn, staffId);
      if (name.trim().isEmpty || code.trim().isEmpty || deliveryFeePaisa < 0 || minOrderPaisa < 0) {
        throw ArgumentError('Enter a name, code and non-negative integer paisa amounts.');
      }
      final now = DateTime.now().toIso8601String();
      final values = <String, Object?>{'name': name.trim(), 'code': code.trim().toUpperCase(),
        'coverage_description': coverageDescription.trim(), 'delivery_fee_paisa': deliveryFeePaisa,
        'min_order_paisa': minOrderPaisa, 'is_active': isActive ? 1 : 0, 'updated_at': now};
      final int savedId;
      if (id == null) {
        savedId = await txn.insert('delivery_areas', {...values, 'created_at': now});
      } else {
        if (await txn.update('delivery_areas', values, where: 'id = ? AND archived_at IS NULL', whereArgs: [id]) != 1) {
          throw StateError('Delivery area is archived or no longer exists.');
        }
        savedId = id;
      }
      return DeliveryArea.fromMap((await txn.query('delivery_areas', where: 'id = ?', whereArgs: [savedId])).single);
    });
  }

  Future<void> archiveArea({required int staffId, required int id}) async {
    await database.transaction((txn) async {
      await _requireManager(txn, staffId);
      final now = DateTime.now().toIso8601String();
      if (await txn.update('delivery_areas', {'archived_at': now, 'updated_at': now, 'is_active': 0},
          where: 'id = ? AND archived_at IS NULL', whereArgs: [id]) != 1) {
        throw StateError('Delivery area is archived or no longer exists.');
      }
    });
  }
}
