import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/staff.dart';
import '../auth/staff_role.dart';
import '../database/pos_database_constants.dart';
import '../orders/dining_type.dart';
import '../orders/order.dart';
import '../orders/paisa_engine.dart';
import '../orders/token_status.dart';
import '../shifts/cash_movement.dart';
import '../shifts/shift.dart';
import 'rider_trip.dart';

/// Controller managing Rider Trips, delivery dispatch, dispatch alerts,
/// and cashier cash reconciliation at trip settlement.
class RiderTripController {
  RiderTripController({required this.database});

  final Database database;

  String _formatTimestamp(DateTime dt) => dt.toIso8601String().replaceAll('T', ' ').substring(0, 19);

  /// Batches one or more delivery orders into a new named Rider Trip.
  ///
  /// - Transitions contained orders to `TokenStatus.outForDelivery`.
  /// - Sums `grand_total` of all `COLLECTION_DUE` (COD) orders as `cash_expected_paisa`.
  /// - Ensures orders are not already on an active non-settled trip.
  Future<RiderTrip> createRiderTrip({
    required int riderStaffId,
    required int shiftId,
    required int businessDayId,
    required String tripName,
    required List<int> orderIds,
    DateTime? dispatchedAt,
  }) async {
    final trimmedTripName = tripName.trim();
    if (trimmedTripName.isEmpty) {
      throw ArgumentError('Trip name cannot be empty.');
    }
    if (orderIds.isEmpty) {
      throw ArgumentError('At least one delivery order must be assigned to the trip.');
    }
    if (orderIds.toSet().length != orderIds.length) {
      throw ArgumentError('A delivery order can only appear once in a trip.');
    }

    // Verify shift is open
    final shiftRows = await database.query(
      PosDatabaseConstants.tableShifts,
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (shiftRows.isEmpty) {
      throw StateError('Shift #$shiftId not found.');
    }
    final shift = Shift.fromMap(shiftRows.first);
    if (shift.isClosed) {
      throw StateError('Cannot dispatch rider trip: Shift #$shiftId is closed.');
    }
    if (shift.businessDayId != businessDayId) {
      throw StateError('Dispatch shift must belong to the selected Business Day.');
    }

    // Verify rider staff exists and is active
    final staffRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ? AND is_active = 1',
      whereArgs: [riderStaffId],
    );
    if (staffRows.isEmpty) {
      throw StateError('Rider staff #$riderStaffId not found or inactive.');
    }
    final riderStaff = Staff.fromMap(staffRows.first);

    return await database.transaction((txn) async {
      final now = dispatchedAt ?? DateTime.now();
      final formattedNow = _formatTimestamp(now);

      var cashExpectedPaisa = 0;
      final validatedOrders = <Order>[];

      for (final orderId in orderIds) {
        final orderRows = await txn.query(
          PosDatabaseConstants.tableOrders,
          where: 'id = ?',
          whereArgs: [orderId],
        );
        if (orderRows.isEmpty) {
          throw StateError('Order #$orderId not found.');
        }
        final order = Order.fromMap(orderRows.first);

        if (order.diningType != DiningType.delivery) {
          throw StateError('Order #$orderId is not a Delivery order (found: ${order.diningType.code}).');
        }
        if (order.isCancelled || order.isVoided || order.paymentStatus == 'REFUNDED' ||
            order.tokenStatus == TokenStatus.delivered || order.tokenStatus == TokenStatus.outForDelivery) {
          throw StateError('Order #$orderId is no longer awaiting dispatch.');
        }
        if (order.businessDayId != businessDayId) {
          throw StateError('Order #$orderId belongs to another Business Day.');
        }

        // Verify order is not already in an active (non-settled and non-cancelled) rider trip
        final existingTripOrders = await txn.rawQuery('''
          SELECT rto.trip_id, rt.status
          FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
          JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
          WHERE rto.order_id = ? AND rt.status IN ('DISPATCHED', 'RETURNED')
        ''', [orderId]);

        if (existingTripOrders.isNotEmpty) {
          throw StateError('Order #$orderId is already assigned to active Trip #${existingTripOrders.first['trip_id']}.');
        }

        // Accumulate expected COD cash
        if (order.paymentStatus == 'COLLECTION_DUE') {
          cashExpectedPaisa += PaisaEngine.rupeesToPaisa(order.grandTotal);
        }

        validatedOrders.add(order);
      }

      // Insert Rider Trip
      final tripId = await txn.insert(
        PosDatabaseConstants.tableRiderTrips,
        {
          'trip_name': trimmedTripName,
          'rider_staff_id': riderStaffId,
          'shift_id': shiftId,
          'business_day_id': businessDayId,
          'status': 'DISPATCHED',
          'cash_expected_paisa': cashExpectedPaisa,
          'cash_collected_paisa': 0,
          'dispatched_at': formattedNow,
          'created_at': formattedNow,
        },
      );

      final tripOrders = <RiderTripOrder>[];

      // Assign orders & transition token status to OUT_FOR_DELIVERY
      for (final order in validatedOrders) {
        final rtoId = await txn.insert(
          PosDatabaseConstants.tableRiderTripOrders,
          {
            'trip_id': tripId,
            'order_id': order.id,
            'status': 'DISPATCHED',
            'assigned_at': formattedNow,
          },
        );

        await txn.update(
          PosDatabaseConstants.tableOrders,
          {'token_status': TokenStatus.outForDelivery.code},
          where: 'id = ?',
          whereArgs: [order.id],
        );

        tripOrders.add(RiderTripOrder(
          id: rtoId,
          tripId: tripId,
          orderId: order.id,
          status: 'DISPATCHED',
          assignedAt: now,
          order: order,
        ));
      }

      return RiderTrip(
        id: tripId,
        tripName: trimmedTripName,
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        status: RiderTripStatus.dispatched,
        cashExpectedPaisa: cashExpectedPaisa,
        cashCollectedPaisa: 0,
        dispatchedAt: now,
        createdAt: now,
        riderName: riderStaff.name,
        orders: tripOrders,
      );
    });
  }

