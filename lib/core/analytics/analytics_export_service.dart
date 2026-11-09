import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'openxml_workbook_builder.dart';

import 'analytics_models.dart';
import 'analytics_time.dart';

enum AnalyticsExportFormat { csv, xlsx, pdf }

typedef ExportProgressCallback = void Function(String stage, int current, int total);

class ExportCancellationToken {
  final bool Function()? _check;
  bool _isCancelled = false;

  ExportCancellationToken([this._check]);

  bool get isCancelled => _isCancelled || (_check?.call() ?? false);
  void cancel() => _isCancelled = true;
}

class ExportCancelledException implements Exception {
  final String message;
  const ExportCancelledException([this.message = 'Export was cancelled.']);
  @override
  String toString() => 'ExportCancelledException: $message';
}

/// Serializes the displayed immutable snapshot without querying operational data.
class AnalyticsExportService {
  Future<List<int>> pdf(
    AnalyticsSnapshot snapshot,
    AnalyticsFamily family, {
    ExportProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) throw const ExportCancelledException();
    final section = snapshot.section(family);
    final document = pw.Document(
      title: 'Manager analytics - ${section.title}',
      author: 'Staff ${snapshot.generatedByStaffId ?? "unknown"}',
    );

    final primaryDark = PdfColor.fromHex('#1E293B');
    final accentAmber = PdfColor.fromHex('#D97706');
    final borderGrey = PdfColor.fromHex('#CBD5E1');
    final cardBg = PdfColor.fromHex('#F8FAFC');

    onProgress?.call('Formatting document blocks', 50, 100);
    if (isCancelled?.call() == true) throw const ExportCancelledException();
    onProgress?.call('Rendering PDF pages', 100, 100);

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 1000,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => _buildBrandHeader(context, snapshot, section, family),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Exploratory snapshot | Asia/Karachi UTC+05:00', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
      ),
      build: (context) => [
        // 1. Executive KPI Cards
        if (section.metrics.isNotEmpty) ...[
          pw.Row(
            children: [
              pw.Container(width: 3.5, height: 11, color: accentAmber),
              pw.SizedBox(width: 5),
              pw.Text('Executive KPI Summary', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < section.metrics.length; i++)
                _buildKpiCard(section.metrics[i], i),
            ],
          ),
          pw.SizedBox(height: 12),
        ],

        // 2. Section Notes
        if (section.notes.isNotEmpty) ...[
          pw.Row(
            children: [
              pw.Container(width: 3.5, height: 10, color: accentAmber),
              pw.SizedBox(width: 5),
              pw.Text('Report Notes & Scope', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryDark)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: cardBg,
              border: pw.Border.all(color: borderGrey, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final note in section.notes)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• ', style: pw.TextStyle(fontSize: 7.5, color: accentAmber, fontWeight: pw.FontWeight.bold)),
                        pw.Expanded(
                          child: pw.Text(note, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
        ],

        // 3. Source Details Tables
        ..._buildSectionTables(section),

        // 4. Audit & Metadata Appendix
        pw.Row(
          children: [
            pw.Container(width: 3.5, height: 11, color: primaryDark),
            pw.SizedBox(width: 5),
            pw.Text('Audit & Metadata Appendix', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: cardBg,
            border: pw.Border.all(color: borderGrey, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final r in _metadata(snapshot, family.name))
                pw.SizedBox(
                  width: 240,
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '${r[0]}: ',
                          style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: primaryDark),
                        ),
                        pw.TextSpan(
                          text: '${r[1] ?? "Unknown"}',
                          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ));

    if (isCancelled?.call() == true) throw const ExportCancelledException();
    return document.save();
  }

  pw.Widget _buildBrandHeader(
    pw.Context context,
    AnalyticsSnapshot snapshot,
    AnalyticsSection section,
    AnalyticsFamily family,
  ) {
    final primaryDark = PdfColor.fromHex('#1E293B');
    final accentAmber = PdfColor.fromHex('#D97706');
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 12),
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
                    'CRUNCH CARTEL POS',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primaryDark),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: accentAmber,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Text(
                      family.name.toUpperCase(),
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'EXECUTIVE ANALYTICS REPORT | ${section.title.toUpperCase()}',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: accentAmber),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Period: ${_date(snapshot.query.startDate)} to ${_date(snapshot.query.endDateExclusive)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryDark)),
              pw.SizedBox(height: 2),
              pw.Text('Staff ID: ${snapshot.generatedByStaffId ?? "unknown"} | Asia/Karachi UTC+05:00', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildKpiCard(AnalyticsMetric metric, int index) {
    final colors = [
      PdfColor.fromHex('#2563EB'),
      PdfColor.fromHex('#059669'),
      PdfColor.fromHex('#D97706'),
      PdfColor.fromHex('#7C3AED'),
      PdfColor.fromHex('#0891B2'),
      PdfColor.fromHex('#DC2626'),
    ];
    final primaryDark = PdfColor.fromHex('#1E293B');
    final accentColor = metric.quality == AnalyticsQuality.missing
        ? PdfColors.grey400
        : (metric.changePercent != null && metric.changePercent! < 0
            ? PdfColor.fromHex('#DC2626')
            : colors[index % colors.length]);

    final badgeColor = metric.quality == AnalyticsQuality.complete
        ? PdfColor.fromHex('#059669')
        : (metric.quality == AnalyticsQuality.missing ? PdfColors.grey600 : PdfColor.fromHex('#D97706'));

    return pw.Container(
      width: 255,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
        border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1'), width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 3.5,
            height: 38,
            decoration: pw.BoxDecoration(
              color: accentColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        metric.label,
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                    pw.Text(
                      '[${metric.quality.name}]',
                      style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: badgeColor),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  _pdfValue(metric.value, metric.unit),
                  style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: primaryDark),
                ),
                pw.SizedBox(height: 2),
                if (metric.changeAbsolute != null)
                  pw.Text(
                    'Absolute change: ${_pdfValue(metric.changeAbsolute, metric.unit)}${metric.changePercent != null ? " (${metric.changePercent! >= 0 ? "+" : ""}${metric.changePercent!.toStringAsFixed(1)}%)" : ""}',
                    style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: metric.changeAbsolute! >= 0 ? PdfColor.fromHex('#059669') : PdfColor.fromHex('#DC2626')),
                  )
                else if (metric.changePercent != null)
                  pw.Text(
                    '${metric.changePercent! >= 0 ? "+" : ""}${metric.changePercent!.toStringAsFixed(1)}% vs prior period',
                    style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: metric.changePercent! >= 0 ? PdfColor.fromHex('#059669') : PdfColor.fromHex('#DC2626')),
                  )
                else
                  pw.Text(
                    'Coverage: ${metric.sampleCount ?? "unknown"} / ${metric.populationCount ?? "unknown"}',
                    style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600),
                  ),
                if (metric.explanation.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    metric.explanation,
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey500),
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tableTitle(String sourceType) {
    return switch (sourceType) {
      'orders' => 'Order Transactions',
      'order_workload' => 'Order Workload Projections',
      'weekday_order_peaks' => 'Weekday Order Distribution',
      'held_carts' => 'Current Active Holds',
      'hold_lifecycle_events' => 'Hold Lifecycle Events',
      'order_revisions' => 'Order Revisions & Line Audits',
      'shifts' => 'Shift Handover & Reconciliations',
      'cash_movements' => 'Till & Safe Cash Movements',
      'order_payments' => 'Tender Collections & Settlements',
      'business_days' => 'Business Day Performance',
      'mandi_procurements' => 'Procurement & Market Purchases',
      'vendor_khata' => 'Supplier Khata Accounts',
      'vendor_transactions' => 'Supplier Ledger Movements',
      'expense_entries' => 'Operating Expense Entries',
      'payroll_entries' => 'Staff Payroll Ledger',
      'kitchen_wastage' => 'Kitchen Spoilage & Wastage',
      'raw_ingredients' => 'Raw Ingredient Stock Levels',
      'inventory_movements' => 'Inventory Movements',
      'rider_trips' => 'Rider Delivery Trips',
      'attempts' => 'Delivery Fulfillment Attempts',
      'sold_items' => 'Menu Item Sales Breakdown',
      'allocations' => 'Order Item Allocations',
      _ => sourceType.replaceAll('_', ' ').toUpperCase(),
    };
  }

  List<pw.Widget> _buildSectionTables(AnalyticsSection section) {
    final primaryDark = PdfColor.fromHex('#1E293B');
    final accentAmber = PdfColor.fromHex('#D97706');
    final borderGrey = PdfColor.fromHex('#CBD5E1');
    final cardBg = PdfColor.fromHex('#F8FAFC');

    if (section.rows.isEmpty) {
      return [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const pw.EdgeInsets.only(top: 4, bottom: 8),
          decoration: pw.BoxDecoration(
            color: cardBg,
            border: pw.Border.all(color: borderGrey, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            'No source rows recorded for this report section in the selected period.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ];
    }

    final groups = <String, List<AnalyticsRow>>{};
    for (final row in section.rows) {
      groups.putIfAbsent(row.sourceType, () => []).add(row);
    }

    final widgets = <pw.Widget>[];

    for (final entry in groups.entries) {
      final sourceType = entry.key;
      final groupRows = entry.value;
      final groupKeys = groupRows.expand((r) => r.cells.keys).toSet();

      // Filter to relevant, non-internal business columns
      final availableCols = section.columns.where((c) {
        if (!groupKeys.contains(c.key)) return false;
        final k = c.key;
        if (k.endsWith('_source') || k.endsWith('_utc_source')) return false;
        if (k == 'contributing_business_day_ids' || k == 'business_day_status_evidence') return false;
        if (k == 'business_day_start' || k == 'business_day_end' || k == 'shift_start' || k == 'shift_end') return false;
        if (k == 'order_cashier_id' || (k == 'cashier_id' && groupKeys.contains('cashier_name_current'))) return false;
        if (k == 'employee_id' && groupKeys.contains('employee_name_current')) return false;
        if (k == 'vendor_id' && groupKeys.contains('supplier_name_current')) return false;
        return true;
      }).toList();

      // Limit columns to max 6 to prevent layout overflow in landscape A4
      final chosenCols = availableCols.length > 6 ? availableCols.take(6).toList() : availableCols;

      final cellAlignments = <int, pw.Alignment>{0: pw.Alignment.centerLeft};
      final headerAlignments = <int, pw.Alignment>{0: pw.Alignment.centerLeft};

      for (var i = 0; i < chosenCols.length; i++) {
        final col = chosenCols[i];
        if (col.unit == AnalyticsUnit.paisa ||
            col.unit == AnalyticsUnit.count ||
            col.unit == AnalyticsUnit.percent ||
            col.unit == AnalyticsUnit.minutes ||
            col.unit == AnalyticsUnit.decimal) {
          cellAlignments[i + 1] = pw.Alignment.centerRight;
          headerAlignments[i + 1] = pw.Alignment.centerRight;
        } else if (col.key == 'token' ||
            col.key == 'status' ||
            col.key == 'payment_status' ||
            col.key == 'dining_type' ||
            col.key == 'aging_status') {
          cellAlignments[i + 1] = pw.Alignment.center;
          headerAlignments[i + 1] = pw.Alignment.center;
        } else {
          cellAlignments[i + 1] = pw.Alignment.centerLeft;
          headerAlignments[i + 1] = pw.Alignment.centerLeft;
        }
      }

      // Safe limit of rows per table in PDF to prevent layout memory explosion
      const maxRowsPerTable = 100;
      final displayRows = groupRows.length > maxRowsPerTable ? groupRows.take(maxRowsPerTable).toList() : groupRows;

      widgets.addAll([
        pw.Row(
          children: [
            pw.Container(width: 3.5, height: 11, color: accentAmber),
            pw.SizedBox(width: 5),
            pw.Text(
              '${_tableTitle(sourceType)} (${groupRows.length} ${groupRows.length == 1 ? "record" : "records"})',
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryDark),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: [
            'Source / ID',
            ...chosenCols.map((c) => c.unit == AnalyticsUnit.paisa
                ? '${c.label} (PKR)'
                : (c.unit == AnalyticsUnit.percent
                    ? '${c.label} (%)'
                    : (c.unit == AnalyticsUnit.minutes ? '${c.label} (min)' : c.label))),
          ],
          data: [
            for (final row in displayRows)
              [
                '${row.sourceType} / ${row.sourceId ?? row.id}',
                ...chosenCols.map((col) => _pdfCell(row.cells[col.key], col)),
              ],
          ],
          cellAlignments: cellAlignments,
          headerAlignments: headerAlignments,
          headerDecoration: pw.BoxDecoration(color: primaryDark),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          oddRowDecoration: pw.BoxDecoration(color: cardBg),
          border: pw.TableBorder.all(color: borderGrey, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        ),
        if (groupRows.length > maxRowsPerTable)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(
              'Showing first $maxRowsPerTable of ${groupRows.length} records. Complete dataset available in Excel (.xlsx) and CSV exports.',
              style: const pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
            ),
          ),
        pw.SizedBox(height: 12),
      ]);
    }

    return widgets;
  }

  String _pdfCell(Object? value, AnalyticsColumn col) {
    if (value == null) return '—';
    if (col.unit == AnalyticsUnit.paisa && value is num) {
      return _formatCurrency(value);
    }
    if (col.unit == AnalyticsUnit.percent && value is num) {
      return '${value.toStringAsFixed(1)}%';
    }
    if (col.unit == AnalyticsUnit.minutes && value is num) {
      return '${value.toStringAsFixed(1)} min';
    }
    final ts = formatAnalyticsTimestamp(value);
    if (ts != null) return ts.fullLabel;
    if (value is double) {
      return value.toStringAsFixed(2);
    }
    return value.toString();
  }

  String _formatCurrency(num paisa) {
    final p = paisa.toInt();
    final isNeg = p < 0;
    final abs = p.abs();
    final r = abs ~/ 100;
    final c = abs % 100;
    final formattedR = r.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${isNeg ? '-' : ''}PKR $formattedR.${c.toString().padLeft(2, '0')}';
  }

  String _pdfValue(Object? value, AnalyticsUnit? unit) {
    if (value == null) return 'Missing data';
    if (unit == AnalyticsUnit.paisa && value is num) {
      return _formatCurrency(value);
    }
    final ts = formatAnalyticsTimestamp(value);
    if (ts != null) return ts.fullLabel;
    if (unit == AnalyticsUnit.percent && value is num) {
      return '${value.toStringAsFixed(1)}%';
    }
    return '$value${unit == null ? "" : " ${unit.name}"}';
  }

  /// Writes only to a directory deliberately selected by the caller. No delivery.
  Future<File> saveToDirectory(
    AnalyticsSnapshot snapshot,
    AnalyticsFamily family,
    AnalyticsExportFormat format,
    String directory, {
    bool Function()? canWrite,
    ExportProgressCallback? onProgress,
    ExportCancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? ExportCancellationToken();
    bool checkCancelled() => token.isCancelled;

    if (checkCancelled()) throw const ExportCancelledException();
    if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');
    if (!await Directory(directory).exists()) {
      throw FileSystemException('Selected export directory is unavailable.', directory);
    }

    onProgress?.call('Preparing export', 0, 100);

    final List<int> bytes = switch (format) {
      AnalyticsExportFormat.csv => utf8.encode(
          csv(snapshot, family, onProgress: onProgress, isCancelled: checkCancelled),
        ),
      AnalyticsExportFormat.xlsx => workbook(
          snapshot,
          onProgress: onProgress,
          isCancelled: checkCancelled,
        ),
      AnalyticsExportFormat.pdf => await pdf(
          snapshot,
          family,
          onProgress: onProgress,
          isCancelled: checkCancelled,
        ),
    };

    if (checkCancelled()) throw const ExportCancelledException();
    if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');

    final base = 'manager-analytics-${family.name}-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    var suffix = 0;
    var target = File(p.join(directory, '$base.${format.name}'));
    while (await target.exists()) {
      target = File(p.join(directory, '$base-${++suffix}.${format.name}'));
    }
    final partial = File('${target.path}.partial');
    try {
      if (checkCancelled()) throw const ExportCancelledException();
      if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');

      final sink = partial.openWrite();
      const chunkSize = 64 * 1024;
      var written = 0;
      try {
        for (var offset = 0; offset < bytes.length; offset += chunkSize) {
          if (checkCancelled()) throw const ExportCancelledException();
          if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');

          final end = (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
          sink.add(bytes.sublist(offset, end));
          written = end;
          onProgress?.call('Writing file', written, bytes.length);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (checkCancelled()) throw const ExportCancelledException();
      if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');

      onProgress?.call('Export complete', bytes.length, bytes.length);
      return await partial.rename(target.path);
    } catch (_) {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      rethrow;
    }
  }

  List<int> workbook(
    AnalyticsSnapshot snapshot, {
    ExportProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    if (isCancelled?.call() == true) throw const ExportCancelledException();
    final sheets = <String, List<List<Object?>>>{
      'Metadata': _metadata(snapshot, 'all snapshot families'),
      for (final section in snapshot.sections) section.family.name: _sectionRows(section),
    };

    final totalSheets = sheets.length;
    final renderedSheets = <({String name, String xml})>[];

    for (var sheet = 0; sheet < sheets.length; sheet++) {
      if (isCancelled?.call() == true) throw const ExportCancelledException();
      final sheetName = sheets.keys.elementAt(sheet);
      final rows = sheets.values.elementAt(sheet);
      onProgress?.call('Serializing sheet $sheetName', sheet + 1, totalSheets);
      final xml = StringBuffer('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
      xml.write('<cols>');
      xml.write('<col min="1" max="1" width="30" customWidth="1"/>');
      xml.write('<col min="2" max="2" width="28" customWidth="1"/>');
      xml.write('<col min="3" max="3" width="22" customWidth="1"/>');
      xml.write('<col min="4" max="150" width="22" customWidth="1"/>');
      xml.write('</cols>');
      xml.write('<sheetData>');
      for (var r = 0; r < rows.length; r++) {
        if (r % 100 == 0 && (isCancelled?.call() == true)) throw const ExportCancelledException();
        final rowData = rows[r];
        final isTableHead = rowData.isNotEmpty && (rowData.first == 'Metric ID' || rowData.first == 'Row ID');
        final isSectionRow = rowData.isNotEmpty && rowData.first == 'section';
        xml.write('<row r="${r + 1}">');
        for (var c = 0; c < rowData.length; c++) {
          final value = rowData[c];
          final ref = '${_column(c)}${r + 1}';
          final sAttr = isTableHead ? ' s="2"' : (isSectionRow || c == 0 ? ' s="1"' : '');
          xml.write(value is num && value.isFinite
              ? '<c r="$ref"$sAttr><v>$value</v></c>'
              : '<c r="$ref" t="inlineStr"$sAttr><is><t xml:space="preserve">${_xml(_safeText(value))}</t></is></c>');
        }
        xml.write('</row>');
      }
      xml.write('</sheetData></worksheet>');
      renderedSheets.add((name: sheetName, xml: xml.toString()));
    }
    if (isCancelled?.call() == true) throw const ExportCancelledException();
    onProgress?.call('Compressing workbook', totalSheets, totalSheets);
    return OpenXmlWorkbookBuilder.package(sheets: renderedSheets);
  }

  String _xml(String value) => OpenXmlWorkbookBuilder.escapeXml(value);

  String _column(int index) => OpenXmlWorkbookBuilder.columnIndexToLetter(index);

  String csv(
    AnalyticsSnapshot snapshot,
    AnalyticsFamily family, {
    ExportProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    if (isCancelled?.call() == true) throw const ExportCancelledException();
    final meta = _metadata(snapshot, family.name);
    final section = snapshot.section(family);
    final rows = _sectionRows(section);
    final allRows = <List<Object?>>[
      <Object?>['# =============================================================================='],
      <Object?>['# RESTAURANT ANALYTICS - EXECUTIVE CSV REPORT'],
      <Object?>['# Section: ${section.title} | Family: ${family.name.toUpperCase()} | Time Basis: ${snapshot.query.timeBasis.name}'],
      <Object?>['# Period: ${_date(snapshot.query.startDate)} to ${_date(snapshot.query.endDateExclusive)} | Staff ID: ${snapshot.generatedByStaffId ?? "unknown"}'],
      <Object?>['# Timezone: Asia/Karachi (UTC+05:00) | Generated: ${snapshot.generatedAt.toUtc().toIso8601String()}'],
      <Object?>['# =============================================================================='],
      <Object?>[],
      <Object?>['# --- 1. SECTION DATA & KPI METRICS ---'],
      ...rows,
      <Object?>[],
      <Object?>['# --- 2. AUDIT METADATA & SYSTEM PROVENANCE ---'],
      <Object?>['# --- AUDIT METADATA & SYSTEM PROVENANCE ---'],
      ...meta,
    ];
    final total = allRows.length;
    final buffer = StringBuffer();
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() == true) throw const ExportCancelledException();
      final row = allRows[i];
      buffer.write(row.map(_csvCell).join(','));
      if (i < total - 1) {
        buffer.write('\r\n');
      }
      if (i % 50 == 0 || i == total - 1) {
        onProgress?.call('Serializing CSV rows', i + 1, total);
      }
    }
    return buffer.toString();
  }

  List<List<Object?>> _metadata(AnalyticsSnapshot s, String family) => [
        ['report_version', s.reportVersion],
        ['source_schema_version', s.sourceSchemaVersion ?? 'Unavailable'],
        ['snapshot_cutoff_utc', s.generatedAt.toUtc().toIso8601String()],
        ['timestamp_policy', 'Asia/Karachi UTC+05:00; naive legacy values assumed Karachi; original UTC/offset values retained in source columns'],
        ['identity_policy', 'At-transaction names are retained evidence; current names are separately labeled; unavailable history is not backfilled'],
        ['report_kind', 'Exploratory current-record snapshot; not a sealed Z-report'],
        ['family', family],
        ['currency', 'PKR; money amounts use integer paisa (100 paisa = PKR 1); decimal unit rates retain labeled PKR/base-unit precision'],
        ['generated_utc', s.generatedAt.toUtc().toIso8601String()],
        ['generated_local', '${s.generatedAt.toUtc().add(const Duration(hours: 5)).toIso8601String().replaceAll('Z', '')}+05:00'],
        ['timezone', 'Asia/Karachi'],
        ['generated_by_staff_id', s.generatedByStaffId],
        ['business_date_start', _date(s.query.startDate)],
        ['business_date_end_exclusive', _date(s.query.endDateExclusive)],
        ['query_start_inclusive', '${s.query.startDate.toIso8601String().replaceAll('Z', '')}+05:00'],
        ['query_end_exclusive', '${s.query.endDateExclusive.toIso8601String().replaceAll('Z', '')}+05:00'],
        ['comparison_mode', s.query.comparisonMode.name],
        ['prior_window_start', s.query.priorStartDate == null ? 'None' : _date(s.query.priorStartDate!)],
        ['prior_window_end_exclusive', s.query.priorEndDateExclusive == null ? 'None' : _date(s.query.priorEndDateExclusive!)],
        ['prior_query_start_inclusive', s.query.priorStartDate == null ? 'None' : '${s.query.priorStartDate!.toIso8601String().replaceAll('Z', '')}+05:00'],
        ['prior_query_end_exclusive', s.query.priorEndDateExclusive == null ? 'None' : '${s.query.priorEndDateExclusive!.toIso8601String().replaceAll('Z', '')}+05:00'],
        ['business_day_ids', s.businessDayIds.join(';')],
        ['live', s.query.live.toString()],
        ['cashier_id', s.query.cashierId],
        ['shift_id', s.query.shiftId],
        ['dining_type', s.query.diningType],
        ['payment_method', s.query.paymentMethod],
        ['funding_stream', s.query.fundingStream],
        for (final entry in s.query.domainFilters.entries)
          [
            'domain_filter_${entry.key.name}',
            entry.value,
            s.filterOptions.where((o) => o.dimension == entry.key && o.id == entry.value).firstOrNull?.label ?? 'Unknown / archived ID'
          ],
        ['time_basis', s.query.timeBasis.name],
        ['grouping', s.query.grouping.name],
        ['hold_stale_threshold_minutes', s.query.holdStaleMinutes],
        ['bucket_definitions', 'Asia/Karachi; start inclusive, end exclusive; Business Day weekday = assigned opening date; calendar weekday = actual creation date; weeks start Monday; months = local calendar months.'],
        ['non_order_scope', 'Shifts/trips and non-order ledgers retain Business Day scope; current stock is current.'],
        ['filter_scope', 'Order cohorts, receiving/owning drawers and current Hold ownership have distinct scopes; each section discloses applicable filters. Current Holds use Cashier ownership only and ignore historical date/Shift/order predicates.'],
        for (final note in s.notes) ['snapshot_note', note],
      ];

  List<List<Object?>> _sectionRows(AnalyticsSection s) => [
        ['section', s.title],
        ['source_row_count', s.rows.length],
        ['metric_count', s.metrics.length],
        for (final note in s.notes) ['section_note', note],
        ['Metric ID', 'Metric', 'Value', 'Unit', 'Quality', 'Formula / explanation', 'Sample count', 'Population count', 'Change percent', 'Change absolute'],
        for (final m in s.metrics) [m.id, m.label, m.value, m.unit.name, m.quality.name, m.explanation, m.sampleCount, m.populationCount, m.changePercent, m.changeAbsolute],
        ['Row ID', 'Source type', 'Source ID', ...s.columns.map((c) => c.unit == null ? c.label : '${c.label} (${c.unit!.name})')],
        for (final row in s.rows) [row.id, row.sourceType, row.sourceId, ...s.columns.map((c) => row.cells[c.key])],
      ];

  String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _safeText(Object? value) {
    final text = value?.toString() ?? '';
    return RegExp(r'^(?:[\t\r\n]|\s*[=+\-@])').hasMatch(text) ? "'$text" : text;
  }

  String _csvCell(Object? value) {
    final text = value is num ? value.toString() : _safeText(value);
    return text.contains(RegExp('[,"\r\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
  }
}
