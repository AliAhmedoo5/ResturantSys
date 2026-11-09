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

    onProgress?.call('Formatting document blocks', 50, 100);
    if (isCancelled?.call() == true) throw const ExportCancelledException();
    onProgress?.call('Rendering PDF pages', 100, 100);

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 100000,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#1E293B'), width: 1.5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Restaurant Analytics - Executive Report',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B')),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  section.title.toUpperCase(),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#D97706')),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Staff ID: ${snapshot.generatedByStaffId ?? "unknown"}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.Text('Period: ${_date(snapshot.query.startDate)} to ${_date(snapshot.query.endDateExclusive)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ],
        ),
      ),
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
          pw.Text('Executive KPI Summary', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B'))),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final metric in section.metrics)
                pw.Container(
                  width: 230,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8FAFC'),
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        metric.label,
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        _pdfValue(metric.value, metric.unit),
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B')),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: pw.BoxDecoration(
                              color: metric.quality == AnalyticsQuality.complete ? PdfColor.fromHex('#DCFCE7') : PdfColor.fromHex('#FEF3C7'),
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                            ),
                            child: pw.Text(
                              '[${metric.quality.name}]',
                              style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: metric.quality == AnalyticsQuality.complete ? PdfColors.green800 : PdfColor.fromHex('#B45309')),
                            ),
                          ),
                          if (metric.changePercent != null) ...[
                            pw.SizedBox(width: 4),
                            pw.Text(
                              '${metric.changePercent! >= 0 ? "+" : ""}${metric.changePercent!.toStringAsFixed(1)}% vs prior',
                              style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: metric.changePercent! >= 0 ? PdfColors.green800 : PdfColors.red800),
                            ),
                          ],
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(metric.explanation, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                      if (metric.sampleCount != null && metric.populationCount != null)
                        pw.Text('Coverage: ${metric.sampleCount} / ${metric.populationCount}', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500)),
                      if (metric.isBalance)
                        pw.Text('Snapshot balance (point-in-time)', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey500)),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
        ],

        // 2. Section Notes
        if (section.notes.isNotEmpty) ...[
          for (final note in section.notes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text('Note: $note', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ),
          pw.SizedBox(height: 8),
        ],

        // 3. Source Details Table
        if (section.rows.isNotEmpty) ...[
          pw.Text('Source details (${section.rows.length} rows)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B'))),
          pw.SizedBox(height: 5),
          pw.TableHelper.fromTextArray(
            headers: ['Source / ID', ...section.columns.map((col) => col.unit == null ? col.label : '${col.label} (${col.unit!.name})')],
            data: [
              for (final row in section.rows)
                ['${row.sourceType} / ${row.sourceId ?? row.id}', ...section.columns.map((col) => _pdfValue(row.cells[col.key], col.unit))],
            ],
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              for (var i = 0; i < section.columns.length; i++)
                i + 1: (section.columns[i].unit != null || section.rows.any((r) => r.cells[section.columns[i].key] is num))
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
            },
            headerAlignments: {
              0: pw.Alignment.centerLeft,
              for (var i = 0; i < section.columns.length; i++)
                i + 1: (section.columns[i].unit != null || section.rows.any((r) => r.cells[section.columns[i].key] is num))
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
            },
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#1E293B')),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 8),
            oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC')),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          ),
          pw.SizedBox(height: 12),
        ],

        // 4. Audit & Metadata Appendix (placed at the end of the format)
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F8FAFC'),
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Audit & Metadata Appendix', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B'))),
              pw.SizedBox(height: 4),
              for (final r in _metadata(snapshot, family.name))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 1.5),
                  child: pw.Text('${r[0]}: ${r[1] ?? "Unknown"}', style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                ),
            ],
          ),
        ),
      ],
    ));

    if (isCancelled?.call() == true) throw const ExportCancelledException();
    return document.save();
  }

  String _pdfValue(Object? value, AnalyticsUnit? unit) {
    if (value == null) return 'Missing data';
    if (unit == AnalyticsUnit.paisa && value is num) {
      final isNeg = value < 0;
      final absVal = value.abs();
      final rupees = (absVal / 100).floor();
      final paisa = (absVal % 100).round();
      final formattedR = rupees.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return '${isNeg ? "-" : ""}PKR $formattedR.${paisa.toString().padLeft(2, "0")}';
    }
    final ts = formatAnalyticsTimestamp(value);
    if (ts != null) return ts.fullLabel;
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
      for (final section in snapshot.sections) section.family.name: _sectionRows(section),
      'Metadata': _metadata(snapshot, 'all snapshot families'),
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
      xml.write('<col min="4" max="25" width="20" customWidth="1"/>');
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
          final isNumeric = value is num && value.isFinite;
          final sAttr = isTableHead
              ? (isNumeric ? ' s="8"' : ' s="2"')
              : (isSectionRow
                  ? ' s="7"'
                  : (isNumeric ? ' s="4"' : (c == 0 ? ' s="1"' : '')));
          xml.write(isNumeric
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
