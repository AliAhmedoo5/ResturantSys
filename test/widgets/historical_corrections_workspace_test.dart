import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/analytics/historical_corrections.dart';
import 'package:resturant_sys/widgets/supervisor/historical_corrections_workspace.dart';

class DisplayedCorrections extends HistoricalCorrections {
  DisplayedCorrections({required super.database,required super.auth});
  @override
  Future<List<int>> closedDays() async => [1];
  @override
  Future<HistoricalCorrectionSnapshot> load(int dayId,{DateTime? cutoff}) async => HistoricalCorrectionSnapshot(
    1,1,DateTime.utc(2026,10,30),jsonEncode({'sections':[
      {'title':'Z-Report / Executive Summary','headers':['Measure','Value'],'rows':[['Collection Due',250000],['Tender CASH (collected)',4500000]]},
      {'title':'Shift Handover Audit','headers':['Shift','Cashier','Float','Expected','Counted','Variance','Audit'],'rows':[[1,'Cashier',0,0,0,0,'CLEAN']]}
    ]}),'synthetic-sealed-hash','2026-10-25T18:00:00Z',[],24);
}

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
  testWidgets('Manager compares sealed and adjusted reports then session lock clears evidence',(tester)async{
    tester.view.physicalSize=const Size(1366,1200);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=PosDatabase(factory:databaseFactoryFfi,customPath:inMemoryDatabasePath);
    final db=(await tester.runAsync(store.initialize))!;addTearDown(store.close);
    final auth=AuthService(database:db)..session.login(const Staff(id:1,name:'Manager',departmentId:1,
      pinHash:'unused',role:StaffRole.manager,isActive:true));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:HistoricalCorrectionsWorkspace(service:DisplayedCorrections(database:db,auth:auth)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));await tester.pumpAndSettle();
    await tester.tap(find.text('Business Day #1').last);await tester.pumpAndSettle();
    expect(find.textContaining('synthetic-sealed-hash'),findsOneWidget);
    expect(find.textContaining('Correction-adjusted · Collection Due · 250000 paisa'),findsOneWidget);
    expect(find.text('CSV (this report)'),findsOneWidget);
    await tester.tap(find.text('Original sealed').first);await tester.pumpAndSettle();
    expect(find.textContaining('Correction-adjusted · Collection Due'),findsNothing);
    auth.session.lock();await tester.pumpAndSettle();
    expect(find.textContaining('synthetic-sealed-hash'),findsNothing);
    expect(find.text('Manager session required.'),findsOneWidget);
  });

}