  /// Marks an order as physically delivered by the rider.
  ///
  /// CRITICAL: Delivered COD orders REMAIN in `Collection Due` status.
  /// Physical delivery does NOT mark an order paid.
  Future<void> markOrderDelivered({
    required int tripId,
    required int orderId,
    DateTime? deliveredAt,
  }) async {
    final trip = await getTrip(tripId);
    if (trip.isSettled || trip.isCancelled) {
      throw StateError('Cannot update order delivery on Trip #$tripId: Trip is ${trip.status.displayName}.');
    }

    final now = deliveredAt ?? DateTime.now();
    final formattedNow = _formatTimestamp(now);

    await database.transaction((txn) async {
      final updated = await txn.update(
        PosDatabaseConstants.tableRiderTripOrders,
        {
          'status': 'DELIVERED',
          'delivered_at': formattedNow,
        },
        where: 'trip_id = ? AND order_id = ?',
        whereArgs: [tripId, orderId],
      );

      if (updated == 0) {
        throw StateError('Order #$orderId is not part of Trip #$tripId.');
      }

      // Update order token status to delivered, while keeping payment_status untouched
      await txn.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': TokenStatus.delivered.code},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  /// Marks an order as returned undelivered.
  ///
  /// Returned orders remain editable until the trip is settled.
  /// Expected cash for the trip is automatically reduced if the order was COD.
  Future<void> markOrderReturned({
    required int tripId,
    required int orderId,
    required String reason,
    DateTime? returnedAt,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Return reason is mandatory.');
    }

    final trip = await getTrip(tripId);
    if (trip.isSettled || trip.isCancelled) {
      throw StateError('Cannot return order on Trip #$tripId: Trip is ${trip.status.displayName}.');
    }

    final now = returnedAt ?? DateTime.now();
    final formattedNow = _formatTimestamp(now);

    await database.transaction((txn) async {
      final updated = await txn.update(
        PosDatabaseConstants.tableRiderTripOrders,
        {
          'status': 'RETURNED',
          'returned_at': formattedNow,
          'notes': trimmedReason,
        },
        where: 'trip_id = ? AND order_id = ?',
        whereArgs: [tripId, orderId],
      );

      if (updated == 0) {
        throw StateError('Order #$orderId is not part of Trip #$tripId.');
      }

      // Return token status back to ready
      await txn.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': TokenStatus.ready.code},
        where: 'id = ?',
        whereArgs: [orderId],
      );

      // Reduce cash expected on the trip if order was COD
      final orderRows = await txn.query(
        PosDatabaseConstants.tableOrders,
        columns: ['grand_total', 'payment_status'],
        where: 'id = ?',
        whereArgs: [orderId],
      );
      if (orderRows.isNotEmpty && orderRows.first['payment_status'] == 'COLLECTION_DUE') {
        final codAmountPaisa = PaisaEngine.rupeesToPaisa((orderRows.first['grand_total'] as num).toDouble());
        await txn.rawUpdate('''
          UPDATE ${PosDatabaseConstants.tableRiderTrips}
          SET cash_expected_paisa = MAX(0, cash_expected_paisa - ?)
          WHERE id = ?
        ''', [codAmountPaisa, tripId]);
      }
    });
  }

  /// Records an auditable dispatch alert on an active rider trip.
  Future<RiderDispatchAlert> recordDispatchAlert({
    required int tripId,
    required int orderId,
    int? revisionId,
    required String alertType,
    required String message,
    DateTime? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now();
    final formattedNow = _formatTimestamp(now);

    final id = await database.insert(
      PosDatabaseConstants.tableRiderDispatchAlerts,
      {
        'trip_id': tripId,
        'order_id': orderId,
        'revision_id': revisionId,
        'alert_type': alertType,
        'message': message.trim(),
        'is_acknowledged': 0,
        'created_at': formattedNow,
      },
    );

    return RiderDispatchAlert(
      id: id,
      tripId: tripId,
      orderId: orderId,
      revisionId: revisionId,
      alertType: alertType,
      message: message.trim(),
      isAcknowledged: false,
      createdAt: now,
    );
  }

  /// Acknowledges an active rider dispatch alert.
  Future<void> acknowledgeDispatchAlert({
    required int alertId,
    required int staffId,
    DateTime? acknowledgedAt,
  }) async {
    final now = acknowledgedAt ?? DateTime.now();
    final formattedNow = _formatTimestamp(now);

    await database.update(
      PosDatabaseConstants.tableRiderDispatchAlerts,
      {
        'is_acknowledged': 1,
        'acknowledged_at': formattedNow,
        'acknowledged_by': staffId,
      },
      where: 'id = ?',
      whereArgs: [alertId],
    );
  }

  /// Executes formal Rider Trip Settlement upon the rider's return:
  ///
  /// 1. Counts physical cash handed over from the rider's trip pouch.
  /// 2. Transitions all delivered COD orders on the trip to `SETTLED`.
  /// 3. Deposits the counted physical cash into the active shift drawer via `cash_movements`.
  /// 4. Marks the rider trip as `SETTLED`.
  /// 5. Permanently locks direct cart and line edits on all contained orders.
  Future<RiderTrip> settleRiderTrip({
    required int tripId,
    required int cashierStaffId,
    required int shiftId,
    required int cashCountedPaisa,
    Map<int, String>? digitalWalletReferences,
    String? notes,
    DateTime? settledAt,
  }) async {
    if (cashCountedPaisa < 0) {
      throw ArgumentError('Counted cash amount cannot be negative.');
    }

    final trip = await getTrip(tripId);
    if (trip.isSettled) {
      throw StateError('Cannot settle Trip #$tripId: Trip is already settled.');
    }
    if (trip.isCancelled) {
      throw StateError('Cannot settle Trip #$tripId: Trip is cancelled.');
    }

    // Spec Requirement: Guard against settling while orders are still in transit
    final inTransit = trip.orders.where((o) => o.status == 'DISPATCHED').toList();
    if (inTransit.isNotEmpty) {
      throw StateError(
        'Cannot settle Trip #$tripId: Order #${inTransit.first.orderId} is still in transit. Mark as Delivered or Returned first.',
      );
    }

    // ADR-0009: Cashier credentials check
    final staffRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [cashierStaffId],
      limit: 1,
    );
    if (staffRows.isEmpty) {
      throw StateError('Staff ID #$cashierStaffId not found.');
    }
    final staffRole = StaffRole.fromCode(staffRows.first['role'] as String);
    if (staffRole != StaffRole.cashier || staffRows.first['login_enabled'] == 0 || staffRows.first['is_active'] != 1) {
      throw StateError('Authorization error: Only cashiers can execute rider trip settlement and drawer deposits.');
    }

    // Verify cashier shift is open
    final shiftRows = await database.query(
      PosDatabaseConstants.tableShifts,
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (shiftRows.isEmpty) {
      throw StateError('Shift #$shiftId not found.');
    }
    final shift = Shift.fromMap(shiftRows.first);
    if (shift.isClosed) {
      throw StateError('Cannot settle trip: Shift #$shiftId is closed.');
    }
    if (shift.staffId != cashierStaffId) {
      throw StateError('Only the Cashier operating this shift can settle rider cash.');
    }
    if (shift.businessDayId != trip.businessDayId) {
      throw StateError('Rider settlement must remain in the trip Business Day.');
    }

    final now = settledAt ?? DateTime.now();
    final formattedNow = _formatTimestamp(now);
    final utcNowIso = now.toUtc().toIso8601String();

    return await database.transaction((txn) async {
      // 1. Transition delivered COD orders to SETTLED
      final deliveredCodOrders = await txn.rawQuery('''
        SELECT o.id, o.grand_total
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableOrders} o ON rto.order_id = o.id
        WHERE rto.trip_id = ? AND rto.status = 'DELIVERED' AND o.payment_status = 'COLLECTION_DUE'
      ''', [tripId]);

      for (final row in deliveredCodOrders) {
        final orderId = row['id'] as int;
        final grandTotal = (row['grand_total'] as num).toDouble();
        final grandTotalPaisa = PaisaEngine.rupeesToPaisa(grandTotal);

        await txn.update(
          PosDatabaseConstants.tableOrders,
          {'payment_status': 'SETTLED'},
          where: 'id = ?',
          whereArgs: [orderId],
        );

        final digitalRef = digitalWalletReferences?[orderId];
        final refCode = digitalRef != null && digitalRef.trim().isNotEmpty
            ? digitalRef.trim()
            : 'TRIP-$tripId';
        final paymentMethod = digitalRef != null && digitalRef.trim().isNotEmpty
            ? 'DIGITAL_WALLET'
            : 'COD';

        // Update or insert order payment row reflecting settled payment
        final existingPayment = await txn.query(
          PosDatabaseConstants.tableOrderPayments,
          where: 'order_id = ? AND payment_method IN (\'COD\', \'DIGITAL_WALLET\')',
          whereArgs: [orderId],
        );

        if (existingPayment.isNotEmpty) {
          await txn.update(
            PosDatabaseConstants.tableOrderPayments,
            {
              'payment_method': paymentMethod,
              'amount_tendered': grandTotal,
              'amount_tendered_paisa': grandTotalPaisa,
              'change_returned': 0.0,
              'change_returned_paisa': 0,
              'reference_code': refCode,
            },
            where: 'id = ?',
            whereArgs: [existingPayment.first['id']],
          );
        } else {
          await txn.insert(
            PosDatabaseConstants.tableOrderPayments,
            {
              'order_id': orderId,
              'payment_method': paymentMethod,
              'amount_tendered': grandTotal,
              'amount_tendered_paisa': grandTotalPaisa,
              'change_returned': 0.0,
              'change_returned_paisa': 0,
              'reference_code': refCode,
            },
          );
        }
      }

      // 2. Deposit counted physical cash into cashier shift drawer via cash_movements
      if (cashCountedPaisa > 0) {
        final cashRupees = PaisaEngine.paisaToRupees(cashCountedPaisa);
        final defaultNotes = 'Rider Trip #$tripId (${trip.tripName}) settlement pouch cash: Rs. ${cashRupees.toStringAsFixed(2)}';
        await txn.insert(
          PosDatabaseConstants.tableCashMovements,
          {
            'shift_id': shiftId,
            'staff_id': cashierStaffId,
            'type': CashMovementType.payIn.dbValue,
            'amount': cashRupees,
            'category': 'Rider Settlement',
            'notes': notes?.trim().isNotEmpty == true ? notes!.trim() : defaultNotes,
            'approved_by': null,
            'created_at': formattedNow,
          },
        );
      }

      // 3. Mark rider trip as SETTLED
      await txn.update(
        PosDatabaseConstants.tableRiderTrips,
        {
          'status': 'SETTLED',
          'cash_collected_paisa': cashCountedPaisa,
          'returned_at': trip.returnedAt != null ? _formatTimestamp(trip.returnedAt!) : formattedNow,
          'settled_at_utc': utcNowIso,
        },
        where: 'id = ?',
        whereArgs: [tripId],
      );

      return RiderTrip(
        id: trip.id,
        tripName: trip.tripName,
        riderStaffId: trip.riderStaffId,
        shiftId: trip.shiftId,
        businessDayId: trip.businessDayId,
        status: RiderTripStatus.settled,
        cashExpectedPaisa: trip.cashExpectedPaisa,
        cashCollectedPaisa: cashCountedPaisa,
        dispatchedAt: trip.dispatchedAt,
        returnedAt: trip.returnedAt ?? now,
        settledAtUtc: DateTime.parse(utcNowIso),
        createdAt: trip.createdAt,
        riderName: trip.riderName,
      );
    });
  }

  /// Checks if an order belongs to a settled rider trip, which locks it permanently.
  Future<bool> isOrderSettledInTrip(int orderId) async {
    final rows = await database.rawQuery('''
      SELECT rt.id
      FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
      JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
      WHERE rto.order_id = ? AND rt.status = 'SETTLED'
      LIMIT 1
    ''', [orderId]);
    return rows.isNotEmpty;
  }

  /// Fetches a single Rider Trip with its contained orders and alerts.
  Future<RiderTrip> getTrip(int tripId) async {
    final rows = await database.rawQuery('''
      SELECT rt.*, st.name as rider_name
      FROM ${PosDatabaseConstants.tableRiderTrips} rt
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON rt.rider_staff_id = st.id
      WHERE rt.id = ?
    ''', [tripId]);

    if (rows.isEmpty) {
      throw StateError('Rider Trip #$tripId not found.');
    }

    final tripRow = rows.first;

    // Fetch trip orders
    final orderRows = await database.rawQuery('''
      SELECT rto.*, o.token_number, o.dining_type, o.subtotal, o.grand_total,
             o.payment_status, o.token_status, o.customer_name, o.customer_phone,
             o.delivery_address_snapshot, o.delivery_fee_paisa, o.business_day_id,
             o.shift_id, o.cashier_id, o.created_at as order_created_at
      FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
      JOIN ${PosDatabaseConstants.tableOrders} o ON rto.order_id = o.id
      WHERE rto.trip_id = ?
      ORDER BY rto.id ASC
    ''', [tripId]);

    final tripOrders = orderRows.map((r) {
      final order = Order.fromMap({
        'id': r['order_id'],
        'business_day_id': r['business_day_id'],
        'shift_id': r['shift_id'],
        'cashier_id': r['cashier_id'],
        'token_number': r['token_number'],
        'dining_type': r['dining_type'],
        'subtotal': r['subtotal'],
        'grand_total': r['grand_total'],
        'payment_status': r['payment_status'],
        'token_status': r['token_status'],
        'customer_name': r['customer_name'],
        'customer_phone': r['customer_phone'],
        'delivery_address_snapshot': r['delivery_address_snapshot'],
        'delivery_fee_paisa': r['delivery_fee_paisa'],
        'created_at': r['order_created_at'],
      });
      return RiderTripOrder.fromMap(r, order: order);
    }).toList();

    // Fetch alerts
    final alertRows = await database.rawQuery('''
      SELECT rda.*, st.name as acknowledged_by_name
      FROM ${PosDatabaseConstants.tableRiderDispatchAlerts} rda
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON rda.acknowledged_by = st.id
      WHERE rda.trip_id = ?
      ORDER BY rda.id DESC
    ''', [tripId]);

    final alerts = alertRows.map((r) => RiderDispatchAlert.fromMap(r)).toList();

    return RiderTrip.fromMap(
      tripRow,
      riderName: tripRow['rider_name'] as String?,
      orders: tripOrders,
      alerts: alerts,
    );
  }

  /// Retrieves active (dispatched or returned, non-settled) rider trips.
  Future<List<RiderTrip>> getActiveTrips({int? shiftId, int? businessDayId}) async {
    final conditions = ["rt.status IN ('DISPATCHED', 'RETURNED')"];
    final args = <Object?>[];

    if (shiftId != null) {
      conditions.add('rt.shift_id = ?');
      args.add(shiftId);
    }
    if (businessDayId != null) {
      conditions.add('rt.business_day_id = ?');
      args.add(businessDayId);
    }

    final rows = await database.rawQuery('''
      SELECT rt.*, st.name as rider_name
      FROM ${PosDatabaseConstants.tableRiderTrips} rt
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON rt.rider_staff_id = st.id
      WHERE ${conditions.join(' AND ')}
      ORDER BY rt.id DESC
    ''', args);

    final trips = <RiderTrip>[];
    for (final row in rows) {
      final tripId = row['id'] as int;
      trips.add(await getTrip(tripId));
    }
    return trips;
  }

  /// Retrieves all unacknowledged dispatch alerts across active trips.
  Future<List<RiderDispatchAlert>> getActiveAlerts() async {
    final rows = await database.rawQuery('''
      SELECT rda.*, st.name as acknowledged_by_name
      FROM ${PosDatabaseConstants.tableRiderDispatchAlerts} rda
      JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rda.trip_id = rt.id
      LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON rda.acknowledged_by = st.id
      WHERE rda.is_acknowledged = 0 AND rt.status IN ('DISPATCHED', 'RETURNED')
      ORDER BY rda.id DESC
    ''');
    return rows.map((r) => RiderDispatchAlert.fromMap(r)).toList();
  }

  /// Retrieves delivery orders ready to be batched and dispatched on a trip.
  Future<List<Order>> getPendingDeliveryOrders({int? shiftId, int? businessDayId}) async {
    final conditions = [
      "o.dining_type = 'DELIVERY'",
      "o.payment_status NOT IN ('CANCELLED', 'VOIDED', 'REFUNDED')",
      "o.token_status NOT IN ('OUT_FOR_DELIVERY', 'DELIVERED')",
      '''NOT EXISTS (
        SELECT 1 FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = o.id AND rt.status IN ('DISPATCHED', 'RETURNED')
      )'''
    ];
    final args = <Object?>[];

    if (shiftId != null) {
      conditions.add('o.shift_id = ?');
      args.add(shiftId);
    }
    if (businessDayId != null) {
      conditions.add('o.business_day_id = ?');
      args.add(businessDayId);
    }

    final rows = await database.rawQuery('''
      SELECT o.*
      FROM ${PosDatabaseConstants.tableOrders} o
      WHERE ${conditions.join(' AND ')}
      ORDER BY o.token_number ASC
    ''', args);

    return rows.map((r) => Order.fromMap(r)).toList();
  }

  /// Retrieves staff eligible to be assigned as delivery riders.
  Future<List<Staff>> getAvailableRiders() async {
    final rows = await database.rawQuery('''
      SELECT s.*, d.name as department_name
      FROM ${PosDatabaseConstants.tableStaff} s
      LEFT JOIN ${PosDatabaseConstants.tableDepartments} d ON s.department_id = d.id
      WHERE s.is_active = 1
      ORDER BY s.name ASC
    ''');
    return rows.map((r) => Staff.fromMap(r)).toList();
  }
}
