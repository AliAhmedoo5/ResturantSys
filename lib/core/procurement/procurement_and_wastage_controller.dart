import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'desi_unit.dart';
import 'kitchen_wastage.dart';
import 'mandi_procurement.dart';
import 'wastage_reason.dart';

/// Domain controller managing traditional wholesale Mandi procurements,
/// recipe-unit cost recalculations, and staff-authenticated kitchen wastage logs.
class ProcurementAndWastageController {
  ProcurementAndWastageController({
    required this.database,
    this.authService,
  });

  final Database database;
  final AuthService? authService;

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  // ===========================================================================
  // MANDI PROCUREMENT
  // ===========================================================================

  /// Records a wholesale procurement entry using traditional Desi units,
  /// auto-calculating recipe-unit cost and updating stock balance immediately.
  Future<MandiProcurement> recordMandiPurchase({
    required int rawIngredientId,
    required DesiUnit unit,
    required double quantity,
    required double totalCost,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Purchased quantity must be greater than zero.');
    }
    if (totalCost <= 0) {
      throw ArgumentError('Total amount paid must be greater than zero.');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    return await database.transaction((txn) async {
      // 1. Fetch raw ingredient
      final ingredientRows = await txn.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [rawIngredientId],
      );

      if (ingredientRows.isEmpty) {
        throw StateError('Raw ingredient with id $rawIngredientId not found.');
      }

      final ingredient = RawIngredient.fromMap(ingredientRows.first);

      // 2. Calculate converted recipe units & unit cost
      final convertedQty = unit.toRecipeUnits(quantity, ingredient.storageUnit);
      if (convertedQty <= 0) {
        throw StateError('Converted quantity must be greater than zero.');
      }
      final costPerRecipeUnit = totalCost / convertedQty;

      // 3. Update stock balance and cost per recipe unit
      await txn.rawUpdate('''
        UPDATE ${PosDatabaseConstants.tableRawIngredients}
        SET current_stock = current_stock + ?,
            cost_per_recipe_unit = ?
        WHERE id = ?;
      ''', [convertedQty, costPerRecipeUnit, rawIngredientId]);

      // 4. Insert Mandi procurement record
      final id = await txn.insert(
        PosDatabaseConstants.tableMandiProcurements,
        {
          'raw_ingredient_id': rawIngredientId,
          'traditional_unit': unit.code,
          'quantity': quantity,
          'total_cost': totalCost,
          'converted_quantity': convertedQty,
          'cost_per_recipe_unit': costPerRecipeUnit,
          'notes': notes?.trim(),
          'created_at': formattedNow,
        },
      );

      return MandiProcurement(
        id: id,
        rawIngredientId: rawIngredientId,
        rawIngredientName: ingredient.name,
        traditionalUnit: unit,
        quantity: quantity,
        totalCost: totalCost,
        convertedQuantity: convertedQty,
        costPerRecipeUnit: costPerRecipeUnit,
        storageUnit: ingredient.storageUnit,
        notes: notes?.trim(),
        createdAt: now,
      );
    });
  }

