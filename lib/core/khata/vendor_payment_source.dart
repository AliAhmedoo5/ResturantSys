/// Multi-source settlement source selection for Vendor Khata balance payments.
enum VendorPaymentSource {
  /// Settlement paid directly in cash from the active shift cash drawer,
  /// auto-generating a CashMovement (Pay-Out) and altering shift reconciliation.
  paidFromActiveDrawer('Paid from Active Drawer'),

  /// Settlement paid from outside the till (e.g., bank transfer, cheque, or owner personal funds),
  /// updating the ledger payable balance without touching the register cash float.
  paidOutsideDrawer('Paid Outside Drawer');

  const VendorPaymentSource(this.displayName);
  final String displayName;
}
