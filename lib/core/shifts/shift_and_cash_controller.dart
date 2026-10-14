import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'business_day.dart';
import 'shift.dart';
import 'cash_movement.dart';
import 'x_report.dart';

/// Controller coordinating the operational lifecycle of Business Days and Cashier Shifts.
///
/// Implements blind cash drawer counts, mid-shift Pay-In/Pay-Out movements,
/// variance math, and the non-blocking discrepancy flag policy (ADR-0006).
class ShiftAndCashController {
  ShiftAndCashController({required this.database});

  final Database database;

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  // ===========================================================================
  // BUSINESS DAY STATE MACHINE
  // ===========================================================================

  /// Retrieves the currently open Business Day, if any.
  Future<BusinessDay?> getActiveBusinessDay() async {
    final rows = await database.rawQuery('''
      SELECT b.*, s.name as opened_by_staff_name
      FROM ${PosDatabaseConstants.tableBusinessDays} b
      LEFT JOIN ${PosDatabaseConstants.tableStaff} s ON b.opened_by_staff_id = s.id
      WHERE b.status = ?
      ORDER BY b.id DESC
      LIMIT 1;
    ''', [BusinessDayStatus.open.dbValue]);

    if (rows.isEmpty) return null;
    return BusinessDay.fromMap(rows.first);
  }

  /// Opens an overarching Business Day.
  ///
  /// Throws [StateError] if another Business Day is already open.
  Future<BusinessDay> openBusinessDay({
    required int openedByStaffId,
    DateTime? openedAt,
  }) async {
    final active = await getActiveBusinessDay();
    if (active != null) {
      throw StateError(
        'A Business Day is already open (ID: #${active.id}). Close it before opening a new one.',
      );
    }

    final effectiveOpenedAt = openedAt ?? DateTime.now();
    final formattedOpenedAt = _formatTimestamp(effectiveOpenedAt);

    final id = await database.insert(
      PosDatabaseConstants.tableBusinessDays,
      {
        'opened_at': formattedOpenedAt,
        'opened_by_staff_id': openedByStaffId,
        'status': BusinessDayStatus.open.dbValue,
      },
    );

    return BusinessDay(
      id: id,
      openedAt: effectiveOpenedAt,
      openedByStaffId: openedByStaffId,
      status: BusinessDayStatus.open,
    );
  }

  /// Concludes and locks an active Business Day.
  ///
  /// Throws [StateError] if there is no active Business Day, or if an active shift is still open.
  Future<BusinessDay> closeBusinessDay({
    required int closedByStaffId,
    DateTime? closedAt,
  }) async {
    final active = await getActiveBusinessDay();
    if (active == null) {
      throw StateError('No active Business Day to close.');
    }

    final activeShift = await getActiveShift();
    if (activeShift != null) {
      throw StateError(
        'Cannot close Business Day while shift #${activeShift.id} is still open. Complete shift handover first.',
      );
    }

    final effectiveClosedAt = closedAt ?? DateTime.now();
    final formattedClosedAt = _formatTimestamp(effectiveClosedAt);

    await database.update(
      PosDatabaseConstants.tableBusinessDays,
      {
        'closed_at': formattedClosedAt,
        'closed_by_staff_id': closedByStaffId,
        'status': BusinessDayStatus.closed.dbValue,
      },
      where: 'id = ?',
      whereArgs: [active.id],
    );

    return BusinessDay(
      id: active.id,
      openedAt: active.openedAt,
      closedAt: effectiveClosedAt,
      openedByStaffId: active.openedByStaffId,
      closedByStaffId: closedByStaffId,
      status: BusinessDayStatus.closed,
    );
  }

  // ===========================================================================
  // CASHIER SHIFT LIFECYCLE
  // ===========================================================================

  /// Retrieves the currently open Shift, if any.
  Future<Shift?> getActiveShift() async {
    final rows = await database.rawQuery('''
      SELECT sh.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.status = ?
      ORDER BY sh.id DESC
      LIMIT 1;
    ''', [ShiftStatus.open.dbValue]);

    if (rows.isEmpty) return null;
    return Shift.fromMap(rows.first);
  }

