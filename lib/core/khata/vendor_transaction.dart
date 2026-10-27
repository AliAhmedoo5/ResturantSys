/// Transaction category for supplier ledger entries.
enum VendorTransactionType {
  /// Credit purchase / stock delivery adding to payable balance.
  purchaseCredit,

  /// Cash settlement paid directly from the cash drawer.
  paymentDrawer,

  /// Payment settled externally (bank transfer, owner pocket, online).
  paymentExternal;

  String get dbValue {
    switch (this) {
      case VendorTransactionType.purchaseCredit:
        return 'PURCHASE_CREDIT';
      case VendorTransactionType.paymentDrawer:
        return 'PAYMENT_DRAWER';
      case VendorTransactionType.paymentExternal:
        return 'PAYMENT_EXTERNAL';
    }
  }

  String get displayName {
    switch (this) {
      case VendorTransactionType.purchaseCredit:
        return 'Credit Delivery';
      case VendorTransactionType.paymentDrawer:
        return 'Paid from Drawer';
      case VendorTransactionType.paymentExternal:
        return 'Paid Outside Drawer';
    }
  }

  static VendorTransactionType fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'PURCHASE_CREDIT':
        return VendorTransactionType.purchaseCredit;
      case 'PAYMENT_DRAWER':
        return VendorTransactionType.paymentDrawer;
      case 'PAYMENT_EXTERNAL':
        return VendorTransactionType.paymentExternal;
      default:
        throw ArgumentError('Unknown VendorTransactionType: $value');
    }
  }
}

/// Ledger entry representing a credit delivery or settlement payment for a vendor.
class VendorTransaction {
  const VendorTransaction({
    required this.id,
    required this.vendorId,
    this.shiftId,
    this.staffId,
    required this.type,
    required this.amount,
    this.referenceSlip,
    this.notes,
    this.rawIngredientId,
    this.quantity,
    required this.createdAt,
    this.vendorName,
    this.rawIngredientName,
    this.staffName,
    this.dueDate,
  });

  final int id;
  final int vendorId;
  final int? shiftId;
  final int? staffId;
  final VendorTransactionType type;
  final double amount;
  final String? referenceSlip;
  final String? notes;
  final int? rawIngredientId;
  final double? quantity;
  final DateTime createdAt;
  final String? vendorName;
  final String? rawIngredientName;
  final String? staffName;
  final DateTime? dueDate;

  bool get isCreditDelivery => type == VendorTransactionType.purchaseCredit;
  bool get isPayment =>
      type == VendorTransactionType.paymentDrawer ||
      type == VendorTransactionType.paymentExternal;

  factory VendorTransaction.fromMap(Map<String, dynamic> map, {
    String? vendorName,
    String? rawIngredientName,
    String? staffName,
  }) {
    return VendorTransaction(
      id: map['id'] as int,
      vendorId: map['vendor_id'] as int,
      shiftId: map['shift_id'] as int?,
      staffId: map['staff_id'] as int?,
      type: VendorTransactionType.fromDbValue(map['type'] as String),
      amount: (map['amount'] as num).toDouble(),
      referenceSlip: map['reference_slip'] as String?,
      notes: map['notes'] as String?,
      rawIngredientId: map['raw_ingredient_id'] as int?,
      quantity: (map['quantity'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      vendorName: vendorName ?? map['vendor_name'] as String?,
      rawIngredientName: rawIngredientName ?? map['raw_ingredient_name'] as String?,
      staffName: staffName ?? map['staff_name'] as String?,
      dueDate: DateTime.tryParse(map['due_date'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'vendor_id': vendorId,
      'shift_id': shiftId,
      'staff_id': staffId,
      'type': type.dbValue,
      'amount': amount,
      'reference_slip': referenceSlip,
      'notes': notes,
      'raw_ingredient_id': rawIngredientId,
      'quantity': quantity,
      'created_at': createdAt.toIso8601String(),
      'due_date': dueDate?.toIso8601String().substring(0,10),
    };
  }
}
