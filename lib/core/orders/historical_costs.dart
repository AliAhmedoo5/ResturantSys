import 'dart:math' as math;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Records the configured acquisition rate at consumption. Returns release the
/// original lots (latest first); later purchases never reprice earlier food.
class HistoricalCosts {
  static Future<void> consume(DatabaseExecutor txn, int orderId, int revision, Map<int, double> quantities) async {
    for (final entry in quantities.entries.where((e) => e.value > 0)) {
      final row = (await txn.query('raw_ingredients', where: 'id=?', whereArgs: [entry.key])).single;
      final rate = (row['cost_per_recipe_unit'] as num?)?.toDouble();
      final known = rate != null && rate.isFinite && rate > 0;
      await txn.insert('order_cost_events', {'order_id': orderId, 'ingredient_id': entry.key,
        'revision': revision, 'kind': 'CONSUME', 'quantity': entry.value,
        'unit_cost_rupees': known ? rate : null, 'cost_paisa': known ? (entry.value * rate * 100).round() : null,
        'recorded_at': DateTime.now().toIso8601String()});
    }
  }

  static Future<void> remove(DatabaseExecutor txn, int orderId, int revision, Map<int, double> quantities, {required bool restock}) async {
    // Legacy orders stay uncovered; no invented cost is assigned to old sales.
    if ((await txn.query('order_cost_coverage', where: 'order_id=?', whereArgs: [orderId])).isEmpty) return;
    for (final entry in quantities.entries.where((e) => e.value > 0)) {
      var remaining = entry.value;
      final lots = await txn.rawQuery('''SELECT c.*,
        COALESCE((SELECT SUM(r.quantity) FROM order_cost_events r WHERE r.source_event_id=c.id),0) removed,
        COALESCE((SELECT SUM(r.cost_paisa) FROM order_cost_events r WHERE r.source_event_id=c.id),0) removed_cost
        FROM order_cost_events c WHERE c.order_id=? AND c.ingredient_id=? AND c.kind='CONSUME' ORDER BY c.id DESC''', [orderId, entry.key]);
      for (final lot in lots) {
        final available = (lot['quantity'] as num).toDouble() - (lot['removed'] as num).toDouble();
        if (available <= 0.00000001) continue;
        final take = math.min(remaining, available);
        final rate = (lot['unit_cost_rupees'] as num?)?.toDouble();
        // Exhausting a lot releases its exact remaining paisa, avoiding drift.
        final cost = rate == null ? null : (take - available).abs() < 0.00000001
          ? (lot['cost_paisa'] as int) - (lot['removed_cost'] as num).toInt() : (take * rate * 100).round();
        await txn.insert('order_cost_events', {'order_id': orderId, 'ingredient_id': entry.key,
          'revision': revision, 'kind': restock ? 'RETURN' : 'COOKED_WASTE', 'quantity': take,
          'unit_cost_rupees': rate, 'cost_paisa': cost, 'source_event_id': lot['id'],
          'recorded_at': DateTime.now().toIso8601String()});
        remaining -= take;
        if (remaining < 0.00000001) break;
      }
      if (remaining > 0.00000001) throw StateError('Historical cost quantities do not reconcile.');
    }
  }
}
