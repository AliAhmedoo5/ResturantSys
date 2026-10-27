import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/widgets/supervisor/operations_workspace.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late PosDatabase store;
  late OperationsController controller;
  late int manager;
  setUp(() async {
    store=PosDatabase(factory:databaseFactoryFfi,customPath:inMemoryDatabasePath);
    final db=await store.initialize();
    controller=OperationsController(db);
    manager=(await db.query('staff',where:"role='MANAGER'")).first['id'] as int;
    await ShiftAndCashController(database:db).openBusinessDay(openedByStaffId:manager);
  });
  tearDown(() async {await store.close();});

  testWidgets('expense form retains draft on invalid amount and posts owner-funded expense', (tester) async {
    await controller.saveCategory(managerId:manager,name:'Utilities');
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OperationsWorkspace(
      controller:controller,managerId:manager,payroll:false))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record expense'));await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);await tester.pumpAndSettle();
    await tester.tap(find.text('Utilities').last);await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField,'Paid-for description'),'Power bill');
    await tester.enterText(find.widgetWithText(TextFormField,'Amount (PKR)'),'abc');
    await tester.enterText(find.widgetWithText(TextFormField,'Reason / correction explanation'),'Monthly payment');
    await tester.tap(find.text('Save'));await tester.pumpAndSettle();
    expect(find.text('Power bill'),findsOneWidget);
    expect(await controller.expenses(managerId:manager),isEmpty);
    await tester.enterText(find.widgetWithText(TextFormField,'Amount (PKR)'),'250.50');
    await tester.tap(find.text('Save'));await tester.pumpAndSettle();
    expect((await controller.expenses(managerId:manager)).single['amount_paisa'],25050);
    expect(await controller.database.query('cash_movements'),isEmpty);
    expect(tester.takeException(),isNull);
  });

  testWidgets('payroll shows non-login employees and balance actions', (tester) async {
    await controller.database.insert('staff',{'name':'Helper','department_id':1,
      'pin_hash':'disabled-helper','role':'CASHIER','login_enabled':0,'created_at':'2026-10-01'});
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OperationsWorkspace(
      controller:controller,managerId:manager,payroll:true))));
    await tester.pumpAndSettle();
    expect(find.text('Configure salary'),findsOneWidget);
    expect(find.text('Accrue salary'),findsOneWidget);
    expect(find.text('Recover advance'),findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));await tester.pumpAndSettle();
    expect(find.text('Helper'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
