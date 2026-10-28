import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/manager_report_controller.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';

class _Reader implements AnalyticsService {
  final pending = <Completer<AnalyticsSnapshot>>[];
  final queries = <AnalyticsQuery>[];
  @override
  Future<AnalyticsSnapshot> load(AnalyticsQuery query) {
    queries.add(query);
    final result = Completer<AnalyticsSnapshot>();
    pending.add(result);
    return result.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AnalyticsQuery query(int day) => AnalyticsQuery(startDate: DateTime(2026, 10, day),
  endDateExclusive: DateTime(2026, 10, day + 1));
AnalyticsSnapshot snapshot(AnalyticsQuery query) => AnalyticsSnapshot(query: query,
  generatedAt: DateTime.utc(2026, 10, 28), sections: [], businessDayIds: []);

void main() {
  test('query changes coalesce pending reads and publish only the latest cohort', () async {
    final reader = _Reader();
    final reports = ManagerReportController(service: reader, query: query(24));
    addTearDown(reports.dispose);
    final first = reports.refresh();
    reports.changeQuery(query(25));
    reports.changeQuery(query(26));
    expect(reader.queries, [query(24)]);
    reader.pending.first.complete(snapshot(query(24)));
    await first;
    expect(reports.snapshot, isNull);
    expect(reader.queries, [query(24), query(26)]);
    reader.pending.last.complete(snapshot(query(26)));
    await Future<void>.delayed(Duration.zero);
    expect(reports.snapshot?.query, query(26));
    expect(reports.busy, isFalse);
  });

  test('lock clears a published report and rejects a pending result', () async {
    final reader = _Reader();
    final session = SessionState()..login(const Staff(id: 1, name: 'Manager',
      departmentId: 1, pinHash: '', role: StaffRole.manager, isActive: true));
    addTearDown(session.dispose);
    final reports = ManagerReportController(service: reader, query: query(24), session: session);
    addTearDown(reports.dispose);
    final first = reports.refresh();
    reader.pending.first.complete(snapshot(query(24)));
    await first;
    expect(reports.snapshot, isNotNull);
    final second = reports.refresh();
    session.lock();
    expect(reports.snapshot, isNull);
    reader.pending.last.complete(snapshot(query(24)));
    await second;
    expect(reports.snapshot, isNull);
    expect(reports.authorized, isFalse);
  });

  test('failed refresh clears old data and retry can recover', () async {
    final reader = _Reader();
    final reports = ManagerReportController(service: reader, query: query(24));
    addTearDown(reports.dispose);
    final first = reports.refresh();
    reader.pending.first.complete(snapshot(query(24)));
    await first;
    final failed = reports.refresh();
    reader.pending.last.completeError(StateError('Persisted access revoked'));
    await failed;
    expect(reports.snapshot, isNull);
    expect(reports.error, isNotNull);
    final retry = reports.refresh();
    reader.pending.last.complete(snapshot(query(24)));
    await retry;
    expect(reports.snapshot, isNotNull);
    expect(reports.error, isNull);
  });

  test('disposal prevents pending reads from publishing or starting queued work', () async {
    final reader = _Reader();
    final reports = ManagerReportController(service: reader, query: query(24));
    var notifications = 0;
    reports.addListener(() => notifications++);
    final pending = reports.refresh();
    reports.changeQuery(query(25));
    reports.dispose();
    final before = notifications;
    reader.pending.first.complete(snapshot(query(24)));
    await pending;
    expect(notifications, before);
    expect(reader.queries, hasLength(1));
  });
}
