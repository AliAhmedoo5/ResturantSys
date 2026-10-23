import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/pos_database_constants.dart';
import '../orders/order_item.dart';
import 'z_report.dart';

/// Generates standardized 6-sheet OpenXML Excel workbooks (.xlsx) with unalterable ISO audit timestamps.
class ExcelReportingEngine {
  ExcelReportingEngine({required this.database});

  final Database database;

  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String _formatTimestamp(DateTime dt) {
    return _isoFormat.format(dt);
  }

  /// Default directory on disk where Excel reports are saved.
  static String resolveDefaultReportsDir({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final win = isWindows ?? Platform.isWindows;
    if (win) {
      final env = environment ?? Platform.environment;
      final programData = env['ProgramData'] ?? r'C:\ProgramData';
      return '$programData\\${PosDatabaseConstants.defaultProgramDataFolder}\\reports';
    }

    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? '.';
    return p.join(home, '.resturant_pos', 'reports');
  }

  /// Generates the complete 6-sheet .xlsx workbook as raw bytes.
  Future<List<int>> generateDailyWorkbookBytes({
    required int businessDayId,
    required ZReport zReport,
    DateTime? auditTimestamp,
  }) async {
    final now = auditTimestamp ?? DateTime.now();
    final isoTimestampStr = _formatTimestamp(now);

    final startTimestamp = _formatTimestamp(zReport.openedAt);
    final endTimestamp = _formatTimestamp((zReport.closedAt ?? now).add(const Duration(minutes: 5)));

    // 1. Gather Sheet 2: Sales by Item data
    final itemRows = await database.rawQuery('''
      SELECT 
        COALESCE(c.name, 'Deals & Combos') as category_name,
        oi.name as item_name,
        SUM(oi.quantity) as units_sold,
        SUM(oi.total_price) as gross_sales
      FROM ${PosDatabaseConstants.tableOrderItems} oi
      JOIN ${PosDatabaseConstants.tableOrders} o ON oi.order_id = o.id
      LEFT JOIN ${PosDatabaseConstants.tableMenuItems} mi ON oi.menu_item_id = mi.id
      LEFT JOIN ${PosDatabaseConstants.tableCategories} c ON mi.category_id = c.id
      WHERE o.business_day_id = ? AND o.payment_status = 'SETTLED'
      GROUP BY oi.name
      ORDER BY gross_sales DESC;
    ''', [businessDayId]);

    // 2. Gather Sheet 3: Stock & BOM Consumption data
    final ingRows = await database.rawQuery('''
      SELECT * FROM ${PosDatabaseConstants.tableRawIngredients}
      ORDER BY name ASC;
    ''');

    // Real BOM recipe usage from settled orders including Deals and Modifiers
    final settledOrderItems = await database.rawQuery('''
      SELECT oi.*
      FROM ${PosDatabaseConstants.tableOrderItems} oi
      JOIN ${PosDatabaseConstants.tableOrders} o ON oi.order_id = o.id
      WHERE o.business_day_id = ? AND o.payment_status = 'SETTLED';
    ''', [businessDayId]);

    final allRecipes = await database.query(PosDatabaseConstants.tableRecipes);
    final recipesByMenuItem = <int, List<Map<String, dynamic>>>{};
    for (final r in allRecipes) {
      final mId = r['menu_item_id'] as int;
      recipesByMenuItem.putIfAbsent(mId, () => []).add(r);
    }

    final recipeUsageMap = <int, double>{};

    for (final itemRow in settledOrderItems) {
      final item = OrderItem.fromMap(itemRow);
      final bom = item.decodedBom;
      if (bom != null) {
        for (final entry in bom.entries) {
          recipeUsageMap[entry.key] = (recipeUsageMap[entry.key] ?? 0) + entry.value;
        }
        continue;
      }
      final modifiers = item.decodedModifiers;
      final removedIngredientIds = <int>{};
      final positiveModifiers = <(int rawIngredientId, double delta)>[];

      for (final mod in modifiers) {
        final rawIngredientId = mod['raw_ingredient_id'] as int?;
        final name = (mod['name'] as String? ?? '').toLowerCase();
        final delta = (mod['ingredient_qty_delta'] as num?)?.toDouble() ?? 0.0;

        if (rawIngredientId != null) {
          if (delta == 0.0 || name.contains('no ')) {
            removedIngredientIds.add(rawIngredientId);
          } else if (delta > 0.0) {
            positiveModifiers.add((rawIngredientId, delta));
          }
        }
      }

      void accumulateMenuItemUsage(int menuItemId) {
        final recipes = recipesByMenuItem[menuItemId] ?? const [];
        for (final recipe in recipes) {
          final ingredientId = recipe['raw_ingredient_id'] as int;
          final qtyPerUnit = (recipe['quantity_per_recipe_unit'] as num).toDouble();
          if (removedIngredientIds.contains(ingredientId)) {
            continue;
          }
          recipeUsageMap[ingredientId] = (recipeUsageMap[ingredientId] ?? 0.0) + (qtyPerUnit * item.quantity);
        }
      }

      if (item.menuItemId != null) {
        accumulateMenuItemUsage(item.menuItemId!);
      } else if (item.dealId != null) {
        for (final choice in item.decodedDealChoices) {
          final choiceMenuItemId = choice['menu_item_id'] as int?;
          if (choiceMenuItemId != null) {
            accumulateMenuItemUsage(choiceMenuItemId);
          }
        }
      }

      for (final mod in positiveModifiers) {
        if (!removedIngredientIds.contains(mod.$1)) {
          recipeUsageMap[mod.$1] = (recipeUsageMap[mod.$1] ?? 0.0) + (mod.$2 * item.quantity);
        }
      }
    }

    final mandiSumRows = await database.rawQuery('''
      SELECT raw_ingredient_id, COALESCE(SUM(converted_quantity), 0.0) as purchased_qty
      FROM ${PosDatabaseConstants.tableMandiProcurements}
      WHERE created_at >= ? AND created_at <= ?
      GROUP BY raw_ingredient_id;
    ''', [startTimestamp, endTimestamp]);
    final mandiMap = {
      for (final r in mandiSumRows)
        r['raw_ingredient_id'] as int: (r['purchased_qty'] as num).toDouble()
    };

    final wastageSumRows = await database.rawQuery('''
      SELECT raw_ingredient_id, COALESCE(SUM(quantity), 0.0) as wasted_qty
      FROM ${PosDatabaseConstants.tableKitchenWastage}
      WHERE created_at >= ? AND created_at <= ?
      GROUP BY raw_ingredient_id;
    ''', [startTimestamp, endTimestamp]);
    final wastageMap = {
      for (final r in wastageSumRows)
        r['raw_ingredient_id'] as int: (r['wasted_qty'] as num).toDouble()
    };

    // 3. Gather Sheet 4: Kitchen Wastage Log
    final wastageLogRows = await database.rawQuery('''
      SELECT kw.*, ri.name as ingredient_name, ri.storage_unit, st.name as staff_name
      FROM ${PosDatabaseConstants.tableKitchenWastage} kw
      LEFT JOIN ${PosDatabaseConstants.tableRawIngredients} ri ON kw.raw_ingredient_id = ri.id
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON kw.staff_id = st.id
      WHERE kw.created_at >= ? AND kw.created_at <= ?
      ORDER BY kw.id ASC;
    ''', [startTimestamp, endTimestamp]);

    // 4. Gather Sheet 5: Shift Handover Audits with Pay-Ins/Outs & Voids
    final shiftHandoverRows = await database.rawQuery('''
      SELECT sh.*, st.name as cashier_name
      FROM ${PosDatabaseConstants.tableShifts} sh
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON sh.staff_id = st.id
      WHERE sh.business_day_id = ?
      ORDER BY sh.id ASC;
    ''', [businessDayId]);

    final shiftMovementsRows = await database.rawQuery('''
      SELECT cm.shift_id, cm.type, COALESCE(SUM(cm.amount), 0.0) as total_amt
      FROM ${PosDatabaseConstants.tableCashMovements} cm
      JOIN ${PosDatabaseConstants.tableShifts} sh ON cm.shift_id = sh.id
      WHERE sh.business_day_id = ?
      GROUP BY cm.shift_id, cm.type;
    ''', [businessDayId]);

    final shiftPayInMap = <int, double>{};
    final shiftPayOutMap = <int, double>{};
    for (final r in shiftMovementsRows) {
      final sId = r['shift_id'] as int;
      final type = r['type'] as String;
      final amt = (r['total_amt'] as num).toDouble();
      if (type == 'PAY_IN') {
        shiftPayInMap[sId] = (shiftPayInMap[sId] ?? 0.0) + amt;
      } else {
        shiftPayOutMap[sId] = (shiftPayOutMap[sId] ?? 0.0) + amt;
      }
    }

    final shiftVoidRows = await database.rawQuery('''
      SELECT shift_id, COUNT(id) as void_count
      FROM ${PosDatabaseConstants.tableOrders}
      WHERE business_day_id = ? AND payment_status = 'VOIDED'
      GROUP BY shift_id;
    ''', [businessDayId]);
    final shiftVoidMap = {
      for (final r in shiftVoidRows)
        ((r['shift_id'] as int?) ?? 0): (r['void_count'] as num).toInt()
    };

    // 5. Gather Sheet 6: Vendor Khata Ledger
    final vendorRows = await database.rawQuery('''
      SELECT * FROM ${PosDatabaseConstants.tableVendorKhata}
      ORDER BY name ASC;
    ''');

    final vendorDeliverySumRows = await database.rawQuery('''
      SELECT vendor_id, COALESCE(SUM(amount), 0.0) as total_delivery
      FROM ${PosDatabaseConstants.tableVendorTransactions}
      WHERE type = 'PURCHASE_CREDIT' AND created_at >= ? AND created_at <= ?
      GROUP BY vendor_id;
    ''', [startTimestamp, endTimestamp]);
    final vendorDeliveryMap = {
      for (final r in vendorDeliverySumRows)
        r['vendor_id'] as int: (r['total_delivery'] as num).toDouble()
    };

    final vendorPaymentSumRows = await database.rawQuery('''
      SELECT vendor_id, COALESCE(SUM(amount), 0.0) as total_paid
      FROM ${PosDatabaseConstants.tableVendorTransactions}
      WHERE type IN ('PAYMENT_DRAWER', 'PAYMENT_EXTERNAL') AND created_at >= ? AND created_at <= ?
      GROUP BY vendor_id;
    ''', [startTimestamp, endTimestamp]);
    final vendorPaymentMap = {
      for (final r in vendorPaymentSumRows)
        r['vendor_id'] as int: (r['total_paid'] as num).toDouble()
    };

    // Build the 6 Worksheets XML
    final sheet1Xml = _buildSheet1ExecutiveSummary(zReport, isoTimestampStr);
    final sheet2Xml = _buildSheet2SalesByItem(itemRows, isoTimestampStr);
    final sheet3Xml = _buildSheet3StockBOM(ingRows, mandiMap, wastageMap, recipeUsageMap, isoTimestampStr);
    final sheet4Xml = _buildSheet4KitchenWastage(wastageLogRows, isoTimestampStr);
    final sheet5Xml = _buildSheet5ShiftHandover(shiftHandoverRows, shiftPayInMap, shiftPayOutMap, shiftVoidMap, isoTimestampStr);
    final sheet6Xml = _buildSheet6VendorKhata(vendorRows, vendorDeliveryMap, vendorPaymentMap, isoTimestampStr);

    // Package into standard OOXML ZIP (.xlsx)
    return _packageOoxmlZip([
      sheet1Xml,
      sheet2Xml,
      sheet3Xml,
      sheet4Xml,
      sheet5Xml,
      sheet6Xml,
    ]);
  }


  /// Saves the generated workbook bytes to disk.
  Future<File> saveWorkbookToFile({
    required List<int> bytes,
    String? filePath,
    int? businessDayId,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final formattedTime = '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}';

    final effectivePath = filePath ??
        p.join(
          resolveDefaultReportsDir(),
          'z_report_day_${businessDayId ?? 1}_$formattedTime.xlsx',
        );

    final file = File(effectivePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Generates and saves the daily 6-sheet Excel report to disk in a single step.
  Future<File> exportDailyReportToFile({
    required int businessDayId,
    required ZReport zReport,
    String? filePath,
    DateTime? auditTimestamp,
  }) async {
    final bytes = await generateDailyWorkbookBytes(
      businessDayId: businessDayId,
      zReport: zReport,
      auditTimestamp: auditTimestamp,
    );
    return saveWorkbookToFile(
      bytes: bytes,
      filePath: filePath,
      businessDayId: businessDayId,
      timestamp: auditTimestamp,
    );
  }

  /// Renders the committed close snapshot without re-reading mutable catalog data.
  List<int> generateSnapshotWorkbook(List<Map<String, dynamic>> sections) {
    return _packageOoxmlZip(sections.map((section) {
      final builder = _SheetXmlBuilder();
      builder.addHeaderRow([section['title']]);
      builder.addTableHeaders(List<String>.from(section['headers'] as List));
      for (final row in section['rows'] as List) {
        builder.addRow(List<dynamic>.from(row as List));
      }
      if (section['detail_rows'] != null) {
        builder.addEmptyRow();
        builder.addSectionHeader('Recorded inventory movements');
        builder.addTableHeaders(List<String>.from(section['detail_headers'] as List));
        for (final row in section['detail_rows'] as List) {
          builder.addRow(List<dynamic>.from(row as List));
        }
      }
      return builder.build();
    }).toList());
  }

  // ===========================================================================
  // SHEET BUILDERS
  // ===========================================================================

  String _buildSheet1ExecutiveSummary(ZReport z, String isoTimestamp) {
    final b = _SheetXmlBuilder();

    b.addHeaderRow(['Resturant Operations POS - Executive Daily Summary']);
    b.addRow(['ISO Audit Timestamp', isoTimestamp]);
    b.addRow(['Business Day ID', '#${z.businessDayId}']);
    b.addRow(['Opened At', _formatTimestamp(z.openedAt), 'Opened By', z.openedByStaffName]);
    b.addRow(['Closed At', z.closedAt != null ? _formatTimestamp(z.closedAt!) : 'Active (Pre-Lock)', 'Closed By', z.closedByStaffName ?? 'N/A']);
    b.addEmptyRow();

    b.addSectionHeader('REVENUE & SALES METRICS');
    b.addRow(['Gross Sales', z.grossSales]);
    b.addRow(['Total Discounts Applied', z.totalDiscounts]);
    b.addRow(['Total Tax Collected', z.totalTax]);
    b.addRow(['Net Sales', z.netSales]);
    b.addRow(['Total Settled Orders', z.totalOrdersCount]);
    b.addEmptyRow();

    b.addSectionHeader('PAYMENT TENDERS BREAKDOWN');
    b.addRow(['Cash Sales (Net Tender Collection)', z.cashSales]);
    b.addRow(['Card Tender Sales', z.cardSales]);
    b.addRow(['Raast QR Tender Sales', z.raastSales]);
    b.addRow(['Total Tender Sales', z.totalTenderSales]);
    b.addEmptyRow();

    b.addSectionHeader('CASH DRAWER RECONCILIATION & VARIANCE');
    b.addRow(['Total Shift Opening Floats', z.totalOpeningFloat]);
    b.addRow(['(+) Cash Receipts', z.drawerCashReceipts]);
    b.addRow(['(+) Total Mid-Shift Pay-Ins', z.totalPayIn]);
    b.addRow(['(-) Total Mid-Shift Pay-Outs', z.totalPayOut]);
    b.addRow(['Expected Total Drawer Cash', z.totalExpectedDrawerCash]);
    b.addRow(['Actual Counted Drawer Cash', z.totalCountedCash]);
    b.addRow(['Net Cash Variance', z.netCashVariance]);
    b.addEmptyRow();

    b.addSectionHeader('SHIFT DISCREPANCIES AUDIT');
    if (z.shifts.isEmpty) {
      b.addRow(['No individual shift handovers recorded for this business day']);
    } else {
      b.addTableHeaders([
        'Shift ID',
        'Staff ID',
        'Expected Cash',
        'Counted Cash',
        'Discrepancy / Variance',
        'Audit Status',
      ]);
      for (final s in z.shifts) {
        b.addRow([
          '#${s.id}',
          'Staff #${s.staffId}',
          s.expectedCash ?? 0.0,
          s.countedCash ?? 0.0,
          s.discrepancy ?? 0.0,
          s.discrepancyStatus,
        ]);
      }
    }
    b.addEmptyRow();

    b.addSectionHeader('OPERATIONAL AUDIT & KHATA SUMMARY');
    b.addRow(['Total Shifts Handed Over', z.totalShiftsCount]);
    b.addRow(['Total Order Voids Count', z.totalVoidCount]);
    b.addRow(['Total Order Voids Value', z.totalVoidAmount]);
    b.addRow(['Kitchen Wastage Logs', z.totalWastageCount]);
    b.addRow(['Kitchen Wastage Financial Loss', z.totalWastageCost]);
    b.addRow(['Mandi Wholesale Purchases', z.totalMandiPurchasesCost]);
    b.addRow(['Vendor Khata Deliveries Count', z.totalVendorDeliveriesCount]);
    b.addRow(['Vendor Khata Payments Settled', z.totalVendorSettlementsAmount]);

    return b.build();
  }

  String _buildSheet2SalesByItem(List<Map<String, dynamic>> items, String isoTimestamp) {
    final b = _SheetXmlBuilder();

    b.addHeaderRow(['Sales by Menu Item Breakdown']);
    b.addRow(['ISO Audit Timestamp', isoTimestamp]);
    b.addEmptyRow();

    b.addTableHeaders(['Category', 'Item Name', 'Units Sold', 'Gross Sales (PKR)']);

    num totalUnits = 0;
    num totalGross = 0;

    for (final item in items) {
      final cat = item['category_name'] as String? ?? 'General';
      final name = item['item_name'] as String? ?? '';
      final units = item['units_sold'] as num? ?? 0;
      final sales = item['gross_sales'] as num? ?? 0;

      totalUnits += units;
      totalGross += sales;

      b.addRow([cat, name, units, sales]);
    }

    b.addEmptyRow();
    b.addBoldRow(['Total Sales', '', totalUnits, totalGross]);

    return b.build();
  }

  String _buildSheet3StockBOM(
    List<Map<String, dynamic>> ingredients,
    Map<int, double> mandiMap,
    Map<int, double> wastageMap,
    Map<int, double> recipeUsageMap,
    String isoTimestamp,
  ) {
    final b = _SheetXmlBuilder();

    b.addHeaderRow(['Stock & BOM Consumption Ledger']);
    b.addRow(['ISO Audit Timestamp', isoTimestamp]);
    b.addEmptyRow();

    b.addTableHeaders([
      'Raw Ingredient',
      'Storage Unit',
      'Opening Stock',
      'Mandi Purchases',
      'Recipe Usage',
      'Wastage',
      'Closing Stock',
    ]);

    for (final ing in ingredients) {
      final id = ing['id'] as int;
      final name = ing['name'] as String? ?? '';
      final unit = ing['storage_unit'] as String? ?? '';
      final closing = (ing['current_stock'] as num?)?.toDouble() ?? 0.0;
      final mandi = mandiMap[id] ?? 0.0;
      final wastage = wastageMap[id] ?? 0.0;
      final recipeUsage = recipeUsageMap[id] ?? 0.0;
      final opening = closing + recipeUsage + wastage - mandi;

      b.addRow([name, unit, opening, mandi, recipeUsage, wastage, closing]);
    }

    return b.build();
  }

  String _buildSheet4KitchenWastage(List<Map<String, dynamic>> logs, String isoTimestamp) {
    final b = _SheetXmlBuilder();

    b.addHeaderRow(['Kitchen Wastage Audit Log']);
    b.addRow(['ISO Audit Timestamp', isoTimestamp]);
    b.addEmptyRow();

    b.addTableHeaders([
      'Timestamp',
      'Ingredient',
      'Quantity',
      'Storage Unit',
      'Financial Loss (PKR)',
      'Reason',
      'Staff ID',
      'Staff Name',
      'Notes',
    ]);

    num totalLoss = 0;
    for (final log in logs) {
      final ts = log['created_at'] as String? ?? '';
      final ing = log['ingredient_name'] as String? ?? '';
      final qty = log['quantity'] as num? ?? 0;
      final unit = log['storage_unit'] as String? ?? '';
      final loss = log['cost_loss'] as num? ?? 0;
      final reason = log['reason'] as String? ?? '';
      final staffId = log['staff_id'] as int? ?? 0;
      final staffName = log['staff_name'] as String? ?? '';
      final notes = log['notes'] as String? ?? '';

      totalLoss += loss;
      b.addRow([ts, ing, qty, unit, loss, reason, staffId, staffName, notes]);
    }

    b.addEmptyRow();
    b.addBoldRow(['Total Wastage Loss', '', '', '', totalLoss, '', '', '', '']);

    return b.build();
  }

  String _buildSheet5ShiftHandover(
    List<Map<String, dynamic>> shifts,
    Map<int, double> payInMap,
    Map<int, double> payOutMap,
    Map<int, int> voidMap,
    String isoTimestamp,
  ) {
    final b = _SheetXmlBuilder();

    b.addHeaderRow(['Shift Handover & Drawer Cash Reconciliations']);
    b.addRow(['ISO Audit Timestamp', isoTimestamp]);
    b.addEmptyRow();

    b.addTableHeaders([
      'Shift ID',
      'Cashier',
      'Opened At',
      'Closed At',
      'Opening Float',
      'Pay-Ins',
      'Pay-Outs',
      'Expected Cash',
      'Counted Cash',
      'Variance',
      'Discrepancy Status',
      'Voids',
      'Status',
    ]);

    for (final sh in shifts) {
      final sId = sh['id'] as int;
      final id = '#$sId';
      final cashier = sh['cashier_name'] as String? ?? 'Staff #${sh['staff_id']}';
      final openedAt = sh['opened_at'] as String? ?? '';
      final closedAt = sh['closed_at'] as String? ?? 'Active';
      final float = sh['opening_float'] as num? ?? 0;
      final payIns = payInMap[sId] ?? 0.0;
      final payOuts = payOutMap[sId] ?? 0.0;
      final expected = sh['expected_cash'] as num? ?? 0;
      final counted = sh['counted_cash'] as num? ?? 0;
      final variance = sh['discrepancy'] as num? ?? 0;
      final discStatus = sh['discrepancy_status'] as String? ?? 'CLEAN';
      final voids = voidMap[sId] ?? 0;
      final status = sh['status'] as String? ?? 'OPEN';

      b.addRow([
        id,
        cashier,
        openedAt,
        closedAt,
        float,
        payIns,
        payOuts,
        expected,
        counted,
        variance,
        discStatus,
        voids,
        status,
      ]);
    }

    return b.build();
  }

  String _buildSheet6VendorKhata(
    List<Map<String, dynamic>> vendors,
    Map<int, double> deliveryMap,
    Map<int, double> paymentMap,
    String isoTimestamp,
  ) {
    final b = _SheetXmlBuilder();

    b.addHeaderRow(['Vendor Khata (Supplier Credit) Ledger']);
    b.addRow(['ISO Audit Timestamp', isoTimestamp]);
    b.addEmptyRow();

    b.addTableHeaders([
      'Vendor Name',
      'Phone Number',
      'Supplied Ingredients',
      'Deliveries Received (PKR)',
      'Payments Settled (PKR)',
      'Current Outstanding Balance (PKR)',
    ]);

    num totalDeliveries = 0;
    num totalPaid = 0;
    num totalBalance = 0;

    for (final v in vendors) {
      final id = v['id'] as int;
      final name = v['name'] as String? ?? '';
      final phone = v['phone'] as String? ?? '';
      final ing = v['supplied_ingredients'] as String? ?? '';
      final delivery = deliveryMap[id] ?? 0.0;
      final paid = paymentMap[id] ?? 0.0;
      final balance = (v['current_balance'] as num?)?.toDouble() ?? 0.0;

      totalDeliveries += delivery;
      totalPaid += paid;
      totalBalance += balance;

      b.addRow([name, phone, ing, delivery, paid, balance]);
    }

    b.addEmptyRow();
    b.addBoldRow(['Total Khata Balance', '', '', totalDeliveries, totalPaid, totalBalance]);

    return b.build();
  }

  // ===========================================================================
  // OOXML PACKAGING
  // ===========================================================================

  List<int> _packageOoxmlZip(List<String> sheetsXml) {
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet4.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet5.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet6.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';
    archive.addFile(ArchiveFile.string('[Content_Types].xml', contentTypesXml));

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    archive.addFile(ArchiveFile.string('_rels/.rels', rootRelsXml));

    // 3. xl/workbook.xml
    const workbookXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Executive Summary" sheetId="1" r:id="rId1"/>
    <sheet name="Sales by Item" sheetId="2" r:id="rId2"/>
    <sheet name="Stock &amp; BOM Consumption" sheetId="3" r:id="rId3"/>
    <sheet name="Kitchen Wastage Log" sheetId="4" r:id="rId4"/>
    <sheet name="Shift Handover Audits" sheetId="5" r:id="rId5"/>
    <sheet name="Vendor Khata Ledger" sheetId="6" r:id="rId6"/>
  </sheets>
</workbook>''';
    archive.addFile(ArchiveFile.string('xl/workbook.xml', workbookXml));

    // 4. xl/_rels/workbook.xml.rels
    const workbookRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/>
  <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet5.xml"/>
  <Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet6.xml"/>
  <Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';
    archive.addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', workbookRelsXml));

    // 5. xl/styles.xml
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/><diagonal/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
</styleSheet>''';
    archive.addFile(ArchiveFile.string('xl/styles.xml', stylesXml));

    // 6. Worksheets
    for (var i = 0; i < sheetsXml.length; i++) {
      archive.addFile(ArchiveFile.string('xl/worksheets/sheet${i + 1}.xml', sheetsXml[i]));
    }

    return ZipEncoder().encode(archive)!;
  }
}

/// Helper class to assemble OpenXML worksheet XML nodes.
class _SheetXmlBuilder {
  final StringBuffer _buffer = StringBuffer();
  int _currentRow = 0;

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _colName(int colIndex) {
    var name = '';
    var n = colIndex;
    while (n > 0) {
      final rem = (n - 1) % 26;
      name = String.fromCharCode(65 + rem) + name;
      n = (n - rem) ~/ 26;
    }
    return name;
  }

  void addEmptyRow() {
    _currentRow++;
    _buffer.writeln('<row r="$_currentRow"/>');
  }

  void addHeaderRow(List<dynamic> values) {
    _currentRow++;
    _buffer.writeln('<row r="$_currentRow">');
    for (var i = 0; i < values.length; i++) {
      final ref = '${_colName(i + 1)}$_currentRow';
      final val = values[i];
      _buffer.writeln('<c r="$ref" t="inlineStr" s="1"><is><t>${_escapeXml(val.toString())}</t></is></c>');
    }
    _buffer.writeln('</row>');
  }

  void addSectionHeader(String title) {
    _currentRow++;
    final ref = 'A$_currentRow';
    _buffer.writeln('<row r="$_currentRow">');
    _buffer.writeln('<c r="$ref" t="inlineStr" s="1"><is><t>${_escapeXml(title)}</t></is></c>');
    _buffer.writeln('</row>');
  }

  void addTableHeaders(List<String> headers) {
    addHeaderRow(headers);
  }

  void addBoldRow(List<dynamic> values) {
    _currentRow++;
    _buffer.writeln('<row r="$_currentRow">');
    for (var i = 0; i < values.length; i++) {
      final ref = '${_colName(i + 1)}$_currentRow';
      final val = values[i];
      if (val is num) {
        _buffer.writeln('<c r="$ref" s="1"><v>$val</v></c>');
      } else {
        _buffer.writeln('<c r="$ref" t="inlineStr" s="1"><is><t>${_escapeXml(val.toString())}</t></is></c>');
      }
    }
    _buffer.writeln('</row>');
  }

  void addRow(List<dynamic> values) {
    _currentRow++;
    _buffer.writeln('<row r="$_currentRow">');
    for (var i = 0; i < values.length; i++) {
      final ref = '${_colName(i + 1)}$_currentRow';
      final val = values[i];
      if (val is num) {
        _buffer.writeln('<c r="$ref"><v>$val</v></c>');
      } else {
        _buffer.writeln('<c r="$ref" t="inlineStr"><is><t>${_escapeXml(val.toString())}</t></is></c>');
      }
    }
    _buffer.writeln('</row>');
  }

  String build() {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
$_buffer  </sheetData>
</worksheet>''';
  }
}
