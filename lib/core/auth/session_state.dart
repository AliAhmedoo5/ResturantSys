import 'package:flutter/foundation.dart';
import 'staff.dart';

/// Manages the active staff session and notifies UI listeners on login/lock transitions.
class SessionState extends ChangeNotifier {
  Staff? _currentStaff;

  Staff? get currentStaff => _currentStaff;
  bool get isAuthenticated => _currentStaff != null;

  /// Establishes an active user session for authenticated staff.
  void login(Staff staff) {
    _currentStaff = staff;
    notifyListeners();
  }

  /// Instantly locks the register and clears the active session.
  void lock() {
    _currentStaff = null;
    notifyListeners();
  }

  /// Alias for lock.
  void logout() => lock();
}