  /// Opens a new sequential cashier shift with an opening cash float in the drawer.
  ///
  /// Throws [StateError] if no Business Day is open or if another shift is currently open.
  /// Throws [ArgumentError] if [openingFloat] is negative.
  Future<Shift> openShift({
    required int staffId,
    required double openingFloat,
    DateTime? openedAt,
  }) async {
    if (openingFloat < 0) {
      throw ArgumentError('Opening float cannot be negative.');
    }

    final activeDay = await getActiveBusinessDay();
    if (activeDay == null) {
      throw StateError('Cannot open shift: No Business Day is currently open.');
    }

    final activeShift = await getActiveShift();
    if (activeShift != null) {
      throw StateError(
        'Cannot open shift: Shift #${activeShift.id} is currently active. Close it first.',
      );
    }

    final effectiveOpenedAt = openedAt ?? DateTime.now();
    final formattedOpenedAt = _formatTimestamp(effectiveOpenedAt);

    final id = await database.insert(
      PosDatabaseConstants.tableShifts,
      {
        'business_day_id': activeDay.id,
        'staff_id': staffId,
        'opened_at': formattedOpenedAt,
        'opening_float': openingFloat,
        'discrepancy_status': DiscrepancyStatus.clean.dbValue,
        'status': ShiftStatus.open.dbValue,
      },
    );

    final staffRow = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [staffId],
    );
    final staffName = staffRow.isNotEmpty ? staffRow.first['name'] as String? : null;