  /// Retrieves recorded Mandi procurements ordered chronologically descending.
  Future<List<MandiProcurement>> getProcurements({
    int? rawIngredientId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (rawIngredientId != null) {
      conditions.add('p.raw_ingredient_id = ?');
      args.add(rawIngredientId);
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    final limitClause = limit != null ? 'LIMIT $limit' : '';

    final rows = await database.rawQuery('''
      SELECT 
        p.*,
        i.name AS raw_ingredient_name,
        i.storage_unit
      FROM ${PosDatabaseConstants.tableMandiProcurements} p
      JOIN ${PosDatabaseConstants.tableRawIngredients} i ON p.raw_ingredient_id = i.id
      $whereClause
      ORDER BY p.id DESC
      $limitClause;
    ''', args);

    return rows.map((r) => MandiProcurement.fromMap(
      r,
      ingredientName: r['raw_ingredient_name'] as String?,
      ingredientUnit: r['storage_unit'] as String?,
    )).toList();
  }

  // ===========================================================================
  // KITCHEN WASTAGE
  // ===========================================================================

  /// Records spoiled, damaged, or burned kitchen stock, verifying the staff PIN,
  /// immediately deducting stock, and logging the financial cost loss.
  Future<KitchenWastage> recordKitchenWastage({
    required String staffPin,
    required int rawIngredientId,
    required double quantity,
    required WastageReason reason,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Wasted quantity must be greater than zero.');
    }

    // 1. Authenticate Staff PIN
    Staff? staff;
    if (authService != null) {
      staff = await authService!.authenticateWithPin(staffPin);
    } else {
      final pinHash = PinHasher.hashPin(staffPin);
      final staffRows = await database.rawQuery('''
        SELECT s.*, d.name AS department_name
        FROM ${PosDatabaseConstants.tableStaff} s
        LEFT JOIN ${PosDatabaseConstants.tableDepartments} d ON s.department_id = d.id
        WHERE s.pin_hash = ? AND s.is_active = 1
        LIMIT 1;
      ''', [pinHash]);

      if (staffRows.isNotEmpty) {
        staff = Staff.fromMap(
          staffRows.first,
          departmentName: staffRows.first['department_name'] as String?,
        );
      }
    }

    if (staff == null) {
      throw ArgumentError('Invalid or unauthorized staff PIN.');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    return await database.transaction((txn) async {
      // 2. Fetch raw ingredient
      final ingredientRows = await txn.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [rawIngredientId],
      );

      if (ingredientRows.isEmpty) {
        throw StateError('Raw ingredient with id $rawIngredientId not found.');
      }

      final ingredient = RawIngredient.fromMap(ingredientRows.first);

      // 3. Compute financial cost loss based on current unit cost
      final costLoss = quantity * ingredient.costPerRecipeUnit;

      // 4. Immediately deduct inventory stock
      await txn.rawUpdate('''
        UPDATE ${PosDatabaseConstants.tableRawIngredients}
        SET current_stock = current_stock - ?
        WHERE id = ?;
      ''', [quantity, rawIngredientId]);

      // 5. Insert Kitchen Wastage record
      final id = await txn.insert(
        PosDatabaseConstants.tableKitchenWastage,
        {
          'staff_id': staff!.id,
          'raw_ingredient_id': rawIngredientId,
          'quantity': quantity,
          'cost_loss': costLoss,
          'reason': reason.code,
          'notes': notes?.trim(),
          'created_at': formattedNow,
        },
      );

      return KitchenWastage(
        id: id,
        staffId: staff.id,
        staffName: staff.name,
        rawIngredientId: rawIngredientId,
        rawIngredientName: ingredient.name,
        quantity: quantity,
        storageUnit: ingredient.storageUnit,
        costLoss: costLoss,
        reason: reason,
        notes: notes?.trim(),
        createdAt: now,
      );
    });
  }

  /// Retrieves kitchen wastage log records ordered chronologically descending.
  Future<List<KitchenWastage>> getWastageLogs({
    int? rawIngredientId,
    int? staffId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (rawIngredientId != null) {
      conditions.add('w.raw_ingredient_id = ?');
      args.add(rawIngredientId);
    }
    if (staffId != null) {
      conditions.add('w.staff_id = ?');
      args.add(staffId);
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    final limitClause = limit != null ? 'LIMIT $limit' : '';

    final rows = await database.rawQuery('''
      SELECT 
        w.*,
        s.name AS staff_name,
        i.name AS raw_ingredient_name,
        i.storage_unit
      FROM ${PosDatabaseConstants.tableKitchenWastage} w
      JOIN ${PosDatabaseConstants.tableStaff} s ON w.staff_id = s.id
      JOIN ${PosDatabaseConstants.tableRawIngredients} i ON w.raw_ingredient_id = i.id
      $whereClause
      ORDER BY w.id DESC
      $limitClause;
    ''', args);

    return rows.map((r) => KitchenWastage.fromMap(
      r,
      staffName: r['staff_name'] as String?,
      rawIngredientName: r['raw_ingredient_name'] as String?,
      storageUnit: r['storage_unit'] as String?,
    )).toList();
  }

  /// Computes cumulative financial cost loss for a given date or all-time.
  Future<double> getTotalWastageLoss({DateTime? since}) async {
    String query = 'SELECT SUM(cost_loss) as total FROM ${PosDatabaseConstants.tableKitchenWastage}';
    final args = <Object?>[];

    if (since != null) {
      query += ' WHERE created_at >= ?';
      args.add(_formatTimestamp(since));
    }

    final result = await database.rawQuery(query, args);
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  /// Helper to fetch all available raw ingredients for selection dropdowns.
  Future<List<RawIngredient>> getRawIngredients() async {
    final rows = await database.query(
      PosDatabaseConstants.tableRawIngredients,
      orderBy: 'name ASC',
    );
    return rows.map((r) => RawIngredient.fromMap(r)).toList();
  }
}
