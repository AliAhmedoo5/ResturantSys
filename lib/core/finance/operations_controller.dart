import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../orders/customer_controller.dart';
import '../payments/payment_event.dart';

enum FundingSource {
  drawer('DRAWER', 'Active drawer'), bank('BANK', 'Bank'), owner('OWNER', 'Owner cash');
  const FundingSource(this.code, this.label);
  final String code, label;
}

class EmployeeBalance {
  const EmployeeBalance(this.payablePaisa, this.advancePaisa);
  final int payablePaisa, advancePaisa;
  int get netDuePaisa => payablePaisa - advancePaisa;
}

/// Manager operations share one atomic boundary with the physical cash ledger.
/// Accrual recognizes payroll expense; payments and advances never accrue it again.
class OperationsController {
  OperationsController(this.database);
  final Database database;
  static String get _now => DateTime.now().toIso8601String();

  static void _positive(int amount) {
    if (amount <= 0 || amount > 9007199254740991) {
      throw ArgumentError('Enter a positive amount within the supported range.');
    }
  }

  static void _reason(String reason) {
    if (reason.trim().isEmpty) throw ArgumentError('A reason is required.');
  }

  static void _period(String period) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      throw ArgumentError('Period must be YYYY-MM.');
    }
  }

  static Future<void> audit(DatabaseExecutor db, int managerId, String entity,
      int id, String action, Map<String, Object?> detail) async {
    await db.insert('operations_audit', {'manager_id': managerId, 'entity': entity,
      'entity_id': id, 'action': action, 'detail': jsonEncode(detail), 'created_at': _now});
  }

  Future<void> _employee(DatabaseExecutor db, int id, {bool active = true}) async {
    final rows = await db.query('staff', where: 'id = ? ${active ? 'AND is_active = 1' : ''}', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Employee is unavailable.');
  }

  Future<int> _openDay(DatabaseExecutor db, int? dayId) async {
    final rows = await db.query('business_days', where: "status = 'OPEN' ${dayId == null ? '' : 'AND id = ?'}",
        whereArgs: dayId == null ? null : [dayId]);
    if (rows.length != 1) throw StateError('An open Business Day is required.');
    return rows.single['id'] as int;
  }

  /// The manager records an approved cash outflow against the current physical
  /// drawer, without opening or operating a cashier shift as that manager.
  Future<int?> _cash(DatabaseExecutor db, {required int managerId,
      required FundingSource source, int? shiftId, required int amount,
      required String category, required String reason, bool reverse = false}) async {
    if (source != FundingSource.drawer) return null;
    final shifts = await db.rawQuery('''SELECT s.id FROM shifts s
      JOIN business_days b ON b.id=s.business_day_id
      WHERE s.id=? AND s.status='OPEN' AND b.status='OPEN' ''', [shiftId]);
    if (shifts.isEmpty) throw StateError('Select an active drawer shift.');
    return db.insert('cash_movements', {'shift_id': shiftId, 'staff_id': managerId,
      'approved_by': managerId, 'type': reverse ? 'PAY_IN' : 'PAY_OUT',
      'amount': amount / 100, 'category': category, 'notes': reason.trim(), 'created_at': _now});
  }

  Future<void> _event(DatabaseExecutor txn, {required String table,
      required int id, required String kind, required int amount,
      required int manager, required FundingSource source, int? day,
      int? shift, int? movement, DateTime? actualAt}) async {
    final recorded = DateTime.now().toUtc();
    final dayId = day ?? await _openDay(txn, null);
    await PaymentEvent.record(txn, eventKey: '$table:$id', kind: kind,
      amountPaisa: amount, paymentSource: source.code, recordedBy: manager,
      approvedBy: manager, recordedAt: recorded, actualAt: actualAt ?? recorded,
      businessDayId: dayId, shiftId: source == FundingSource.drawer ? shift : null,
      movementId: movement, sourceTable: table, sourceId: id);
  }

  Future<void> _openOriginal(DatabaseExecutor txn, String table, Map<String, Object?> old) async {
    int? day = old['business_day_id'] as int?;
    if (day == null) {
      final events = await txn.query('payment_events', where: 'source_table=? AND source_id=?',
        whereArgs: [table, old['id']], limit: 1);
      if (events.isNotEmpty) day = events.single['business_day_id'] as int?;
    }
    if (day == null && old['cash_movement_id'] != null) {
      final rows = await txn.rawQuery('SELECT s.business_day_id FROM cash_movements m JOIN shifts s ON s.id=m.shift_id WHERE m.id=?', [old['cash_movement_id']]);
      if (rows.isNotEmpty) day = rows.single['business_day_id'] as int;
    }
    if (day == null || (await txn.query('business_days', where: "id=? AND status='OPEN'", whereArgs: [day])).isEmpty) {
      throw StateError('Closed or unknown historical periods cannot be corrected here.');
    }
  }

  Future<void> setSalary({required int managerId, required int employeeId,
      required String effectivePeriod, required int amountPaisa, required String reason}) async {
    _positive(amountPaisa); _period(effectivePeriod); _reason(reason);
    await database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      await _employee(txn, employeeId);
      final posted = await txn.query('payroll_entries', where: "employee_id=? AND period>=? AND kind='ACCRUAL'",
          whereArgs: [employeeId, effectivePeriod], limit: 1);
      if (posted.isNotEmpty) throw StateError('Salary changes must start after posted accruals.');
      await txn.insert('salary_rates', {'employee_id': employeeId,
        'effective_period': effectivePeriod, 'amount_paisa': amountPaisa,
        'manager_id': managerId, 'reason': reason.trim(), 'created_at': _now});
    });
  }

  Future<int> _rate(DatabaseExecutor db, int employeeId, String period) async {
    final rows = await db.query('salary_rates', where: 'employee_id=? AND effective_period<=?',
        whereArgs: [employeeId, period], orderBy: 'effective_period DESC', limit: 1);
    if (rows.isEmpty) throw StateError('Configure a salary effective for this period first.');
    return rows.single['amount_paisa'] as int;
  }

  Future<EmployeeBalance> _balance(DatabaseExecutor db, int employeeId) async {
    final row = (await db.rawQuery('''SELECT COALESCE(SUM(payable_delta_paisa),0) payable,
      COALESCE(SUM(advance_delta_paisa),0) advance FROM payroll_entries WHERE employee_id=?''', [employeeId])).single;
    return EmployeeBalance(row['payable'] as int, row['advance'] as int);
  }

  Future<EmployeeBalance> employeeBalance({required int managerId, required int employeeId}) =>
      database.transaction((txn) async {
        await CustomerController.requireRole(txn, managerId, manager: true);
        return _balance(txn, employeeId);
      });

  /// Replays are checked before cash mutations and return the original entry only
  /// if its payload matches. The transaction and unique key prevent double cash.
  Future<int?> _replay(DatabaseExecutor db, String table, String requestKey,
      Map<String, Object?> payload) async {
    _reason(requestKey);
    final rows = await db.query(table, where: 'request_key=?', whereArgs: [requestKey.trim()]);
    if (rows.isEmpty) return null;
    final old = rows.single;
    for (final field in payload.keys) {
      if (old[field] != payload[field]) throw StateError('Request reference already used for different data.');
    }
    return old['id'] as int;
  }

  Future<int> postPayroll({required int managerId, required int employeeId,
      required String period, required String kind, int? amountPaisa,
      FundingSource? source, int? shiftId, required String reason, required String requestKey, DateTime? actualAt}) async {
    _period(period); _reason(reason);
    if (!['ACCRUAL','PAYMENT','ADVANCE','RECOVERY'].contains(kind)) throw ArgumentError('Invalid payroll action.');
    return database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      final rate = kind == 'ACCRUAL' ? await _rate(txn, employeeId, period) : null;
      final amount = kind == 'ACCRUAL' ? amountPaisa ?? rate! : amountPaisa ?? 0;
      _positive(amount);
      if (rate != null && amount > rate) throw ArgumentError('Accrual cannot exceed the configured monthly salary.');
      final funded = kind == 'PAYMENT' || kind == 'ADVANCE';
      if (funded && source == null) throw ArgumentError('Select a payment source.');
      final payload = <String,Object?>{'employee_id': employeeId, 'period': period,
        'kind': kind, 'amount_paisa': amount, 'source': funded ? source!.code : 'NONE',
        'manager_id': managerId, 'reason': reason.trim()};
      final replay = await _replay(txn, 'payroll_entries', requestKey, payload);
      if (replay != null) return replay;
      await _employee(txn, employeeId, active: kind == 'ACCRUAL' || kind == 'ADVANCE');
      final balance = await _balance(txn, employeeId);
      if (kind == 'PAYMENT' && amount > balance.netDuePaisa) {
        throw StateError('Payment exceeds salary due after outstanding advances. Recover advances explicitly.');
      }
      if (kind == 'ADVANCE' && balance.advancePaisa + amount > await _rate(txn, employeeId, period)) {
        throw StateError('Outstanding advances cannot exceed one configured monthly salary.');
      }
      if (kind == 'RECOVERY' && (amount > balance.payablePaisa || amount > balance.advancePaisa)) {
        throw StateError('Recovery exceeds accrued salary or outstanding advances.');
      }
      final movement = funded ? await _cash(txn, managerId: managerId, source: source!,
          shiftId: shiftId, amount: amount, category: 'Payroll $kind', reason: reason) : null;
      final entry = await txn.insert('payroll_entries', {...payload, 'request_key': requestKey.trim(),
        'payable_delta_paisa': kind == 'ACCRUAL' ? amount : (kind == 'PAYMENT' || kind == 'RECOVERY' ? -amount : 0),
        'advance_delta_paisa': kind == 'ADVANCE' ? amount : (kind == 'RECOVERY' ? -amount : 0),
        'cash_movement_id': movement, 'created_at': _now});
      if (funded) await _event(txn, table: 'payroll_entries', id: entry, kind: 'PAYROLL_$kind',
        amount: -amount, manager: managerId, source: source!, shift: shiftId,
        movement: movement, actualAt: actualAt);
      return entry;
    });
  }

  Future<int> reversePayroll({required int managerId, required int entryId,
      int? shiftId, required String reason, required String requestKey}) async {
    _reason(reason);
    return database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      final old = (await txn.query('payroll_entries', where: 'id=?', whereArgs: [entryId])).single;
      if (old['kind'] == 'REVERSAL') throw StateError('Cannot reverse a reversal.');
      final payload = <String,Object?>{'reversal_of': entryId, 'manager_id': managerId, 'reason': reason.trim()};
      final replay = await _replay(txn, 'payroll_entries', requestKey, payload);
      if (replay != null) return replay;
      final balance = await _balance(txn, old['employee_id'] as int);
      final payable = old['payable_delta_paisa'] as int;
      final advance = old['advance_delta_paisa'] as int;
      if (balance.payablePaisa - payable < 0 || balance.advancePaisa - advance < 0) {
        throw StateError('Reverse dependent payments or recoveries first.');
      }
      final source = FundingSource.values.where((s) => s.code == old['source']).firstOrNull;
      if (source != null) await _openOriginal(txn, 'payroll_entries', old);
      final movement = source == null ? null : await _cash(txn,
          managerId: managerId, source: source, shiftId: shiftId,
          amount: old['amount_paisa'] as int, category: 'Payroll reversal', reason: reason, reverse: true);
      final entry = await txn.insert('payroll_entries', {...payload, 'employee_id': old['employee_id'],
        'period': old['period'], 'kind': 'REVERSAL', 'amount_paisa': old['amount_paisa'],
        'payable_delta_paisa': -payable, 'advance_delta_paisa': -advance,
        'source': old['source'], 'cash_movement_id': movement,
        'request_key': requestKey.trim(), 'created_at': _now});
      if (source != null) await _event(txn, table: 'payroll_entries', id: entry,
        kind: 'PAYROLL_REVERSAL', amount: old['amount_paisa'] as int,
        manager: managerId, source: source, shift: shiftId, movement: movement);
      return entry;
    });
  }

  Future<int> saveCategory({required int managerId, int? id, required String name,
      String description = '', bool active = true, int sortOrder = 0,
      String allowedSource = 'ANY', int? approvalThresholdPaisa}) async {
    _reason(name);
    if (!['ANY','DRAWER','BANK','OWNER'].contains(allowedSource) ||
        (approvalThresholdPaisa != null && approvalThresholdPaisa < 0)) throw ArgumentError('Invalid category policy.');
    return database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      final data = <String,Object?>{'name': name.trim(), 'description': description.trim(),
        'active': active ? 1 : 0, 'sort_order': sortOrder, 'allowed_source': allowedSource,
        'approval_threshold_paisa': approvalThresholdPaisa};
      Map<String,Object?>? before;
      if (id != null) {
        before = (await txn.query('expense_categories', where: 'id=?', whereArgs: [id])).single;
        await txn.update('expense_categories', data, where: 'id=?', whereArgs: [id]);
      }
      final savedId = id ?? await txn.insert('expense_categories', data);
      await audit(txn, managerId, 'expense_category', savedId, 'SAVE', {'before': before, 'after': data});
      return savedId;
    });
  }

  Future<void> deleteCategory({required int managerId, required int id}) async {
    await database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      final before = (await txn.query('expense_categories', where: 'id=?', whereArgs: [id])).single;
      final used = await txn.query('expense_entries', where: 'category_id=?', whereArgs: [id], limit: 1);
      if (used.isEmpty) {
        await txn.delete('expense_categories', where: 'id=?', whereArgs: [id]);
      } else {
        await txn.update('expense_categories', {'active': 0}, where: 'id=?', whereArgs: [id]);
      }
      await audit(txn, managerId, 'expense_category', id, used.isEmpty ? 'DELETE' : 'ARCHIVE', before);
    });
  }

  Future<int> postExpense({required int managerId, required int categoryId,
      required int amountPaisa, required String description, String payee = '',
      required FundingSource source, int? shiftId, int? businessDayId,
      String? receiptPath, required String reason, required String requestKey,
      int? correctsEntryId, DateTime? actualAt}) async {
    _positive(amountPaisa); _reason(description); _reason(reason);
    return database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      final payload = <String,Object?>{'category_id': categoryId, 'amount_paisa': amountPaisa,
        'description': description.trim(), 'payee': payee.trim(), 'source': source.code,
        'manager_id': managerId, 'reason': reason.trim(), 'receipt_path': receiptPath,
        'correction_of': correctsEntryId};
      final replay = await _replay(txn, 'expense_entries', requestKey, payload);
      if (replay != null) return replay;
      final category = (await txn.query('expense_categories', where: 'id=? AND active=1', whereArgs: [categoryId])).firstOrNull;
      if (category == null) throw StateError('Select an active expense category.');
      if (category['allowed_source'] != 'ANY' && category['allowed_source'] != source.code) {
        throw StateError('This category does not permit that payment source.');
      }
      final day = await _openDay(txn, businessDayId);
      if (correctsEntryId != null) {
        await _reverseExpense(txn, managerId: managerId, entryId: correctsEntryId,
            shiftId: shiftId, day: day, reason: reason, requestKey: '$requestKey:reverse');
      }
      final movement = await _cash(txn, managerId: managerId, source: source, shiftId: shiftId,
          amount: amountPaisa, category: 'Expense: ${category['name']}', reason: reason);
      final entry = await txn.insert('expense_entries', {...payload, 'category_snapshot': category['name'],
        'expense_delta_paisa': amountPaisa, 'business_day_id': day,
        'cash_movement_id': movement, 'request_key': requestKey.trim(), 'created_at': _now});
      await _event(txn, table: 'expense_entries', id: entry, kind: 'EXPENSE',
        amount: -amountPaisa, manager: managerId, source: source, day: day,
        shift: shiftId, movement: movement, actualAt: actualAt);
      return entry;
    });
  }

  Future<int> _reverseExpense(DatabaseExecutor txn, {required int managerId,
      required int entryId, int? shiftId, required int day,
      required String reason, required String requestKey}) async {
    final payload = <String,Object?>{'reversal_of': entryId, 'manager_id': managerId, 'reason': reason.trim()};
    final replay = await _replay(txn, 'expense_entries', requestKey, payload);
    if (replay != null) return replay;
    final old = (await txn.query('expense_entries', where: 'id=?', whereArgs: [entryId])).single;
    if (old['reversal_of'] != null) throw StateError('Cannot reverse a reversal.');
    await _openOriginal(txn, 'expense_entries', old);
    final source = FundingSource.values.singleWhere((s) => s.code == old['source']);
    final movement = await _cash(txn, managerId: managerId, source: source, shiftId: shiftId,
        amount: old['amount_paisa'] as int, category: 'Expense reversal', reason: reason, reverse: true);
    final entry = await txn.insert('expense_entries', {...old, ...payload, 'id': null,
      'business_day_id': day, 'correction_of': null,
      'expense_delta_paisa': -(old['amount_paisa'] as int), 'cash_movement_id': movement,
      'request_key': requestKey.trim(), 'created_at': _now});
    await _event(txn, table: 'expense_entries', id: entry, kind: 'EXPENSE_REVERSAL',
      amount: old['amount_paisa'] as int, manager: managerId, source: source,
      day: day, shift: shiftId, movement: movement);
    return entry;
  }

  Future<int> reverseExpense({required int managerId, required int entryId,
      int? shiftId, required String reason, required String requestKey}) async {
    _reason(reason);
    return database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      return _reverseExpense(txn, managerId: managerId, entryId: entryId,
          shiftId: shiftId, day: await _openDay(txn, null), reason: reason, requestKey: requestKey);
    });
  }

  Future<List<Map<String,Object?>>> categories({required int managerId}) => database.transaction((txn) async {
    await CustomerController.requireRole(txn, managerId, manager: true);
    return txn.query('expense_categories', orderBy: 'sort_order, name COLLATE NOCASE');
  });

  Future<List<Map<String,Object?>>> payrollHistory({required int managerId, required int employeeId}) => database.transaction((txn) async {
    await CustomerController.requireRole(txn, managerId, manager: true);
    return txn.query('payroll_entries', where: 'employee_id=?', whereArgs: [employeeId], orderBy: 'id DESC');
  });

  Future<List<Map<String,Object?>>> employees({required int managerId}) => database.transaction((txn) async {
    await CustomerController.requireRole(txn, managerId, manager: true);
    return txn.rawQuery('''SELECT s.id,s.name,s.is_active,
      COALESCE((SELECT SUM(p.payable_delta_paisa) FROM payroll_entries p WHERE p.employee_id=s.id),0) payable_paisa,
      COALESCE((SELECT SUM(p.advance_delta_paisa) FROM payroll_entries p WHERE p.employee_id=s.id),0) advance_paisa
      FROM staff s ORDER BY s.name''');
  });

  Future<List<Map<String,Object?>>> salaryHistory({required int managerId, required int employeeId}) => database.transaction((txn) async {
    await CustomerController.requireRole(txn, managerId, manager: true);
    return txn.query('salary_rates', where: 'employee_id=?', whereArgs: [employeeId], orderBy: 'effective_period DESC');
  });

  Future<List<Map<String,Object?>>> expenses({required int managerId}) => database.transaction((txn) async {
    await CustomerController.requireRole(txn, managerId, manager: true);
    return txn.query('expense_entries', orderBy: 'id DESC');
  });
}
