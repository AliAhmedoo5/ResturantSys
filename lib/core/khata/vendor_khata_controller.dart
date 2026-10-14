import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'vendor.dart';
import 'vendor_payment_source.dart';
import 'vendor_statement.dart';
import 'vendor_transaction.dart';

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
    if (openingBalance < 0) {
      throw ArgumentError('Opening balance cannot be negative.');
    }

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
    if (openingBalance != null && openingBalance < 0) {
      throw ArgumentError('Opening balance cannot be negative.');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    final existing = await getVendorById(id);
    if (existing == null) {
      throw StateError('Vendor with ID #$id does not exist.');
    }

    final balanceDelta = openingBalance != null
        ? (openingBalance - existing.openingBalance)
        : 0.0;

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

  /// Deletes a vendor and cascades to delete all associated ledger transactions.
  Future<void> deleteVendor(int id) async {
    final deletedCount = await database.delete(
      PosDatabaseConstants.tableVendorKhata,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deletedCount == 0) {
      throw StateError('Vendor with ID #$id does not exist.');
    }
  }

  /// Retrieves all vendors with an optional name/supplied ingredients search filter.
  Future<List<Vendor>> getVendors({String? searchQuery}) async {
    final query = searchQuery?.trim();
    if (query != null && query.isNotEmpty) {
      final rows = await database.rawQuery('''
        SELECT * FROM ${PosDatabaseConstants.tableVendorKhata}
        WHERE name LIKE ? OR supplied_ingredients LIKE ?
        ORDER BY name ASC;
      ''', ['%$query%', '%$query%']);
      return rows.map((r) => Vendor.fromMap(r)).toList();
    }

    final rows = await database.query(
      PosDatabaseConstants.tableVendorKhata,
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
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Credit delivery amount must be greater than zero.');
    }
    if (quantity != null && quantity <= 0) {
      throw ArgumentError('Delivered quantity must be greater than zero.');
    }

    final effectiveDate = createdAt ?? DateTime.now();
    final formattedDate = _formatTimestamp(effectiveDate);

    return await database.transaction((txn) async {
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

      // 2. If raw ingredient is linked, update stock
      String? ingredientName;
      if (rawIngredientId != null && quantity != null) {
        final ingredientRows = await txn.query(
          PosDatabaseConstants.tableRawIngredients,
          where: 'id = ?',
          whereArgs: [rawIngredientId],
        );
        if (ingredientRows.isNotEmpty) {
          ingredientName = ingredientRows.first['name'] as String?;
          await txn.rawUpdate('''
            UPDATE ${PosDatabaseConstants.tableRawIngredients}
            SET current_stock = current_stock + ?
            WHERE id = ?;
          ''', [quantity, rawIngredientId]);
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
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Settlement payment amount must be greater than zero.');
    }

    if (paymentSource == VendorPaymentSource.paidFromActiveDrawer) {
      if (shiftId == null || staffId == null) {
        throw ArgumentError(
          'Shift ID and Staff ID are required when settling payment from active cash drawer.',
        );
      }
    }

    final effectiveDate = createdAt ?? DateTime.now();
    final formattedDate = _formatTimestamp(effectiveDate);

    return await database.transaction((txn) async {
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

      // 2. If paid from active drawer, verify active shift and auto-generate CashMovement (Pay-Out)
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

        await txn.insert(
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
          'reference_slip': referenceSlip?.trim(),
          'notes': notes?.trim(),
          'created_at': formattedDate,
        },
      );

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
        i.name AS raw_ingredient_name,
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
        i.name AS raw_ingredient_name,
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
