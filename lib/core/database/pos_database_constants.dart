/// Constants and default configuration for the SQLite database.
abstract final class PosDatabaseConstants {
  static const int schemaVersion = 7;
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
  static const String tableOrderItems = 'order_items';
  static const String tableOrderPayments = 'order_payments';
  static const String tableOrderVoids = 'order_voids';

  // Catalog, BOM, Modifier & Discount Tables
  static const String tableCategories = 'categories';
  static const String tableMenuItems = 'menu_items';
  static const String tableRawIngredients = 'raw_ingredients';
  static const String tableRecipes = 'recipes';
  static const String tableModifiers = 'modifiers';
  static const String tableDiscountPresets = 'discount_presets';
  static const String tableDeals = 'deals';
  static const String tableDealItems = 'deal_items';
  static const String tableDealItemOptions = 'deal_item_options';

  // Procurement and Kitchen Wastage Tables
  static const String tableMandiProcurements = 'mandi_procurements';
  static const String tableKitchenWastage = 'kitchen_wastage';

  // Vendor Khata (Supplier Credit Ledger) Tables
  static const String tableVendorKhata = 'vendor_khata';
  static const String tableVendorTransactions = 'vendor_transactions';

  // Settings Keys
  static const String settingDiscrepancyThreshold = 'discrepancy_threshold';
  static const String defaultDiscrepancyThreshold = '100.00';
  static const String settingCashierVoidRequestsEnabled = 'cashier_void_requests_enabled';
  static const String defaultCashierVoidRequestsEnabled = 'true';

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
