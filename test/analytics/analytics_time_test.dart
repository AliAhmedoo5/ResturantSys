import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_time.dart';

void main() {
  test('calendar query bounds preserve wall fields independently of host timezone', () {
    for (final input in [DateTime(2026,10,28,10,30,15,123,456), DateTime.utc(2026,10,28,10,30,15,123,456)]) {
      final normalized = analyticsWallClock(input);
      expect(normalized.isUtc, isTrue);
      expect(normalized, DateTime.utc(2026,10,28,10,30,15,123,456));
      expect(analyticsKarachiTime('2026-10-28T05:30:15.123456Z'), normalized);
    }
  });
}
