import 'package:flutter/material.dart';
import '../../core/finance/operations_controller.dart';
import '../../core/orders/paisa_engine.dart';

typedef _Row = Map<String,Object?>;

/// Shared manager forms keep validation errors and entered values in the dialog.
class OperationField {
  const OperationField(this.name, this.label, {this.initial = '', this.options,
      this.required = true, this.onAdd});
  final String name, label, initial;
  final Map<String,String>? options;
  final bool required;
  final Future<MapEntry<String,String>?> Function()? onAdd;
}

Future<void> showOperationForm(BuildContext context, {required String title,
    required List<OperationField> fields, required Future<void> Function(Map<String,String>) save,
    String? notice}) => showDialog<void>(context: context, barrierDismissible: false,
      builder: (_) => _OperationForm(title: title, fields: fields, save: save, notice: notice));

class _OperationForm extends StatefulWidget {
  const _OperationForm({required this.title, required this.fields, required this.save, this.notice});
  final String title;
  final List<OperationField> fields;
  final String? notice;
  final Future<void> Function(Map<String,String>) save;
  @override
  State<_OperationForm> createState() => _OperationFormState();
}

class _OperationFormState extends State<_OperationForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String,TextEditingController> _controllers;
  late final Map<String,Map<String,String>> _options;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controllers = {for (final f in widget.fields) f.name: TextEditingController(text: f.initial)};
    _options = {for (final f in widget.fields) if (f.options != null) f.name: Map.of(f.options!)};
  }
  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }
  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.save({for (final e in _controllers.entries) e.key: e.value.text.trim()});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _saving = false; });
    }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _form,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.notice != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(widget.notice!)),
        for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 16), child:
          f.options == null ? TextFormField(controller: _controllers[f.name], enabled: !_saving,
            decoration: InputDecoration(labelText: f.label, border: const OutlineInputBorder()),
            validator: (v) => f.required && (v == null || v.trim().isEmpty) ? 'Required' : null) :
          Row(children: [Expanded(child: DropdownButtonFormField<String>(
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: ValueKey('${f.name}:${_controllers[f.name]!.text}:${_options[f.name]!.length}'),
            initialValue: _controllers[f.name]!.text.isEmpty ? null : _controllers[f.name]!.text,
            isExpanded: true, decoration: InputDecoration(labelText: f.label, border: const OutlineInputBorder()),
            items: _options[f.name]!.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: _saving ? null : (v) => _controllers[f.name]!.text = v ?? '',
            validator: (v) => f.required && (v == null || v.isEmpty) ? 'Required' : null)),
            if (f.onAdd != null) IconButton(tooltip: 'Add ${f.label}', icon: const Icon(Icons.add),
              onPressed: _saving ? null : () async {
                final added = await f.onAdd!();
                if (added != null && mounted) setState(() {
                  _options[f.name]![added.key] = added.value; _controllers[f.name]!.text = added.key;
                });
              }),
          ])),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])))),
    actions: [TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save'))]);
}

int parseMoney(String value, {bool zeroAllowed = false}) {
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) throw ArgumentError('Enter PKR with at most two decimal places.');
  final parts = value.split('.');
  final amount = int.parse(parts[0]) * 100 + (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2,'0')));
  if (amount < (zeroAllowed ? 0 : 1)) throw ArgumentError('Enter a positive amount.');
  return amount;
}

class OperationsWorkspace extends StatefulWidget {
  const OperationsWorkspace({super.key, required this.controller, required this.managerId, required this.payroll});
  final OperationsController controller;
  final int managerId;
  final bool payroll;
  @override
  State<OperationsWorkspace> createState() => _OperationsWorkspaceState();
}

