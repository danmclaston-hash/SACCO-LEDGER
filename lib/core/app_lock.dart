import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// App lock PIN. Kept only on this device, never sent anywhere.
/// Stored as a slow salted hash, so reading the phone's storage does not reveal the PIN.
class PinLock {
  static const iterations = 20000;

  static bool validPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  static String newSalt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < iterations; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Url.encode(bytes);
  }

  static bool check(String pin, String salt, String expected) {
    final got = hash(pin, salt);
    if (got.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < got.length; i++) {
      diff |= got.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// How long the app may sit in the background before it asks for the PIN again.
const lockAfter = Duration(seconds: 60);
const maxPinTries = 5;
