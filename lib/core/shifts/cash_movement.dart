/// Type of drawer cash movement: Pay-In or Pay-Out.
enum CashMovementType {
  payIn,
  payOut;

  String get dbValue => this == CashMovementType.payIn ? 'PAY_IN' : 'PAY_OUT';
  String get displayName => this == CashMovementType.payIn ? 'Pay-In' : 'Pay-Out';

  static CashMovementType fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'PAY_IN':
        return CashMovementType.payIn;
      case 'PAY_OUT':
        return CashMovementType.payOut;
      default:
        throw ArgumentError('Unknown CashMovementType: $value');
    }
  }
}

/// An audited mid-shift drawer cash transaction (e.g. petty cash, ice, cash drops).
class CashMovement {
  const CashMovement({
    required this.id,
    required this.shiftId,
    required this.staffId,
    required this.type,
    required this.amount,
    required this.category,
    required this.notes,
    required this.createdAt,
    this.staffName,
    this.approvedBy,
  });

  final int id;
  final int shiftId;
  final int staffId;
  final CashMovementType type;
  final double amount;
  final String category;
  final String notes;
  final DateTime createdAt;
  final String? staffName;
  final int? approvedBy;

  bool get isPayIn => type == CashMovementType.payIn;
  bool get isPayOut => type == CashMovementType.payOut;

  factory CashMovement.fromMap(Map<String, dynamic> map) {
    return CashMovement(
      id: map['id'] as int,
      shiftId: map['shift_id'] as int,
      staffId: map['staff_id'] as int,
      type: CashMovementType.fromDbValue(map['type'] as String),
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      notes: map['notes'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      staffName: map['staff_name'] as String?,
      approvedBy: map['approved_by'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'shift_id': shiftId,
      'staff_id': staffId,
      'type': type.dbValue,
      'amount': amount,
      'category': category,
      'notes': notes,
      'approved_by': approvedBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
