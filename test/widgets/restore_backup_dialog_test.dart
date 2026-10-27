import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/database/database_restore_service.dart';
import 'package:resturant_sys/widgets/supervisor/restore_backup_dialog.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Restore extends DatabaseRestoreService {
  _Restore() : super(auth: AuthService(database: _UnusedDatabase()));
  bool scheduled = false;
  @override
  Future<PreparedRestore> prepare(String archivePath) async => const PreparedRestore('unused-preview', 'pos_backup.zip', 21, 123, 7);
  @override
  Future<String> schedule(PreparedRestore prepared) async { scheduled = true; return 'safety-backup.zip'; }
}
void main() {
  testWidgets('Manager reviews archive and replacement warning before scheduling restore', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Restore();
    await tester.pumpWidget(MaterialApp(home: RestoreBackupDialog(service: service, pickArchive: () async => 'backup.zip')));
    final submit = find.widgetWithText(FilledButton, 'Create safety backup and restore on restart');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('Select backup ZIP')); await tester.pumpAndSettle();
    expect(find.textContaining('Orders: 123'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile)); await tester.pumpAndSettle();
    await tester.tap(submit); await tester.pumpAndSettle();
    expect(service.scheduled, isTrue);
    expect(find.textContaining('Safety backup: safety-backup.zip'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