    return Shift(
      id: id,
      businessDayId: activeDay.id,
      staffId: staffId,
      openedAt: effectiveOpenedAt,
      openingFloat: openingFloat,
      discrepancyStatus: DiscrepancyStatus.clean,
      status: ShiftStatus.open,
      staffName: staffName,
    );
  }

  // ===========================================================================
  // MID-SHIFT CASH MOVEMENTS (PAY-IN & PAY-OUT)
  // ===========================================================================

  /// Records a mid-shift Pay-In or Pay-Out (petty cash, milk, ice, cash drops).
  ///
  /// Throws [ArgumentError] if [amount] <= 0 or [notes] is blank.
  /// Throws [StateError] if the shift is closed or not found.
  Future<CashMovement> recordCashMovement({
    required int shiftId,
    required int staffId,
    required CashMovementType type,
    required double amount,
    required String category,
    required String notes,
    DateTime? createdAt,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Cash movement amount must be greater than zero.');
    }
    if (notes.trim().isEmpty) {
      throw ArgumentError('Cash movement notes are mandatory.');
    }

    final shiftRows = await database.query(
      PosDatabaseConstants.tableShifts,
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (shiftRows.isEmpty) {
      throw StateError('Shift #$shiftId not found.');
    }
    final shift = Shift.fromMap(shiftRows.first);
    if (shift.isClosed) {
      throw StateError('Cannot record cash movement: Shift #$shiftId is already closed.');
    }

    final effectiveCreatedAt = createdAt ?? DateTime.now();
    final formattedCreatedAt = _formatTimestamp(effectiveCreatedAt);

    final id = await database.insert(
      PosDatabaseConstants.tableCashMovements,
      {
        'shift_id': shiftId,
        'staff_id': staffId,
        'type': type.dbValue,
        'amount': amount,
        'category': category.trim().isNotEmpty ? category.trim() : 'General',
        'notes': notes.trim(),
        'created_at': formattedCreatedAt,
      },
    );

    final staffRow = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [staffId],
    );
    final staffName = staffRow.isNotEmpty ? staffRow.first['name'] as String? : null;

    return CashMovement(
      id: id,
      shiftId: shiftId,
      staffId: staffId,
      type: type,
      amount: amount,
      category: category.trim().isNotEmpty ? category.trim() : 'General',
      notes: notes.trim(),
      createdAt: effectiveCreatedAt,
      staffName: staffName,
    );
  }

  /// Retrieves all cash movements recorded under [shiftId].
  Future<List<CashMovement>> getCashMovements(int shiftId) async {
    final rows = await database.rawQuery('''
      SELECT cm.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableCashMovements} cm
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON cm.staff_id = st.id
      WHERE cm.shift_id = ?
      ORDER BY cm.id ASC;
    ''', [shiftId]);

    return rows.map((r) => CashMovement.fromMap(r)).toList();
  }

  // ===========================================================================
  // SHIFT MATH, BLIND CLOSE, AND NON-BLOCKING DISCREPANCY POLICY
  // ===========================================================================

  /// Reads the configured supervisor discrepancy threshold from system settings.
  Future<double> getDiscrepancyThreshold() async {
    final rows = await database.query(
      PosDatabaseConstants.tableSystemSettings,
      where: 'key = ?',
      whereArgs: [PosDatabaseConstants.settingDiscrepancyThreshold],
    );
    if (rows.isNotEmpty) {
      final val = double.tryParse(rows.first['value'] as String);
      if (val != null) return val;
    }
    return double.parse(PosDatabaseConstants.defaultDiscrepancyThreshold);
  }

  /// Computes settled cash order totals for a shift.
  Future<double> calculateCashSales(int shiftId) async {
    try {
      final rows = await database.rawQuery('''
        SELECT COALESCE(SUM(op.amount_tendered - op.change_returned), 0.0) as cash_sales
        FROM ${PosDatabaseConstants.tableOrderPayments} op
        JOIN ${PosDatabaseConstants.tableOrders} o ON op.order_id = o.id
        WHERE o.shift_id = ? 
          AND o.payment_status = 'SETTLED' 
          AND op.payment_method = 'CASH';
      ''', [shiftId]);

      if (rows.isNotEmpty) {
        return (rows.first['cash_sales'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {
      // Graceful fallback if orders table is empty or being initialized
    }
    return 0.0;
  }

  /// Computes card and Raast tender sales for a shift.
  Future<Map<String, double>> calculateTenderSales(int shiftId) async {
    final result = {'CARD': 0.0, 'RAAST': 0.0};
    try {
      final rows = await database.rawQuery('''
        SELECT op.payment_method, COALESCE(SUM(op.amount_tendered), 0.0) as total
        FROM ${PosDatabaseConstants.tableOrderPayments} op
        JOIN ${PosDatabaseConstants.tableOrders} o ON op.order_id = o.id
        WHERE o.shift_id = ? 
          AND o.payment_status = 'SETTLED'
          AND op.payment_method IN ('CARD', 'RAAST')
        GROUP BY op.payment_method;
      ''', [shiftId]);

      for (final row in rows) {
        final method = row['payment_method'] as String;
        final sum = (row['total'] as num?)?.toDouble() ?? 0.0;
        result[method] = sum;
      }
    } catch (_) {}
    return result;
  }

  /// Closes an active shift with a cashier's blind physical cash drawer count.
  ///
  /// Computes discrepancy: Counted Cash - (Opening Float + Cash Sales + Pay-Ins - Pay-Outs).
  ///
  /// If discrepancy variance exceeds the threshold, the shift is flagged as `FLAGGED`
  /// without freezing the POS (ADR-0006), allowing immediate shift handover to the next cashier.
  Future<Shift> closeShift({
    required int shiftId,
    required double countedCash,
    DateTime? closedAt,
  }) async {
    if (countedCash < 0) {
      throw ArgumentError('Counted cash cannot be negative.');
    }

    final shiftRows = await database.query(
      PosDatabaseConstants.tableShifts,
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (shiftRows.isEmpty) {
      throw StateError('Shift #$shiftId not found.');
    }
    final existingShift = Shift.fromMap(shiftRows.first);
    if (existingShift.isClosed) {
      throw StateError('Shift #$shiftId is already closed.');
    }

    // 1. Gather shift cash movements
    final movements = await getCashMovements(shiftId);
    double totalPayIn = 0.0;
    double totalPayOut = 0.0;
    for (final m in movements) {
      if (m.isPayIn) {
        totalPayIn += m.amount;
      } else {
        totalPayOut += m.amount;
      }
    }

    // 2. Gather cash sales
    final cashSales = await calculateCashSales(shiftId);

    // 3. Expected Drawer Cash & Discrepancy Variance
    final expectedCash = existingShift.openingFloat + cashSales + totalPayIn - totalPayOut;
    final discrepancy = countedCash - expectedCash;

    // 4. Threshold Evaluation
    final threshold = await getDiscrepancyThreshold();
    final isFlagged = discrepancy.abs() > threshold;
    final discrepancyStatus = isFlagged ? DiscrepancyStatus.flagged : DiscrepancyStatus.clean;

    final effectiveClosedAt = closedAt ?? DateTime.now();
    final formattedClosedAt = _formatTimestamp(effectiveClosedAt);

    await database.update(
      PosDatabaseConstants.tableShifts,
      {
        'closed_at': formattedClosedAt,
        'counted_cash': countedCash,
        'expected_cash': expectedCash,
        'discrepancy': discrepancy,
        'discrepancy_status': discrepancyStatus.dbValue,
        'status': ShiftStatus.closed.dbValue,
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );

    return Shift(
      id: existingShift.id,
      businessDayId: existingShift.businessDayId,
      staffId: existingShift.staffId,
      openedAt: existingShift.openedAt,
      closedAt: effectiveClosedAt,
      openingFloat: existingShift.openingFloat,
      countedCash: countedCash,
      expectedCash: expectedCash,
      discrepancy: discrepancy,
      discrepancyStatus: discrepancyStatus,
      status: ShiftStatus.closed,
      staffName: existingShift.staffName,
    );
  }

  /// Retrieves all shifts that have active un-resolved discrepancy flags.
  Future<List<Shift>> getFlaggedShifts() async {
    final rows = await database.rawQuery('''
      SELECT sh.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.discrepancy_status = ?
      ORDER BY sh.id DESC;
    ''', [DiscrepancyStatus.flagged.dbValue]);

    return rows.map((r) => Shift.fromMap(r)).toList();
  }

  /// Retrieves all historical shifts flagged with cash discrepancies (both active flagged and resolved).
  Future<List<Shift>> getHistoricalDiscrepancyShifts() async {
    final rows = await database.rawQuery('''
      SELECT 
        sh.*, 
        st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.discrepancy_status != ?
      ORDER BY sh.id DESC;
    ''', [DiscrepancyStatus.clean.dbValue]);

    return rows.map((r) => Shift.fromMap(r)).toList();
  }

  /// Asynchronously marks a flagged shift discrepancy as RESOLVED with supervisor notes.
  Future<Shift> resolveDiscrepancy({
    required int shiftId,
    required int supervisorStaffId,
    required String resolutionNotes,
    DateTime? resolvedAt,
  }) async {
    if (resolutionNotes.trim().isEmpty) {
      throw ArgumentError('Resolution notes are mandatory for supervisor audit.');
    }

    final shiftRows = await database.query(
      PosDatabaseConstants.tableShifts,
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (shiftRows.isEmpty) {
      throw StateError('Shift #$shiftId not found.');
    }

    final effectiveResolvedAt = resolvedAt ?? DateTime.now();
    final formattedResolvedAt = _formatTimestamp(effectiveResolvedAt);

    await database.update(
      PosDatabaseConstants.tableShifts,
      {
        'discrepancy_status': DiscrepancyStatus.resolved.dbValue,
        'resolved_by_staff_id': supervisorStaffId,
        'resolution_notes': resolutionNotes.trim(),
        'resolved_at': formattedResolvedAt,
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );

    final updatedRows = await database.rawQuery('''
      SELECT sh.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.id = ?;
    ''', [shiftId]);

    return Shift.fromMap(updatedRows.first);
  }

  // ===========================================================================
  // X-REPORT SUMMARY GENERATION
  // ===========================================================================

  /// Generates an interim or closing X-Report for [shiftId].
  Future<XReport> generateXReport(int shiftId) async {
    final shiftRows = await database.rawQuery('''
      SELECT sh.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.id = ?;
    ''', [shiftId]);

    if (shiftRows.isEmpty) {
      throw StateError('Shift #$shiftId not found.');
    }

    final shift = Shift.fromMap(shiftRows.first);
    final movements = await getCashMovements(shiftId);
    double totalPayIn = 0.0;
    double totalPayOut = 0.0;
    for (final m in movements) {
      if (m.isPayIn) {
        totalPayIn += m.amount;
      } else {
        totalPayOut += m.amount;
      }
    }

    final cashSales = await calculateCashSales(shiftId);
    final tenderSales = await calculateTenderSales(shiftId);
    final expectedDrawerCash = shift.openingFloat + cashSales + totalPayIn - totalPayOut;

    return XReport(
      businessDayId: shift.businessDayId,
      shiftId: shift.id,
      staffId: shift.staffId,
      cashierName: shift.staffName ?? 'Cashier #${shift.staffId}',
      openedAt: shift.openedAt,
      generatedAt: DateTime.now(),
      closedAt: shift.closedAt,
      openingFloat: shift.openingFloat,
      cashSales: cashSales,
      cardSales: tenderSales['CARD'] ?? 0.0,
      raastSales: tenderSales['RAAST'] ?? 0.0,
      totalPayIn: totalPayIn,
      totalPayOut: totalPayOut,
      expectedDrawerCash: shift.expectedCash ?? expectedDrawerCash,
      countedCash: shift.countedCash,
      discrepancy: shift.discrepancy,
      discrepancyStatus: shift.discrepancyStatus,
      cashMovements: movements,
      isInterim: shift.isOpen,
    );
  }
}
