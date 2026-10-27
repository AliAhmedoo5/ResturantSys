import '../../lib/core/auth/pin_hasher.dart';

void main() {
  final creation = Stopwatch()..start();
  final verifier = PinHasher.hashPin('7391');
  creation.stop();
  final verification = Stopwatch()..start();
  final valid = PinHasher.verifyPin('7391', verifier);
  verification.stop();
  print('Release PIN derivation: ${creation.elapsedMilliseconds} ms');
  print('Release PIN verification: ${verification.elapsedMilliseconds} ms');
  if (!valid) throw StateError('Release PIN verification failed.');
  if (verification.elapsedMilliseconds >= 2000) {
    throw StateError('Release PIN verification exceeded two seconds.');
  }
}
