import 'package:flutter/material.dart';
import '../../core/analytics/historical_corrections.dart';
import '../../core/auth/staff_role.dart';
import '../../core/time/actual_event_time.dart';
import 'analytics_export_actions.dart';

class HistoricalCorrectionsWorkspace extends StatefulWidget {
  const HistoricalCorrectionsWorkspace({super.key,required this.service});
  final HistoricalCorrections service;
  @override
  State<HistoricalCorrectionsWorkspace> createState()=>_HistoricalCorrectionsWorkspaceState();
}
class _HistoricalCorrectionsWorkspaceState extends State<HistoricalCorrectionsWorkspace> {
  List<int> _days=[];
  int? _day;
  HistoricalCorrectionSnapshot? _snapshot;
  String? _error;
  bool _busy=false, _adjusted=true;
  final _cutoff=TextEditingController();
  bool get _authorized {
    final staff=widget.service.auth.session.currentStaff;
    return staff!=null && staff.role==StaffRole.manager && staff.isActive && staff.loginEnabled;
  }
  @override
  void initState(){super.initState();widget.service.auth.session.addListener(_sessionChanged);_loadDays();}
  void _sessionChanged(){if(mounted){setState((){_snapshot=null;_days=[];_day=null;});if(_authorized)_loadDays();}}
  @override
  void dispose(){widget.service.auth.session.removeListener(_sessionChanged);_cutoff.dispose();super.dispose();}
  Future<void> _loadDays() async {
    if(!_authorized)return;
    try{final days=await widget.service.closedDays();if(mounted&&_authorized)setState(()=>_days=days);}
    catch(_){if(mounted)setState(()=>_error='Manager session required.');}
  }
  Future<void> _load()async{
    if(!mounted||_day==null||!_authorized)return;
    setState((){_busy=true;_error=null;_snapshot=null;});
    try{final value=await widget.service.load(_day!,cutoff:parseActualEventTime(_cutoff.text));if(mounted&&_authorized)setState(()=>_snapshot=value);}
    catch(e){if(mounted)setState(()=>_error='$e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _append({int? reverseId})async{
    if(!mounted||_day==null||!_authorized)return;
    final form=GlobalKey<FormState>();
    final fields={for(final key in ['pin','amount','shift','order','source','reason','event','sourceTable','sourceId'])key:TextEditingController()};
    var kind=HistoricalCorrectionType.collection;
    var payment='DRAWER_CASH';
    var reconciled=false,saving=false;
    String? error;
    await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(dialog,update){
      Widget field(String key,String label,{bool optional=false})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(controller:fields[key],
        obscureText:key=='pin',decoration:InputDecoration(labelText:label),validator:(v){
          if(!optional&&(v??'').trim().isEmpty)return 'Required';
          if(key=='reason'&&(v??'').trim().length<10)return 'Use at least 10 characters';
          if(['amount','shift','order','sourceId'].contains(key)&&(v??'').isNotEmpty&&int.tryParse(v!)==null)return 'Enter Integer Paisa or a whole ID';
          if(key=='event'){try{parseActualEventTime(v);}catch(e){return '$e';}}
          return null;
        }));
      return AlertDialog(title:Text(reverseId==null?'Append historical correction':'Contra-reverse correction #$reverseId'),
        content:SizedBox(width:560,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Original sealed reports and today’s drawer remain unchanged. Verify original evidence and reconcile the physical effect before recording.'),
          const SizedBox(height:12),
          if(reverseId==null)...[
            DropdownButtonFormField<HistoricalCorrectionType>(isExpanded:true,initialValue:kind,decoration:const InputDecoration(labelText:'Correction type'),
              items:[for(final type in HistoricalCorrectionType.values)DropdownMenuItem(value:type,child:Text(switch(type){
                HistoricalCorrectionType.collection=>'Late Collection Due receipt',HistoricalCorrectionType.drawerPayout=>'Late supplier payout',
                HistoricalCorrectionType.expense=>'Late expense',HistoricalCorrectionType.refund=>'Late refund',HistoricalCorrectionType.discrepancyExplanation=>'Discrepancy explanation'}))],onChanged:(v)=>update(()=>kind=v!)),
            field('amount','Signed amount (Integer Paisa)'),field('shift','Affected closed Shift ID',optional:true),
            field('order','Original Order ID (required for collection)',optional:true),
            DropdownButtonFormField<String>(isExpanded:true,initialValue:payment,decoration:const InputDecoration(labelText:'Payment Source'),
              items:[for(final source in ['DRAWER_CASH','BANK_DIGITAL','OWNER_FUNDS'])DropdownMenuItem(value:source,child:Text(source))],onChanged:(v)=>update(()=>payment=v!)),
            field('event','Actual Event Time (Pakistan YYYY-MM-DD HH:MM)'),field('source','Unique source evidence reference'),
            DropdownButtonFormField<String>(isExpanded:true,decoration:const InputDecoration(labelText:'Supporting original evidence (optional)'),
              items:const [DropdownMenuItem(value:'orders',child:Text('Original Order')),DropdownMenuItem(value:'vendor_transactions',child:Text('Supplier credit delivery')),DropdownMenuItem(value:'payroll_entries',child:Text('Payroll accrual'))],
              onChanged:(v)=>fields['sourceTable']!.text=v??''),field('sourceId','Original evidence ID (optional)',optional:true),
            CheckboxListTile(value:reconciled,onChanged:(v)=>update(()=>reconciled=v??false),title:const Text('I verified this evidence and reconciled that the physical effect was not posted elsewhere.')),
          ],
          field('reason','Business reason'),field('pin','Your Manager PIN'),
          if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        ])))),actions:[TextButton(onPressed:saving?null:()=>Navigator.pop(dialog),child:const Text('Cancel')),
        FilledButton(onPressed:saving?null:()async{
          if(!form.currentState!.validate())return;
          update(()=>saving=true);
          try{
            if(reverseId!=null){await widget.service.reverse(reverseId,managerPin:fields['pin']!.text,reason:fields['reason']!.text);}
            else{await widget.service.append(managerPin:fields['pin']!.text,businessDayId:_day!,
              shiftId:int.tryParse(fields['shift']!.text),orderId:int.tryParse(fields['order']!.text),type:kind,
              deltaPaisa:int.parse(fields['amount']!.text),evidenceKey:fields['source']!.text,reason:fields['reason']!.text,
              sourceTable:fields['sourceTable']!.text.trim().isEmpty?null:fields['sourceTable']!.text.trim(),sourceId:int.tryParse(fields['sourceId']!.text),
              reconciled:reconciled,eventTime:parseActualEventTime(fields['event']!.text),paymentSource:payment);}
            if(dialog.mounted)Navigator.pop(dialog);
          }catch(e){if(dialog.mounted)update((){error='$e';saving=false;});}
        },child:Text(saving?'Recording…':reverseId==null?'Append correction':'Append contra-reversal'))]);
    }));
    // Dialog route disposes its text fields after the closing animation.
    await _load();
  }
  @override
  Widget build(BuildContext context){
    if(!_authorized)return const Center(child:Text('Manager session required.'));
    final snapshot=_snapshot;
    final report=snapshot?.toAnalyticsSnapshot(adjusted:_adjusted);
    final section=report?.section(AnalyticsFamily.cash);
    return ListView(padding:const EdgeInsets.all(20),children:[
      Text('Historical corrections',style:Theme.of(context).textTheme.headlineSmall),
      const Text('Compare original sealed evidence with an explicit adjustment bridge. Unknown historical evidence remains unknown.'),
      const SizedBox(height:16),
      Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
        SizedBox(width:240,child:DropdownButtonFormField<int>(isExpanded:true,initialValue:_day,decoration:const InputDecoration(labelText:'Closed Business Day'),
          items:[for(final id in _days)DropdownMenuItem(value:id,child:Text('Business Day #$id',overflow:TextOverflow.ellipsis))],onChanged:_busy?null:(v){setState(()=>_day=v);_load();})),
        SizedBox(width:290,child:TextField(controller:_cutoff,decoration:const InputDecoration(labelText:'Recording cutoff (Pakistan)',hintText:'YYYY-MM-DD HH:MM; blank = now'))),
        OutlinedButton(onPressed:_busy?null:_load,child:const Text('Apply cutoff')),
        SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('Original sealed')),ButtonSegment(value:true,label:Text('Correction-adjusted'))],selected:{_adjusted},onSelectionChanged:(v)=>setState(()=>_adjusted=v.single)),
        FilledButton(onPressed:_day==null||_busy?null:()=>_append(),child:const Text('Append correction')),
      ]),
      if(_days.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('No closed Business Days available.')),
      if(_busy)const LinearProgressIndicator(),if(_error!=null)Text(_error!),
      if(snapshot!=null&&report!=null&&section!=null)...[
        for(final note in section.notes)Padding(padding:const EdgeInsets.only(top:8),child:SelectableText(note)),
        const SizedBox(height:12),AnalyticsExportActions(snapshot:report,family:AnalyticsFamily.cash,canExport:()=>mounted&&_authorized&&identical(snapshot,_snapshot)),
        for(final row in section.rows)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${row.cells['basis']} · ${row.cells['measure']} · ${row.cells['amount']??'Unknown'} paisa'),
          if(row.cells['sealed_evidence'] != null) SelectableText('${row.cells['sealed_evidence']}'),
          if(row.sourceType=='historical_corrections')...[
            SelectableText('Correction #${row.sourceId}; ${row.cells['manager_name_snapshot']}; recorded ${row.cells['recorded_at']}; actual ${row.cells['event_time']??'Unknown'}'),
            SelectableText('Evidence ${row.cells['source_reference']}; ${row.cells['target_entity_type']} #${row.cells['target_entity_id']??'Unknown'}; Shift #${row.cells['affected_shift_id']??'Unknown'}'),
            Text('${row.cells['reason']}'),
            if(row.cells['reverses_correction_id']==null)TextButton(onPressed:()=>_append(reverseId:int.parse(row.sourceId!)),child:const Text('Append contra-reversal')),
          ]
        ]))),
      ],
    ]);
  }
}
