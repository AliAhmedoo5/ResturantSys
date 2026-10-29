import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late PosDatabase store;
  late Database db;
  late OperationsController operations;
  late VendorKhataController khata;
  late ShiftAndCashController shifts;
  late int manager, cashier, shift, employee;
  var serial=0;
  String key() => 'request-${serial++}';

  setUp(() async {
    store=PosDatabase(factory:databaseFactoryFfi,customPath:inMemoryDatabasePath);
    db=await store.initialize();
    operations=OperationsController(db);
    khata=VendorKhataController(database:db);
    shifts=ShiftAndCashController(database:db);
    manager=(await db.query('staff',where:"role IN ('SUPERVISOR','MANAGER','OWNER')")).first['id'] as int;
    cashier=(await db.query('staff',where:"role='CASHIER'")).first['id'] as int;
    employee=await db.insert('staff',{'name':'Kitchen helper','department_id':1,
      'pin_hash':'no-login-helper','role':'CASHIER','login_enabled':0,'created_at':'2026-10-01'});
    await shifts.openBusinessDay(openedByStaffId:manager);
    shift=(await shifts.openShift(staffId:cashier,openingFloat:10000)).id;
  });
  tearDown(() async {await store.close();});

  Future<void> salary([int amount=100000]) => operations.setSalary(managerId:manager,
      employeeId:employee,effectivePeriod:'2026-10',amountPaisa:amount,reason:'Employment agreement');
  Future<int> payroll(String kind,{int? amount,FundingSource? source,String? request}) =>
      operations.postPayroll(managerId:manager,employeeId:employee,period:'2026-10',kind:kind,
        amountPaisa:amount,source:source,shiftId:shift,reason:'Approved payroll',requestKey:request ?? key());
  Future<int> category({String source='ANY'}) => operations.saveCategory(managerId:manager,
      name:'Utilities',allowedSource:source);
  Future<int> expense(int category,{FundingSource source=FundingSource.drawer,int amount=10000,
      int? corrects,String? request}) => operations.postExpense(managerId:manager,
      categoryId:category,amountPaisa:amount,description:'Electricity',source:source,
      shiftId:shift,reason:'Meter bill',requestKey:request ?? key(),correctsEntryId:corrects);

  test('salary, multiple advances, explicit recoveries and partial payments reconcile',() async {
    await salary();
    await payroll('ADVANCE',amount:10000,source:FundingSource.drawer);
    await payroll('ADVANCE',amount:5000,source:FundingSource.owner);
    await payroll('ACCRUAL');
    await payroll('RECOVERY',amount:15000);
    await payroll('PAYMENT',amount:25000,source:FundingSource.drawer);
    var balance=await operations.employeeBalance(managerId:manager,employeeId:employee);
    expect(balance.payablePaisa,60000); expect(balance.advancePaisa,0);
    await payroll('PAYMENT',amount:60000,source:FundingSource.bank);
    balance=await operations.employeeBalance(managerId:manager,employeeId:employee);
    expect(balance.netDuePaisa,0);
    final movements=await shifts.getCashMovements(shift);
    expect(movements,hasLength(2));
    expect(movements.fold<double>(0,(sum,m)=>sum+m.amount),350);
  });

  test('accrual is once per employee/month and request replay creates no cash twice',() async {
    await salary(); await payroll('ACCRUAL');
    await expectLater(payroll('ACCRUAL'),throwsA(isA<DatabaseException>()));
    final request=key();
    final first=await payroll('PAYMENT',amount:1000,source:FundingSource.drawer,request:request);
    expect(await payroll('PAYMENT',amount:1000,source:FundingSource.drawer,request:request),first);
    expect(await shifts.getCashMovements(shift),hasLength(1));
    await expectLater(payroll('PAYMENT',amount:2000,source:FundingSource.drawer,request:request),throwsStateError);
  });

  test('payroll overpayment and advance recovery are validated before cash mutates',() async {
    await salary(); await payroll('ADVANCE',amount:20000,source:FundingSource.owner);
    await payroll('ACCRUAL');
    await expectLater(payroll('PAYMENT',amount:90000,source:FundingSource.drawer),throwsStateError);
    await expectLater(payroll('RECOVERY',amount:30000),throwsStateError);
    await expectLater(payroll('ADVANCE',amount:90000,source:FundingSource.drawer),throwsStateError);
    expect(await shifts.getCashMovements(shift),isEmpty);
  });

  test('salary rates are effective dated and cannot rewrite already accrued periods',() async {
    await salary(); await payroll('ACCRUAL');
    await expectLater(operations.setSalary(managerId:manager,employeeId:employee,
      effectivePeriod:'2026-09',amountPaisa:50000,reason:'Retroactive'),throwsStateError);
    await operations.setSalary(managerId:manager,employeeId:employee,
      effectivePeriod:'2026-11',amountPaisa:110000,reason:'Raise');
    await operations.postPayroll(managerId:manager,employeeId:employee,period:'2026-11',
      kind:'ACCRUAL',reason:'November',requestKey:key());
    expect((await operations.employeeBalance(managerId:manager,employeeId:employee)).payablePaisa,210000);
  });

  test('prorated accrual can be reversed and replaced without double liability',() async {
    await salary();
    final original=await payroll('ACCRUAL',amount:50000);
    expect((await operations.employeeBalance(managerId:manager,employeeId:employee)).payablePaisa,50000);
    await operations.reversePayroll(managerId:manager,entryId:original,reason:'Proration corrected',requestKey:key());
    await payroll('ACCRUAL',amount:60000);
    expect((await operations.employeeBalance(managerId:manager,employeeId:employee)).payablePaisa,60000);
  });

  test('payroll reversal retains original and restores actual drawer cash once',() async {
    await salary(); await payroll('ACCRUAL');
    final payment=await payroll('PAYMENT',amount:20000,source:FundingSource.drawer);
    final request=key();
    final reversal=await operations.reversePayroll(managerId:manager,entryId:payment,
      shiftId:shift,reason:'Cash returned',requestKey:request);
    expect(await operations.reversePayroll(managerId:manager,entryId:payment,
      shiftId:shift,reason:'Cash returned',requestKey:request),reversal);
    expect(await db.query('payroll_entries'),hasLength(3));
    expect((await shifts.getCashMovements(shift)).last.amount,200);
    expect((await operations.employeeBalance(managerId:manager,employeeId:employee)).payablePaisa,100000);
    await expectLater(db.update('payroll_entries',{'reason':'erase'},where:'id=?',whereArgs:[payment]),throwsA(isA<DatabaseException>()));
  });

  test('dependent recovery prevents reversing an already recovered advance',() async {
    await salary();
    final advance=await payroll('ADVANCE',amount:10000,source:FundingSource.bank);
    await payroll('ACCRUAL'); await payroll('RECOVERY',amount:10000);
    await expectLater(operations.reversePayroll(managerId:manager,entryId:advance,
      reason:'Wrong advance',requestKey:key()),throwsStateError);
  });

  test('expense source policy, category rename snapshots, archive and restore',() async {
    final id=await category(source:'BANK');
    await expectLater(expense(id),throwsStateError);
    await expense(id,source:FundingSource.bank);
    await operations.saveCategory(managerId:manager,id:id,name:'Power',allowedSource:'BANK');
    expect((await operations.expenses(managerId:manager)).single['category_snapshot'],'Utilities');
    await operations.deleteCategory(managerId:manager,id:id);
    expect((await operations.categories(managerId:manager)).single['active'],0);
    await expectLater(expense(id,source:FundingSource.bank),throwsStateError);
    await operations.saveCategory(managerId:manager,id:id,name:'Power',allowedSource:'BANK');
    await expense(id,source:FundingSource.bank);
    expect(await shifts.getCashMovements(shift),isEmpty);
  });

  test('case-insensitive duplicate categories rejected and unused category deletes',() async {
    final id=await category();
    await expectLater(operations.saveCategory(managerId:manager,name:'utilities'),throwsA(isA<DatabaseException>()));
    await operations.deleteCategory(managerId:manager,id:id);
    expect(await operations.categories(managerId:manager),isEmpty);
    expect(await db.query('operations_audit'),hasLength(2));
  });

  test('expense correction is atomic reversal plus replacement with linked cash',() async {
    final id=await category();
    final original=await expense(id);
    final corrected=await expense(id,amount:15000,corrects:original);
    final entries=await operations.expenses(managerId:manager);
    expect(entries,hasLength(3));
    expect(entries.first['id'],corrected);
    expect(entries.first['correction_of'],original);
    expect(entries.fold<int>(0,(sum,e)=>sum+(e['expense_delta_paisa'] as int)),15000);
    expect(await shifts.getCashMovements(shift),hasLength(3));
    await expectLater(expense(id,corrects:original),throwsA(isA<DatabaseException>()));
    expect(await shifts.getCashMovements(shift),hasLength(3));
    expect(await operations.expenses(managerId:manager),hasLength(3));
  });

  test('expense replay is exactly once; reversal immutable and duplicate reversal rolls back',() async {
    final id=await category(); final request=key();
    final original=await expense(id,request:request);
    expect(await expense(id,request:request),original);
    await operations.reverseExpense(managerId:manager,entryId:original,shiftId:shift,reason:'Returned cash',requestKey:key());
    await expectLater(operations.reverseExpense(managerId:manager,entryId:original,shiftId:shift,
      reason:'Twice',requestKey:key()),throwsA(isA<DatabaseException>()));
    expect(await shifts.getCashMovements(shift),hasLength(2));
    final net=(await shifts.getCashMovements(shift)).fold<double>(0,(sum,m)=>sum+(m.type.dbValue=='PAY_IN' ? m.amount : -m.amount));
    expect(net,0);
    await expectLater(db.delete('expense_entries'),throwsA(isA<DatabaseException>()));
  });

  test('closed drawer rejects funded posting atomically while external funds work',() async {
    final id=await category();
    await shifts.closeShift(shiftId:shift,staffId:cashier,countedCash:10000);
    await expectLater(expense(id),throwsStateError);
    expect(await operations.expenses(managerId:manager),isEmpty);
    await expense(id,source:FundingSource.owner);
    expect(await operations.expenses(managerId:manager),hasLength(1));
  });

  test('Cashier cannot configure or post payroll and expenses',() async {
    await expectLater(operations.saveCategory(managerId:cashier,name:'Denied'),throwsStateError);
    await expectLater(operations.setSalary(managerId:cashier,employeeId:employee,
      effectivePeriod:'2026-10',amountPaisa:10000,reason:'Denied'),throwsStateError);
    await expectLater(operations.postPayroll(managerId:cashier,employeeId:employee,
      period:'2026-10',kind:'ADVANCE',amountPaisa:100,source:FundingSource.bank,
      reason:'Denied',requestKey:key()),throwsStateError);
    final id=await category();
    await expectLater(operations.postExpense(managerId:cashier,categoryId:id,
      amountPaisa:100,description:'Denied',source:FundingSource.owner,reason:'Denied',requestKey:key()),throwsStateError);
  });

  test('supplier item restrictions, snapshots, due dates and allocated partial payments',() async {
    final vendor=await khata.createVendor(name:'Packaging',phone:'1');
    final item=await khata.createSuppliedItem(managerId:manager,vendorId:vendor.id,name:'Box',unit:'count');
    final invoice=await khata.recordCreditDelivery(vendorId:vendor.id,amount:1000,
      rawIngredientId:item,quantity:100,createdAt:DateTime(2026,10,1),dueDate:DateTime(2026,10,15),staffId:manager);
    await khata.recordSettlementPayment(vendorId:vendor.id,amount:300,
      paymentSource:VendorPaymentSource.paidFromActiveDrawer,shiftId:shift,staffId:manager,
      allocations:{invoice.id:30000});
    expect((await khata.invoices(vendor.id)).single['due_paisa'],70000);
    expect((await khata.invoices(vendor.id)).single['due_date'],'2026-10-15');
    await khata.setSuppliedItems(managerId:manager,vendorId:vendor.id,ingredientIds:{});
    await expectLater(khata.recordCreditDelivery(vendorId:vendor.id,amount:100,
      rawIngredientId:item,quantity:10),throwsStateError);
    expect((await db.query('raw_ingredients',where:'id=?',whereArgs:[item])).single['current_stock'],100);
    expect((await khata.invoices(vendor.id)).single['ingredient_name_snapshot'],'Box');
    await khata.recordSettlementPayment(vendorId:vendor.id,amount:700,
      paymentSource:VendorPaymentSource.paidOutsideDrawer,staffId:manager);
    expect((await khata.invoices(vendor.id)).single['due_paisa'],0);
    expect(await shifts.getCashMovements(shift),hasLength(1));
  });

  test('wrong-supplier allocation and overpayment roll back payable and cash',() async {
    final vendor=await khata.createVendor(name:'A',phone:'1');
    final other=await khata.createVendor(name:'B',phone:'2');
    await khata.recordCreditDelivery(vendorId:vendor.id,amount:100);
    final invoice=await khata.recordCreditDelivery(vendorId:other.id,amount:100);
    await expectLater(khata.recordSettlementPayment(vendorId:vendor.id,amount:50,
      paymentSource:VendorPaymentSource.paidFromActiveDrawer,shiftId:shift,staffId:manager,
      allocations:{invoice.id:5000}),throwsStateError);
    await expectLater(khata.recordSettlementPayment(vendorId:vendor.id,amount:101,
      paymentSource:VendorPaymentSource.paidFromActiveDrawer,shiftId:shift,staffId:manager),throwsStateError);
    expect((await khata.getVendorById(vendor.id))!.currentBalance,100);
    expect(await shifts.getCashMovements(shift),isEmpty);
  });

  test('automatic allocation covers opening payable then earliest due invoices',() async {
    final vendor=await khata.createVendor(name:'Terms',phone:'1',openingBalance:10);
    final late=await khata.recordCreditDelivery(vendorId:vendor.id,amount:100,
      createdAt:DateTime(2026,10,1),dueDate:DateTime(2026,10,30));
    final early=await khata.recordCreditDelivery(vendorId:vendor.id,amount:100,
      createdAt:DateTime(2026,10,1),dueDate:DateTime(2026,10,15));
    await khata.recordSettlementPayment(vendorId:vendor.id,amount:160,
      paymentSource:VendorPaymentSource.paidOutsideDrawer,staffId:manager);
    final invoices=await khata.invoices(vendor.id);
    expect(invoices.singleWhere((i)=>i['id']==early.id)['due_paisa'],0);
    expect(invoices.singleWhere((i)=>i['id']==late.id)['due_paisa'],5000);
    expect(await db.query('supplier_payment_allocations'),hasLength(3));
  });

  test('supplier duplicate references and invalid dates do not mutate stock',() async {
    final vendor=await khata.createVendor(name:'Duplicate',phone:'1');
    await khata.recordCreditDelivery(vendorId:vendor.id,amount:100,referenceSlip:'INV-1');
    await expectLater(khata.recordCreditDelivery(vendorId:vendor.id,amount:100,referenceSlip:'INV-1'),throwsStateError);
    await expectLater(khata.recordCreditDelivery(vendorId:vendor.id,amount:100,
      createdAt:DateTime(2026,10,2),dueDate:DateTime(2026,10,1)),throwsArgumentError);
    expect((await khata.getVendorById(vendor.id))!.currentBalance,100);
  });

  test('worked hours recording validates inputs, computes net minutes, prevents replay, and rejects cashier', () async {
    // 1. Cashier cannot record worked hours
    await expectLater(
      operations.recordWorkedHours(
        managerId: cashier,
        employeeId: employee,
        workDate: '2026-10-25',
        clockIn: DateTime.utc(2026, 10, 25, 11, 0),
        clockOut: DateTime.utc(2026, 10, 25, 20, 0),
        breakMinutes: 60,
        requestKey: key(),
      ),
      throwsStateError,
    );

    // 2. Invalid inputs reject
    await expectLater(
      operations.recordWorkedHours(
        managerId: manager,
        employeeId: employee,
        workDate: 'invalid-date',
        clockIn: DateTime.utc(2026, 10, 25, 11, 0),
        clockOut: DateTime.utc(2026, 10, 25, 20, 0),
        requestKey: key(),
      ),
      throwsArgumentError,
    );
    await expectLater(
      operations.recordWorkedHours(
        managerId: manager,
        employeeId: employee,
        workDate: '2026-10-25',
        clockIn: DateTime.utc(2026, 10, 25, 20, 0),
        clockOut: DateTime.utc(2026, 10, 25, 11, 0),
        requestKey: key(),
      ),
      throwsArgumentError,
    );
    await expectLater(
      operations.recordWorkedHours(
        managerId: manager,
        employeeId: employee,
        workDate: '2026-10-25',
        clockIn: DateTime.utc(2026, 10, 25, 11, 0),
        clockOut: DateTime.utc(2026, 10, 25, 12, 0),
        breakMinutes: 120, // Break exceeds shift
        requestKey: key(),
      ),
      throwsArgumentError,
    );

    // 3. Manager successfully records worked hours: 11:00 to 20:00 (9 hrs = 540m) - 60m break = 480m (8.0 hrs)
    final req = key();
    final id1 = await operations.recordWorkedHours(
      managerId: manager,
      employeeId: employee,
      workDate: '2026-10-25',
      clockIn: DateTime.utc(2026, 10, 25, 11, 0),
      clockOut: DateTime.utc(2026, 10, 25, 20, 0),
      breakMinutes: 60,
      reason: 'Shift attendance',
      requestKey: req,
    );
    expect(id1, isPositive);

    final history = await operations.workedHoursHistory(managerId: manager, employeeId: employee);
    expect(history, hasLength(1));
    expect(history.first['worked_minutes'], 480);
    expect(history.first['work_date'], '2026-10-25');
    expect(history.first['employee_name'], 'Kitchen helper');

    // 4. Request replay with identical payload returns existing id
    final idReplay = await operations.recordWorkedHours(
      managerId: manager,
      employeeId: employee,
      workDate: '2026-10-25',
      clockIn: DateTime.utc(2026, 10, 25, 11, 0),
      clockOut: DateTime.utc(2026, 10, 25, 20, 0),
      breakMinutes: 60,
      reason: 'Shift attendance',
      requestKey: req,
    );
    expect(idReplay, id1);

    // 5. Request replay with modified payload throws StateError
    await expectLater(
      operations.recordWorkedHours(
        managerId: manager,
        employeeId: employee,
        workDate: '2026-10-25',
        clockIn: DateTime.utc(2026, 10, 25, 11, 0),
        clockOut: DateTime.utc(2026, 10, 25, 21, 0),
        breakMinutes: 60,
        reason: 'Modified',
        requestKey: req,
      ),
      throwsStateError,
    );
  });

  test('worked_hours table is immutable; UPDATE and DELETE abort with financial history trigger', () async {
    final id = await operations.recordWorkedHours(
      managerId: manager,
      employeeId: employee,
      workDate: '2026-10-25',
      clockIn: DateTime.utc(2026, 10, 25, 11, 0),
      clockOut: DateTime.utc(2026, 10, 25, 19, 0),
      breakMinutes: 0,
      requestKey: key(),
    );

    await expectLater(
      db.rawUpdate('UPDATE worked_hours SET worked_minutes = 999 WHERE id = ?', [id]),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.rawDelete('DELETE FROM worked_hours WHERE id = ?', [id]),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('department labor allocation prorates monthly salary based on verified hours (ADR-0020 Example 3)', () async {
    // Cook Danish earned PKR 30,000 (3,000,000 paisa) in October 2026
    final kitchenDept = (await db.query('departments', where: "name='Kitchen'")).first['id'] as int;
    final serviceDept = (await db.query('departments', where: "name='Front Counter'")).first['id'] as int;

    final danish = await db.insert('staff', {
      'name': 'Danish',
      'department_id': kitchenDept,
      'pin_hash': 'danish-pin',
      'role': 'CASHIER',
      'login_enabled': 0,
      'created_at': '2026-10-01',
    });

    await operations.setSalary(
      managerId: manager,
      employeeId: danish,
      effectivePeriod: '2026-10',
      amountPaisa: 3000000,
      reason: 'Monthly wage agreement',
    );
    await operations.postPayroll(
      managerId: manager,
      employeeId: danish,
      period: '2026-10',
      kind: 'ACCRUAL',
      amountPaisa: 3000000,
      reason: 'October earned accrual',
      requestKey: key(),
    );

    // Danish worked 80 hours (4800 mins) in Kitchen, 120 hours (7200 mins) in Service. Total = 200 hours.
    await operations.recordWorkedHours(
      managerId: manager,
      employeeId: danish,
      departmentId: kitchenDept,
      workDate: '2026-10-10',
      clockIn: DateTime.utc(2026, 10, 10, 8, 0),
      clockOut: DateTime.utc(2026, 10, 10, 16, 0),
      breakMinutes: 0,
      workedMinutes: 4800, // 80 hrs
      requestKey: key(),
    );
    await operations.recordWorkedHours(
      managerId: manager,
      employeeId: danish,
      departmentId: serviceDept,
      workDate: '2026-10-20',
      clockIn: DateTime.utc(2026, 10, 20, 8, 0),
      clockOut: DateTime.utc(2026, 10, 20, 16, 0),
      breakMinutes: 0,
      workedMinutes: 7200, // 120 hrs
      requestKey: key(),
    );

    final allocation = await operations.departmentLaborAllocation(managerId: manager, period: '2026-10');
    expect(allocation['total_labor_cost_paisa'], 3000000);

    final depts = allocation['departments'] as List<Map<String, dynamic>>;
    final kitchenAlloc = depts.firstWhere((d) => d['department_id'] == kitchenDept)['allocated_paisa'];
    final serviceAlloc = depts.firstWhere((d) => d['department_id'] == serviceDept)['allocated_paisa'];

    // 80/200 = 40% -> 1,200,000 paisa (PKR 12,000.00)
    // 120/200 = 60% -> 1,800,000 paisa (PKR 18,000.00)
    expect(kitchenAlloc, 1200000);
    expect(serviceAlloc, 1800000);
    expect(kitchenAlloc + serviceAlloc, 3000000);
  });

  test('department labor allocation defaults to primary department for unlogged staff and avoids payment double-expense', () async {
    final kitchenDept = (await db.query('departments', where: "name='Kitchen'")).first['id'] as int;
    final helper = await db.insert('staff', {
      'name': 'Unlogged helper',
      'department_id': kitchenDept,
      'pin_hash': 'helper-pin',
      'role': 'CASHIER',
      'login_enabled': 0,
      'created_at': '2026-10-01',
    });

    await operations.setSalary(
      managerId: manager,
      employeeId: helper,
      effectivePeriod: '2026-10',
      amountPaisa: 2000000,
      reason: 'Base salary',
    );
    await operations.postPayroll(
      managerId: manager,
      employeeId: helper,
      period: '2026-10',
      kind: 'ACCRUAL',
      amountPaisa: 2000000,
      reason: 'Full month accrual',
      requestKey: key(),
    );
    // Salary payment and advances do NOT count as another expense or allocate twice
    await operations.postPayroll(
      managerId: manager,
      employeeId: helper,
      period: '2026-10',
      kind: 'PAYMENT',
      amountPaisa: 1500000,
      source: FundingSource.drawer,
      shiftId: shift,
      reason: 'Salary partial payment',
      requestKey: key(),
    );

    final allocation = await operations.departmentLaborAllocation(managerId: manager, period: '2026-10');
    final helperAlloc = (allocation['employees'] as List<Map<String, dynamic>>)
        .firstWhere((e) => e['employee_id'] == helper);
    expect(helperAlloc['method'], 'PRIMARY_DEPARTMENT_DEFAULT');
    expect(helperAlloc['accrual_paisa'], 2000000);
    final depts = helperAlloc['allocations'] as List<Map<String, dynamic>>;
    expect(depts.single['department_id'], kitchenDept);
    expect(depts.single['allocated_paisa'], 2000000);
  });
}
