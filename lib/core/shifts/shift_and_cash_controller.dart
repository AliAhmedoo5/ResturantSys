import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'business_day.dart';
import '../payments/payment_event.dart';
import 'report_export_service.dart';
import 'report_delivery_service.dart';
import 'shift.dart';
import 'cash_movement.dart';
import 'x_report.dart';
import 'z_report.dart';
import '../auth/staff_role.dart';
import '../database/database_backup_service.dart';

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

  /// Validates that [staffId] belongs to an active staff member with [requiredRole].
  ///
  /// Throws [StateError] if staff is not found, inactive, or has the wrong role.
  Future<Map<String, dynamic>> _assertActiveRole(int staffId, StaffRole requiredRole, String errorMessage) async {
    final staffRow = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ? AND is_active = 1 AND login_enabled = 1',
      whereArgs: [staffId],
      limit: 1,
    );
    if (staffRow.isEmpty) {
      throw StateError('Staff #$staffId not found or inactive.');
    }
    final role = StaffRole.fromCode(staffRow.first['role'] as String);
    if (role != requiredRole) {
      throw StateError(errorMessage);
    }
    return staffRow.first;
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
    // Only Managers can open Business Days (ADR-0009)
    final staffRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [openedByStaffId],
      limit: 1,
    );
    if (staffRows.isEmpty || staffRows.first['login_enabled'] == 0 || staffRows.first['is_active'] != 1) {
      throw StateError('Authorization error: Active system login required.');
    }
    if (staffRows.isNotEmpty) {
      final role = StaffRole.fromCode(staffRows.first['role'] as String);
      if (role == StaffRole.cashier) {
        throw StateError('Authorization error: Business Day must be opened by a Manager.');
      }
    }

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
  /// If [autoLockActiveShifts] is true, any active cashier shift under this business day
  /// is automatically finalized and locked before closing the day (required for supervisor Z-Report).
  ///
  /// Throws [StateError] if there is no active Business Day, or if an active shift is still open and [autoLockActiveShifts] is false.
  Future<BusinessDay> closeBusinessDay({
    required int closedByStaffId,
    DateTime? closedAt,
    bool autoLockActiveShifts = false,
  }) async {
    return database.transaction((txn) async {
      final staff = await txn.query('staff', where: 'id = ? AND is_active = 1 AND login_enabled = 1', whereArgs: [closedByStaffId]);
      if (staff.isEmpty || StaffRole.fromCode(staff.first['role'] as String) != StaffRole.manager) {
        throw StateError('Authorization error: Business Day must be closed by an active Manager.');
      }
      final days = await txn.query('business_days', where: "status = 'OPEN'", orderBy: 'id DESC', limit: 1);
      if (days.isEmpty) throw StateError('No active Business Day to close.');
      final day = BusinessDay.fromMap(days.first);
      final shifts = await txn.query('shifts', where: "business_day_id = ? AND status = 'OPEN'", whereArgs: [day.id]);
      if (shifts.isNotEmpty && !autoLockActiveShifts) {
        throw StateError('Cannot close Business Day while a shift is still open. Complete shift handover first.');
      }
      final timestamp = _formatTimestamp(closedAt ?? DateTime.now());
      for (final shift in shifts) {
        final id = shift['id'] as int;
        final cashReceiptsPaisa = await _drawerCashReceiptsPaisa(txn, shiftId: id);
        final movements = await txn.rawQuery("SELECT COALESCE(SUM(CASE WHEN type='PAY_IN' THEN amount ELSE -amount END),0) AS net FROM cash_movements WHERE shift_id=?", [id]);
        final expected = (shift['opening_float'] as num).toDouble() + cashReceiptsPaisa / 100 + (movements.first['net'] as num).toDouble();
        final counted = (shift['counted_cash'] as num?)?.toDouble();
        await txn.update('shifts', {
          'status': 'CLOSED', 'closed_at': timestamp, 'expected_cash': expected,
          'counted_cash': counted, 'discrepancy': counted == null ? null : counted-expected,
          'discrepancy_status': counted == null ? 'FLAGGED' : shift['discrepancy_status'],
        }, where: 'id=?', whereArgs: [id]);
      }
      await txn.update('business_days', {
        'status': 'CLOSED', 'closed_at': timestamp, 'closed_by_staff_id': closedByStaffId,
      }, where: "id=? AND status='OPEN'", whereArgs: [day.id]);
      await ReportExportService.capture(txn, day.id, closedByStaffId);
      return BusinessDay.fromMap({...days.first, 'status':'CLOSED', 'closed_at':timestamp, 'closed_by_staff_id':closedByStaffId});
    });
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

    // Manager credentials cannot open or operate cashier shifts (ADR-0009)
    final staffRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [staffId],
      limit: 1,
    );
    if (staffRows.isEmpty || staffRows.first['login_enabled'] == 0 || staffRows.first['is_active'] != 1) {
      throw StateError('Authorization error: Active system login required.');
    }
    if (staffRows.isNotEmpty) {
      final role = StaffRole.fromCode(staffRows.first['role'] as String);
      if (role != StaffRole.cashier) {
        throw StateError('Authorization error: Manager credentials cannot open or operate cashier shifts.');
      }
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
    int? approvedBy,
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

    // Manager credentials cannot operate cashier shifts (ADR-0009)
    final staffRow = await _assertActiveRole(
      staffId,
      StaffRole.cashier,
      'Authorization error: Manager credentials cannot operate cashier shifts.',
    );

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
        'approved_by': approvedBy,
        'created_at': formattedCreatedAt,
      },
    );

    final staffName = staffRow['name'] as String?;

    return CashMovement(
      id: id,
      shiftId: shiftId,
      staffId: staffId,
      type: type,
      amount: amount,
      category: category.trim().isNotEmpty ? category.trim() : 'General',
      notes: notes.trim(),
      approvedBy: approvedBy,
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

  /// Sets the configurable supervisor discrepancy threshold in system settings.
  ///
  /// Throws [ArgumentError] if [threshold] is negative.
  /// Throws [StateError] if [managerStaffId] does not belong to an active Manager.
  Future<void> setDiscrepancyThreshold(
    double threshold, {
    required int managerStaffId,
  }) async {
    if (threshold < 0) {
      throw ArgumentError('Discrepancy threshold cannot be negative.');
    }

    await _assertActiveRole(
      managerStaffId,
      StaffRole.manager,
      'Authorization error: Only Managers can configure the discrepancy threshold.',
    );

    final now = _formatTimestamp(DateTime.now());
    await database.insert(
      PosDatabaseConstants.tableSystemSettings,
      {
        'key': PosDatabaseConstants.settingDiscrepancyThreshold,
        'value': threshold.toStringAsFixed(2),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Physical cash receipts before refunds, which are posted separately as
  /// drawer PAY_OUT movements. Net tender collection must not be used here.
  Future<int> _drawerCashReceiptsPaisa(
    DatabaseExecutor executor, {
    int? shiftId,
    int? businessDayId,
  }) async {
    final scope = shiftId != null ? 'COALESCE(pe.shift_id,o.shift_id)' : 'COALESCE(pe.business_day_id,o.business_day_id)';
    final rows = await executor.rawQuery("""
      SELECT COALESCE(SUM(
        COALESCE(op.amount_tendered_paisa, CAST(ROUND(op.amount_tendered * 100) AS INTEGER))
        - COALESCE(op.change_returned_paisa, CAST(ROUND(op.change_returned * 100) AS INTEGER))
      ), 0) AS receipt_paisa
      FROM order_payments op JOIN orders o ON o.id = op.order_id LEFT JOIN payment_events pe ON pe.tender_id=op.id
      WHERE $scope = ? AND op.payment_method = 'CASH'
        AND COALESCE(op.amount_tendered_paisa, CAST(ROUND(op.amount_tendered * 100) AS INTEGER)) > 0
        AND o.payment_status != 'VOIDED'
        AND (pe.id IS NOT NULL OR o.payment_status IN ('SETTLED', 'REFUND_PENDING', 'CANCELLED', 'REFUNDED'))
    """, [shiftId ?? businessDayId]);
    return (rows.single['receipt_paisa'] as num).toInt();
  }

  /// Returns physical cash receipts for drawer reconciliation. Cash refund
  /// payment lines are excluded because their PAY_OUT already reduces the till.
  Future<double> calculateCashSales(int shiftId) async {
    return await _drawerCashReceiptsPaisa(database, shiftId: shiftId) / 100;
  }

  /// Retrieves a shift by [id].
  Future<Shift> getShift(int id) async {
    final shiftRows = await database.rawQuery('''
      SELECT sh.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.id = ?;
    ''', [id]);

    if (shiftRows.isEmpty) {
      throw StateError('Shift #$id not found.');
    }

    return Shift.fromMap(shiftRows.first);
  }

  /// Calculates expected drawer cash balance for [shiftId] accounting for
  /// opening float, settled/prepaid cash sales, pay-ins, and pay-outs (including refunds).
  Future<double> calculateExpectedCash(int shiftId) async {
    final shift = await getShift(shiftId);
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
    return shift.openingFloat + cashSales + totalPayIn - totalPayOut;
  }

  /// Computes card and Raast tender sales for a shift.
  Future<Map<String, double>> calculateTenderSales(int shiftId) async {
    final result = {'CARD': 0.0, 'RAAST': 0.0};
    try {
      final rows = await database.rawQuery('''
        SELECT op.payment_method, COALESCE(SUM(op.amount_tendered), 0.0) as total
        FROM ${PosDatabaseConstants.tableOrderPayments} op
        JOIN ${PosDatabaseConstants.tableOrders} o ON op.order_id = o.id
        LEFT JOIN payment_events pe ON pe.tender_id=op.id WHERE COALESCE(pe.shift_id,o.shift_id) = ?
          AND (pe.id IS NOT NULL OR o.payment_status = 'SETTLED')
          AND op.payment_method IN ('CARD', 'RAAST', 'JAZZCASH', 'EASYPAISA', 'BANK_TRANSFER')
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
    required int staffId,
    required double countedCash,
    DateTime? closedAt,
  }) async {
    if (countedCash < 0) {
      throw ArgumentError('Counted cash cannot be negative.');
    }

    await _assertActiveRole(
      staffId,
      StaffRole.cashier,
      'Authorization error: Only an active Cashier can close a cashier shift.',
    );

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
  ///
  /// Enforces Manager-only authorization (StaffRole.manager) per ADR-0009.
  /// The shift's discrepancy variance, counted cash, and expected cash remain immutable.
  Future<Shift> resolveDiscrepancy({
    required int shiftId,
    required int supervisorStaffId,
    required String resolutionNotes,
    DateTime? resolvedAt,
  }) async {
    if (resolutionNotes.trim().isEmpty) {
      throw ArgumentError('Resolution notes are mandatory for supervisor audit.');
    }

    await _assertActiveRole(
      supervisorStaffId,
      StaffRole.manager,
      'Authorization error: Only Managers can resolve shift discrepancies.',
    );

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

  // ===========================================================================
  // MASTER END-OF-DAY Z-REPORT GENERATION & DAY FINALIZATION
  // ===========================================================================

  /// Aggregates multi-shift totals, revenue, payment tender splits, cash drawer variances,
  /// voids, wastage, and supplier khata for an entire Business Day.
  Future<ZReport> generateZReport(int businessDayId) async {
    final dayRows = await database.rawQuery('''
      SELECT b.*, 
             s1.name as opened_by_staff_name,
             s2.name as closed_by_staff_name
      FROM ${PosDatabaseConstants.tableBusinessDays} b
      LEFT JOIN ${PosDatabaseConstants.tableStaff} s1 ON b.opened_by_staff_id = s1.id
      LEFT JOIN ${PosDatabaseConstants.tableStaff} s2 ON b.closed_by_staff_id = s2.id
      WHERE b.id = ?;
    ''', [businessDayId]);

    if (dayRows.isEmpty) {
      throw StateError('Business Day #$businessDayId not found.');
    }

    final day = BusinessDay.fromMap(dayRows.first);

    // 1. Shifts under this business day
    final shiftRows = await database.rawQuery('''
      SELECT sh.*, st.name as staff_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.business_day_id = ?
      ORDER BY sh.id ASC;
    ''', [businessDayId]);
    final shifts = shiftRows.map((r) => Shift.fromMap(r)).toList();

    // 2. Sales totals from settled orders
    double grossSales = 0.0;
    double totalDiscounts = 0.0;
    double totalTax = 0.0;
    double netSales = 0.0;
    int totalOrdersCount = 0;

    final salesRows = await database.rawQuery('''
      SELECT 
        COUNT(id) as total_orders,
        COALESCE(SUM(subtotal), 0.0) as gross_sales,
        COALESCE(SUM(discount_amount), 0.0) as total_discounts,
        COALESCE(SUM(tax_amount), 0.0) as total_tax,
        COALESCE(SUM(grand_total), 0.0) as net_sales
      FROM ${PosDatabaseConstants.tableOrders}
      WHERE business_day_id = ? AND payment_status NOT IN ('VOIDED','CANCELLED','REFUNDED');
    ''', [businessDayId]);

    if (salesRows.isNotEmpty) {
      final r = salesRows.first;
      totalOrdersCount = (r['total_orders'] as num?)?.toInt() ?? 0;
      grossSales = (r['gross_sales'] as num?)?.toDouble() ?? 0.0;
      totalDiscounts = (r['total_discounts'] as num?)?.toDouble() ?? 0.0;
      totalTax = (r['total_tax'] as num?)?.toDouble() ?? 0.0;
      netSales = (r['net_sales'] as num?)?.toDouble() ?? 0.0;
    }

    // Collected tender balances include funds retained pending explicit refund.
    final tenderRows = await database.rawQuery("""
      SELECT op.payment_method,
        SUM(COALESCE(op.amount_tendered_paisa,CAST(ROUND(op.amount_tendered*100) AS INTEGER))
        -COALESCE(op.change_returned_paisa,CAST(ROUND(op.change_returned*100) AS INTEGER))) AS paisa
      FROM order_payments op JOIN orders o ON o.id=op.order_id LEFT JOIN payment_events pe ON pe.tender_id=op.id
      WHERE COALESCE(pe.business_day_id,o.business_day_id)=? AND o.payment_status != 'VOIDED' AND (pe.id IS NOT NULL OR o.payment_status IN ('SETTLED','REFUND_PENDING','CANCELLED','REFUNDED'))
      GROUP BY op.payment_method
    """,[businessDayId]);
    final tenderSalesPaisa = {for(final row in tenderRows) row['payment_method'] as String:(row['paisa'] as num).toInt()};
    final cashSales=(tenderSalesPaisa['CASH']??0)/100;
    final cardSales=(tenderSalesPaisa['CARD']??0)/100;
    final raastSales=(tenderSalesPaisa['RAAST']??0)/100;
    final dueRows=await database.rawQuery("SELECT COALESCE(SUM($outstandingCollectionPaisaSql),0) AS paisa FROM orders o WHERE o.business_day_id=? AND o.payment_status='COLLECTION_DUE'",[businessDayId]);
    final collectionDuePaisa=(dueRows.single['paisa'] as num).toInt();

    // 4. Voids
    int totalVoidCount = 0;
    double totalVoidAmount = 0.0;
    final voidRows = await database.rawQuery('''
      SELECT COUNT(id) as void_count, COALESCE(SUM(grand_total), 0.0) as void_amount
      FROM ${PosDatabaseConstants.tableOrders}
      WHERE business_day_id = ? AND payment_status = 'VOIDED';
    ''', [businessDayId]);

    if (voidRows.isNotEmpty) {
      totalVoidCount = (voidRows.first['void_count'] as num?)?.toInt() ?? 0;
      totalVoidAmount = (voidRows.first['void_amount'] as num?)?.toDouble() ?? 0.0;
    }

    // 5. Cash drawer reconciliations across all shifts
    double totalOpeningFloat = 0.0;
    double totalPayIn = 0.0;
    double totalPayOut = 0.0;
    double totalCountedCash = 0.0;

    for (final sh in shifts) {
      totalOpeningFloat += sh.openingFloat;
      if (sh.countedCash != null) {
        totalCountedCash += sh.countedCash!;
      }
      final movements = await getCashMovements(sh.id);
      for (final m in movements) {
        if (m.isPayIn) {
          totalPayIn += m.amount;
        } else {
          totalPayOut += m.amount;
        }
      }
    }

    final drawerCashReceiptsPaisa = await _drawerCashReceiptsPaisa(
      database, businessDayId: businessDayId,
    );
    final totalExpectedDrawerCash = totalOpeningFloat + drawerCashReceiptsPaisa / 100 + totalPayIn - totalPayOut;
    final netCashVariance = totalCountedCash - totalExpectedDrawerCash;

    // 6. Kitchen Wastage, Mandi Procurements, and Vendor Khata in day timeframe
    final startTimestamp = _formatTimestamp(day.openedAt);
    final endTimestamp = _formatTimestamp((day.closedAt ?? DateTime.now()).add(const Duration(minutes: 5)));

    int totalWastageCount = 0;
    double totalWastageCost = 0.0;
    try {
      final wastageRows = await database.rawQuery('''
        SELECT COUNT(id) as count, COALESCE(SUM(cost_loss), 0.0) as cost
        FROM ${PosDatabaseConstants.tableKitchenWastage}
        WHERE created_at >= ? AND created_at <= ?;
      ''', [startTimestamp, endTimestamp]);
      if (wastageRows.isNotEmpty) {
        totalWastageCount = (wastageRows.first['count'] as num?)?.toInt() ?? 0;
        totalWastageCost = (wastageRows.first['cost'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    double totalMandiPurchasesCost = 0.0;
    try {
      final mandiRows = await database.rawQuery('''
        SELECT COALESCE(SUM(total_cost), 0.0) as cost
        FROM ${PosDatabaseConstants.tableMandiProcurements}
        WHERE created_at >= ? AND created_at <= ?;
      ''', [startTimestamp, endTimestamp]);
      if (mandiRows.isNotEmpty) {
        totalMandiPurchasesCost = (mandiRows.first['cost'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    int totalVendorDeliveriesCount = 0;
    double totalVendorSettlementsAmount = 0.0;
    try {
      final deliveryRows = await database.rawQuery('''
        SELECT COUNT(id) as count
        FROM ${PosDatabaseConstants.tableVendorTransactions}
        WHERE type = 'PURCHASE_CREDIT' AND created_at >= ? AND created_at <= ?;
      ''', [startTimestamp, endTimestamp]);
      if (deliveryRows.isNotEmpty) {
        totalVendorDeliveriesCount = (deliveryRows.first['count'] as num?)?.toInt() ?? 0;
      }

      final settlementRows = await database.rawQuery('''
        SELECT COALESCE(SUM(amount), 0.0) as amount
        FROM ${PosDatabaseConstants.tableVendorTransactions}
        WHERE type IN ('PAYMENT_DRAWER', 'PAYMENT_EXTERNAL') AND created_at >= ? AND created_at <= ?;
      ''', [startTimestamp, endTimestamp]);
      if (settlementRows.isNotEmpty) {
        totalVendorSettlementsAmount = (settlementRows.first['amount'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    return ZReport(
      businessDayId: day.id,
      openedAt: day.openedAt,
      closedAt: day.closedAt,
      generatedAt: DateTime.now(),
      openedByStaffName: day.openedByStaffName ?? 'Staff #${day.openedByStaffId}',
      closedByStaffName: day.closedByStaffName,
      totalShiftsCount: shifts.length,
      shifts: shifts,
      grossSales: grossSales,
      netSales: netSales,
      totalTax: totalTax,
      totalDiscounts: totalDiscounts,
      cashSales: cashSales,
      cardSales: cardSales,
      raastSales: raastSales,
      drawerCashReceiptsPaisa: drawerCashReceiptsPaisa,
      tenderSalesPaisa:tenderSalesPaisa,
      collectionDuePaisa:collectionDuePaisa,
      totalOpeningFloat: totalOpeningFloat,
      totalPayIn: totalPayIn,
      totalPayOut: totalPayOut,
      totalExpectedDrawerCash: totalExpectedDrawerCash,
      totalCountedCash: totalCountedCash,
      netCashVariance: netCashVariance,
      totalOrdersCount: totalOrdersCount,
      totalVoidCount: totalVoidCount,
      totalVoidAmount: totalVoidAmount,
      totalWastageCount: totalWastageCount,
      totalWastageCost: totalWastageCost,
      totalMandiPurchasesCost: totalMandiPurchasesCost,
      totalVendorDeliveriesCount: totalVendorDeliveriesCount,
      totalVendorSettlementsAmount: totalVendorSettlementsAmount,
    );
  }

  /// Finalizes and locks an active Business Day with supervisor authority.
  ///
  /// Concludes the business day, archives shifts, triggers automated dual-target backups,
  /// and prepares the operational session for the next business day (which resets daily tokens to #01).
  Future<BusinessDay> finalizeBusinessDayWithZReport({
    required int closedByStaffId,
    DateTime? closedAt,
    DatabaseBackupService? backupService,
    String? sourceDbPath,
  }) async {
    final closedDay = await closeBusinessDay(
      closedByStaffId: closedByStaffId,
      closedAt: closedAt,
      autoLockActiveShifts: true,
    );

    // Filesystem failures are recoverable from the committed snapshot on restart.
    try {
      await ReportExportService(database: database).exportPending();
      await ReportDeliveryService(database: database).enqueueReadyReports();
    } catch (_) {
      // Committed report snapshots are retried by the startup/background worker.
    }

    // Automated dual-target database backup on every Z-Report closure
    try {
      final service = backupService ?? DatabaseBackupService(database: database);
      final srcPath = sourceDbPath ?? database.path;
      if (srcPath.isNotEmpty && srcPath != inMemoryDatabasePath) {
        await service.executeBackup(sourceDbPath: srcPath);
      }
    } catch (_) {
      // Non-fatal backup guardrail
    }

    return closedDay;
  }
}
