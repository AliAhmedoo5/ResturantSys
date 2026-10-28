import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _OpenNative = Int32 Function(
    Pointer<Pointer<Void>>, Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _OpenDart = int Function(
    Pointer<Pointer<Void>>, Pointer<Utf16>, Pointer<Utf16>, int);
typedef _DeriveNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32,
    Pointer<Uint8>, Uint32, Uint64, Pointer<Uint8>, Uint32, Uint32);
typedef _DeriveDart = int Function(Pointer<Void>, Pointer<Uint8>, int,
    Pointer<Uint8>, int, int, Pointer<Uint8>, int, int);
typedef _CloseNative = Int32 Function(Pointer<Void>, Uint32);
typedef _CloseDart = int Function(Pointer<Void>, int);

/// Uses Windows CNG for the same PBKDF2-HMAC-SHA256 verifier stored by the POS.
/// Must be called from an authentication isolate, as derivation is synchronous.
abstract final class WindowsPbkdf2 {
  static final _library = DynamicLibrary.open('bcrypt.dll');
  static final _open =
      _library.lookupFunction<_OpenNative, _OpenDart>('BCryptOpenAlgorithmProvider');
  static final _derive =
      _library.lookupFunction<_DeriveNative, _DeriveDart>('BCryptDeriveKeyPBKDF2');
  static final _close =
      _library.lookupFunction<_CloseNative, _CloseDart>('BCryptCloseAlgorithmProvider');

  static Uint8List derive(String pin, Uint8List salt, int rounds) {
    return using((arena) {
      final handle = arena<Pointer<Void>>();
      final algorithm = 'SHA256'.toNativeUtf16(allocator: arena);
      final encoded = utf8.encode(pin);
      final password = arena<Uint8>(encoded.isEmpty ? 1 : encoded.length);
      final nonce = arena<Uint8>(salt.isEmpty ? 1 : salt.length);
      final output = arena<Uint8>(32);
      password.asTypedList(encoded.length).setAll(0, encoded);
      nonce.asTypedList(salt.length).setAll(0, salt);
      try {
        // BCRYPT_ALG_HANDLE_HMAC_FLAG is required for PBKDF2's SHA256 PRF.
        _check(_open(handle, algorithm, nullptr, 0x00000008));
        _check(_derive(handle.value, password, encoded.length, nonce,
            salt.length, rounds, output, 32, 0));
        // Copy before the arena releases its native allocations.
        return Uint8List.fromList(output.asTypedList(32));
      } finally {
        password.asTypedList(encoded.length).fillRange(0, encoded.length, 0);
        encoded.fillRange(0, encoded.length, 0);
        nonce.asTypedList(salt.length).fillRange(0, salt.length, 0);
        output.asTypedList(32).fillRange(0, 32, 0);
        if (handle.value != nullptr) _close(handle.value, 0);
      }
    });
  }

  static void _check(int status) {
    if (status < 0) {
      throw StateError('Windows PIN derivation failed (NTSTATUS $status).');
    }
  }
}
