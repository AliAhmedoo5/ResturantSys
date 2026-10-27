import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/staff_role.dart';

Future<void> requireManager(DatabaseExecutor db, int staffId) async {
  final rows = await db.query('staff', where: 'id=? AND is_active=1 AND login_enabled=1', whereArgs: [staffId]);
  if (rows.isEmpty || !StaffRole.fromCode(rows.single['role'] as String).isManager) {
    throw StateError('An active Manager session is required.');
  }
}

Future<void> auditConfiguration(DatabaseExecutor db, int actorId, String kind, Object before, Object after) async {
  await db.insert('configuration_audit', {'actor_id': actorId, 'kind': kind,
    'before_json': jsonEncode(before), 'after_json': jsonEncode(after), 'created_at': DateTime.now().toIso8601String()});
}
