/// Known restaurant timestamps use Asia/Karachi (UTC+05:00). UTC instances
/// returned here carry wall-clock fields for deterministic grouping/formatting.
DateTime? analyticsKarachiTime(Object? raw) {
  if (raw is! String) return null;
  final parsed = DateTime.tryParse(raw);
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
