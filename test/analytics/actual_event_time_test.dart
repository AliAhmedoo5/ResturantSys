import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/time/actual_event_time.dart';

void main() {
  test('optional actual input shares strict Pakistan calendar parsing', () {
    expect(parseActualEventTime(' '), isNull);
    expect(parseActualEventTime(null), isNull);
    expect(parseActualEventTime('2026-10-28 10:30'), DateTime.utc(2026,10,28,5,30));
    expect(parseActualEventTime('2024-02-29 00:00'), DateTime.utc(2024,2,28,19));
    for (final invalid in ['2026-02-29 10:30','2026-04-31 10:30','2026-13-01 10:30','2026-10-28 24:00','2026-10-28 10:60','2026-10-28T10:30','2026-10-28 10:30Z']) {
      expect(() => parseActualEventTime(invalid), throwsFormatException);
    }
  });
}
