import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A local-only SMTP endpoint with a disposable self-signed certificate. It
/// never forwards messages and is not included in the application build.
class TlsSmtpFixture {
  TlsSmtpFixture._(this._server, this.rejectionCode) {
    _subscription = _server.listen(_accept, onError: (Object _) {
      // A disconnected TLS probe is not a completed SMTP session. Tests still
      // require authentication, received MIME, and the expected outbox state.
    });
  }

  final SecureServerSocket _server;
  final int? rejectionCode;
  late final StreamSubscription<SecureSocket> _subscription;
  final _clients = <SecureSocket>{};
  final received = Completer<String>();
  final authenticated = <String>[];
  int get port => _server.port;

  static Future<TlsSmtpFixture> start({int? rejectionCode}) async {
    final directory = Platform.environment['SMTP_FIXTURE_DIRECTORY']!;
    final security = SecurityContext()
      ..useCertificateChain('$directory/cert.pem')
      ..usePrivateKey('$directory/key.pem');
    return TlsSmtpFixture._(await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4, 0, security), rejectionCode);
  }

  void _accept(SecureSocket socket) {
    _clients.add(socket);
    // The mailer closes immediately after QUIT. A late fixture reply can fail
    // on the output sink even when the SMTP exchange completed successfully.
    unawaited(socket.done.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    var data = false;
    var authStep = 0;
    final lines = <String>[];
    socket.write('220 localhost synthetic SMTP\r\n');
    socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final command = line.toUpperCase();
      if (data) {
        if (line == '.') {
          data = false;
          if (!received.isCompleted) received.complete(lines.join('\r\n'));
          socket.write(rejectionCode == null ? '250 2.0.0 synthetic accepted\r\n'
              : '$rejectionCode synthetic explicit rejection\r\n');
        } else { lines.add(line.startsWith('..') ? line.substring(1) : line); }
      } else if (authStep != 0) {
        authenticated.add(utf8.decode(base64Decode(line)));
        if (authStep == 1) {
          authStep = 2;
          socket.write('334 UGFzc3dvcmQ6\r\n');
        } else { authStep = 0; socket.write('235 2.7.0 authenticated\r\n'); }
      } else if (command.startsWith('EHLO') || command.startsWith('HELO')) {
        socket.write('250-localhost\r\n250-AUTH LOGIN PLAIN\r\n250 SIZE 25000000\r\n');
      } else if (command.startsWith('AUTH PLAIN ')) {
        authenticated.addAll(utf8.decode(base64Decode(line.split(' ').last)).split('\u0000').where((part) => part.isNotEmpty));
        socket.write('235 2.7.0 authenticated\r\n');
      } else if (command.startsWith('AUTH LOGIN')) {
        authStep = 1;
        socket.write('334 VXNlcm5hbWU6\r\n');
      } else if (command == 'DATA') {
        data = true;
        socket.write('354 End with a dot\r\n');
      } else if (command == 'QUIT') {
        socket.write('221 closing\r\n');
      } else {
        socket.write('250 ok\r\n');
      }
    }, onError: (Object _) {}, onDone: () { _clients.remove(socket); socket.destroy(); });
  }

  Future<void> close() async {
    await _subscription.cancel();
    for (final socket in _clients.toList()) { socket.destroy(); }
    await _server.close();
  }
}
