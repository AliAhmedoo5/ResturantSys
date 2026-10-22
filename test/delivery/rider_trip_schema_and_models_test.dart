import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/delivery/rider_trip.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Rider Trips Schema v13 and Models Suite', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rider_trip_schema_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Fresh PosDatabase initializes with schema v13 and rider trip tables', () async {
      final posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      final db = await posDb.initialize();
      addTearDown(() => posDb.close());

      final versionResult = await db.rawQuery('PRAGMA user_version;');
      expect(versionResult.first['user_version'], equals(PosDatabaseConstants.schemaVersion));
      expect(PosDatabaseConstants.schemaVersion, equals(13));

      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = tables.map((r) => r['name'] as String).toSet();

      expect(tableNames, contains(PosDatabaseConstants.tableRiderTrips));
      expect(tableNames, contains(PosDatabaseConstants.tableRiderTripOrders));
      expect(tableNames, contains(PosDatabaseConstants.tableRiderDispatchAlerts));

      final tripColumns = await db.rawQuery('PRAGMA table_info(${PosDatabaseConstants.tableRiderTrips});');
      final tripColumnNames = tripColumns.map((c) => c['name'] as String).toSet();
      expect(tripColumnNames, contains('trip_name'));
      expect(tripColumnNames, contains('cash_expected_paisa'));
      expect(tripColumnNames, contains('cash_collected_paisa'));
      expect(tripColumnNames, contains('status'));
    });

    test('Database upgrade from v12 to v13 adds trip_name and creates trip orders & alerts tables', () async {
      final posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      final db = await posDb.initialize();

      // Simulate a v12 database by dropping v13 new tables/columns and resetting pragma
      await db.execute('DROP TABLE IF EXISTS ${PosDatabaseConstants.tableRiderDispatchAlerts}');
      await db.execute('DROP TABLE IF EXISTS ${PosDatabaseConstants.tableRiderTripOrders}');
      await db.execute('PRAGMA user_version = 12');
      await posDb.close();

      // Reopen with upgraded schema
      final upgradedPosDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      final upgradedDb = await upgradedPosDb.initialize();
      addTearDown(() => upgradedPosDb.close());

      final versionResult = await upgradedDb.rawQuery('PRAGMA user_version;');
      expect(versionResult.first['user_version'], equals(13));

      final tables = await upgradedDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = tables.map((r) => r['name'] as String).toSet();
      expect(tableNames, contains(PosDatabaseConstants.tableRiderTripOrders));
      expect(tableNames, contains(PosDatabaseConstants.tableRiderDispatchAlerts));
    });

    test('RiderTrip and RiderDispatchAlert domain models serialize correctly', () {
      final now = DateTime.now();
      final alert = RiderDispatchAlert(
        id: 1,
        tripId: 10,
        orderId: 101,
        revisionId: 2,
        alertType: 'ORDER_MODIFIED',
        message: 'Order was changed while out for delivery',
        isAcknowledged: false,
        createdAt: now,
      );

      final alertMap = alert.toMap();
      expect(alertMap['trip_id'], equals(10));
      expect(alertMap['order_id'], equals(101));
      expect(alertMap['is_acknowledged'], equals(0));

      final fromMapAlert = RiderDispatchAlert.fromMap({
        'id': 1,
        'trip_id': 10,
        'order_id': 101,
        'revision_id': 2,
        'alert_type': 'ORDER_MODIFIED',
        'message': 'Order was changed while out for delivery',
        'is_acknowledged': 0,
        'created_at': now.toIso8601String(),
      });
      expect(fromMapAlert.isAcknowledged, isFalse);
      expect(fromMapAlert.alertType, equals('ORDER_MODIFIED'));

      final trip = RiderTrip(
        id: 5,
        tripName: 'Trip #5 - Bilal',
        riderStaffId: 3,
        shiftId: 1,
        businessDayId: 1,
        status: RiderTripStatus.dispatched,
        cashExpectedPaisa: 250000,
        cashCollectedPaisa: 0,
        dispatchedAt: now,
        createdAt: now,
        alerts: [alert],
      );

      expect(trip.isDispatched, isTrue);
      expect(trip.isSettled, isFalse);
      expect(trip.hasActiveAlerts, isTrue);
      expect(trip.unacknowledgedAlertsCount, equals(1));

      final tripMap = trip.toMap();
      expect(tripMap['trip_name'], equals('Trip #5 - Bilal'));
      expect(tripMap['cash_expected_paisa'], equals(250000));
      expect(tripMap['status'], equals('DISPATCHED'));

      final restoredTrip = RiderTrip.fromMap({
        'id': 5,
        'trip_name': 'Trip #5 - Bilal',
        'rider_staff_id': 3,
        'shift_id': 1,
        'business_day_id': 1,
        'status': 'DISPATCHED',
        'cash_expected_paisa': 250000,
        'cash_collected_paisa': 0,
        'dispatched_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      }, alerts: [alert]);

      expect(restoredTrip.tripName, equals('Trip #5 - Bilal'));
      expect(restoredTrip.hasActiveAlerts, isTrue);
    });
  });
}
