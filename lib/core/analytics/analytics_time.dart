import 'package:intl/intl.dart';

/// Known restaurant timestamps use Asia/Karachi (UTC+05:00). UTC instances
/// returned here carry wall-clock fields for deterministic grouping/formatting.
DateTime analyticsWallClock(DateTime time) => DateTime.utc(time.year, time.month,
    time.day, time.hour, time.minute, time.second, time.millisecond, time.microsecond);

DateTime? analyticsKarachiTime(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) {
    final utc = raw.isUtc ? raw.add(const Duration(hours: 5)) : raw;
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second, utc.millisecond, utc.microsecond);
  }
  if (raw is! String) return null;

  var cleaned = raw.trim();
  // Strip trailing bracketed annotations like "[Asia/Karachi]" or "(naive legacy...)"
  if (cleaned.contains('[')) {
    cleaned = cleaned.substring(0, cleaned.indexOf('[')).trim();
  }
  if (cleaned.contains('(')) {
    cleaned = cleaned.substring(0, cleaned.indexOf('(')).trim();
  }

  final parsed = DateTime.tryParse(cleaned) ?? DateTime.tryParse(raw);
  if (parsed == null) return null;
  if (parsed.isUtc) return parsed.add(const Duration(hours: 5));
  return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
      parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
}

String? analyticsTimestamp(Object? raw) {
  final time = analyticsKarachiTime(raw);
  if (time == null) return null;
  final text = time.toIso8601String().replaceFirst('T', ' ').split('.').first;
  return '$text +05:00 [Asia/Karachi]${analyticsTimestampAssumption(raw) ? ' (naive legacy timestamp; assumed Asia/Karachi)' : ''}';
}

bool analyticsTimestampAssumption(Object? raw) => raw is String &&
    DateTime.tryParse(raw) != null && !DateTime.parse(raw).isUtc;

/// Rich, human-readable timestamp model with 12-hour AM/PM time, date, real day of week,
/// and Business Day attribution for clear dashboard displays.
class FormattedAnalyticsTimestamp {
  const FormattedAnalyticsTimestamp({
    required this.time12,
    required this.date,
    required this.realDay,
    required this.realDayShort,
    required this.displayLine,
    this.businessDayLabel,
    this.rawIso,
    this.isDateOnly = false,
  });

  /// 12-hour time with uppercase AM / PM: e.g. "05:10 PM"
  final String time12;

  /// Calendar date: e.g. "09 Nov 2026"
  final String date;

  /// Full real day of week: e.g. "Monday"
  final String realDay;

  /// Short real day of week: e.g. "Mon"
  final String realDayShort;

  /// Single line display: e.g. "Mon, 09 Nov 2026 • 05:10 PM" or "Mon, 09 Nov 2026"
  final String displayLine;

  /// Optional Business Day label: e.g. "Business Day #1"
  final String? businessDayLabel;

  /// Original raw string for tooltip inspection
  final String? rawIso;

  /// Whether this was pure date with no time
  final bool isDateOnly;

  /// Full human-readable label: "Mon, 09 Nov 2026 • 05:10 PM (Business Day #1)"
  String get fullLabel => businessDayLabel != null
      ? '$displayLine ($businessDayLabel)'
      : displayLine;

  @override
  String toString() => fullLabel;
}

/// Formats any operational timestamp into human-readable 12-hour AM/PM time,
/// calendar date, real day of the week, and associated Business Day.
FormattedAnalyticsTimestamp? formatAnalyticsTimestamp(
  Object? raw, {
  Object? businessDayId,
}) {
  final time = analyticsKarachiTime(raw);
  if (time == null) return null;

  final isDateOnly = raw is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw.trim());
  final time12 = DateFormat('hh:mm a').format(time);
  final date = DateFormat('dd MMM yyyy').format(time);
  final realDay = DateFormat('EEEE').format(time);
  final realDayShort = DateFormat('EEE').format(time);
  final displayLine = isDateOnly ? '$realDayShort, $date' : '$realDayShort, $date • $time12';

  String? dayLabel;
  if (businessDayId != null) {
    final str = businessDayId.toString().trim();
    if (str.isNotEmpty && str != 'null' && str != '—') {
      final numOnly = str.replaceAll(RegExp(r'[^0-9]'), '');
      if (numOnly.isNotEmpty) {
        dayLabel = 'Business Day #$numOnly';
      } else {
        dayLabel = str;
      }
    }
  }

  return FormattedAnalyticsTimestamp(
    time12: time12,
    date: date,
    realDay: realDay,
    realDayShort: realDayShort,
    displayLine: displayLine,
    businessDayLabel: dayLabel,
    rawIso: raw?.toString(),
    isDateOnly: isDateOnly,
  );
}
