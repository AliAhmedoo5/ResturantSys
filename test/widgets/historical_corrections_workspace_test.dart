import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/analytics/historical_corrections.dart';
import 'package:resturant_sys/widgets/supervisor/historical_corrections_workspace.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  testWidgets('correction workspace explains evidence and blocks anonymous sessions', (tester) async {
    final store = PosDatabase(factory:databaseFactoryFfi,customPath:inMemoryDatabasePath);
    final db = (await tester.runAsync(store.initialize))!;
    addTearDown(store.close);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:HistoricalCorrectionsWorkspace(
      service:HistoricalCorrections(database:db,auth:AuthService(database:db))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Manager session'), findsOneWidget);
    expect(find.text('Append correction'),findsNothing);
  });
}

