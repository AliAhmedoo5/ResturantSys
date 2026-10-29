/// Constants and default configuration for the SQLite database.
abstract final class PosDatabaseConstants {
  static const int schemaVersion = 22;
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

  // Delivery & Customer Directory Tables (Schema v9)
  static const String tableDeliveryAreas = 'delivery_areas';
  static const String tableCustomerAddresses = 'customer_addresses';

  // Order Revisions & Line Deltas (Schema v9)
  static const String tableOrderRevisions = 'order_revisions';
  static const String tableOrderRevisionLines = 'order_revision_lines';

  // Rider Trips & Logistics (Schema v9)
  static const String tableRiderTrips = 'rider_trips';
  static const String tableRiderTripOrders = 'rider_trip_orders';
  static const String tableRiderDispatchAlerts = 'rider_dispatch_alerts';

  // Catalog Image Galleries (Schema v9)
  static const String tableCatalogImages = 'catalog_images';

  // Offline Report Outbox (Schema v9)
  static const String tableReportOutbox = 'report_outbox';

  // Rounding Variance Ledger (Schema v9)
  static const String tableRoundingVarianceLedger = 'rounding_variance_ledger';

  // Settings Keys
  static const String settingDiscrepancyThreshold = 'discrepancy_threshold';
  static const String defaultDiscrepancyThreshold = '100.00';
  static const String settingCashierVoidRequestsEnabled = 'cashier_void_requests_enabled';
  static const String defaultCashierVoidRequestsEnabled = 'true';
  static const String settingSecondaryBackupPath = 'secondary_backup_path';
  static const String defaultSecondaryBackupPath = '';
  static const String settingLocalBackupPath = 'local_backup_path';
  static const String defaultLocalBackupPath = '';
  static const String defaultBackupsSubFolder = 'backups';

  // Onboarding & Restaurant Identity Settings
  static const String settingOnboardingCompleted = 'onboarding_completed';
  static const String defaultOnboardingCompleted = 'false';
  static const String settingRestaurantName = 'restaurant_name';
  static const String defaultRestaurantName = 'ResturantPOS';
  static const String settingCurrencyCode = 'currency_code';
  static const String defaultCurrencyCode = 'PKR';
  static const String settingDefaultTaxRate = 'default_tax_rate';
  static const String defaultDefaultTaxRate = '0.0';
  static const String settingTaxInclusive = 'tax_inclusive';
  static const String defaultTaxInclusive = 'true';

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

