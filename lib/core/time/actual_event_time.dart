/// Parses the shared optional Pakistan-time input without the host timezone or
/// DateTime's automatic normalization of invalid calendar fields.
DateTime? parseActualEventTime(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) throw const FormatException('Use YYYY-MM-DD HH:MM for Pakistan time.');
  final fields = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
  final local = DateTime.utc(fields[0], fields[1], fields[2], fields[3], fields[4]);
  if (local.year != fields[0] || local.month != fields[1] || local.day != fields[2] || local.hour != fields[3] || local.minute != fields[4]) {
    throw const FormatException('Enter a valid Pakistan date and time (YYYY-MM-DD HH:MM).');
  }
  return local.subtract(const Duration(hours: 5));
}
