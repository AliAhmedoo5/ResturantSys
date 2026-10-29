import '../payments/payment_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'vendor.dart';
import 'vendor_payment_source.dart';
import 'vendor_statement.dart';
import 'vendor_transaction.dart';
import '../orders/customer_controller.dart';
import '../orders/paisa_engine.dart';
import '../finance/operations_controller.dart';

/// Domain controller managing the supplier credit ledger (Vendor Khata),
/// credit delivery stock intake, multi-source balance settlements,
/// and automated cash drawer pay-out synchronization.
class VendorKhataController {
  VendorKhataController({
    required this.database,
    this.shiftController,
  });

  final Database database;
  final ShiftAndCashController? shiftController;

  Future<List<Map<String, Object?>>> suppliedItems(int vendorId) => database.rawQuery('''
    SELECT i.*, s.sku FROM supplier_items s JOIN raw_ingredients i ON i.id=s.ingredient_id
    WHERE s.vendor_id=? AND s.active=1 ORDER BY i.name''', [vendorId]);

  Future<void> setSuppliedItems({required int managerId, required int vendorId,
      required Set<int> ingredientIds}) async {
    await database.transaction((txn) async {
      await CustomerController.requireRole(txn, managerId, manager: true);
      if ((await txn.query('vendor_khata', where: 'id=? AND archived_at IS NULL', whereArgs: [vendorId])).isEmpty) {
        throw StateError('Restore this supplier before editing supplied items.');
      }
      await txn.update('supplier_items', {'active': 0}, where: 'vendor_id=?', whereArgs: [vendorId]);
      for (final id in ingredientIds) {
        await txn.rawInsert('''INSERT INTO supplier_items(vendor_id,ingredient_id,active)
          VALUES(?,?,1) ON CONFLICT(vendor_id,ingredient_id) DO UPDATE SET active=1''', [vendorId,id]);
      }
      await OperationsController.audit(txn, managerId, 'supplier', vendorId,
          'SUPPLIED_ITEMS', {'ingredient_ids': ingredientIds.toList()});
    });
  }

  Future<int> createSuppliedItem({required int managerId, required int vendorId,
      required String name, required String unit}) async {
    if (name.trim().isEmpty || !['g','kg','ml','count'].contains(unit)) throw ArgumentError('Enter a name and valid stock unit.');
    return database.transaction((txn) async {
      await CustomerController.requireRole(txn,managerId,manager:true);
      if ((await txn.query('vendor_khata',where:'id=? AND archived_at IS NULL',whereArgs:[vendorId])).isEmpty) throw StateError('Supplier is unavailable.');
      final existing = await txn.query('raw_ingredients',where:'name=? COLLATE NOCASE',whereArgs:[name.trim()]);
      if (existing.isNotEmpty && existing.single['storage_unit'] != unit) throw StateError('An item with this name has a different stock unit.');
      final id = existing.isEmpty ? await txn.insert('raw_ingredients',{'name':name.trim(),'storage_unit':unit,'created_at':_formatTimestamp(DateTime.now())}) : existing.single['id'] as int;
      await txn.rawInsert('''INSERT INTO supplier_items(vendor_id,ingredient_id,active)
        VALUES(?,?,1) ON CONFLICT(vendor_id,ingredient_id) DO UPDATE SET active=1''',[vendorId,id]);
      await OperationsController.audit(txn,managerId,'supplier',vendorId,'ADD_SUPPLIED_ITEM',{'ingredient_id':id,'name':name.trim(),'unit':unit});
      return id;
    });
  }

  /// Includes fully paid invoices, preserving historical due dates and snapshots.
  Future<List<Map<String,Object?>>> invoices(int vendorId) => database.rawQuery('''
    SELECT t.*, COALESCE(t.amount_paisa,CAST(ROUND(t.amount*100) AS INTEGER))
      - COALESCE((SELECT SUM(a.amount_paisa) FROM supplier_payment_allocations a WHERE a.invoice_id=t.id),0) AS due_paisa
    FROM vendor_transactions t WHERE t.vendor_id=? AND t.type='PURCHASE_CREDIT'
    ORDER BY COALESCE(t.due_date,substr(t.created_at,1,10)),t.id''', [vendorId]);

