import 'vendor.dart';
import 'vendor_transaction.dart';

/// Single chronological line item in a vendor's statement of accounts.
class VendorStatementEntry {
  const VendorStatementEntry({
    required this.transaction,
    required this.creditAmount,
    required this.debitAmount,
    required this.runningBalance,
  });

  final VendorTransaction transaction;

  /// Stock delivery / purchase amount added to payable ledger.
  final double creditAmount;

  /// Settlement payment reducing payable ledger.
  final double debitAmount;

  /// Running balance owed to the vendor at this point in time.
  final double runningBalance;
}

/// Chronological supplier statement with running balance calculations.
class VendorStatement {
  const VendorStatement({
    required this.vendor,
    required this.openingBalance,
    required this.currentBalance,
    required this.entries,
  });

  final Vendor vendor;
  final double openingBalance;
  final double currentBalance;
  final List<VendorStatementEntry> entries;

  double get totalPurchases =>
      entries.fold(0.0, (sum, e) => sum + e.creditAmount);

  double get totalSettled =>
      entries.fold(0.0, (sum, e) => sum + e.debitAmount);
}
