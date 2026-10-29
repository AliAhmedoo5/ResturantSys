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
    store=PosDatabase(factory:databaseFactoryFfiNoIsolate,customPath:inMemoryDatabasePath);
    final db=await store.initialize();
    controller=OperationsController(db);
    manager=(await db.query('staff',where:"role IN ('SUPERVISOR','MANAGER','OWNER')")).first['id'] as int;
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

  testWidgets('payroll workspace logs worked hours with department, shift times, and break minutes', (tester) async {
    final helperId = await controller.database.insert('staff', {'name':'Cook Farhan','department_id':1,
      'pin_hash':'farhan-helper','role':'CASHIER','login_enabled':0,'created_at':'2026-10-01'});
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OperationsWorkspace(
      controller:controller,managerId:manager,payroll:true))));
    await tester.pumpAndSettle();

    expect(find.text('Log worked hours'), findsOneWidget);
    await tester.tap(find.text('Log worked hours'));
    await tester.pumpAndSettle();

    expect(find.text('Log worked hours'), findsWidgets);
    expect(find.text('Work date (YYYY-MM-DD)'), findsOneWidget);
    expect(find.text('Clock-in (HH:MM or YYYY-MM-DD HH:MM)'), findsOneWidget);
    expect(find.text('Clock-out (HH:MM or YYYY-MM-DD HH:MM)'), findsOneWidget);
    expect(find.text('Break duration in minutes (0 if none)'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Work date (YYYY-MM-DD)'), '2026-10-25');
    await tester.enterText(find.widgetWithText(TextFormField, 'Clock-in (HH:MM or YYYY-MM-DD HH:MM)'), '11:00');
    await tester.enterText(find.widgetWithText(TextFormField, 'Clock-out (HH:MM or YYYY-MM-DD HH:MM)'), '20:00');
    await tester.enterText(find.widgetWithText(TextFormField, 'Break duration in minutes (0 if none)'), '60');
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason / attendance notes'), 'Verified Sunday shift');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final hours = await controller.workedHoursHistory(managerId: manager, employeeId: helperId);
    expect(hours, hasLength(1));
    expect(hours.first['work_date'], '2026-10-25');
    expect(hours.first['worked_minutes'], 480);
    expect(hours.first['reason'], 'Verified Sunday shift');
    expect(find.textContaining('Worked: 2026-10-25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payroll workspace safely handles overnight shift crossing midnight (e.g. 22:00 to 04:00)', (tester) async {
    final nightCookId = await controller.database.insert('staff', {'name':'Night Chef','department_id':1,
      'pin_hash':'night-chef','role':'CASHIER','login_enabled':0,'created_at':'2026-10-01'});
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OperationsWorkspace(
      controller:controller,managerId:manager,payroll:true))));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night Chef').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log worked hours'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Work date (YYYY-MM-DD)'), '2026-10-25');
    await tester.enterText(find.widgetWithText(TextFormField, 'Clock-in (HH:MM or YYYY-MM-DD HH:MM)'), '22:00');
    await tester.enterText(find.widgetWithText(TextFormField, 'Clock-out (HH:MM or YYYY-MM-DD HH:MM)'), '04:00');
    await tester.enterText(find.widgetWithText(TextFormField, 'Break duration in minutes (0 if none)'), '60');
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason / attendance notes'), 'Overnight kitchen prep');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final hours = await controller.workedHoursHistory(managerId: manager, employeeId: nightCookId);
    expect(hours, hasLength(1));
    // 22:00 to 04:00 next day = 6 hours (360 mins) - 60m break = 300 mins (5.0 hrs)
    expect(hours.first['worked_minutes'], 300);
    expect(hours.first['work_date'], '2026-10-25');
    expect(tester.takeException(), isNull);
  });

  testWidgets('payroll workspace displays Department Labor Allocation breakdown in Manager UI', (tester) async {
    final kitchenDept = (await controller.database.query('departments', where: "name='Kitchen'")).first['id'] as int;
    final cookId = await controller.database.insert('staff', {'name':'Cook Tariq','department_id':kitchenDept,
      'pin_hash':'tariq-pin','role':'CASHIER','login_enabled':0,'created_at':'2026-10-01'});
    final currentPeriod = DateTime.now().toIso8601String().substring(0, 7);

    await controller.setSalary(
      managerId: manager,
      employeeId: cookId,
      effectivePeriod: currentPeriod,
      amountPaisa: 4000000,
      reason: 'Standard monthly salary',
    );
    await controller.postPayroll(
      managerId: manager,
      employeeId: cookId,
      period: currentPeriod,
      kind: 'ACCRUAL',
      amountPaisa: 4000000,
      reason: 'Current period accrual',
      requestKey: 'accrual-tariq',
    );

    await tester.pumpWidget(MaterialApp(home:Scaffold(body:OperationsWorkspace(
      controller:controller,managerId:manager,payroll:true))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Department Labor Allocation ($currentPeriod)'), findsOneWidget);
    expect(find.textContaining('Kitchen: Rs. 40000.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
