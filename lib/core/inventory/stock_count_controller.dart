import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../settings/managed_configuration.dart';

/// Counts reject intervening movements and require a fresh snapshot/recount.
/// Live stock is never overwritten from an old physical observation.
class StockCountController {
  StockCountController(this.database);
  final Database database;

  Future<List<Map<String, Object?>>> ingredients(int managerId) async {
    await requireManager(database, managerId);
    return database.query('raw_ingredients', orderBy: 'name');
  }

  Future<List<Map<String, Object?>>> sessions(int managerId) async {
    await requireManager(database, managerId);
    return database.rawQuery('''SELECT c.*, creator.name AS creator_name, approver.name AS approver_name
      FROM stock_counts c JOIN staff creator ON creator.id=c.created_by
      LEFT JOIN staff approver ON approver.id=c.approved_by ORDER BY c.id DESC''');
  }

  Future<List<Map<String, Object?>>> lines(int managerId, int id) async {
    await requireManager(database, managerId);
    return database.rawQuery('''SELECT l.*, r.name FROM stock_count_lines l
      JOIN raw_ingredients r ON r.id=l.ingredient_id WHERE count_id=? ORDER BY r.name''', [id]);
  }

  Future<int> start({required int managerId, required List<int> ingredientIds, required String reason}) =>
      database.transaction((txn) async {
    await requireManager(txn, managerId);
    if (ingredientIds.isEmpty || ingredientIds.toSet().length != ingredientIds.length || reason.trim().isEmpty) {
      throw ArgumentError('Select ingredients and enter a count reason.');
    }
    final id = await txn.insert('stock_counts', {'created_by': managerId,
      'created_at': DateTime.now().toIso8601String(), 'reason': reason.trim()});
    for (final ingredientId in ingredientIds) {
      final rows = await txn.query('raw_ingredients', where: 'id=?', whereArgs: [ingredientId]);
      if (rows.isEmpty) throw StateError('Ingredient no longer exists.');
      final r = rows.single;
      final sequence = await _sequence(txn, ingredientId);
      await txn.insert('stock_count_lines', {'count_id': id, 'ingredient_id': ingredientId,
        'expected': r['current_stock'], 'snapshot_sequence': sequence, 'unit': r['storage_unit']});
    }
    return id;
  });

  Future<void> submit({required int managerId, required int id, required Map<int, double> quantities}) =>
      database.transaction((txn) async {
    await requireManager(txn, managerId);
    await _status(txn, id, 'DRAFT');
    final rows = await txn.query('stock_count_lines', where: 'count_id=?', whereArgs: [id]);
    if (quantities.length != rows.length) throw ArgumentError('Count every selected ingredient.');
    for (final row in rows) {
      final ingredientId = row['ingredient_id'] as int;
      final quantity = quantities[ingredientId];
      if (quantity == null || !quantity.isFinite || quantity < 0) throw ArgumentError('Enter finite, non-negative physical quantities.');
      await _fresh(txn, row);
      final variance = quantity - (row['expected'] as num).toDouble();
      final ingredient = (await txn.query('raw_ingredients', where: 'id=?', whereArgs: [ingredientId])).single;
      final cost = (ingredient['cost_per_recipe_unit'] as num?)?.toDouble();
      // Recipe cost is per gram for kg storage; preserve unknown cost as null.
      final costFactor = row['unit'] == 'kg' ? 1000 : 1;
      await txn.update('stock_count_lines', {'counted': quantity, 'variance': variance,
        'estimated_cost_paisa': cost == null || cost <= 0 ? null : (variance * costFactor * cost * 100).round()},
        where: 'count_id=? AND ingredient_id=?', whereArgs: [id, ingredientId]);
    }
    await txn.update('stock_counts', {'status': 'SUBMITTED', 'submitted_by': managerId, 'submitted_at': DateTime.now().toIso8601String()}, where: 'id=?', whereArgs: [id]);
  });

  Future<void> review({required int managerId, required int id, required bool approve}) => database.transaction((txn) async {
    await requireManager(txn, managerId);
    await _status(txn, id, 'SUBMITTED');
    await txn.update('stock_counts', {'status': approve ? 'APPROVED' : 'REJECTED',
      'approved_by': managerId, 'approved_at': DateTime.now().toIso8601String()}, where: 'id=?', whereArgs: [id]);
  });

  Future<void> post({required int managerId, required int id}) => database.transaction((txn) async {
    await requireManager(txn, managerId);
    final count = (await txn.query('stock_counts', where: 'id=?', whereArgs: [id])).single;
    if (count['status'] == 'POSTED') return; // Safe retry; one adjusting event per line.
    await _status(txn, id, 'APPROVED');
    final rows = await txn.query('stock_count_lines', where: 'count_id=?', whereArgs: [id]);
    for (final row in rows) {
      await _fresh(txn, row);
      final ingredientId = row['ingredient_id'] as int;
      await txn.rawUpdate('UPDATE raw_ingredients SET current_stock=current_stock+? WHERE id=?', [row['variance'], ingredientId]);
      if ((row['variance'] as num) != 0) {
        await txn.update('stock_count_lines', {'movement_id': await _sequence(txn, ingredientId)},
          where: 'count_id=? AND ingredient_id=?', whereArgs: [id, ingredientId]);
      }
    }
    await txn.update('stock_counts', {'status': 'POSTED', 'posted_by': managerId, 'posted_at': DateTime.now().toIso8601String()}, where: 'id=?', whereArgs: [id]);
  });

  Future<int> _sequence(DatabaseExecutor txn, int ingredientId) async =>
    (await txn.rawQuery('SELECT COALESCE(MAX(id),0) AS seq FROM inventory_movements WHERE ingredient_id=?', [ingredientId])).single['seq'] as int;

  Future<void> _fresh(DatabaseExecutor txn, Map<String, Object?> row) async {
    final live = await txn.query('raw_ingredients', columns: ['storage_unit'], where: 'id=?', whereArgs: [row['ingredient_id']]);
    if (live.isEmpty || live.single['storage_unit'] != row['unit'] ||
        await _sequence(txn, row['ingredient_id'] as int) != row['snapshot_sequence']) {
      throw StateError('Stock or its storage unit changed after the snapshot. Start a new count and recount this selection.');
    }
  }

  Future<void> _status(DatabaseExecutor txn, int id, String expected) async {
    final rows = await txn.query('stock_counts', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty || rows.single['status'] != expected) throw StateError('Count must be $expected.');
  }
}
