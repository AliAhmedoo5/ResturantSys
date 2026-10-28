import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('an existing staff PIN unlocks within two seconds', () async {
    final directory = await Directory.systemTemp.createTemp('pin_latency_');
    final store = PosDatabase(
      factory: databaseFactoryFfi,
      customPath: '${directory.path}/pos.db',
      seedDefaultStaff: false,
    );
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    final db = await store.initialize();
    // Provision an existing modern verifier outside the measured login path.
    final hashTimer = Stopwatch()..start();
    final verifier = PinHasher.hashPin('7391');
    hashTimer.stop();
    // ignore: avoid_print
    print('PIN derivation latency (ms): ${hashTimer.elapsedMilliseconds}');
    await db.insert('staff', {
      'name': 'Latency fixture',
      'department_id': 1,
      'role': 'CASHIER',
      'pin_hash': verifier,
      'is_active': 1,
      'created_at': '2026-10-28 00:00:00',
    });
    final auth = AuthService(database: db);
    final timings = <int>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      auth.session.lock();
      final timer = Stopwatch()..start();
      final staff = await auth.authenticateAndLogin('7391');
      timer.stop();
      expect(staff, isNotNull);
      expect(auth.session.isAuthenticated, isTrue);
      timings.add(timer.elapsedMilliseconds);
    }
    // Only elapsed durations are recorded; never log entered PINs or verifiers.
    // ignore: avoid_print
    print('PIN login latency (ms): $timings');
    if (Platform.isWindows) {
      expect(timings, everyElement(lessThan(2000)),
          reason: 'Verifying PIN must finish within two seconds on every unlock.');
    }
  });
}
