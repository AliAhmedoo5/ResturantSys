import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'excel_reporting_engine.dart';
import '../payments/payment_event.dart';

/// A sealed report snapshot survives process loss and filesystem outages.
class ReportExportService {
  ReportExportService({required this.database, String? directory})
      : directory = directory ?? (database.path == inMemoryDatabasePath
          ? ExcelReportingEngine.resolveDefaultReportsDir()
          : p.join(p.dirname(database.path), 'reports'));
  final Database database;
  final String directory;

  static Future<void> capture(DatabaseExecutor db, int dayId, int managerId) async {
    final day = (await db.query('business_days', where: 'id=?', whereArgs: [dayId])).single;
    final opened = day['opened_at'] as String;
    final closed = day['closed_at'] as String;
    final openedByStaffId = day['opened_by_staff_id'];
    final closedByStaffId = day['closed_by_staff_id'];

    String openedByName = 'Manager';
    String closedByName = 'Manager';
    if (openedByStaffId != null) {
      final staffRow = await db.query('staff', where: 'id=?', whereArgs: [openedByStaffId], limit: 1);
      if (staffRow.isNotEmpty) openedByName = staffRow.first['name'] as String;
    }
    if (closedByStaffId != null) {
      final staffRow = await db.query('staff', where: 'id=?', whereArgs: [closedByStaffId], limit: 1);
      if (staffRow.isNotEmpty) closedByName = staffRow.first['name'] as String;
    }

    final generated = DateTime.now();
    final name = await db.query('system_settings', where: "key='restaurant_name'");
    final restaurantName = name.isEmpty ? 'Crunch Cartel POS' : name.first['value'] as String;

    final totals = (await db.rawQuery("""SELECT COUNT(*) AS orders,
      COALESCE(SUM(CAST(ROUND(subtotal*100) AS INTEGER)),0) AS gross,
      COALESCE(SUM(CAST(ROUND(discount_amount*100) AS INTEGER)),0) AS discount,
      COALESCE(SUM(CAST(ROUND(tax_amount*100) AS INTEGER)),0) AS tax,
      COALESCE(SUM(CAST(ROUND(grand_total*100) AS INTEGER)),0) AS net,
      COALESCE(SUM(cash_rounding_paisa),0) AS rounding
      FROM orders WHERE business_day_id=? AND payment_status NOT IN ('VOIDED','CANCELLED','REFUNDED')""", [dayId])).single;

    final tenders = await db.rawQuery("""SELECT op.payment_method,
      SUM(COALESCE(op.amount_tendered_paisa,CAST(ROUND(op.amount_tendered*100) AS INTEGER))
      -COALESCE(op.change_returned_paisa,CAST(ROUND(op.change_returned*100) AS INTEGER))) AS paisa
      FROM order_payments op JOIN orders o ON o.id=op.order_id LEFT JOIN payment_events pe ON pe.tender_id=op.id
      WHERE COALESCE(pe.business_day_id,o.business_day_id)=? AND (pe.id IS NOT NULL OR o.payment_status IN ('SETTLED','REFUND_PENDING','CANCELLED','REFUNDED'))
      GROUP BY op.payment_method ORDER BY op.payment_method""", [dayId]);

    final due = (await db.rawQuery("SELECT COALESCE(SUM($outstandingCollectionPaisaSql),0) AS paisa FROM orders o WHERE o.business_day_id=? AND o.payment_status='COLLECTION_DUE'", [dayId])).single['paisa'];

    final sales = await db.rawQuery("""SELECT o.token_number,oi.name,oi.quantity,
      CAST(ROUND(oi.total_price*100) AS INTEGER) AS paisa,o.payment_status
      FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE o.business_day_id=? ORDER BY o.token_number,oi.id""", [dayId]);

    final channels = await db.rawQuery("""SELECT dining_type, COUNT(*) as orders_count,
      COALESCE(SUM(CAST(ROUND(subtotal*100) AS INTEGER)), 0) as food_paisa,
      COALESCE(SUM(delivery_fee_paisa), 0) as delivery_paisa,
      COALESCE(SUM(CAST(ROUND(grand_total*100) AS INTEGER)), 0) as total_paisa
      FROM orders
      WHERE business_day_id = ? AND payment_status NOT IN ('VOIDED', 'CANCELLED', 'REFUNDED')
      GROUP BY dining_type ORDER BY dining_type""", [dayId]);

    final inventory = await db.rawQuery("""SELECT i.name,i.storage_unit,i.current_stock,
      COALESCE((SELECT SUM(m.quantity_delta) FROM inventory_movements m WHERE m.ingredient_id=i.id AND m.business_day_id=?),0) AS delta
      FROM raw_ingredients i ORDER BY i.name""", [dayId]);

    final movementRows = await db.rawQuery("""SELECT m.id,m.recorded_at,i.name,m.quantity_delta,m.balance_after
      FROM inventory_movements m JOIN raw_ingredients i ON i.id=m.ingredient_id
      WHERE m.business_day_id=? ORDER BY m.id""",[dayId]);

    final wastage = await db.rawQuery("""SELECT w.created_at,i.name,w.quantity,w.reason,CAST(ROUND(w.cost_loss*100) AS INTEGER) AS loss, st.name as staff_name
      FROM kitchen_wastage w JOIN raw_ingredients i ON i.id=w.raw_ingredient_id
      LEFT JOIN staff st ON st.id=w.staff_id
      WHERE datetime(w.created_at)>=datetime(?) AND datetime(w.created_at)<=datetime(?) ORDER BY w.id""", [opened,closed]);

    final shifts = await db.rawQuery("""SELECT s.*,st.name FROM shifts s JOIN staff st ON st.id=s.staff_id
      WHERE s.business_day_id=? ORDER BY s.id""", [dayId]);

    final cashMovements = await db.rawQuery("""SELECT cm.*, st.name as staff_name
      FROM cash_movements cm
      JOIN shifts s ON s.id = cm.shift_id
      LEFT JOIN staff st ON st.id = cm.staff_id
      WHERE s.business_day_id = ? ORDER BY cm.id""", [dayId]);

    final vendors = await db.rawQuery("""SELECT v.name,t.type,CAST(ROUND(t.amount*100) AS INTEGER) AS paisa,t.created_at,t.reference_slip,t.due_date
      FROM vendor_transactions t JOIN vendor_khata v ON v.id=t.vendor_id
      WHERE datetime(t.created_at)>=datetime(?) AND datetime(t.created_at)<=datetime(?) ORDER BY t.id""", [opened,closed]);

    final riderTrips = await db.rawQuery("""SELECT rt.*, st.name as rider_name
      FROM rider_trips rt
      LEFT JOIN staff st ON st.id = rt.rider_staff_id
      WHERE rt.business_day_id = ? ORDER BY rt.id""", [dayId]);

    final workedHours = await db.rawQuery("""SELECT wh.*, st.name as employee_name, d.name as department_name
      FROM worked_hours wh
      JOIN staff st ON st.id = wh.employee_id
      LEFT JOIN departments d ON d.id = wh.department_id
      WHERE wh.business_day_id = ? ORDER BY wh.id""", [dayId]);

    final expenses = await db.rawQuery("""SELECT ee.*, st.name as manager_name
      FROM expense_entries ee
      LEFT JOIN staff st ON st.id = ee.manager_id
      WHERE ee.business_day_id = ? ORDER BY ee.id""", [dayId]);

    final payrolls = await db.rawQuery("""SELECT pe.*, st.name as employee_name
      FROM payroll_entries pe
      JOIN staff st ON st.id = pe.employee_id
      WHERE datetime(pe.created_at)>=datetime(?) AND datetime(pe.created_at)<=datetime(?)
      ORDER BY pe.id""", [opened, closed]);

    int paisa(Object? value) => (((value as num?)?.toDouble() ?? 0)*100).round();

    final totalCountedPaisa = shifts.fold<int>(0, (sum, s) => sum + (s['counted_cash'] != null ? paisa(s['counted_cash']) : 0));
    final totalExpectedPaisa = shifts.fold<int>(0, (sum, s) => sum + paisa(s['expected_cash']));
    final totalDiscrepancyPaisa = shifts.fold<int>(0, (sum, s) => sum + (s['discrepancy'] != null ? paisa(s['discrepancy']) : 0));
    final totalExpensePaisa = expenses.fold<int>(0, (sum, e) => sum + (e['amount_paisa'] as int? ?? 0));
    final totalDrawerPayoutPaisa = cashMovements.where((cm) => cm['type'] == 'PAY_OUT').fold<int>(0, (sum, cm) => sum + paisa(cm['amount']));
    final totalOwnerExpensePaisa = expenses.where((e) => e['source'] == 'OWNER').fold<int>(0, (sum, e) => sum + (e['amount_paisa'] as int? ?? 0));
    final totalPayrollAccruedPaisa = payrolls.fold<int>(0, (sum, p) => sum + (p['amount_paisa'] as int? ?? 0));
    final totalWastageLossPaisa = wastage.fold<int>(0, (sum, w) => sum + (w['loss'] as int? ?? 0));
    final totalWorkedMinutes = workedHours.fold<int>(0, (sum, w) => sum + (w['worked_minutes'] as int? ?? 0));
    final finalSafeCashPaisa = totalCountedPaisa;

    Map<String,dynamic> section(String title,List<String> headers,List<List<dynamic>> rows) => {'title':title,'headers':headers,'rows':rows};

    final sections = [
      section('Z-Report / Executive Summary', ['Measure','Value (money in integer paisa)'], [
        ['Restaurant', restaurantName],
        ['Business Day', dayId],
        ['Business date', opened.substring(0, 10)],
        ['Opened', opened],
        ['Closed / snapshot cutoff', closed],
        ['Generated', generated.toIso8601String()],
        ['Timezone', generated.timeZoneName],
        ['UTC offset minutes', generated.timeZoneOffset.inMinutes],
        ['Report revision', 1],
        ['Orders', totals['orders']],
        ['Gross sales', totals['gross']],
        ['Discounts', totals['discount']],
        ['Tax carve-out', totals['tax']],
        ['Net sales incl. Collection Due', totals['net']],
        ['Cash rounding', totals['rounding']],
        ['Collection Due', due],
        ...tenders.map((r) => ['Tender ${r['payment_method']} (collected)', r['paisa']]),
        ['Count missing shifts', shifts.where((s) => s['counted_cash'] == null).length],
        ['Total cash counted', totalCountedPaisa],
        ['Net cash discrepancy', totalDiscrepancyPaisa],
        ['Total operating expenses', totalExpensePaisa],
        ['Total wastage loss', totalWastageLossPaisa],
        ['Total worked labor hours', (totalWorkedMinutes / 60.0).toStringAsFixed(1)],
      ]),
      section('Sales by Item / Order Status', ['Token','Item','Quantity','Amount (paisa)','Payment status'], sales.map((r) => [r['token_number'], r['name'], r['quantity'], r['paisa'], r['payment_status']]).toList()),
      section('Inventory Movement', ['Ingredient','Unit','Opening stock','Net movement','Closing stock'], inventory.map((r) => [r['name'], r['storage_unit'], (r['current_stock'] as num) - (r['delta'] as num), r['delta'], r['current_stock']]).toList()),
      section('Kitchen Wastage', ['Recorded','Ingredient','Quantity','Reason','Loss (paisa)'], wastage.map((r) => [r['created_at'], r['name'], r['quantity'], r['reason'], r['loss']]).toList()),
      section('Shift Handover Audit', ['Shift','Cashier','Float (paisa)','Expected (paisa)','Counted (paisa)','Variance (paisa)','Audit'], shifts.map((r) => [r['id'], r['name'], paisa(r['opening_float']), paisa(r['expected_cash']), r['counted_cash'] == null ? 'NOT COUNTED' : paisa(r['counted_cash']), r['discrepancy'] == null ? 'UNKNOWN' : paisa(r['discrepancy']), r['discrepancy_status']]).toList()),
      section('Vendor Khata Movements', ['Vendor','Type','Amount (paisa)','Recorded'], vendors.map((r) => [r['name'], r['type'], r['paisa'], r['created_at']]).toList()),
      section('Delivery & Rider Fulfillment', ['Trip #', 'Rider', 'Status', 'Dispatched', 'Settled', 'Expected COD (paisa)', 'Collected COD (paisa)', 'Variance (paisa)'], riderTrips.map((r) => [r['trip_name'] ?? 'Trip #${r['id']}', r['rider_name'] ?? 'Rider', r['status'], r['dispatched_at'] ?? 'N/A', r['settled_at_utc'] ?? 'In-Flight', r['cash_expected_paisa'] ?? 0, r['cash_collected_paisa'] ?? 0, ((r['cash_collected_paisa'] as num?) ?? 0) - ((r['cash_expected_paisa'] as num?) ?? 0)]).toList()),
      section('Labor & Attendance Productivity', ['Employee', 'Department', 'Work Date', 'Clock In', 'Clock Out', 'Break (min)', 'Worked (min)'], workedHours.map((w) => [w['employee_name'], w['department_name'] ?? 'Front Counter', w['work_date'], w['clock_in'], w['clock_out'], w['break_minutes'], w['worked_minutes']]).toList()),
      section('Operating Expenses & Payroll', ['Category', 'Description', 'Payee', 'Source', 'Amount (paisa)', 'Recorded'], expenses.map((e) => [e['category_snapshot'] ?? 'Operating', e['description'], e['payee'], e['source'], e['amount_paisa'], e['created_at']]).toList()),
      section('Overall Financial Position & Safe Handover', ['Financial Item', 'Classification', 'Amount (paisa)', 'Audit Notes'], [
        ['Cashier Drawers Physical Count', 'TILL_HANDOVER', totalCountedPaisa, 'Audited physical count across closed shifts'],
        ['Drawer Cash Pay-Outs', 'OPERATIONAL_OUTFLOW', totalDrawerPayoutPaisa, 'Operational till outflows during shifts'],
        ['Owner Out-Of-Pocket Expenses', 'OWNER_OUTFLOW', totalOwnerExpensePaisa, 'Expenses settled directly from owner personal funds'],
        ['Accrued Staff Payroll', 'LIABILITY_ACCRUAL', totalPayrollAccruedPaisa, 'Staff payroll accrued during business day'],
        ['Final Safe Cash Handover', 'SAFE_DEPOSIT', finalSafeCashPaisa, 'Total physical cash deposited into master safe'],
      ]),
    ];

    // Detail rows for Excel / drill-downs
    sections[1]['channel_headers'] = ['Dining Channel', 'Orders', 'Food Sales (paisa)', 'Delivery Surcharges (paisa)', 'Total (paisa)'];
    sections[1]['channel_rows'] = channels.map((c) => [c['dining_type'], c['orders_count'], c['food_paisa'], c['delivery_paisa'], c['total_paisa']]).toList();

    sections[2]['detail_headers'] = ['Movement ID', 'Recorded', 'Ingredient', 'Quantity delta', 'Balance after'];
    sections[2]['detail_rows'] = movementRows.map((r) => [r['id'], r['recorded_at'], r['name'], r['quantity_delta'], r['balance_after']]).toList();

    sections[4]['detail_headers'] = ['Shift ID', 'Recorded', 'Type', 'Category', 'Amount (paisa)', 'Notes'];
    sections[4]['detail_rows'] = cashMovements.map((cm) => [cm['shift_id'], cm['created_at'], cm['type'], cm['category'], paisa(cm['amount']), cm['notes'] ?? '']).toList();

    sections[8]['detail_headers'] = ['Employee', 'Period', 'Kind', 'Source', 'Amount (paisa)', 'Recorded'];
    sections[8]['detail_rows'] = payrolls.map((p) => [p['employee_name'], p['period'], p['kind'], p['source'], p['amount_paisa'], p['created_at']]).toList();

    final kpis = {
      'restaurant_name': restaurantName,
      'business_day_id': dayId,
      'business_date': opened.substring(0, 10),
      'opened_at': opened,
      'closed_at': closed,
      'opened_by_name': openedByName,
      'closed_by_name': closedByName,
      'gross_sales_paisa': totals['gross'],
      'net_sales_paisa': totals['net'],
      'orders_count': totals['orders'],
      'counted_cash_paisa': totalCountedPaisa,
      'expected_cash_paisa': totalExpectedPaisa,
      'discrepancy_paisa': totalDiscrepancyPaisa,
      'total_expenses_paisa': totalExpensePaisa,
      'wastage_loss_paisa': totalWastageLossPaisa,
      'worked_minutes': totalWorkedMinutes,
      'labor_hours': totalWorkedMinutes / 60.0,
    };

    final policies = await db.query('system_settings', where: "key='report_delivery_settings'");
    final delivery = policies.isEmpty ? null : jsonDecode(policies.single['value'] as String);
    final snapshot = jsonEncode({
      'kpis': kpis,
      'delivery': delivery,
      'business_day_id': dayId,
      'business_date': opened.substring(0, 10),
      'revision': 1,
      'cutoff': closed,
      'sections': sections,
    });

    await db.insert('report_runs', {
      'business_day_id': dayId,
      'snapshot_json': snapshot,
      'content_hash': sha256.convert(utf8.encode(snapshot)).toString(),
      'created_by': managerId,
      'created_at': generated.toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> history() => database.query('report_runs', orderBy: 'id DESC');

  /// Returns successfully persisted immutable artifact references.
  Future<void> exportPending() async {
    final runs = await database.query('report_runs', where: "status != 'READY'", orderBy: 'id');
    for (final run in runs) {
      final now = DateTime.now().toUtc();
      final claimed = await database.update('report_runs', {
        'status': 'GENERATING',
        'export_lease_until': now.add(const Duration(minutes: 10)).toIso8601String(),
      }, where: "id=? AND status!='READY' AND (status!='GENERATING' OR export_lease_until IS NULL OR export_lease_until<=?)",
        whereArgs: [run['id'], now.toIso8601String()]);
      if (claimed != 1) continue;
      try {
        final snapshot = jsonDecode(run['snapshot_json'] as String) as Map<String, dynamic>;
        final sections = (snapshot['sections'] as List).map((s) => Map<String, dynamic>.from(s as Map)).toList();
        final kpis = snapshot['kpis'] as Map<String, dynamic>? ?? {};
        final dayId = snapshot['business_day_id'] ?? 0;
        final businessDate = snapshot['business_date'] as String? ?? '';
        final contentHash = run['content_hash'] as String? ?? '';
        final base = 'business_day_${dayId}_${businessDate}_v1_${contentHash.length >= 12 ? contentHash.substring(0, 12) : contentHash}';
        final folder = Directory(directory);
        await folder.create(recursive: true);

        final document = pw.Document(
          title: 'Business Day $businessDate Z-Report',
          author: kpis['restaurant_name'] as String? ?? 'Crunch Cartel POS',
        );

        String money(num? value) {
          if (value == null) return 'Rs. 0.00';
          final p = value.toInt();
          final isNeg = p < 0;
          final abs = p.abs();
          final r = abs ~/ 100;
          final c = abs % 100;
          final formattedR = r.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
          return '${isNeg ? '-' : ''}Rs. $formattedR.${c.toString().padLeft(2, '0')}';
        }

        final primaryDark = PdfColor.fromHex('#1E293B');
        final accentAmber = PdfColor.fromHex('#D97706');
        final borderGrey = PdfColor.fromHex('#E2E8F0');
        final cardBg = PdfColor.fromHex('#F8FAFC');

        pw.Widget buildBrandHeader(pw.Context context, String sectionTitle) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: primaryDark, width: 1.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          kpis['restaurant_name'] as String? ?? 'CRUNCH CARTEL POS',
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primaryDark),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: pw.BoxDecoration(
                            color: accentAmber,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                          ),
                          child: pw.Text('DAY #$dayId', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('EXECUTIVE Z-REPORTClose | ${sectionTitle.toUpperCase()}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: accentAmber)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Date: $businessDate', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryDark)),
                    pw.Text('Asia/Karachi UTC+05:00', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                    pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          );
        }

        pw.Widget buildCard(String title, String mainValue, String subText, {PdfColor? badgeColor}) {
          return pw.Container(
            width: 145,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: cardBg,
              border: pw.Border.all(color: borderGrey),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                pw.SizedBox(height: 3),
                pw.Text(mainValue, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryDark)),
                pw.SizedBox(height: 2),
                pw.Text(subText, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: badgeColor ?? PdfColors.grey600)),
              ],
            ),
          );
        }

