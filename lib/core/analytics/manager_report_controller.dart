import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/session_state.dart';
import '../auth/staff_role.dart';
import 'analytics_models.dart';
import 'analytics_service.dart';

/// Owns which report may be published across refreshes and session changes.
/// Persisted authorization remains the responsibility of the report reader.
class ManagerReportController extends ChangeNotifier {
  ManagerReportController({required AnalyticsService service,
    required AnalyticsQuery query, SessionState? session,
    Duration refreshInterval = const Duration(seconds: 30)})
      : _service = service, _query = query, _session = session,
        _refreshInterval = refreshInterval {
    _session?.addListener(_sessionChanged);
    _startTimer();
  }

  AnalyticsService _service;
  SessionState? _session;
  Duration _refreshInterval;
  AnalyticsQuery _query;
  AnalyticsSnapshot? _snapshot;
  String? _error;
  Timer? _timer;
  bool _busy = false, _queued = false, _visible = true, _disposed = false;
  int _revision = 0;

  AnalyticsQuery get query => _query;
  AnalyticsSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get busy => _busy;
  bool get authorized {
    if (_session == null) return true;
    final staff = _session!.currentStaff;
    return staff != null && staff.role == StaffRole.manager &&
        staff.isActive && staff.loginEnabled;
  }

  void configure({required AnalyticsService service, SessionState? session,
    required Duration refreshInterval}) {
    final changed = !identical(_service, service) || !identical(_session, session);
    _session?.removeListener(_sessionChanged);
    _service = service;
    _session = session;
    _refreshInterval = refreshInterval;
    _session?.addListener(_sessionChanged);
    if (changed) {
      _sessionChanged();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_disposed || !authorized || !_visible || !_query.live) return;
    _timer = Timer.periodic(_refreshInterval, (_) => refresh());
  }

  void _sessionChanged() {
    _revision++;
    _queued = false;
    _snapshot = null;
    _error = null;
    notifyListeners();
    _startTimer();
    if (authorized) refresh();
  }

  void setVisible(bool visible) {
    _visible = visible;
    _startTimer();
    if (visible && authorized && _query.live) refresh();
  }

  void changeQuery(AnalyticsQuery query) {
    _revision++;
    _query = query;
    _snapshot = null;
    _error = null;
    notifyListeners();
    _startTimer();
    refresh();
  }

  Future<void> refresh() async {
    if (_disposed || !authorized || !_visible) return;
    if (_busy) { _queued = true; return; }
    final revision = _revision;
    final query = _query;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await _service.load(query);
      if (!_disposed && revision == _revision && authorized) {
        _snapshot = snapshot;
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed && revision == _revision && authorized) {
        // Persisted revocation can precede notification from the session.
        _snapshot = null;
        _error = 'Unable to load analytics. Check your Manager session and retry.';
        notifyListeners();
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
        if (_queued) { _queued = false; refresh(); }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    _session?.removeListener(_sessionChanged);
    super.dispose();
  }
}
