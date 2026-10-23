import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;
import 'report_delivery_failure.dart';

typedef GmailSubmission = Future<void> Function(mail.Message message, SmtpServer server);

/// Submits immutable report bytes to Gmail over TLS. Successful SMTP submission
/// is acceptance, not evidence that the recipient received the message.
class GmailReportSender {
  GmailReportSender({GmailSubmission? submit}) : _submit = submit ?? _submitToGmail;

  final GmailSubmission _submit;

  static Future<void> _submitToGmail(mail.Message message, SmtpServer server) async {
    await mail.send(message, server, timeout: const Duration(seconds: 20));
  }

  Future<String> send(Map<String, dynamic> job, {
    required String sender,
    required String password,
  }) async {
    final payload = Map<String, dynamic>.from(jsonDecode(job['payload_json'] as String) as Map);
    if (job['channel'] != 'EMAIL' || payload['gmail_sender'] != sender) {
      throw const ReportDeliveryFailure('Gmail sender or report channel no longer matches.');
    }
    final message = mail.Message()
      ..from = mail.Address(sender, 'Restaurant Reports')
      ..recipients.add(job['recipient'] as String)
      ..subject = payload['subject'] as String
      ..text = 'Business Day ${payload['business_date']} reports are attached as PDF and Excel.';
    final messageId = '<${job['idempotency_key']}@gmail.com>';
    message.headers['Message-ID'] = messageId;
    var totalBytes = 0;
    try {
      for (final raw in payload['artifacts'] as List) {
        final artifact = Map<String, dynamic>.from(raw as Map);
        final file = File(artifact['path'] as String);
        // Allow room for MIME/base64 expansion within Gmail's message limit.
        totalBytes += await file.length();
        if (totalBytes > 18 * 1024 * 1024) {
          throw const ReportDeliveryFailure('Report attachments exceed the Gmail sending size limit.');
        }
        final bytes = await file.readAsBytes();
        if (sha256.convert(bytes).toString() != artifact['sha256']) {
          throw const ReportDeliveryFailure('Report attachment checksum mismatch.');
        }
        if (!['pdf', 'xlsx'].contains(artifact['kind'])) {
          throw const ReportDeliveryFailure('Unsupported report attachment.');
        }
        message.attachments.add(mail.StreamAttachment(
          Stream<List<int>>.value(bytes),
          artifact['kind'] == 'pdf' ? 'application/pdf'
              : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          fileName: p.basename(file.path),
        ));
      }
    } on FileSystemException {
      throw const ReportDeliveryFailure('Saved report file is unavailable; restore it before retrying.');
    }
    final server = SmtpServer('smtp.gmail.com', port: 465, ssl: true,
      username: sender, password: password);
    try {
      await _submit(message, server).timeout(const Duration(seconds: 40));
      return messageId;
    } on mail.SmtpClientAuthenticationException {
      throw const ReportDeliveryFailure('Gmail sign-in failed. Check the saved address and Google app password.');
    } on SocketException catch (error) {
      // Only known connection failures are safe to resend automatically. A
      // dropped connection after DATA may already have delivered the email.
      final failedToConnect = error.message.toLowerCase().contains('failed host lookup') ||
          [101, 111, 10051, 10061, 11001].contains(error.osError?.errorCode);
      throw ReportDeliveryFailure(
        failedToConnect ? 'Connection unavailable; retry scheduled.'
            : 'Gmail connection interrupted; check Sent mail before retrying.',
        retryable: failedToConnect, ambiguous: !failedToConnect,
      );
    } on TimeoutException {
      throw const ReportDeliveryFailure('Gmail submission timed out; check Sent mail before retrying.', ambiguous: true);
    } on mail.MailerException {
      // SMTP errors can contain addresses, server diagnostics or auth details.
      // Preserve no raw exception text in the outbox or UI.
      throw const ReportDeliveryFailure('Gmail did not confirm submission; check Sent mail before retrying.', ambiguous: true);
    }
  }
}