        pw.Widget buildEmptyBox(String message) {
          return pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const pw.EdgeInsets.only(top: 4, bottom: 8),
            decoration: pw.BoxDecoration(
              color: cardBg,
              border: pw.Border.all(color: borderGrey),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(message, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          );
        }

        // PAGE 1: Executive Dashboard, Financial Summary & Item Sales
        final grossPaisa = (kpis['gross_sales_paisa'] as num?)?.toInt() ?? 0;
        final netPaisa = (kpis['net_sales_paisa'] as num?)?.toInt() ?? 0;
        final countedPaisa = (kpis['counted_cash_paisa'] as num?)?.toInt() ?? 0;
        final discPaisa = (kpis['discrepancy_paisa'] as num?)?.toInt() ?? 0;
        final ordersCount = (kpis['orders_count'] as num?)?.toInt() ?? 0;
        final wastagePaisa = (kpis['wastage_loss_paisa'] as num?)?.toInt() ?? 0;
        final expensePaisa = (kpis['total_expenses_paisa'] as num?)?.toInt() ?? 0;
        final workedMins = (kpis['worked_minutes'] as num?)?.toDouble() ?? 0.0;
        final laborHours = workedMins / 60.0;
        final salesPerHour = laborHours > 0 ? money((netPaisa / laborHours).round()) : 'Rs. 0.00';
        final ordersPerHour = laborHours > 0 ? (ordersCount / laborHours).toStringAsFixed(2) : '0';

        final monetarySummaryLabels = {
          'Gross sales', 'Discounts', 'Tax carve-out', 'Net sales incl. Collection Due',
          'Cash rounding', 'Collection Due', 'Total cash counted', 'Net cash discrepancy',
          'Total operating expenses', 'Total wastage loss',
        };

        document.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          maxPages: 1000,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => buildBrandHeader(context, 'Executive Dashboard & Item Sales'),
          footer: (context) => pw.Text('Snapshot: $contentHash | Immutable Z-Close Document', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
          build: (context) => [
            // KPI Scorecard Grid
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                buildCard('GROSS / NET SALES', money(netPaisa), '$ordersCount Orders | Gross: ${money(grossPaisa)}'),
                buildCard('CASH IN TILL HANDOVER', money(countedPaisa), 'Physical Count in Drawers'),
                buildCard('CASH DISCREPANCY', money(discPaisa), discPaisa == 0 ? 'STATUS: CLEAN (0.00 Variance)' : 'STATUS: REVIEW NEEDED', badgeColor: discPaisa == 0 ? PdfColor.fromHex('#15803D') : PdfColor.fromHex('#B91C1C')),
                buildCard('OPERATIONAL OVERHEADS', money(expensePaisa), 'Total Day In-Drawer & Owner Expenses'),
                buildCard('KITCHEN WASTAGE LOSS', money(wastagePaisa), 'Recorded Cooking / Spoilage Loss'),
                buildCard('LOGGED LABOR HOURS', '${laborHours.toStringAsFixed(1)} hrs', 'Verified Staff On-Shift Attendance'),
              ],
            ),
            pw.SizedBox(height: 12),

            // Executive Summary & Tenders Table
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Executive Financial Summary & Tender Collections', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: ['Financial Measure', 'Recorded Value'],
              data: (sections[0]['rows'] as List).map((row) {
                final r = List<dynamic>.from(row as List);
                final label = r[0].toString();
                final val = r[1];
                final isMoney = val is num && (monetarySummaryLabels.contains(label) || label.startsWith('Tender '));
                return [label, isMoney ? money(val) : val.toString()];
              }).toList(),
              headerDecoration: pw.BoxDecoration(color: primaryDark),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              oddRowDecoration: pw.BoxDecoration(color: cardBg),
              border: pw.TableBorder.all(color: borderGrey, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            ),
            pw.SizedBox(height: 12),

            // Sales by Item Table
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Sales by Item & Order Status', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: ['Token', 'Item Name', 'Quantity', 'Amount', 'Payment Status'],
              data: (sections[1]['rows'] as List).map((row) {
                final r = List<dynamic>.from(row as List);
                return [r[0].toString(), r[1].toString(), r[2].toString(), money(r[3] as num?), r[4].toString()];
              }).toList(),
              headerDecoration: pw.BoxDecoration(color: primaryDark),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              oddRowDecoration: pw.BoxDecoration(color: cardBg),
              border: pw.TableBorder.all(color: borderGrey, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            ),
            pw.SizedBox(height: 12),

            // Sales Channels Breakdown
            if (sections[1]['channel_rows'] != null && (sections[1]['channel_rows'] as List).isNotEmpty) ...[
              pw.Row(
                children: [
                  pw.Container(width: 3.5, height: 11, color: accentAmber),
                  pw.SizedBox(width: 5),
                  pw.Text('Sales by Dining Channel (Dine-In, Takeaway, Delivery)', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: ['Dining Channel', 'Orders', 'Food Sales', 'Delivery Fees', 'Channel Total'],
                data: (sections[1]['channel_rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), money(r[2] as num?), money(r[3] as num?), money(r[4] as num?)];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              ),
            ],
          ],
        ));

        // PAGE 2: Shift Handover Audits, Fulfillment & Labor Productivity
        document.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          maxPages: 1000,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => buildBrandHeader(context, 'Shift Audits, Delivery & Labor Productivity'),
          footer: (context) => pw.Text('Snapshot: $contentHash | Page ${context.pageNumber}', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
          build: (context) => [
            // Shift Handover Audit Table
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Cashier Shift Reconciliation & Blind Count Handover', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: ['Shift', 'Cashier', 'Opening Float', 'Expected Cash', 'Counted Cash', 'Variance', 'Audit Status'],
              data: (sections[4]['rows'] as List).map((row) {
                final r = List<dynamic>.from(row as List);
                return [
                  r[0].toString(),
                  r[1].toString(),
                  money(r[2] as num?),
                  money(r[3] as num?),
                  r[4] == 'NOT COUNTED' ? 'NOT COUNTED' : money(r[4] as num?),
                  r[5] == 'UNKNOWN' ? 'UNKNOWN' : money(r[5] as num?),
                  r[6].toString(),
                ];
              }).toList(),
              headerDecoration: pw.BoxDecoration(color: primaryDark),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              oddRowDecoration: pw.BoxDecoration(color: cardBg),
              border: pw.TableBorder.all(color: borderGrey, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            ),
            if (sections[4]['detail_rows'] != null && (sections[4]['detail_rows'] as List).isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Drawer Cash Movements (Pay-Ins & Pay-Outs)', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              pw.SizedBox(height: 3),
              pw.TableHelper.fromTextArray(
                headers: ['Shift', 'Recorded At', 'Movement', 'Category', 'Amount', 'Reason / Notes'],
                data: (sections[4]['detail_rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), r[2].toString(), r[3].toString(), money(r[4] as num?), r[5].toString()];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#334155')),
                headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              ),
            ],
            pw.SizedBox(height: 12),
            // Delivery & Rider Trips
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Delivery & Rider Trip Settlements', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            if ((sections[6]['rows'] as List).isEmpty)
              buildEmptyBox('No delivery rider trips dispatched during this business day (0 trips).')
            else
              pw.TableHelper.fromTextArray(
                headers: ['Trip #', 'Rider Name', 'Status', 'Dispatched', 'Settled At', 'Expected COD', 'Collected COD', 'Trip Discrepancy'],
                data: (sections[6]['rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [
                    r[0].toString(),
                    r[1].toString(),
                    r[2].toString(),
                    r[3].toString(),
                    r[4].toString(),
                    money(r[5] as num?),
                    money(r[6] as num?),
                    money(r[7] as num?),
                  ];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              ),
            pw.SizedBox(height: 14),

            // Labor & Attendance Productivity
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Staff Attendance & Labor Productivity', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            if ((sections[7]['rows'] as List).isEmpty)
              buildEmptyBox('No staff attendance or worked hours logged for this business day (0 records).')
            else ...[
              pw.TableHelper.fromTextArray(
                headers: ['Employee Name', 'Department / Role', 'Work Date', 'Clock In', 'Clock Out', 'Break (min)', 'Worked (min)', 'Labor Hours'],
                data: (sections[7]['rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  final minutes = (r[6] as num?)?.toInt() ?? 0;
                  return [
                    r[0].toString(),
                    r[1].toString(),
                    r[2].toString(),
                    r[3].toString(),
                    r[4].toString(),
                    r[5].toString(),
                    r[6].toString(),
                    '${(minutes / 60.0).toStringAsFixed(1)} hrs',
                  ];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: cardBg,
                  border: pw.Border.all(color: borderGrey),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Text('Total Direct Labor: ${laborHours.toStringAsFixed(1)} hrs', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryDark)),
                    pw.Text('Sales Productivity: $salesPerHour/hr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('Orders / Labor Hour: $ordersPerHour orders/hr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          ],
        ));

        // PAGE 3: Kitchen Production, Wastage & Inventory Movement
        document.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          maxPages: 1000,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => buildBrandHeader(context, 'Kitchen Production, Wastage & Stock Bridge'),
          footer: (context) => pw.Text('Snapshot: $contentHash | Page ${context.pageNumber}', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
          build: (context) => [
            // Kitchen Wastage
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Kitchen Wastage Incidents', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            if ((sections[3]['rows'] as List).isEmpty)
              buildEmptyBox('Zero kitchen wastage recorded during this business day (Rs. 0.00 loss).')
            else
              pw.TableHelper.fromTextArray(
                headers: ['Recorded Time', 'Raw Ingredient', 'Quantity Discarded', 'Reason / Incident', 'Financial Loss'],
                data: (sections[3]['rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), r[2].toString(), r[3].toString(), money(r[4] as num?)];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              ),
            pw.SizedBox(height: 14),

            // Inventory Movement
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Raw Ingredient Stock Bridge & Consumption', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: ['Ingredient Name', 'Storage Unit', 'Opening Stock', 'Net Movement Delta', 'Closing Stock Balance'],
              data: (sections[2]['rows'] as List).map((row) {
                final r = List<dynamic>.from(row as List);
                return [r[0].toString(), r[1].toString(), r[2].toString(), r[3].toString(), r[4].toString()];
              }).toList(),
              headerDecoration: pw.BoxDecoration(color: primaryDark),
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              oddRowDecoration: pw.BoxDecoration(color: cardBg),
              border: pw.TableBorder.all(color: borderGrey, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
            ),
            if (sections[2]['detail_rows'] != null && (sections[2]['detail_rows'] as List).isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Recorded Ledger Movements', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              pw.SizedBox(height: 3),
              pw.TableHelper.fromTextArray(
                headers: ['Movement ID', 'Recorded At', 'Ingredient', 'Quantity Delta', 'Balance After'],
                data: (sections[2]['detail_rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), r[2].toString(), r[3].toString(), r[4].toString()];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#334155')),
                headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              ),
            ],
          ],
        ));

        // PAGE 4: Overheads, Payroll & Vendor Khata Ledger
        document.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          maxPages: 1000,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => buildBrandHeader(context, 'Overheads, Khata & Final Safe Settlement'),
          footer: (context) => pw.Text('Snapshot: $contentHash | Page ${context.pageNumber}', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
          build: (context) => [
            // Operating Expenses
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Operating Expenses & Outflows', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            if ((sections[8]['rows'] as List).isEmpty)
              buildEmptyBox('Zero operating expenses logged for this business day (0 records).')
            else
              pw.TableHelper.fromTextArray(
                headers: ['Category', 'Description', 'Payee', 'Payment Source', 'Amount', 'Recorded At'],
                data: (sections[8]['rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), r[2].toString(), r[3].toString(), money(r[4] as num?), r[5].toString()];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              ),
            pw.SizedBox(height: 10),

            // Staff Payroll Accruals
            if (sections[8]['detail_rows'] != null && (sections[8]['detail_rows'] as List).isNotEmpty) ...[
              pw.Text('Staff Payroll Accruals & Advances', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              pw.SizedBox(height: 3),
              pw.TableHelper.fromTextArray(
                headers: ['Employee Name', 'Period', 'Kind', 'Payment Source', 'Amount', 'Recorded At'],
                data: (sections[8]['detail_rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), r[2].toString(), r[3].toString(), money(r[4] as num?), r[5].toString()];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#334155')),
                headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              ),
              pw.SizedBox(height: 10),
            ],

            // Vendor Khata Movements
            pw.Row(
              children: [
                pw.Container(width: 3.5, height: 11, color: accentAmber),
                pw.SizedBox(width: 5),
                pw.Text('Supplier Khata Movements & Settlements', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              ],
            ),
            pw.SizedBox(height: 4),
            if ((sections[5]['rows'] as List).isEmpty)
              buildEmptyBox('Zero vendor Khata transactions recorded during this business day (0 records).')
            else
              pw.TableHelper.fromTextArray(
                headers: ['Supplier Name', 'Transaction Type', 'Settlement Amount', 'Recorded At'],
                data: (sections[5]['rows'] as List).map((row) {
                  final r = List<dynamic>.from(row as List);
                  return [r[0].toString(), r[1].toString(), money(r[2] as num?), r[3].toString()];
                }).toList(),
                headerDecoration: pw.BoxDecoration(color: primaryDark),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                oddRowDecoration: pw.BoxDecoration(color: cardBg),
                border: pw.TableBorder.all(color: borderGrey, width: 0.5),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              ),
            pw.SizedBox(height: 12),

            // Final Safe Handover Summary Card
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: cardBg,
                border: pw.Border.all(color: accentAmber, width: 1.2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DAY CLOSE AUDIT & MASTER SAFE HANDOVER', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryDark)),
                      pw.SizedBox(height: 2),
                      pw.Text('Physical Cash Deposited in Safe: ${money(countedPaisa)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: accentAmber)),
                      pw.Text('Reconciled by: ${kpis['closed_by_name'] ?? "Manager"} | Business Day #$dayId status: LOCKED & SEALED', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Container(
                    width: 140,
                    height: 35,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: borderGrey)),
                    child: pw.Center(child: pw.Text('Manager Signature / Seal', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
                  ),
                ],
              ),
            ),
          ],
        ));

        final outputs = {
          'pdf': await document.save(),
          'xlsx': ExcelReportingEngine(database: database).generateSnapshotWorkbook(sections),
        };
        final previous = run['artifacts_json'] == null ? <dynamic>[] : jsonDecode(run['artifacts_json'] as String) as List;
        final artifacts = <Map<String, dynamic>>[];
        for (final output in outputs.entries) {
          final earlier = previous.where((artifact) => artifact['kind'] == output.key).toList();
          final path = earlier.isEmpty ? p.join(directory, '$base.${output.key}') : earlier.single['path'] as String;
          final file = File(path);
          final expected = await file.exists() && earlier.isNotEmpty ? earlier.single['sha256'] as String : sha256.convert(output.value).toString();
          artifacts.add({'kind': output.key, 'path': path, 'sha256': expected, 'size_bytes': output.value.length});
        }
        await database.update('report_runs', {'artifacts_json': jsonEncode(artifacts)}, where: 'id=?', whereArgs: [run['id']]);
        for (final artifact in artifacts) {
          final file = File(artifact['path'] as String);
          if (!await file.exists()) {
            await file.parent.create(recursive: true);
            final temporary = File('${file.path}.tmp');
            await temporary.writeAsBytes(outputs[artifact['kind']]!, flush: true);
            await temporary.rename(file.path);
          }
          final bytes = await file.readAsBytes();
          if (sha256.convert(bytes).toString() != artifact['sha256']) {
            throw StateError('Existing report file failed its immutable checksum');
          }
          artifact['size_bytes'] = bytes.length;
        }
        await database.update('report_runs', {'status': 'READY', 'artifacts_json': jsonEncode(artifacts), 'error_message': null, 'export_lease_until': null}, where: 'id=?', whereArgs: [run['id']]);
      } catch (e) {
        await database.update('report_runs', {'status': 'PENDING', 'error_message': 'Local report export failed; check storage and retry.', 'export_lease_until': null}, where: 'id=?', whereArgs: [run['id']]);
      }
    }
  }
}
