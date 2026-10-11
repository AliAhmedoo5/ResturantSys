/// Constants and default configuration for the SQLite database.
abstract final class PosDatabaseConstants {
  static const int schemaVersion = 2;
  static const String databaseFileName = 'pos.db';
  static const String defaultProgramDataFolder = 'ResturantPOS';
  static const String defaultDataSubFolder = 'data';

  // Tables
  static const String tableDepartments = 'departments';
  static const String tableStaff = 'staff';
  static const String tableSystemSettings = 'system_settings';
  static const String tableBusinessDays = 'business_days';
  static const String tableShifts = 'shifts';
  static const String tableCashMovements = 'cash_movements';
  static const String tableOrders = 'orders';
  static const String tableOrderPayments = 'order_payments';

  // Settings Keys
  static const String settingDiscrepancyThreshold = 'discrepancy_threshold';
  static const String defaultDiscrepancyThreshold = '100.00';

  // Default Departments
  static const List<String> defaultDepartments = [
    'Front Counter',
    'Kitchen',
    'Management',
  ];

  // Default Initial Staff Accounts
  static const String defaultSupervisorName = 'Supervisor';
  static const String defaultSupervisorPin = '1234';
  static const String defaultSupervisorDepartment = 'Management';

  static const String defaultCashierName = 'Counter Cashier';
  static const String defaultCashierPin = '1111';
  static const String defaultCashierDepartment = 'Front Counter';

  static const String defaultKitchenName = 'Kitchen Cook';
  static const String defaultKitchenPin = '2222';
  static const String defaultKitchenDepartment = 'Kitchen';
}
