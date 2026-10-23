import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/staff_role.dart';
import 'report_export_service.dart';
import 'gmail_report_sender.dart';
import 'report_credential_store.dart';
import 'report_delivery_failure.dart';
export 'report_delivery_failure.dart';

typedef ReportTransport = Future<String> Function(Map<String,dynamic> job);

class ReportRecipient {
  const ReportRecipient({required this.channel,required this.address,required this.approved,this.consent = ''});
  final String channel;
  final String address;
  final bool approved;
  final String consent;
  Map<String,dynamic> toJson() => {'channel':channel,'address':address.trim(),'approved':approved,'consent':consent.trim()};
}

/// Offline outbox worker. It never mutates financial or inventory records.
class ReportDeliveryService {
  ReportDeliveryService({required this.database, ReportTransport? transport,
    ReportCredentialStore? credentialStore, GmailSubmission? gmailSubmission})
      : _transport = transport,
        _credentials = credentialStore ?? SecureReportCredentialStore(database.path),
        _gmail = GmailReportSender(submit: gmailSubmission);
  final Database database;
  final ReportTransport? _transport;
  final ReportCredentialStore _credentials;
  final GmailReportSender _gmail;
  Timer? _timer;
  bool _running = false;

  Future<void> _manager(int staffId) async {
    final staff = await database.query('staff',where:'id=? AND is_active=1',whereArgs:[staffId]);
    if (staff.isEmpty || StaffRole.fromCode(staff.single['role'] as String)!=StaffRole.manager) {
      throw StateError('Only an active Manager may manage report delivery.');
    }
  }

  Future<Map<String,dynamic>> settings({required int managerStaffId}) async {
    await _manager(managerStaffId);
    final policy = await _settings();
    final reference = policy['gmail_credential_id'] as String?;
    return {...policy, 'gmail_password_saved': reference != null &&
      await _credentials.read(reference) != null};
  }

  Future<Map<String,dynamic>> _settings() async {
    final rows = await database.query('system_settings',where:"key='report_delivery_settings'");
    return rows.isEmpty ? <String,dynamic>{} : Map<String,dynamic>.from(jsonDecode(rows.single['value'] as String) as Map);
  }

