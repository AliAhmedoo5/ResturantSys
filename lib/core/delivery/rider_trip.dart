import '../orders/order.dart';

/// Lifecycle status for a rider delivery trip.
enum RiderTripStatus {
  dispatched('DISPATCHED', 'Dispatched'),
  returned('RETURNED', 'Returned'),
  settled('SETTLED', 'Settled'),
  cancelled('CANCELLED', 'Cancelled');

  const RiderTripStatus(this.code, this.displayName);

  final String code;
  final String displayName;

  static RiderTripStatus fromCode(String code) {
    return RiderTripStatus.values.firstWhere(
      (s) => s.code.toUpperCase() == code.toUpperCase(),
      orElse: () => RiderTripStatus.dispatched,
    );
  }

  bool get isDispatched => this == RiderTripStatus.dispatched;
  bool get isReturned => this == RiderTripStatus.returned;
  bool get isSettled => this == RiderTripStatus.settled;
  bool get isCancelled => this == RiderTripStatus.cancelled;
}

/// An order assignment stop on a rider trip.
class RiderTripOrder {
  const RiderTripOrder({
    required this.id,
    required this.tripId,
    required this.orderId,
    required this.status,
    required this.assignedAt,
    this.deliveredAt,
    this.returnedAt,
    this.notes,
    this.order,
  });

  final int id;
  final int tripId;
  final int orderId;
  final String status; // 'DISPATCHED', 'DELIVERED', 'RETURNED'
  final DateTime assignedAt;
  final DateTime? deliveredAt;
  final DateTime? returnedAt;
  final String? notes;
  final Order? order;

  bool get isDispatched => status == 'DISPATCHED';
  bool get isDelivered => status == 'DELIVERED';
  bool get isReturned => status == 'RETURNED';

  factory RiderTripOrder.fromMap(Map<String, Object?> map, {Order? order}) {
    return RiderTripOrder(
      id: (map['id'] as int?) ?? 0,
      tripId: map['trip_id'] as int,
      orderId: map['order_id'] as int,
      status: (map['status'] as String?) ?? 'DISPATCHED',
      assignedAt: DateTime.parse(map['assigned_at'] as String),
      deliveredAt: map['delivered_at'] != null ? DateTime.parse(map['delivered_at'] as String) : null,
      returnedAt: map['returned_at'] != null ? DateTime.parse(map['returned_at'] as String) : null,
      notes: map['notes'] as String?,
      order: order,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'trip_id': tripId,
      'order_id': orderId,
      'status': status,
      'assigned_at': assignedAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'returned_at': returnedAt?.toIso8601String(),
      'notes': notes,
    };
  }
}

/// An auditable dispatch alert raised when an Out for Delivery order is revised or cancelled.
class RiderDispatchAlert {
  const RiderDispatchAlert({
    required this.id,
    required this.tripId,
    required this.orderId,
    this.revisionId,
    required this.alertType,
    required this.message,
    this.isAcknowledged = false,
    required this.createdAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.acknowledgedByName,
  });

  final int id;
  final int tripId;
  final int orderId;
  final int? revisionId;
  final String alertType; // 'ORDER_MODIFIED', 'ORDER_CANCELLED'
  final String message;
  final bool isAcknowledged;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final int? acknowledgedBy;
  final String? acknowledgedByName;

  factory RiderDispatchAlert.fromMap(Map<String, Object?> map, {String? acknowledgedByName}) {
    return RiderDispatchAlert(
      id: (map['id'] as int?) ?? 0,
      tripId: map['trip_id'] as int,
      orderId: map['order_id'] as int,
      revisionId: map['revision_id'] as int?,
      alertType: map['alert_type'] as String,
      message: map['message'] as String,
      isAcknowledged: ((map['is_acknowledged'] as int?) ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      acknowledgedAt: map['acknowledged_at'] != null ? DateTime.parse(map['acknowledged_at'] as String) : null,
      acknowledgedBy: map['acknowledged_by'] as int?,
      acknowledgedByName: acknowledgedByName ?? map['acknowledged_by_name'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'trip_id': tripId,
      'order_id': orderId,
      'revision_id': revisionId,
      'alert_type': alertType,
      'message': message,
      'is_acknowledged': isAcknowledged ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'acknowledged_at': acknowledgedAt?.toIso8601String(),
      'acknowledged_by': acknowledgedBy,
    };
  }
}

/// A batched rider dispatch trip containing multiple delivery orders and cash reconciliation.
class RiderTrip {
  const RiderTrip({
    required this.id,
    required this.tripName,
    required this.riderStaffId,
    required this.shiftId,
    required this.businessDayId,
    required this.status,
    required this.cashExpectedPaisa,
    this.cashCollectedPaisa = 0,
    required this.dispatchedAt,
    this.returnedAt,
    this.settledAtUtc,
    required this.createdAt,
    this.riderName,
    this.orders = const [],
    this.alerts = const [],
  });

  final int id;
  final String tripName;
  final int riderStaffId;
  final int shiftId;
  final int businessDayId;
  final RiderTripStatus status;
  final int cashExpectedPaisa;
  final int cashCollectedPaisa;
  final DateTime dispatchedAt;
  final DateTime? returnedAt;
  final DateTime? settledAtUtc;
  final DateTime createdAt;
  final String? riderName;
  final List<RiderTripOrder> orders;
  final List<RiderDispatchAlert> alerts;

  bool get isSettled => status.isSettled;
  bool get isDispatched => status.isDispatched;
  bool get isReturned => status.isReturned;
  bool get isCancelled => status.isCancelled;

  bool get hasActiveAlerts => alerts.any((a) => !a.isAcknowledged);
  int get unacknowledgedAlertsCount => alerts.where((a) => !a.isAcknowledged).length;

  factory RiderTrip.fromMap(
    Map<String, Object?> map, {
    String? riderName,
    List<RiderTripOrder> orders = const [],
    List<RiderDispatchAlert> alerts = const [],
  }) {
    return RiderTrip(
      id: (map['id'] as int?) ?? 0,
      tripName: (map['trip_name'] as String?) ?? 'Trip #${map['id']}',
      riderStaffId: map['rider_staff_id'] as int,
      shiftId: map['shift_id'] as int,
      businessDayId: map['business_day_id'] as int,
      status: RiderTripStatus.fromCode(map['status'] as String),
      cashExpectedPaisa: (map['cash_expected_paisa'] as int?) ?? 0,
      cashCollectedPaisa: (map['cash_collected_paisa'] as int?) ?? 0,
      dispatchedAt: DateTime.parse(map['dispatched_at'] as String),
      returnedAt: map['returned_at'] != null ? DateTime.parse(map['returned_at'] as String) : null,
      settledAtUtc: map['settled_at_utc'] != null ? DateTime.parse(map['settled_at_utc'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      riderName: riderName ?? map['rider_name'] as String?,
      orders: orders,
      alerts: alerts,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'trip_name': tripName,
      'rider_staff_id': riderStaffId,
      'shift_id': shiftId,
      'business_day_id': businessDayId,
      'status': status.code,
      'cash_expected_paisa': cashExpectedPaisa,
      'cash_collected_paisa': cashCollectedPaisa,
      'dispatched_at': dispatchedAt.toIso8601String(),
      'returned_at': returnedAt?.toIso8601String(),
      'settled_at_utc': settledAtUtc?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
