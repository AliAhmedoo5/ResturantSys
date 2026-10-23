import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailer/mailer.dart' as mail;
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/report_credential_store.dart';
import 'package:resturant_sys/core/shifts/report_delivery_service.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _DeviceCredentials implements ReportCredentialStore {
  final values = <String, String>{};
  bool unavailable = false;
  @override
  Future<String?> read(String reference) async => values[reference];
  @override
  Future<void> write(String reference, String password) async {
    if (unavailable) throw StateError('Secure storage unavailable');
    values[reference] = password;
  }
  @override
  Future<void> delete(String reference) async { values.remove(reference); }
}

void main() {
  late Directory folder;
  late PosDatabase owner;
  late Database db;
  late _DeviceCredentials credentials;
  late int manager;
  late int cashier;
  const secret = 'abcdefghijklmnop';

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('synthetic_gmail_reports_');
    owner = PosDatabase(factory: databaseFactoryFfi, customPath: '${folder.path}/test.db');
    db = await owner.initialize();
    manager = (await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1)).single['id'] as int;
    cashier = (await db.query('staff', where: "role = 'CASHIER'", limit: 1)).single['id'] as int;
    credentials = _DeviceCredentials();
  });
  tearDown(() async { await owner.close(); await folder.delete(recursive: true); });

  Future<void> configure(ReportDeliveryService service, {String sender = 'synthetic.restaurant@gmail.com'}) =>
      service.configure(managerStaffId: manager, emailProvider: 'GMAIL', gmailSender: sender,
        gmailAppPassword: 'abcd efgh ijkl mnop', recipients: [
          const ReportRecipient(channel: 'EMAIL', address: 'owner@example.invalid', approved: true),
        ]);

  Future<void> closeDay() async {
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: manager);
    await shifts.openShift(staffId: cashier, openingFloat: 0);
    await shifts.finalizeBusinessDayWithZReport(closedByStaffId: manager);
  }

  test('Gmail submits real report attachments over TLS without persisting the password in SQLite', () async {
    var submissions = 0;
    final service = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (message, server) async {
        submissions++;
        expect(server.host, 'smtp.gmail.com');
        expect(server.port, 465);
        expect(server.ssl, isTrue);
        expect(server.username, 'synthetic.restaurant@gmail.com');
        expect(server.password, secret);
        expect(message.recipients, ['owner@example.invalid']);
        expect(message.attachments.length, 2);
        final pdf = await message.attachments.first.asStream().expand((bytes) => bytes).toList();
        expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
        final xlsx = await message.attachments.last.asStream().expand((bytes) => bytes).toList();
        expect(xlsx.take(2), [80, 75]);
      });
    await configure(service);
    expect(credentials.values.values.single, secret);
    expect((await service.settings(managerStaffId: manager))['gmail_password_saved'], isTrue);
    await closeDay();
    expect((await service.history(managerStaffId: manager)).single['status'], 'PENDING');
    await service.processPending(now: DateTime.now().add(const Duration(minutes: 1)));
    expect(submissions, 1);
    expect((await service.history(managerStaffId: manager)).single['status'], 'ACCEPTED');
    for (final table in ['system_settings', 'report_delivery_audit', 'report_runs', 'report_outbox']) {
      expect(jsonEncode(await db.query(table)), isNot(contains(secret)), reason: table);
    }
    await service.configure(managerStaffId: manager, emailProvider: 'GMAIL',
      gmailSender: 'synthetic.restaurant@gmail.com', recipients: [
        const ReportRecipient(channel: 'EMAIL', address: 'owner@example.invalid', approved: true),
      ]);
    expect(credentials.values.values.single, secret, reason: 'A blank field keeps the saved credential');
  });

  test('Gmail connection failure retries after reopening SQLite without reversing day closure', () async {
    final service = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (_, __) async => throw const SocketException('Failed host lookup'));
    await configure(service);
    await closeDay();
    await service.processPending(now: DateTime.now().add(const Duration(minutes: 1)));
    final job = (await service.history(managerStaffId: manager)).single;
    expect(job['status'], 'PENDING');
    expect(job['retry_count'], 1);
    expect(await ShiftAndCashController(database: db).getActiveBusinessDay(), isNull);
    await owner.close();
    db = await owner.initialize();
    final restarted = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (_, __) async {});
    await restarted.processPending(now: DateTime.parse(job['next_attempt_at'] as String).add(const Duration(seconds: 1)));
    expect((await restarted.history(managerStaffId: manager)).single['status'], 'ACCEPTED');
  });

  test('Gmail authentication rejection is sanitized and requires correcting credentials', () async {
    var reject = true;
    final service = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (_, __) async {
        if (reject) throw mail.SmtpClientAuthenticationException(secret);
      });
    await configure(service);
    await closeDay();
    await service.processPending(now: DateTime.now().add(const Duration(minutes: 1)));
    final job = (await service.history(managerStaffId: manager)).single;
    expect(job['status'], 'FAILED');
    expect(job['error_message'], contains('app password'));
    expect(jsonEncode(job), isNot(contains(secret)));
    reject = false;
    await configure(service);
    await service.retry(managerStaffId: manager, jobId: job['id'] as int, reason: 'Replaced revoked Google app password');
    await service.processPending(now: DateTime.now().add(const Duration(minutes: 1)));
    expect((await service.history(managerStaffId: manager)).single['status'], 'ACCEPTED');
  });

  test('An uncertain Gmail send is never automatically resubmitted', () async {
    var attempts = 0;
    final service = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (_, __) async { attempts++; throw TimeoutException(secret); });
    await configure(service);
    await closeDay();
    await service.processPending(now: DateTime.now().add(const Duration(minutes: 1)));
    await service.processPending(now: DateTime.now().add(const Duration(days: 1)));
    expect(attempts, 1);
    final job = (await service.history(managerStaffId: manager)).single;
    expect(job['status'], 'AMBIGUOUS');
    expect(job['error_message'], contains('Sent mail'));
    expect(jsonEncode(job), isNot(contains(secret)));
  });

  test('Changing Gmail sender cancels old queued jobs instead of silently redirecting them', () async {
    var attempts = 0;
    final service = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (_, __) async { attempts++; });
    await configure(service);
    await closeDay();
    await configure(service, sender: 'different.restaurant@gmail.com');
    await service.processPending(now: DateTime.now().add(const Duration(minutes: 1)));
    expect(attempts, 0);
    expect((await service.history(managerStaffId: manager)).single['status'], 'CANCELLED');
    expect(credentials.values.length, 1);
  });

  test('Only Manager can configure or remove Gmail credentials; storage failure leaves settings unchanged', () async {
    final service = ReportDeliveryService(database: db, credentialStore: credentials);
    await expectLater(service.configure(managerStaffId: cashier, emailProvider: 'GMAIL',
      gmailSender: 'synthetic.restaurant@gmail.com', gmailAppPassword: secret, recipients: []), throwsStateError);
    expect(credentials.values, isEmpty);
    credentials.unavailable = true;
    await expectLater(configure(service), throwsStateError);
    expect(await db.query('system_settings', where: "key='report_delivery_settings'"), isEmpty);
    credentials.unavailable = false;
    await configure(service);
    await expectLater(service.forgetGmailPassword(managerStaffId: cashier), throwsStateError);
    expect(credentials.values, isNotEmpty);
    await service.forgetGmailPassword(managerStaffId: manager);
    expect(credentials.values, isEmpty);
    expect((await service.settings(managerStaffId: manager))['gmail_password_saved'], isFalse);
    await service.configure(managerStaffId: manager, emailProvider: 'GMAIL',
      gmailSender: 'synthetic.restaurant@gmail.com', autoSend: false, recipients: []);
    expect((await service.settings(managerStaffId: manager))['auto_send'], isFalse,
      reason: 'A restored installation can disable sending without the old app password');
  });

  test('Manager can check saved Gmail sign-in without sending email or closing a day', () async {
    var verifications = 0;
    final service = ReportDeliveryService(database: db, credentialStore: credentials,
      gmailSubmission: (_, __) async => fail('Sign-in check must not send an email'),
      gmailVerification: (server) async {
        expect(server.username, 'synthetic.restaurant@gmail.com');
        expect(server.password, secret);
        verifications++;
      });
    await configure(service);
    await expectLater(service.verifyGmailSignIn(managerStaffId: cashier), throwsStateError);
    await service.verifyGmailSignIn(managerStaffId: manager);
    expect(verifications, 1);
    expect(await service.history(managerStaffId: manager), isEmpty);
    expect(await db.query('business_days'), isEmpty);
  });
}
