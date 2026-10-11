/// Operational status of a cashier shift.
enum ShiftStatus {
  open,
  closed;

  String get dbValue => name.toUpperCase();

  static ShiftStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'OPEN':
        return ShiftStatus.open;
      case 'CLOSED':
        return ShiftStatus.closed;
      default:
        throw ArgumentError('Unknown ShiftStatus: $value');
    }
  }
}

/// Discrepancy audit status for cash drawer handover.
enum DiscrepancyStatus {
  clean,
  flagged,
  resolved;

  String get dbValue => name.toUpperCase();

  static DiscrepancyStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'CLEAN':
        return DiscrepancyStatus.clean;
      case 'FLAGGED':
        return DiscrepancyStatus.flagged;
      case 'RESOLVED':
        return DiscrepancyStatus.resolved;
      default:
        throw ArgumentError('Unknown DiscrepancyStatus: $value');
    }
  }
}

/// An individual cashier shift within an overarching Business Day.
///
/// Records opening float, mid-shift movements, blind cash counts, and discrepancy flags.
class Shift {
  const Shift({
    required this.id,
    required this.businessDayId,
    required this.staffId,
    required this.openedAt,
    this.closedAt,
    required this.openingFloat,
    this.countedCash,
    this.expectedCash,
    this.discrepancy,
    this.discrepancyStatus = DiscrepancyStatus.clean,
    required this.status,
    this.staffName,
    this.resolvedByStaffId,
    this.resolutionNotes,
    this.resolvedAt,
  });

  final int id;
  final int businessDayId;
  final int staffId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;
  final double? countedCash;
  final double? expectedCash;
  final double? discrepancy;
  final DiscrepancyStatus discrepancyStatus;
  final ShiftStatus status;
  final String? staffName;
  final int? resolvedByStaffId;
  final String? resolutionNotes;
  final DateTime? resolvedAt;

  bool get isOpen => status == ShiftStatus.open;
  bool get isClosed => status == ShiftStatus.closed;
  bool get isFlagged => discrepancyStatus == DiscrepancyStatus.flagged;
  bool get isClean => discrepancyStatus == DiscrepancyStatus.clean;
  bool get isResolved => discrepancyStatus == DiscrepancyStatus.resolved;

  factory Shift.fromMap(Map<String, dynamic> map) {
    return Shift(
      id: map['id'] as int,
      businessDayId: map['business_day_id'] as int,
      staffId: map['staff_id'] as int,
      openedAt: DateTime.parse(map['opened_at'] as String),
      closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
      openingFloat: (map['opening_float'] as num).toDouble(),
      countedCash: (map['counted_cash'] as num?)?.toDouble(),
      expectedCash: (map['expected_cash'] as num?)?.toDouble(),
      discrepancy: (map['discrepancy'] as num?)?.toDouble(),
      discrepancyStatus: map['discrepancy_status'] != null
          ? DiscrepancyStatus.fromDbValue(map['discrepancy_status'] as String)
          : DiscrepancyStatus.clean,
      status: ShiftStatus.fromDbValue(map['status'] as String),
      staffName: map['staff_name'] as String?,
      resolvedByStaffId: map['resolved_by_staff_id'] as int?,
      resolutionNotes: map['resolution_notes'] as String?,
      resolvedAt: map['resolved_at'] != null ? DateTime.parse(map['resolved_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'business_day_id': businessDayId,
      'staff_id': staffId,
      'opened_at': openedAt.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'opening_float': openingFloat,
      'counted_cash': countedCash,
      'expected_cash': expectedCash,
      'discrepancy': discrepancy,
      'discrepancy_status': discrepancyStatus.dbValue,
      'status': status.dbValue,
      'resolved_by_staff_id': resolvedByStaffId,
      'resolution_notes': resolutionNotes,
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }
}