  Future<void> configure({required int managerStaffId, String endpoint = '',
    required List<ReportRecipient> recipients, bool autoSend=true, int maxAttempts=8,
    String emailProvider = 'RELAY', String gmailSender = '', String? gmailAppPassword}) async {
    await _manager(managerStaffId);
    final previous = await _settings();
    final sender = gmailSender.trim().toLowerCase();
    String destination;
    if (emailProvider == 'GMAIL') {
      if (!RegExp(r'^[a-z0-9.]+@(gmail|googlemail)\.com$').hasMatch(sender)) {
        throw ArgumentError('Enter the dedicated Gmail address used to send reports.');
      }
      destination = 'gmail:$sender';
    } else if (emailProvider == 'RELAY') {
      final uri = Uri.tryParse(endpoint.trim());
      if (uri==null || uri.scheme!='https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
        throw ArgumentError('Enter an HTTPS report relay URL without credentials or query parameters.');
      }
      destination = uri.toString();
    } else {
      throw ArgumentError('Choose Gmail or the existing relay.');
    }
    if (maxAttempts<1 || maxAttempts>20) throw ArgumentError('Maximum attempts must be 1–20.');
    final seen = <String>{};
    for (final recipient in recipients) {
      final address = recipient.address.trim();
      if (!recipient.approved) throw ArgumentError('Only approved recipients may be configured.');
      if (recipient.channel=='EMAIL') {
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) throw ArgumentError('Invalid approved email address.');
      } else if (recipient.channel=='WHATSAPP') {
        if (emailProvider == 'GMAIL') throw ArgumentError('Gmail sends email only. WhatsApp requires the relay option.');
        if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(address) || recipient.consent.trim().isEmpty) {
          throw ArgumentError('WhatsApp needs an international number and recorded recipient consent.');
        }
      } else {
        throw ArgumentError('Unsupported report channel.');
      }
      if (!seen.add('${recipient.channel}:$address')) throw ArgumentError('Duplicate report recipient.');
    }
    String? credentialId;
    var newCredential = false;
    if (emailProvider == 'GMAIL') {
      final password = (gmailAppPassword ?? '').replaceAll(RegExp(r'\s'), '');
      if (password.isNotEmpty) {
        if (!RegExp(r'^[a-zA-Z0-9]{16}$').hasMatch(password)) {
          throw ArgumentError('Use the 16-character Google app password, not your Google account password.');
        }
        final random = Random.secure();
        credentialId = List.generate(24, (_) => random.nextInt(256))
            .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        await _credentials.write(credentialId, password);
        newCredential = true;
      } else {
        credentialId = previous['gmail_sender'] == sender
            ? previous['gmail_credential_id'] as String? : null;
        if (credentialId == null || await _credentials.read(credentialId) == null) {
          throw ArgumentError('Enter a Google app password for this Gmail address.');
        }
      }
    }
    final value = jsonEncode({'endpoint':destination,'auto_send':autoSend,'max_attempts':maxAttempts,
      'email_provider':emailProvider, if (emailProvider == 'GMAIL') ...{
        'gmail_sender':sender, 'gmail_credential_id':credentialId,
      }, 'recipients':recipients.map((r)=>r.toJson()).toList()});
    try {
      await database.transaction((txn) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('system_settings',{'key':'report_delivery_settings','value':value,'updated_at':now},conflictAlgorithm:ConflictAlgorithm.replace);
      await txn.insert('report_delivery_audit',{'staff_id':managerStaffId,'action':'CONFIGURE','details_json':value,'created_at':now});
      });
    } catch (_) {
      if (newCredential) {
        try { await _credentials.delete(credentialId!); } catch (_) {}
      }
      rethrow;
    }
    final oldReference = previous['gmail_credential_id'] as String?;
    if (oldReference != null && oldReference != credentialId) {
      try { await _credentials.delete(oldReference); } catch (_) {}
    }
  }

  Future<void> forgetGmailPassword({required int managerStaffId}) async {
    await _manager(managerStaffId);
    final policy = await _settings();
    final reference = policy['gmail_credential_id'] as String?;
    if (reference != null) await _credentials.delete(reference);
    await database.insert('report_delivery_audit', {
      'staff_id':managerStaffId, 'action':'REMOVE_GMAIL_PASSWORD',
      'details_json':'{}', 'created_at':DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> _deliver(Map<String, dynamic> job) async {
    if (_transport != null) return _transport(job);
    final payload = Map<String, dynamic>.from(jsonDecode(job['payload_json'] as String) as Map);
    if (payload['email_provider'] != 'GMAIL') return sendToRelay(job);
    final policy = await _settings();
    final sender = payload['gmail_sender'] as String?;
    final reference = policy['gmail_credential_id'] as String?;
    if (sender == null || sender != policy['gmail_sender'] || reference == null) {
      throw const ReportDeliveryFailure('Gmail settings changed; check the sender before retrying.');
    }
    String? password;
    try { password = await _credentials.read(reference); }
    catch (_) { throw const ReportDeliveryFailure('Unable to unlock the saved Gmail app password on this device.'); }
    if (password == null) throw const ReportDeliveryFailure('Save the Gmail app password on this device before retrying.');
    return _gmail.send(job, sender: sender, password: password);
  }

  Future<List<Map<String,dynamic>>> history({required int managerStaffId}) async {
    await _manager(managerStaffId);
    return database.query('report_outbox',orderBy:'id DESC');
  }

  /// Idempotent recovery: close commits the settings snapshot before any disk I/O.
  Future<void> enqueueReadyReports() async {
    final runs = await database.query('report_runs',where:"status='READY'");
    for (final run in runs) {
      final snapshot = Map<String,dynamic>.from(jsonDecode(run['snapshot_json'] as String) as Map);
      final policy = snapshot['delivery'] as Map?;
      if (policy==null || policy['auto_send']!=true) continue;
      for (final target in policy['recipients'] as List) {
        final recipient = Map<String,dynamic>.from(target as Map);
        if (recipient['approved']!=true) continue;
        final key = sha256.convert(utf8.encode('${run['business_day_id']}:1:${recipient['channel']}:${recipient['address']}:1:AUTO')).toString();
        final payload = jsonEncode({'report_run_id':run['id'],'revision':1,'business_date':snapshot['business_date'],
          'snapshot_sha256':run['content_hash'],'channel':recipient['channel'],'recipient':recipient['address'],
          'consent':recipient['consent'],'subject':'Business Day ${snapshot['business_date']} — Z Report',
          'email_provider':policy['email_provider'] ?? 'RELAY', 'gmail_sender':policy['gmail_sender'],
          'artifacts':jsonDecode(run['artifacts_json'] as String)});
        await database.insert('report_outbox',{'business_day_id':run['business_day_id'],'channel':recipient['channel'],
          'recipient':recipient['address'],'payload_json':payload,'status':'PENDING','retry_count':0,
          'next_attempt_at':DateTime.now().toUtc().toIso8601String(),'created_at':DateTime.now().toUtc().toIso8601String(),
          'idempotency_key':key,'report_run_id':run['id'],'endpoint':policy['endpoint'],'max_attempts':policy['max_attempts']??8,
        },conflictAlgorithm:ConflictAlgorithm.ignore);
      }
    }
  }

  Future<void> retry({required int managerStaffId,required int jobId,required String reason}) async {
    await _manager(managerStaffId);
    if (reason.trim().isEmpty) throw ArgumentError('A reason is required to retry.');
    await database.transaction((txn) async {
      final jobs = await txn.query('report_outbox',where:'id=?',whereArgs:[jobId]);
      if (jobs.isEmpty || !['FAILED','AMBIGUOUS','PENDING'].contains(jobs.single['status'])) {
        throw StateError('Only pending, failed or ambiguous deliveries may be retried.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update('report_outbox',{'status':'PENDING','next_attempt_at':now,'error_message':null,'lease_until':null,
        'max_attempts':(jobs.single['retry_count'] as int)+8},where:'id=?',whereArgs:[jobId]);
      await txn.insert('report_delivery_audit',{'staff_id':managerStaffId,'action':'RETRY','details_json':jsonEncode({'job_id':jobId,'reason':reason.trim()}),'created_at':now});
    });
  }

  /// Runs on startup and once per minute while the desktop app is running.
  void start() {
    if (_timer!=null) return;
    unawaited(_tick());
    _timer = Timer.periodic(const Duration(minutes:1),(_)=>unawaited(_tick()));
  }
  void stop() { _timer?.cancel(); _timer=null; }
  Future<void> _tick() async {
    if (_running) return;
    _running=true;
    try {
      await ReportExportService(database:database).exportPending();
      await enqueueReadyReports();
      await processPending();
    } catch (_) {
      // Database/file outages retry on next tick; no credentials enter logs.
    } finally { _running=false; }
  }

  Future<void> processPending({DateTime? now}) async {
    final clock = (now??DateTime.now()).toUtc();
    final timestamp = clock.toIso8601String();
    // A crashed send may already have reached its provider; never blindly resend.
    await database.update('report_outbox',{'status':'AMBIGUOUS','error_message':'Worker stopped during delivery; review provider history before retry.'},
      where:"status='PROCESSING' AND (lease_until IS NULL OR lease_until<=?)",whereArgs:[timestamp]);
    for (var index=0;index<20;index++) {
      final job = await database.transaction<Map<String,dynamic>?>((txn) async {
        final jobs = await txn.query('report_outbox',where:"status='PENDING' AND next_attempt_at<=?",whereArgs:[timestamp],orderBy:'id',limit:1);
        if (jobs.isEmpty) return null;
        final row=jobs.single;
        await txn.update('report_outbox',{'status':'PROCESSING','retry_count':(row['retry_count'] as int)+1,
          'lease_until':clock.add(const Duration(minutes:2)).toIso8601String()},where:"id=? AND status='PENDING'",whereArgs:[row['id']]);
        return {...row,'retry_count':(row['retry_count'] as int)+1};
      });
      if (job==null) break;
      try {
        final policy=await _settings();
        final allowed=(policy['recipients'] as List? ?? []).any((r)=>r['approved']==true && r['channel']==job['channel'] && r['address']==job['recipient']);
        if (policy['auto_send']!=true || !allowed || policy['endpoint']!=job['endpoint']) {
          await database.update('report_outbox',{'status':'CANCELLED','error_message':'Delivery policy or recipient approval was revoked.','lease_until':null},where:'id=?',whereArgs:[job['id']]);
          continue;
        }
        if ((job['retry_count'] as int)>(job['max_attempts'] as int)) throw const ReportDeliveryFailure('Maximum delivery attempts reached.');
        final reference = await _deliver(job).timeout(const Duration(seconds:45));
        if (reference.trim().isEmpty) throw const ReportDeliveryFailure('No provider acceptance evidence; review before retry.',ambiguous:true);
        await database.update('report_outbox',{'status':'ACCEPTED','provider_reference':reference,'processed_at':timestamp,'error_message':null,'lease_until':null},where:'id=?',whereArgs:[job['id']]);
      } catch (error) {
        final failure = error is ReportDeliveryFailure ? error
          : error is SocketException ? const ReportDeliveryFailure('Connection unavailable; retry scheduled.',retryable:true)
          : error is TimeoutException ? const ReportDeliveryFailure('Delivery timed out; review provider history before retry.',ambiguous:true)
          : const ReportDeliveryFailure('Delivery failed; check the saved delivery settings.');
        final attempts=job['retry_count'] as int;
        final retryable=failure.retryable && attempts<(job['max_attempts'] as int);
        final delay = Duration(seconds:(60*(1<<attempts.clamp(0,10)))+(job['id'] as int)%31);
        await database.update('report_outbox',{'status':failure.ambiguous?'AMBIGUOUS':retryable?'PENDING':'FAILED',
          'error_message':failure.message,'next_attempt_at':clock.add(delay).toIso8601String(),'lease_until':null},where:'id=?',whereArgs:[job['id']]);
      }
    }
  }

  /// HTTPS relay must deduplicate Idempotency-Key and return explicit acceptance.
  /// Authentication remains outside SQLite; no master provider key is bundled.
  static Future<String> sendToRelay(Map<String,dynamic> job) async {
    final endpoint=Uri.tryParse(job['endpoint'] as String? ?? '');
    final token=Platform.environment['RESTAURANT_REPORT_RELAY_TOKEN'];
    if (endpoint==null || endpoint.scheme!='https' || endpoint.host.isEmpty || token==null || token.isEmpty) {
      throw const ReportDeliveryFailure('Configure HTTPS relay and RESTAURANT_REPORT_RELAY_TOKEN.');
    }
    final payload=Map<String,dynamic>.from(jsonDecode(job['payload_json'] as String) as Map);
    final attachments=<Map<String,dynamic>>[];
    for (final raw in payload['artifacts'] as List) {
      final artifact=Map<String,dynamic>.from(raw as Map);
      final bytes=await File(artifact['path'] as String).readAsBytes();
      if (sha256.convert(bytes).toString()!=artifact['sha256']) throw const ReportDeliveryFailure('Report attachment checksum mismatch.');
      attachments.add({'kind':artifact['kind'],'sha256':artifact['sha256'],'content_base64':base64Encode(bytes)});
    }
    payload.remove('artifacts');
    payload['attachments']=attachments;
    payload['idempotency_key']=job['idempotency_key'];
    final client=HttpClient()..connectionTimeout=const Duration(seconds:15);
    try {
      return await (() async {
      final request=await client.postUrl(endpoint);
      request.followRedirects=false;
      request.headers.contentType=ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader,'Bearer $token');
      request.headers.set('Idempotency-Key',job['idempotency_key'] as String);
      request.write(jsonEncode(payload));
      final response=await request.close();
      final body=await response.transform(utf8.decoder).join();
      if (response.statusCode==429 || response.statusCode>=500) {
        throw const ReportDeliveryFailure('Report relay unavailable; retry scheduled.',retryable:true);
      }
      if (response.statusCode<200 || response.statusCode>=300) {
        throw const ReportDeliveryFailure('Report relay rejected delivery; check approved sender and recipient configuration.');
      }
      Map<String,dynamic> result;
      try { result=jsonDecode(body) as Map<String,dynamic>; }
      catch (_) { throw const ReportDeliveryFailure('Relay acceptance response is invalid; review before retry.',ambiguous:true); }
      final reference=result['provider_reference'];
      if (result['accepted']!=true || reference is! String || reference.trim().isEmpty) {
        throw const ReportDeliveryFailure('Relay did not confirm provider acceptance; review before retry.',ambiguous:true);
      }
      return reference;
      })().timeout(const Duration(seconds:40));
    } finally { client.close(force:true); }
  }
}