class _OperationsWorkspaceState extends State<OperationsWorkspace> {
  List<_Row> _staff = [], _categories = [], _expenses = [], _history = [], _rates = [];
  int? _employeeId, _shiftId;
  String? _error;
  bool _loading = true;
  OperationsController get _controller => widget.controller;
  int get _manager => widget.managerId;
  String get _period => DateTime.now().toIso8601String().substring(0,7);
  String _money(Object? amount) => PaisaEngine.formatRupees((amount as num?)?.toInt() ?? 0);
  String _request() => 'manager-$_manager-${DateTime.now().microsecondsSinceEpoch}';
  static const _sources = {'DRAWER':'Active drawer', 'BANK':'Bank', 'OWNER':'Owner cash'};
  FundingSource _source(String code) => FundingSource.values.singleWhere((s) => s.code == code);

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final staff = await _controller.employees(managerId: _manager);
      final categories = await _controller.categories(managerId: _manager);
      final expenses = await _controller.expenses(managerId: _manager);
      final shifts = await _controller.database.query('shifts', columns:['id'], where: "status='OPEN'", orderBy:'id DESC', limit:1);
      final employee = _employeeId ?? staff.firstOrNull?['id'] as int?;
      final history = employee == null ? <_Row>[] : await _controller.payrollHistory(managerId: _manager, employeeId: employee);
      final rates = employee == null ? <_Row>[] : await _controller.salaryHistory(managerId: _manager, employeeId: employee);
      if (!mounted) return;
      setState(() { _staff=staff; _categories=categories; _expenses=expenses;
        _history=history; _rates=rates; _employeeId=employee;
        _shiftId=shifts.firstOrNull?['id'] as int?; _loading=false; _error=null; });
    } catch(e) { if (mounted) setState(() { _error=e.toString(); _loading=false; }); }
  }

  Future<void> _payrollAction(String kind) async {
    if (_employeeId == null) return;
    final employee = _employeeId!;
    final request = _request();
    await showOperationForm(context, title: kind == 'SALARY' ? 'Configure monthly salary' : 'Payroll: $kind',
      notice: 'Amounts are in PKR. Leave accrual amount blank for the full monthly salary, or enter a manager-approved prorated amount with the reason. Drawer payments reduce active shift cash once. Advances remain separate until explicit recovery.',
      fields: [OperationField('period', kind == 'SALARY' ? 'Effective period (YYYY-MM)' : 'Period (YYYY-MM)', initial: _period),
        OperationField('amount',kind=='ACCRUAL' ? 'Accrual amount (PKR, optional)' : 'Amount (PKR)',required:kind!='ACCRUAL'),
        if (kind == 'PAYMENT' || kind == 'ADVANCE') const OperationField('source','Payment source',initial:'OWNER', options:_sources),
        const OperationField('reason','Reason')], save: (v) async {
        if (kind == 'SALARY') {
          await _controller.setSalary(managerId:_manager, employeeId:employee,
            effectivePeriod:v['period']!, amountPaisa:parseMoney(v['amount']!), reason:v['reason']!);
        } else {
          await _controller.postPayroll(managerId:_manager, employeeId:employee,
            period:v['period']!, kind:kind, amountPaisa:kind == 'ACCRUAL' && v['amount']!.isEmpty ? null : parseMoney(v['amount']!),
            source:v['source'] == null ? null : _source(v['source']!), shiftId:_shiftId,
            reason:v['reason']!, requestKey:request);
        }
      });
    await _load();
  }

  Future<MapEntry<String,String>?> _category([_Row? old]) async {
    MapEntry<String,String>? result;
    await showOperationForm(context, title: old == null ? 'New expense category' : 'Edit expense category', fields:[
      OperationField('name','Name',initial:old?['name'] as String? ?? ''),
      OperationField('description','Description',required:false,initial:old?['description'] as String? ?? ''),
      OperationField('active','Status',initial:old?['active']==0 ? '0':'1', options:const {'1':'Active','0':'Archived'}),
      OperationField('source','Allowed payment source',initial:old?['allowed_source'] as String? ?? 'ANY', options:const {'ANY':'Any',..._sources}),
      OperationField('sort','Sort order',initial:'${old?['sort_order'] ?? 0}'),
      OperationField('threshold','Manager approval threshold (PKR, optional)',required:false,
        initial:old?['approval_threshold_paisa'] == null ? '' : ((old!['approval_threshold_paisa'] as int)/100).toStringAsFixed(2)),
    ], notice:'All expense posting requires a Manager. Used categories archive when removed. Historical entries retain the original category name.', save:(v) async {
      final id=await _controller.saveCategory(managerId:_manager,id:old?['id'] as int?,
        name:v['name']!,description:v['description']!,active:v['active']=='1',
        allowedSource:v['source']!,sortOrder:int.parse(v['sort']!),
        approvalThresholdPaisa:v['threshold']!.isEmpty ? null : parseMoney(v['threshold']!,zeroAllowed:true));
      result=MapEntry('$id',v['name']!);
    });
    return result;
  }

  Future<void> _expense([_Row? old]) async {
    final request=_request();
    await showOperationForm(context,title:old==null ? 'Record expense' : 'Correct expense #${old['id']}',
      notice:old==null ? 'Drawer funding reduces active shift cash. Bank and owner funds do not affect the drawer.' :
        'This reverses the original and posts a replacement atomically. Confirm the original funds were returned; the reversal is a PAY_IN for drawer-funded expenses.',
      fields:[OperationField('category','Category',initial:old==null || !_categories.any((c)=>c['id']==old['category_id'] && c['active']==1) ? '' : '${old['category_id']}',
        options:{for(final c in _categories) if(c['active']==1) '${c['id']}':c['name'] as String},
        onAdd:() => _category()),
        OperationField('description','Paid-for description',initial:old?['description'] as String? ?? ''),
        OperationField('payee','Payee',required:false,initial:old?['payee'] as String? ?? ''),
        OperationField('amount','Amount (PKR)',initial:old==null ? '' : ((old['amount_paisa'] as int)/100).toStringAsFixed(2)),
        OperationField('source','Payment source',initial:old?['source'] as String? ?? 'OWNER',options:_sources),
        OperationField('receipt','Receipt path (optional)',required:false,initial:old?['receipt_path'] as String? ?? ''),
        const OperationField('reason','Reason / correction explanation')], save:(v) async {
        await _controller.postExpense(managerId:_manager,categoryId:int.parse(v['category']!),
          amountPaisa:parseMoney(v['amount']!),description:v['description']!,payee:v['payee']!,
          source:_source(v['source']!),shiftId:_shiftId,receiptPath:v['receipt']!.isEmpty ? null : v['receipt'],
          reason:v['reason']!,requestKey:request,correctsEntryId:old?['id'] as int?);
      });
    await _load();
  }

  Future<void> _reverse(_Row row, bool payroll) async {
    final request=_request();
    await showOperationForm(context,title:'Reverse entry #${row['id']}',
      notice:'Confirm funds have been returned to the original source. Drawer reversals add cash to the current active drawer. The original entry is retained.',
      fields:const [OperationField('reason','Reversal reason')],save:(v) async {
        if(payroll) {
          await _controller.reversePayroll(managerId:_manager,entryId:row['id'] as int,
            shiftId:_shiftId,reason:v['reason']!,requestKey:request);
        } else {
          await _controller.reverseExpense(managerId:_manager,entryId:row['id'] as int,
            shiftId:_shiftId,reason:v['reason']!,requestKey:request);
        }
      });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if(_loading) return const Center(child:CircularProgressIndicator());
    final employee=_staff.where((s)=>s['id']==_employeeId).firstOrNull;
    final history=widget.payroll ? _history : _expenses;
    final reversed=history.where((r)=>r['reversal_of']!=null).map((r)=>r['reversal_of']).toSet();
    return ListView(padding:const EdgeInsets.all(20),children:[
      Row(children:[Expanded(child:Text(widget.payroll ? 'Payroll & employee balances' : 'Expenses & categories',style:Theme.of(context).textTheme.headlineSmall)),
        IconButton(tooltip:'Refresh',onPressed:_load,icon:const Icon(Icons.refresh))]),
      if(_error!=null) Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(widget.payroll) ...[
        DropdownButtonFormField<int>(key:ValueKey(_employeeId),initialValue:_employeeId,
          decoration:const InputDecoration(labelText:'Employee'),
          items:_staff.map((s)=>DropdownMenuItem(value:s['id'] as int,child:Text('${s['name']}${s['is_active']==0 ? ' (inactive)' : ''}'))).toList(),
          onChanged:(v) async {setState(()=>_employeeId=v);await _load();}),
        const SizedBox(height:12),
        if(employee!=null) Text('Accrued payable: ${_money(employee['payable_paisa'])}   •   Outstanding advances: ${_money(employee['advance_paisa'])}   •   Net due: ${_money((employee['payable_paisa'] as int)-(employee['advance_paisa'] as int))}'),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          for(final action in const {'SALARY':'Configure salary','ACCRUAL':'Accrue salary','ADVANCE':'Pay advance','RECOVERY':'Recover advance','PAYMENT':'Pay salary'}.entries)
            OutlinedButton(onPressed:_employeeId==null ? null : ()=>_payrollAction(action.key),child:Text(action.value)),
        ]),
        for(final rate in _rates) ListTile(title:Text('Monthly salary ${_money(rate['amount_paisa'])} from ${rate['effective_period']}'),subtitle:Text('${rate['reason']}')),
      ] else ...[
        Text('Net recorded expense: ${_money(_expenses.fold<int>(0,(sum,e)=>sum+(e['expense_delta_paisa'] as int)))}'),
        Wrap(spacing:8,children:[FilledButton(onPressed:()=>_expense(),child:const Text('Record expense')),
          OutlinedButton(onPressed:() async {await _category();await _load();},child:const Text('New category'))]),
        for(final category in _categories) ListTile(title:Text('${category['name']} ${category['active']==0 ? '(archived)' : ''}'),
          subtitle:Text('${category['description']} • ${category['allowed_source']}'),
          trailing:Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(tooltip:'Edit category',onPressed:() async {await _category(category);await _load();},icon:const Icon(Icons.edit_outlined)),
            IconButton(tooltip:'Delete unused / archive used category',onPressed:() async {
              try {await _controller.deleteCategory(managerId:_manager,id:category['id'] as int);await _load();}
              catch(e) {if(mounted) setState(()=>_error=e.toString());}
            },icon:const Icon(Icons.archive_outlined)),
          ])),
      ],
      const Divider(),
      const Text('Immutable history'),
      for(final row in history) Card(child:ListTile(
        title:Text(widget.payroll ? '#${row['id']} ${row['period']} ${row['kind']} ${_money(row['amount_paisa'])}' :
          '#${row['id']} ${row['category_snapshot']} • ${row['description']} ${_money(row['expense_delta_paisa'])}'),
        subtitle:Text('${row['source']} • ${row['created_at']} • Manager #${row['manager_id']}\n${row['reason']}${reversed.contains(row['id']) ? ' • REVERSED' : ''}'),
        trailing:row['reversal_of']!=null || reversed.contains(row['id']) ? null :
          Wrap(children:[if(!widget.payroll) TextButton(onPressed:()=>_expense(row),child:const Text('Correct')),
            TextButton(onPressed:()=>_reverse(row,widget.payroll),child:const Text('Reverse'))]),
      )),
    ]);
  }
}
