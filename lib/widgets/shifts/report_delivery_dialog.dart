import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/shifts/report_delivery_service.dart';
import '../../core/shifts/report_export_service.dart';

/// Manager-only configuration, local archive, and independent delivery history.
class ReportDeliveryDialog extends StatefulWidget {
  const ReportDeliveryDialog({super.key,required this.service,required this.managerStaffId});
  final ReportDeliveryService service;
  final int managerStaffId;
  @override
  State<ReportDeliveryDialog> createState()=>_ReportDeliveryDialogState();
}
class _ReportDeliveryDialogState extends State<ReportDeliveryDialog> {
  final _endpoint=TextEditingController();
  final _gmailSender=TextEditingController();
  final _gmailPassword=TextEditingController();
  final _emails=TextEditingController();
  final _whatsapp=TextEditingController();
  final _consent=TextEditingController();
  final _attempts=TextEditingController(text:'8');
  bool _automatic=true;
  bool _approved=false;
  bool _busy=true;
  String _provider='GMAIL';
  bool _passwordSaved=false;
  String? _message;
  List<Map<String,dynamic>> _jobs=[];
  List<Map<String,dynamic>> _reports=[];
  @override
  void initState(){super.initState();_load();}
  @override
  void dispose(){for(final controller in [_endpoint,_gmailSender,_gmailPassword,_emails,_whatsapp,_consent,_attempts]){controller.dispose();}super.dispose();}
  Future<void> _load() async {
    try {
      final policy=await widget.service.settings(managerStaffId:widget.managerStaffId);
      final jobs=await widget.service.history(managerStaffId:widget.managerStaffId);
      final reports=await ReportExportService(database:widget.service.database).history();
      if(!mounted)return;
      final targets=policy['recipients'] as List? ?? [];
      _provider=policy['email_provider'] as String? ?? (policy.isEmpty?'GMAIL':'RELAY');
      _gmailSender.text=policy['gmail_sender'] as String? ?? '';
      _passwordSaved=policy['gmail_password_saved']==true;
      _endpoint.text=policy['endpoint'] as String? ?? '';
      _emails.text=targets.where((r)=>r['channel']=='EMAIL').map((r)=>r['address']).join('\n');
      _whatsapp.text=targets.where((r)=>r['channel']=='WHATSAPP').map((r)=>r['address']).join('\n');
      _consent.text=targets.where((r)=>r['channel']=='WHATSAPP').map((r)=>r['consent']).where((s)=>s!=null && s!='').join('; ');
      _automatic=policy['auto_send'] as bool? ?? true;
      _approved=targets.isNotEmpty;
      _attempts.text='${policy['max_attempts']??8}';
      setState((){_jobs=jobs;_reports=reports;_busy=false;});
    }catch(_){if(mounted)setState((){_message='Unable to load report settings. Try again.';_busy=false;});}
  }
  List<String> _addresses(String value)=>value.split(RegExp(r'[\n,;]+')).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
  Future<void> _save() async {
    setState(()=>_busy=true);
    try{
      await widget.service.configure(managerStaffId:widget.managerStaffId,endpoint:_endpoint.text,
        emailProvider:_provider,gmailSender:_gmailSender.text,gmailAppPassword:_gmailPassword.text,
        autoSend:_automatic,maxAttempts:int.tryParse(_attempts.text)??0,
        recipients:[
          ..._addresses(_emails.text).map((address)=>ReportRecipient(channel:'EMAIL',address:address,approved:_approved)),
          if(_provider=='RELAY') ..._addresses(_whatsapp.text).map((address)=>ReportRecipient(channel:'WHATSAPP',address:address,approved:_approved,consent:_consent.text)),
        ]);
      _gmailPassword.clear();
      await _load();
      if(mounted)setState(()=>_message='Saved. Automatic delivery uses approved targets at the next Business Day close.');
    }catch(error){if(mounted)setState(()=>_message=error is ArgumentError?'${error.message}':'Unable to save report settings.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _forgetPassword() async {
    setState(()=>_busy=true);
    try {
      await widget.service.forgetGmailPassword(managerStaffId:widget.managerStaffId);
      _gmailPassword.clear();
      await _load();
      if(mounted)setState(()=>_message='Gmail password removed. Save a new app password to resume sending.');
    } catch (_) {
      if(mounted)setState((){_busy=false;_message='Unable to remove the saved Gmail password.';});
    }
  }
  Future<void> _verifyGmail() async {
    setState(()=>_busy=true);
    try {
      await widget.service.verifyGmailSignIn(managerStaffId:widget.managerStaffId);
      if(mounted)setState(()=>_message='Gmail sign-in verified. No email was sent.');
    } catch (error) {
      if(mounted)setState(()=>_message=error is ReportDeliveryFailure
          ? error.message : 'Unable to verify Gmail sign-in.');
    } finally { if(mounted)setState(()=>_busy=false); }
  }
  Future<void> _retry(Map<String,dynamic> job) async {
    final reason=TextEditingController();
    final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Retry delivery'),
      content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('For an ambiguous attempt, check provider history first. The original recipient and report stay fixed.'),
        TextField(controller:reason,autofocus:true,decoration:const InputDecoration(labelText:'Required reason')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Queue retry'))]));
    final explanation=reason.text;
    reason.dispose();
    if(confirmed!=true || !mounted)return;
    setState(()=>_busy=true);
    try{await widget.service.retry(managerStaffId:widget.managerStaffId,jobId:job['id'] as int,reason:explanation);await _load();}
    catch(error){if(mounted)setState((){_message=error is ArgumentError?'${error.message}':'Unable to queue retry.';_busy=false;});}
  }
  Future<void> _recover() async {
    setState(()=>_busy=true);
    await ReportExportService(database:widget.service.database).exportPending();
    await widget.service.enqueueReadyReports();
    await _load();
  }
  Future<void> _open(String path) async {
    try{await Process.run(Platform.isWindows?'explorer.exe':Platform.isMacOS?'open':'xdg-open',[path]);}
    catch(_){if(mounted)setState(()=>_message='Open the saved report from: $path');}
  }
  String _masked(String address){final at=address.indexOf('@');return at>0?'${address[0]}***${address.substring(at)}':'***${address.length>4?address.substring(address.length-4):''}';}
  @override
  Widget build(BuildContext context)=>AlertDialog(
    title:const Text('Report delivery & local archive'),
    content:SizedBox(width:950,height:550,child:_busy?const Center(child:CircularProgressIndicator()):DefaultTabController(length:3,child:Column(children:[
      if(_message!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(_message!,semanticsLabel:_message)),
      const TabBar(tabs:[Tab(text:'Delivery settings'),Tab(text:'Local PDF & Excel'),Tab(text:'Delivery history')]),
      Expanded(child:TabBarView(children:[
        ListView(padding:const EdgeInsets.symmetric(vertical:16),children:[
          const Text('Email the saved PDF and Excel reports after closing the Business Day. Sending resumes when internet returns while this app is open.'),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(value:_provider,
            decoration:const InputDecoration(labelText:'Send reports using'),
            items:const [DropdownMenuItem(value:'GMAIL',child:Text('Gmail — no domain or server needed')),
              DropdownMenuItem(value:'RELAY',child:Text('Existing Email / WhatsApp relay'))],
            onChanged:(value){if(value!=null)setState(()=>_provider=value);}),
          if(_provider=='GMAIL') ...[
            TextField(controller:_gmailSender,keyboardType:TextInputType.emailAddress,
              decoration:const InputDecoration(labelText:'Restaurant Gmail address',hintText:'restaurant@gmail.com')),
            TextField(controller:_gmailPassword,obscureText:true,autocorrect:false,enableSuggestions:false,
              decoration:InputDecoration(labelText:'Google app password',
                helperText:_passwordSaved?'Password saved securely on this device. Leave blank to keep it.'
                    :'Enable Google 2-Step Verification, then create a 16-character app password.')),
            const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text(
              'Use an app password from myaccount.google.com/apppasswords. Your normal Google password will not work. The password stays in protected storage on this device.')),
            if(_passwordSaved) Align(alignment:Alignment.centerLeft,
              child:OutlinedButton(onPressed:_verifyGmail,child:const Text('Check saved Gmail sign-in (no email sent)'))),
            if(_passwordSaved) Align(alignment:Alignment.centerLeft,
              child:TextButton(onPressed:_forgetPassword,child:const Text('Remove saved Gmail password'))),
          ],
          if(_provider=='RELAY')
          TextField(controller:_endpoint,decoration:const InputDecoration(labelText:'HTTPS relay endpoint',helperText:'Authentication: RESTAURANT_REPORT_RELAY_TOKEN environment variable. No key is saved here.')),
          TextField(controller:_emails,minLines:1,maxLines:3,decoration:const InputDecoration(labelText:'Approved email recipients',helperText:'One address per line')),
          if(_provider=='RELAY') ...[
          TextField(controller:_whatsapp,minLines:1,maxLines:3,decoration:const InputDecoration(labelText:'Approved WhatsApp recipients (optional)',helperText:'International numbers, e.g. +923001234567. Requires official provider setup.')),
          TextField(controller:_consent,decoration:const InputDecoration(labelText:'WhatsApp recipient consent record')),
          ],
          CheckboxListTile(contentPadding:EdgeInsets.zero,value:_approved,onChanged:(value)=>setState(()=>_approved=value??false),title:const Text('I verified and approved these recipients to receive financial reports')),
          SwitchListTile(contentPadding:EdgeInsets.zero,value:_automatic,onChanged:(value)=>setState(()=>_automatic=value),title:const Text('Automatically queue reports after Business Day close')),
          TextField(controller:_attempts,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Maximum attempts (1–20)',helperText:'Exponential backoff. Failed attempts never reopen the Business Day.')),
          const SizedBox(height:12),Align(alignment:Alignment.centerLeft,child:FilledButton(onPressed:_save,child:const Text('Save approved delivery settings'))),
        ]),
        ListView(padding:const EdgeInsets.symmetric(vertical:12),children:[
          Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:_recover,icon:const Icon(Icons.refresh),label:const Text('Retry local report export'))),
          if(_reports.isEmpty)const Text('No closed Business Day reports yet.'),
          ..._reports.map((report){
            final artifacts=report['artifacts_json']==null?<dynamic>[]:jsonDecode(report['artifacts_json'] as String) as List;
            return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Business Day #${report['business_day_id']} · ${report['status']}',style:Theme.of(context).textTheme.titleMedium),
              if(report['error_message']!=null)Text('${report['error_message']}'),
              ...artifacts.map((artifact)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('${artifact['kind']}'.toUpperCase()),
                subtitle:SelectableText('${artifact['path']}'),trailing:IconButton(tooltip:'Open saved report',onPressed:()=>_open(artifact['path'] as String),icon:const Icon(Icons.open_in_new)))),
            ])));
          }),
        ]),
        ListView(padding:const EdgeInsets.symmetric(vertical:12),children:[
          const Text('ACCEPTED means Gmail or the relay accepted submission. For an ambiguous Gmail attempt, check the sender’s Sent mail before retrying. Queued jobs resume when this PC and app are running.'),
          if(_jobs.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('No report deliveries queued.')),
          ..._jobs.map((job)=>Card(child:ListTile(
            title:Text('Day #${job['business_day_id']} · ${job['channel']} · ${_masked(job['recipient'] as String)}'),
            subtitle:Text('${job['status']} · Attempts ${job['retry_count']}\nNext attempt: ${job['next_attempt_at']}\n${job['error_message']??job['provider_reference']??''}'),
            isThreeLine:true,trailing:['PENDING','FAILED','AMBIGUOUS'].contains(job['status'])?TextButton(onPressed:()=>_retry(job),child:const Text('Retry')):null))),
        ]),
      ])),
    ]))),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))],
  );
}
