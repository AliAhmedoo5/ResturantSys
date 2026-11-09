import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_time.dart';

void main() {
  test('calendar query bounds preserve wall fields independently of host timezone', () {
    for (final input in [DateTime(2026, 10, 28, 10, 30, 15, 123, 456), DateTime.utc(2026, 10, 28, 10, 30, 15, 123, 456)]) {
      final normalized = analyticsWallClock(input);
      expect(normalized.isUtc, isTrue);
      expect(normalized, DateTime.utc(2026, 10, 28, 10, 30, 15, 123, 456));
      expect(analyticsKarachiTime('2026-10-28T05:30:15.123456Z'), normalized);
    }
  });

  test('formatAnalyticsTimestamp formats 12-hour time with AM/PM, real day, date, and business day', () {
    // 1. Afternoon time -> PM, with business day
    final ts1 = formatAnalyticsTimestamp('2026-11-09T17:10:20.451837', businessDayId: 1);
    expect(ts1, isNotNull);
    expect(ts1!.time12, '05:10 PM');
    expect(ts1.date, '09 Nov 2026');
    expect(ts1.realDay, 'Monday');
    expect(ts1.realDayShort, 'Mon');
    expect(ts1.displayLine, 'Mon, 09 Nov 2026 • 05:10 PM');
    expect(ts1.businessDayLabel, 'Business Day #1');
    expect(ts1.fullLabel, 'Mon, 09 Nov 2026 • 05:10 PM (Business Day #1)');

    // 2. Morning time -> AM
    final ts2 = formatAnalyticsTimestamp('2026-11-04 09:30:15', businessDayId: '5');
    expect(ts2, isNotNull);
    expect(ts2!.time12, '09:30 AM');
    expect(ts2.realDay, 'Wednesday');
    expect(ts2.businessDayLabel, 'Business Day #5');

    // 3. String that carries legacy notes doesn't crash and cleans properly
    final ts3 = formatAnalyticsTimestamp('2026-11-09 17:10:20 +05:00 [Asia/Karachi] (naive legacy timestamp; assumed Asia/Karachi)');
    expect(ts3, isNotNull);
    expect(ts3!.time12, '05:10 PM');
    expect(ts3.displayLine, 'Mon, 09 Nov 2026 • 05:10 PM');
    expect(ts3.displayLine, isNot(contains('naive legacy')));
    expect(ts3.displayLine, isNot(contains('[Asia/Karachi]')));
  });
}
