import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/database_backup_service.dart';
import 'package:resturant_sys/core/database/database_restore_service.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory temp, media;
  late PosDatabase store;
  late Database db;
  late AuthService auth;
  late DatabaseRestoreService restores;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('guided_restore_');
    media = await Directory('${temp.path}/media').create();
    store = PosDatabase(factory: databaseFactoryFfi, customPath: '${temp.path}/pos.db');
    db = await store.initialize();
    auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    restores = DatabaseRestoreService(auth: auth, mediaPath: media.path);
    await db.update('system_settings', {'value': '${temp.path}/backups'}, where: 'key=?', whereArgs: ['local_backup_path']);
  });
  tearDown(() async { await store.close(); await temp.delete(recursive: true); });
  Future<String> backup() async {
    final result = await DatabaseBackupService(database: db, catalogMediaDirectoryPath: media.path)
      .executeBackup(sourceDbPath: db.path, localBackupDir: '${temp.path}/backups');
    expect(result.success, isTrue, reason: result.warningMessage);
    return result.localBackupPath!;
  }

  test('validated restore keeps current data until restart, restores media and retains safety backup', () async {
    await File('${media.path}/original.jpg').writeAsBytes([1, 2, 3]);
    final archive = await backup();
    await db.update('system_settings', {'value': 'changed'}, where: 'key=?', whereArgs: ['restaurant_name']);
    await File('${media.path}/original.jpg').writeAsBytes([9]);
    final preview = await restores.prepare(archive);
    expect(preview.orderCount, 0);
    final safety = await restores.schedule(preview);
    expect(await File(safety).exists(), isTrue);
    expect((await db.query('system_settings', where: 'key=?', whereArgs: ['restaurant_name'])).single['value'], 'changed');
    await store.close();
    final message = await DatabaseRestoreService.applyPending(databasePath: '${temp.path}/pos.db');
    expect(message, contains('successfully'));
    db = await store.initialize();
    expect((await db.query('system_settings', where: 'key=?', whereArgs: ['restaurant_name'])).single['value'], isNot('changed'));
    expect(await File('${media.path}/original.jpg').readAsBytes(), [1, 2, 3]);
    expect(await DatabaseRestoreService.applyPending(databasePath: db.path), isNull);
    expect((await db.query('configuration_audit', where: "kind='RESTORE_APPLIED'")), hasLength(1));
  });

  test('Cashier, locked session and open Business Day cannot prepare a restore', () async {
    final archive = await backup();
    auth.session.login(Staff.fromMap((await db.query('staff', where: 'id=2')).single));
    await expectLater(restores.prepare(archive), throwsStateError);
    auth.session.lock();
    await expectLater(restores.prepare(archive), throwsStateError);
    auth.session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    await db.insert('business_days', {'opened_at': DateTime.now().toIso8601String(), 'opened_by_staff_id': 1, 'status': 'OPEN'});
    await expectLater(restores.prepare(archive), throwsStateError);
  });

  test('invalid archives and traversal leave live records intact', () async {
    final corrupt = File('${temp.path}/bad.zip');
    await corrupt.writeAsString('not a zip');
    await expectLater(restores.prepare(corrupt.path), throwsA(anything));
    final encoder = ZipFileEncoder()..create('${temp.path}/traversal.zip');
    encoder.addArchiveFile(ArchiveFile('../outside.txt', 1, [1]));
    await encoder.close();
    await expectLater(restores.prepare('${temp.path}/traversal.zip'), throwsA(isA<FormatException>()));
    expect(await File('${temp.path}/outside.txt').exists(), isFalse);
    expect(await db.query('staff'), isNotEmpty);
  });

  test('canceling a validated preview never schedules a replacement', () async {
    final preview = await restores.prepare(await backup());
    await preview.discard();
    expect(await Directory(preview.directory).exists(), isFalse);
    expect(await File('${db.path}.restore-request.json').exists(), isFalse);
  });
}
