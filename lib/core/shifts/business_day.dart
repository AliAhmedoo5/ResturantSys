/// Lifecycle status of an overarching Business Day.
enum BusinessDayStatus {
  open,
  closed;

  String get dbValue => name.toUpperCase();

  static BusinessDayStatus fromDbValue(String value) {
    switch (value.toUpperCase()) {
      case 'OPEN':
        return BusinessDayStatus.open;
      case 'CLOSED':
        return BusinessDayStatus.closed;
      default:
        throw ArgumentError('Unknown BusinessDayStatus: $value');
    }
  }
}

/// Overarching Business Day entity grouping sequential cashier shifts.
///
/// Supports cross-midnight operations until explicitly finalized with Z-Report.
class BusinessDay {
  const BusinessDay({
    required this.id,
    required this.openedAt,
    this.closedAt,
    required this.openedByStaffId,
    this.closedByStaffId,
    required this.status,
    this.openedByStaffName,
    this.closedByStaffName,
  });

  final int id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openedByStaffId;
  final int? closedByStaffId;
  final BusinessDayStatus status;
  final String? openedByStaffName;
  final String? closedByStaffName;

  bool get isOpen => status == BusinessDayStatus.open;
  bool get isClosed => status == BusinessDayStatus.closed;

  factory BusinessDay.fromMap(Map<String, dynamic> map) {
    return BusinessDay(
      id: map['id'] as int,
      openedAt: DateTime.parse(map['opened_at'] as String),
      closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
      openedByStaffId: map['opened_by_staff_id'] as int,
      closedByStaffId: map['closed_by_staff_id'] as int?,
      status: BusinessDayStatus.fromDbValue(map['status'] as String),
      openedByStaffName: map['opened_by_staff_name'] as String?,
      closedByStaffName: map['closed_by_staff_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'opened_at': openedAt.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'opened_by_staff_id': openedByStaffId,
      'closed_by_staff_id': closedByStaffId,
      'status': status.dbValue,
    };
  }
}