  Future<void> _uniqueReference(DatabaseExecutor txn, int vendorId, String type,
      String? reference, String? requestKey) async {
    if (reference?.trim().isNotEmpty == true) {
      final rows = await txn.query('vendor_transactions', columns: ['id'],
          where: "vendor_id=? AND ${type == 'PURCHASE_CREDIT' ? "type='PURCHASE_CREDIT'" : "type IN ('PAYMENT_DRAWER','PAYMENT_EXTERNAL')"} AND reference_slip=?",
          whereArgs: [vendorId,reference!.trim()], limit: 1);
      if (rows.isNotEmpty) throw StateError('This supplier reference has already been posted.');
    }
    if (requestKey != null && requestKey.trim().isEmpty) throw ArgumentError('Request key cannot be blank.');
  }

  Future<void> _allocate(DatabaseExecutor txn, int vendorId, int paymentId,
      int amount, Map<int,int>? allocations) async {
    var remaining = amount;
    final rows = await txn.rawQuery('''SELECT t.id,
      COALESCE(t.amount_paisa,CAST(ROUND(t.amount*100) AS INTEGER)) - COALESCE(SUM(a.amount_paisa),0) due
      FROM vendor_transactions t LEFT JOIN supplier_payment_allocations a ON a.invoice_id=t.id
      WHERE t.vendor_id=? AND t.type='PURCHASE_CREDIT' GROUP BY t.id
      ORDER BY COALESCE(t.due_date,substr(t.created_at,1,10)),t.id''', [vendorId]);
    if (allocations != null) {
      if (allocations.isEmpty || allocations.values.any((v) => v <= 0) ||
          allocations.values.fold<int>(0,(a,b) => a+b) != amount) {
        throw ArgumentError('Invoice allocations must exactly equal the payment.');
      }
      for (final entry in allocations.entries) {
        final invoice = rows.where((r) => r['id'] == entry.key).firstOrNull;
        if (invoice == null || entry.value > (invoice['due'] as int)) {
          throw StateError('Allocation exceeds invoice due or belongs to another supplier.');
        }
        await txn.insert('supplier_payment_allocations', {'payment_id': paymentId,
          'invoice_id': entry.key, 'amount_paisa': entry.value});
      }
      return;
    }
    // Opening payable has no invoice. Its allocation remains explicitly labeled.
    final vendor = (await txn.query('vendor_khata', where:'id=?',whereArgs:[vendorId])).single;
    final openingPaid = (await txn.rawQuery('''SELECT COALESCE(SUM(a.amount_paisa),0) paid
      FROM supplier_payment_allocations a JOIN vendor_transactions t ON t.id=a.payment_id
      WHERE t.vendor_id=? AND a.invoice_id IS NULL''',[vendorId])).single['paid'] as int;
    final openingDue = PaisaEngine.rupeesToPaisa(vendor['opening_balance'] as num) - openingPaid;
    if (openingDue > 0) {
      final value = remaining < openingDue ? remaining : openingDue;
      await txn.insert('supplier_payment_allocations', {'payment_id': paymentId, 'amount_paisa': value});
      remaining -= value;
    }
    for (final row in rows) {
      final due = row['due'] as int;
      final value = remaining < due ? remaining : due;
      if (value > 0) await txn.insert('supplier_payment_allocations', {'payment_id': paymentId,
        'invoice_id': row['id'], 'amount_paisa': value});
      remaining -= value;
    }
    if (remaining != 0) throw StateError('Payment cannot be reconciled to the supplier payable.');
  }

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  // ===========================================================================
  // SUPPLIER DIRECTORY CRUD
  // ===========================================================================

