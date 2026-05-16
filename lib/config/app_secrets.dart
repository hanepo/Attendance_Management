import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Resolves AES material from optional `--dart-define` values.
///
/// If you do **not** pass keys at build time, **demo keys** are used (same as
/// early project defaults) so `flutter build apk --release` works out of the
/// box for client demos. For stronger secrecy, pass `ATTENDANCE_AES_KEY` and
/// `ATTENDANCE_AES_IV` (or use `dart_define.client.json` / your own JSON file).
class AppSecrets {
  AppSecrets._();

  static const String _fallbackAesKey = 'AttendanceSecure2024KeyAES256!!!';
  static const String _fallbackAesIv = 'AttendIV2024!!!!';

  static late final String aesKey;
  static late final String aesIv;

  /// Call once at startup before [EncryptionService.init].
  static void initSync() {
    const keyEnv = String.fromEnvironment(
      'ATTENDANCE_AES_KEY',
      defaultValue: '',
    );
    const ivEnv = String.fromEnvironment(
      'ATTENDANCE_AES_IV',
      defaultValue: '',
    );

    if (keyEnv.isNotEmpty && ivEnv.isNotEmpty) {
      aesKey = keyEnv;
      aesIv = ivEnv;
    } else {
      aesKey = _fallbackAesKey;
      aesIv = _fallbackAesIv;
      if (kReleaseMode) {
        debugPrint(
          'AES: using bundled demo key/IV (no --dart-define). OK for client '
          'demos; for production pass ATTENDANCE_AES_KEY and ATTENDANCE_AES_IV.',
        );
      }
    }

    _validateDimensions();
  }

  static void _validateDimensions() {
    final keyLen = utf8.encode(aesKey).length;
    if (keyLen != 32) {
      throw FlutterError(
        'ATTENDANCE_AES_KEY must be exactly 32 bytes when UTF-8 encoded '
        '(got $keyLen).',
      );
    }
    final ivLen = utf8.encode(aesIv).length;
    if (ivLen != 16) {
      throw FlutterError(
        'ATTENDANCE_AES_IV must be exactly 16 bytes when UTF-8 encoded '
        '(got $ivLen).',
      );
    }
  }
}