  /// Creates a new vendor in the directory with an optional opening payable balance.
  Future<Vendor> createVendor({
    required String name,
    required String phone,
    String? suppliedIngredients,
    double openingBalance = 0.0,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError('Vendor name cannot be empty.');
    }
    if (trimmedPhone.isEmpty) {
      throw ArgumentError('Vendor phone cannot be empty.');
    }
    if (!openingBalance.isFinite || openingBalance < 0) {
      throw ArgumentError('Opening balance cannot be negative.');
    }
    openingBalance = PaisaEngine.rupeesToPaisa(openingBalance) / 100;

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    final id = await database.insert(
      PosDatabaseConstants.tableVendorKhata,
      {
        'name': trimmedName,
        'phone': trimmedPhone,
        'supplied_ingredients': suppliedIngredients?.trim(),
        'opening_balance': openingBalance,
        'current_balance': openingBalance,
        'created_at': formattedNow,
        'updated_at': formattedNow,
      },
    );

    return Vendor(
      id: id,
      name: trimmedName,
      phone: trimmedPhone,
      suppliedIngredients: suppliedIngredients?.trim(),
      openingBalance: openingBalance,
      currentBalance: openingBalance,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Updates an existing vendor's contact details, supplied ingredients, and opening balance.
  Future<Vendor> updateVendor({
    required int id,
    required String name,
    required String phone,
    String? suppliedIngredients,
    double? openingBalance,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError('Vendor name cannot be empty.');
    }
    if (trimmedPhone.isEmpty) {
      throw ArgumentError('Vendor phone cannot be empty.');
    }
    if (openingBalance != null && (!openingBalance.isFinite || openingBalance < 0)) {
      throw ArgumentError('Opening balance cannot be negative.');
    }
    if (openingBalance != null) openingBalance = PaisaEngine.rupeesToPaisa(openingBalance) / 100;

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    final existing = await getVendorById(id);
    if (existing == null) {
      throw StateError('Vendor with ID #$id does not exist.');
    }

    final balanceDelta = openingBalance != null
        ? (openingBalance - existing.openingBalance)
        : 0.0;
    if (openingBalance != null) {
      final allocated = (await database.rawQuery('''SELECT COALESCE(SUM(a.amount_paisa),0) paid
        FROM supplier_payment_allocations a JOIN vendor_transactions t ON t.id=a.payment_id
        WHERE t.vendor_id=? AND a.invoice_id IS NULL''',[id])).single['paid'] as int;
      if (PaisaEngine.rupeesToPaisa(openingBalance) < allocated) throw StateError('Opening payable cannot be reduced below its allocated payments.');
    }

    await database.rawUpdate('''
      UPDATE ${PosDatabaseConstants.tableVendorKhata}
      SET name = ?,
          phone = ?,
          supplied_ingredients = ?,
          opening_balance = COALESCE(?, opening_balance),
          current_balance = current_balance + ?,
          updated_at = ?
      WHERE id = ?;
    ''', [
      trimmedName,
      trimmedPhone,
      suppliedIngredients?.trim(),
      openingBalance,
      balanceDelta,
      formattedNow,
      id,
    ]);

    final vendor = await getVendorById(id);
    return vendor!;
  }

  /// Permanently removes only unused suppliers; archives financial history.
  Future<void> deleteVendor(int id) async {
    await database.transaction((txn) async {
      final rows = await txn.query('vendor_khata', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Vendor with ID #$id does not exist.');
      final history = await txn.query('vendor_transactions', columns: ['id'],
          where: 'vendor_id = ?', whereArgs: [id], limit: 1);
      final vendor = Vendor.fromMap(rows.first);
      if (history.isNotEmpty || vendor.openingBalance != 0 || vendor.currentBalance != 0) {
        final now = _formatTimestamp(DateTime.now());
        await txn.update('vendor_khata', {'archived_at': now, 'updated_at': now},
            where: 'id = ?', whereArgs: [id]);
      } else {
        await txn.delete('vendor_khata', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<void> setVendorArchived(int id, bool archived) async {
    final now = _formatTimestamp(DateTime.now());
    final count = await database.update('vendor_khata',
        {'archived_at': archived ? now : null, 'updated_at': now},
        where: 'id = ?', whereArgs: [id]);
    if (count == 0) throw StateError('Vendor with ID #$id does not exist.');
  }

  /// Retrieves all vendors with an optional name/supplied ingredients search filter.
  Future<List<Vendor>> getVendors({String? searchQuery, bool includeArchived = false}) async {
    final query = searchQuery?.trim();
    if (query != null && query.isNotEmpty) {
      final rows = await database.rawQuery('''
        SELECT * FROM ${PosDatabaseConstants.tableVendorKhata}
        WHERE (name LIKE ? OR supplied_ingredients LIKE ?)
          ${includeArchived ? '' : 'AND archived_at IS NULL'}
        ORDER BY name ASC;
      ''', ['%$query%', '%$query%']);
      return rows.map((r) => Vendor.fromMap(r)).toList();
    }

    final rows = await database.query(
      PosDatabaseConstants.tableVendorKhata,
      where: includeArchived ? null : 'archived_at IS NULL',
      orderBy: 'name ASC',
    );
    return rows.map((r) => Vendor.fromMap(r)).toList();
  }

  /// Retrieves a single vendor by primary key [id].
  Future<Vendor?> getVendorById(int id) async {
    final rows = await database.query(
      PosDatabaseConstants.tableVendorKhata,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Vendor.fromMap(rows.first);
  }

  // ===========================================================================
  // CREDIT DELIVERY ENTRY
  // ===========================================================================

  /// Records an incoming stock shipment on credit, increases the vendor's running
  /// payable balance without immediate cash outflow, and optionally updates stock.
  Future<VendorTransaction> recordCreditDelivery({
    required int vendorId,
    required double amount,
    String? referenceSlip,
    int? rawIngredientId,
    double? quantity,
    String? notes,
    int? staffId,
    DateTime? createdAt,
    DateTime? dueDate,
    String? requestKey,
  }) async {
    if (!amount.isFinite || amount <= 0 || PaisaEngine.rupeesToPaisa(amount) <= 0) {
      throw ArgumentError('Credit delivery amount must be greater than zero.');
    }
    if (quantity != null && (!quantity.isFinite || quantity <= 0)) {
      throw ArgumentError('Delivered quantity must be greater than zero.');
    }

    final effectiveDate = createdAt ?? DateTime.now();
    final formattedDate = _formatTimestamp(effectiveDate);
    if ((rawIngredientId == null) != (quantity == null)) {
      throw ArgumentError('Ingredient and received quantity must be provided together.');
    }
    if (dueDate != null && DateTime(dueDate.year,dueDate.month,dueDate.day)
        .isBefore(DateTime(effectiveDate.year,effectiveDate.month,effectiveDate.day))) {
      throw ArgumentError('Invoice due date cannot precede the invoice date.');
    }
    final amountPaisa = PaisaEngine.rupeesToPaisa(amount);
    amount = amountPaisa / 100;

    return await database.transaction((txn) async {
      if (staffId != null) await CustomerController.requireRole(txn, staffId, manager: true);
      await _uniqueReference(txn,vendorId,'PURCHASE_CREDIT',referenceSlip,requestKey);
      // 1. Verify vendor exists
      final vendorRows = await txn.query(
        PosDatabaseConstants.tableVendorKhata,
        where: 'id = ?',
        whereArgs: [vendorId],
      );
      if (vendorRows.isEmpty) {
        throw StateError('Vendor with ID #$vendorId not found.');
      }
      final vendor = Vendor.fromMap(vendorRows.first);

      if (vendor.isArchived) {
        throw StateError('Restore this supplier before recording a new delivery.');
      }

      // 2. If raw ingredient is linked, update stock
      String? ingredientName;
      String? unitSnapshot;
      if (rawIngredientId != null && quantity != null) {
        final linked = await txn.query('supplier_items', where: 'vendor_id=? AND ingredient_id=? AND active=1',
            whereArgs: [vendorId,rawIngredientId]);
        if (linked.isEmpty) throw StateError('This ingredient is not in the supplier catalog.');
        final ingredientRows = await txn.query(
          PosDatabaseConstants.tableRawIngredients,
          where: 'id = ?',
          whereArgs: [rawIngredientId],
        );
        if (ingredientRows.isEmpty) throw StateError('Ingredient does not exist.');
        if (ingredientRows.isNotEmpty) {
          ingredientName = ingredientRows.first['name'] as String?;
          unitSnapshot = ingredientRows.first['storage_unit'] as String?;
          await txn.rawUpdate('''
            UPDATE ${PosDatabaseConstants.tableRawIngredients}
            SET current_stock = current_stock + ?, cost_per_recipe_unit = ?
            WHERE id = ?;
          ''', [quantity, amount / quantity, rawIngredientId]);
        }
      }

      // 3. Update vendor current_balance (increases payable)
      await txn.rawUpdate('''
        UPDATE ${PosDatabaseConstants.tableVendorKhata}
        SET current_balance = current_balance + ?,
            updated_at = ?
        WHERE id = ?;
      ''', [amount, formattedDate, vendorId]);

      // 4. Insert vendor transaction
      final txnId = await txn.insert(
        PosDatabaseConstants.tableVendorTransactions,
        {
          'vendor_id': vendorId,
          'shift_id': null,
          'staff_id': staffId,
          'type': VendorTransactionType.purchaseCredit.dbValue,
          'amount': amount,
          'amount_paisa': amountPaisa,
          'due_date': dueDate == null ? null : _formatTimestamp(dueDate).substring(0,10),
          'ingredient_name_snapshot': ingredientName,
          'unit_snapshot': unitSnapshot,
          'request_key': requestKey?.trim(),
          'reference_slip': referenceSlip?.trim(),
          'notes': notes?.trim(),
          'raw_ingredient_id': rawIngredientId,
          'quantity': quantity,
          'created_at': formattedDate,
        },
      );

      return VendorTransaction(
        id: txnId,
        vendorId: vendorId,
        staffId: staffId,
        type: VendorTransactionType.purchaseCredit,
        amount: amount,
        referenceSlip: referenceSlip?.trim(),
        notes: notes?.trim(),
        rawIngredientId: rawIngredientId,
        quantity: quantity,
        createdAt: effectiveDate,
        dueDate: dueDate,
        vendorName: vendor.name,
        rawIngredientName: ingredientName,
      );
    });
  }

  // ===========================================================================
  // MULTI-SOURCE SETTLEMENT
  // ===========================================================================

  /// Records a settlement payment to a vendor, deducting from the running payable balance.
  ///
  /// If [paymentSource] is [VendorPaymentSource.paidFromActiveDrawer]:
  /// - Requires [shiftId] and [staffId].
  /// - Automatically logs a CashMovement (Pay-Out) in the cash drawer.
  ///
  /// If [paymentSource] is [VendorPaymentSource.paidOutsideDrawer]:
  /// - Updates ledger payable without affecting drawer cash float.
  Future<VendorTransaction> recordSettlementPayment({
    required int vendorId,
    required double amount,
    required VendorPaymentSource paymentSource,
    int? shiftId,
    int? staffId,
    String? referenceSlip,
    String? notes,
    DateTime? createdAt,
    Map<int,int>? allocations,
    String? requestKey,
    DateTime? actualAt,
    int? businessDayId,
  }) async {
    if (!amount.isFinite || amount <= 0 || PaisaEngine.rupeesToPaisa(amount) <= 0) {
      throw ArgumentError('Settlement payment amount must be greater than zero.');
    }

    if (paymentSource == VendorPaymentSource.paidFromActiveDrawer) {
      if (shiftId == null || staffId == null) {
        throw ArgumentError(
          'Shift ID and Staff ID are required when settling payment from active cash drawer.',
        );
      }
    }

    if (staffId == null) throw ArgumentError('A recording Manager is required for supplier payment.');
    final effectiveDate = createdAt ?? DateTime.now();
    final formattedDate = _formatTimestamp(effectiveDate);
    final amountPaisa = PaisaEngine.rupeesToPaisa(amount);
    amount = amountPaisa / 100;

    return await database.transaction((txn) async {
      if (staffId != null) await CustomerController.requireRole(txn, staffId, manager: true);
      // 1. Verify vendor exists
      final vendorRows = await txn.query(
        PosDatabaseConstants.tableVendorKhata,
        where: 'id = ?',
        whereArgs: [vendorId],
      );
      if (vendorRows.isEmpty) {
        throw StateError('Vendor with ID #$vendorId not found.');
      }
      final vendor = Vendor.fromMap(vendorRows.first);

      final isDrawerPayment =
          paymentSource == VendorPaymentSource.paidFromActiveDrawer;
      final txnType = isDrawerPayment
          ? VendorTransactionType.paymentDrawer
          : VendorTransactionType.paymentExternal;
      if (amountPaisa > PaisaEngine.rupeesToPaisa(vendor.currentBalance)) {
        throw StateError('Payment exceeds supplier payable.');
      }
      await _uniqueReference(txn,vendorId,txnType.dbValue,referenceSlip,requestKey);

      // 2. If paid from active drawer, verify active shift and auto-generate CashMovement (Pay-Out)
      int? movementId;
      if (isDrawerPayment) {
        final shiftRows = await txn.query(
          PosDatabaseConstants.tableShifts,
          where: 'id = ?',
          whereArgs: [shiftId],
        );
        if (shiftRows.isEmpty) {
          throw ArgumentError('Shift with ID #$shiftId not found.');
        }
        final shiftStatus = shiftRows.first['status'] as String;
        if (shiftStatus != 'OPEN') {
          throw StateError('Cannot settle drawer payment against closed shift #$shiftId.');
        }

        final slipPart = referenceSlip != null && referenceSlip.trim().isNotEmpty
            ? ' (Slip: ${referenceSlip.trim()})'
            : '';
        final notePart = notes != null && notes.trim().isNotEmpty
            ? ' - ${notes.trim()}'
            : '';
        final movementNotes =
            'Khata settlement to ${vendor.name}$slipPart$notePart';

        movementId = await txn.insert(
          PosDatabaseConstants.tableCashMovements,
          {
            'shift_id': shiftId,
            'staff_id': staffId,
            'type': 'PAY_OUT',
            'amount': amount,
            'category': 'Vendor Khata',
            'notes': movementNotes,
            'created_at': formattedDate,
          },
        );
      }

      // 3. Update vendor current_balance (deducts payable)
      await txn.rawUpdate('''
        UPDATE ${PosDatabaseConstants.tableVendorKhata}
        SET current_balance = current_balance - ?,
            updated_at = ?
        WHERE id = ?;
      ''', [amount, formattedDate, vendorId]);

      // 4. Insert vendor transaction
      final txnId = await txn.insert(
        PosDatabaseConstants.tableVendorTransactions,
        {
          'vendor_id': vendorId,
          'shift_id': isDrawerPayment ? shiftId : null,
          'staff_id': staffId,
          'type': txnType.dbValue,
          'amount': amount,
          'amount_paisa': amountPaisa,
          'request_key': requestKey?.trim(),
          'reference_slip': referenceSlip?.trim(),
          'notes': notes?.trim(),
          'created_at': formattedDate,
        },
      );

      await _allocate(txn,vendorId,txnId,amountPaisa,allocations);
      if (staffId != null) {
        final days = await txn.query('business_days', where: "status='OPEN'" +
          (businessDayId == null ? '' : ' AND id=?'),
          whereArgs: businessDayId == null ? null : [businessDayId]);
        if (days.length != 1 && (isDrawerPayment || actualAt != null || createdAt != null || businessDayId != null)) {
          throw StateError('An open Business Day is required for an attributed or late payment.');
        }
        final recorded = DateTime.now().toUtc();
        await PaymentEvent.record(txn, eventKey: 'vendor_transactions:$txnId',
          kind: 'SUPPLIER_PAYMENT', amountPaisa: -amountPaisa,
          paymentSource: isDrawerPayment ? 'DRAWER' : paymentSource == VendorPaymentSource.owner
            ? 'OWNER' : paymentSource == VendorPaymentSource.bank ? 'BANK' : 'EXTERNAL_UNKNOWN',
          recordedBy: staffId, approvedBy: staffId, recordedAt: recorded,
          actualAt: actualAt ?? createdAt ?? recorded,
          businessDayId: days.length == 1 ? days.single['id'] as int : null,
          shiftId: isDrawerPayment ? shiftId : null, movementId: movementId,
          sourceTable: 'vendor_transactions', sourceId: txnId);
      }

      return VendorTransaction(
        id: txnId,
        vendorId: vendorId,
        shiftId: isDrawerPayment ? shiftId : null,
        staffId: staffId,
        type: txnType,
        amount: amount,
        referenceSlip: referenceSlip?.trim(),
        notes: notes?.trim(),
        createdAt: effectiveDate,
        vendorName: vendor.name,
      );
    });
  }

  // ===========================================================================
  // VENDOR STATEMENT VIEW
  // ===========================================================================

  /// Generates a comprehensive statement of accounts for a vendor,
  /// with chronological delivery chits, settlement payments, and running balance math.
  Future<VendorStatement> getVendorStatement(int vendorId) async {
    final vendor = await getVendorById(vendorId);
    if (vendor == null) {
      throw StateError('Vendor with ID #$vendorId not found.');
    }

    final rawTxns = await database.rawQuery('''
      SELECT 
        vt.*,
        v.name AS vendor_name,
        COALESCE(vt.ingredient_name_snapshot,i.name) AS raw_ingredient_name,
        st.name AS staff_name
      FROM ${PosDatabaseConstants.tableVendorTransactions} vt
      JOIN ${PosDatabaseConstants.tableVendorKhata} v ON vt.vendor_id = v.id
      LEFT JOIN ${PosDatabaseConstants.tableRawIngredients} i ON vt.raw_ingredient_id = i.id
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON vt.staff_id = st.id
      WHERE vt.vendor_id = ?
      ORDER BY vt.created_at ASC, vt.id ASC;
    ''', [vendorId]);

    final transactions = rawTxns.map((r) => VendorTransaction.fromMap(r)).toList();

    double runningBalance = vendor.openingBalance;
    final entries = <VendorStatementEntry>[];

    for (final txn in transactions) {
      if (txn.isCreditDelivery) {
        runningBalance += txn.amount;
        entries.add(VendorStatementEntry(
          transaction: txn,
          creditAmount: txn.amount,
          debitAmount: 0.0,
          runningBalance: runningBalance,
        ));
      } else {
        runningBalance -= txn.amount;
        entries.add(VendorStatementEntry(
          transaction: txn,
          creditAmount: 0.0,
          debitAmount: txn.amount,
          runningBalance: runningBalance,
        ));
      }
    }

    return VendorStatement(
      vendor: vendor,
      openingBalance: vendor.openingBalance,
      currentBalance: vendor.currentBalance,
      entries: entries,
    );
  }

  /// Retrieves recent vendor transactions across all suppliers or filtered by [vendorId].
  Future<List<VendorTransaction>> getVendorTransactions({
    int? vendorId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (vendorId != null) {
      conditions.add('vt.vendor_id = ?');
      args.add(vendorId);
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    final limitClause = limit != null ? 'LIMIT $limit' : '';

    final rows = await database.rawQuery('''
      SELECT 
        vt.*,
        v.name AS vendor_name,
        COALESCE(vt.ingredient_name_snapshot,i.name) AS raw_ingredient_name,
        st.name AS staff_name
      FROM ${PosDatabaseConstants.tableVendorTransactions} vt
      JOIN ${PosDatabaseConstants.tableVendorKhata} v ON vt.vendor_id = v.id
      LEFT JOIN ${PosDatabaseConstants.tableRawIngredients} i ON vt.raw_ingredient_id = i.id
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON vt.staff_id = st.id
      $whereClause
      ORDER BY vt.created_at DESC, vt.id DESC
      $limitClause;
    ''', args);

    return rows.map((r) => VendorTransaction.fromMap(r)).toList();
  }
}
