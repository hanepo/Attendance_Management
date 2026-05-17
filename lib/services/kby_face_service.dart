import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:facesdk_plugin/facesdk_plugin.dart';
import 'package:image/image.dart' as img;

/// One detected face from the KBY SDK, including passive liveness score.
class KbyFaceExtraction {
  KbyFaceExtraction({
    required this.templates,
    required this.liveness,
  });

  final Uint8List templates;

  /// Vendor-reported score; higher typically means more likely a live face.
  final double liveness;

  bool get passesSdkLiveness =>
      liveness >= KbyFaceService.minSdkLivenessScore;
}

class KbyFaceService {
  static final KbyFaceService _instance = KbyFaceService._internal();
  factory KbyFaceService() => _instance;
  KbyFaceService._internal();

  final _plugin = FacesdkPlugin();
  bool _initialized = false;

  /// Tune with real devices; vendor scores are usually in \[0, 1\].
  static const double minSdkLivenessScore = 0.58;

  static const double matchThreshold = 0.8;
  static const double multiMatchMargin = 0.06;

  static const String _embeddedAndroidLicense =
      "PjnUMBHfBhtT/oa8ySF6mwinqAj2oBls4vSsDmsdrpL/xHwPLtq9Dll/4IIe2KIkXQEh81/21yQhK"
      "AUQOmCvuuNcaZX+DS/EBhinprH+Y+XBzdGz2KWKEZjeDnhoSo8ql1CDDmMiCdRleZ7PbcPv10/dkdI"
      "mwGLFerErQxL/qKIz+8CQqOryw/7RjpNgkbpufY+Nd635HN3dbG4Z+AKdpsl2hB+hl/16O1IhQiGia"
      "4V2+1q9PsFfj6HFST+CQD17kXfsXkoQzMsFwQn4BSuyiiPUdHfJ+EFYMoeF96Jhqfe1CH3af41l0wK"
      "LNqXthBE24m96v06lDFPXkxDOCZCzug==";

  static const String _embeddedIosLicense =
      "LvqLS/kUqek3yNzQYaskd7H2oQZeZ/9msTJ16au/DAz0ZcDtnJUqlY6Du5YffkGKZ2oWlCrE8JBJfb"
      "rVcPvchPnZv6ZDOSZ9R1JCg+KlmyCQ2s6Xre6nhcjoAjvKbVhY3wFpwWOeKuvsCzv6hmKf5YBUMa6I"
      "yTwcqsoCKbcVq5mJDWbWpQXwKOiFXwhmyXHBruWzI1Jd6i6cNzYRixgqLWi1sS3Kak5EiHhc91TKPd"
      "LmZkLQQwWxr2OFSS8s3MRhrooAxxRU7XVglU+cg7tpqjvMcUSfbcLE8OYCV8DDIZfbBpEp5y1YN/gg"
      "OpX04tojhkSIhX9l5MRTiZfMdovaZg==";

  static String _licenseAndroid() {
    const fromEnv = String.fromEnvironment(
      'KBY_LICENSE_ANDROID',
      defaultValue: '',
    );
    if (fromEnv.isNotEmpty) return fromEnv;
    return _embeddedAndroidLicense;
  }

  static String _licenseIos() {
    const fromEnv = String.fromEnvironment(
      'KBY_LICENSE_IOS',
      defaultValue: '',
    );
    if (fromEnv.isNotEmpty) return fromEnv;
    return _embeddedIosLicense;
  }

  bool get isInitialized => _initialized;

  /// Last native return codes (for diagnostics when [isInitialized] is false).
  int? lastActivationReturn;
  int? lastInitReturn;
  String? lastInitException;

  /// Call before [init] to retry after a failure (e.g. engine not attached yet).
  void resetSdkState() {
    _initialized = false;
    lastActivationReturn = null;
    lastInitReturn = null;
    lastInitException = null;
  }

  /// Maps [FacesdkPlugin.setActivation] return codes (see vendor `SDK_ERROR`).
  static const Map<int, String> activationErrorDescriptions = {
    -1: 'Invalid or corrupt license key.',
    -2:
        'SDK_LICENSE_APPID_ERROR: the bundled license is not registered for '
        'package com.attendance.attendance_app (signing cert may already be correct).',
    -3: 'License has expired.',
    -4: 'SDK not activated.',
    -5: 'SDK initialization error.',
    -100:
        'Native face library could not load on this device.',
    -101:
        'This is an Android emulator (x86). Face recognition cannot run here. '
        'On Windows: build with your PC, but run on a real phone via USB.',
  };

  /// True when running on an Android emulator (face SDK will not work).
  static Future<bool> isAndroidEmulator() async {
    if (!Platform.isAndroid) return false;
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      return !android.isPhysicalDevice;
    } catch (_) {
      return false;
    }
  }

  /// Human-readable reason the SDK did not start (release signing / license, etc.).
  String describeInitFailure() {
    if (_initialized) return '';
    final a = lastActivationReturn;
    final i = lastInitReturn;
    final buf = StringBuffer()
      ..writeln('The face engine did not start on this install.');
    if (a != null && a != 0) {
      buf.writeln('Activation step returned code: $a');
      final detail = activationErrorDescriptions[a];
      if (detail != null) {
        buf.writeln(detail);
      }
    }
    if (i != null && i != 0) {
      buf.writeln('Init step returned code: $i');
    }
    if (lastInitException != null && lastInitException!.isNotEmpty) {
      buf.writeln('Error: $lastInitException');
    }
    buf.writeln();
    if (a == -101) {
      buf.writeln(
        'You are on an Android **emulator**. The KBY Face SDK has no x86 libraries.\n\n'
        'On a Windows PC you **can** use Flutter, but the app must run on:\n'
        '• A **physical Android phone** (USB cable + USB debugging), OR\n'
        '• An ARM64 emulator image only (slow; phone is easier).\n\n'
        'Steps:\n'
        '1. Close the emulator in Android Studio\n'
        '2. Plug in your phone, allow USB debugging\n'
        '3. In PowerShell: flutter devices  (must show your phone, not emulator)\n'
        '4. flutter run -d <your-phone-id>',
      );
    } else if (a == -100) {
      buf.writeln(
        'Native library failed on this device. Try:\n'
        '• flutter clean && flutter pub get && flutter run\n'
        '• Use a physical phone (not emulator)\n'
        '• Reinstall the app',
      );
    } else if (a == -2) {
      buf.writeln(
        'Your signing certificate is OK if SHA-1 is\n'
        '0E:9D:41:77:0C:34:3D:6C:E0:E7:D8:1B:43:81:08:77:8E:F7:3C:3F\n'
        '(team-debug.keystore). This error means the KBY license string in the '
        'app was issued for a different package name, not '
        'com.attendance.attendance_app.\n\n'
        'Fix: request a new license from KBY (contact@kby-ai.com). See '
        'KBY_LICENSE_REQUEST.txt in the project.\n\n'
        'After you receive the key, rebuild:\n'
        'flutter run --dart-define=KBY_LICENSE_ANDROID=YOUR_NEW_KEY',
      );
    } else {
      buf.writeln(
        'If activation failed: many trial licenses only allow one signature. '
        'You may need a release license from the vendor, or pass '
        'KBY_LICENSE_ANDROID when building.',
      );
    }
    return buf.toString().trim();
  }

  Future<void> init() async {
    if (_initialized) return;
    lastInitException = null;
    lastActivationReturn = null;
    lastInitReturn = null;
    try {
      if (Platform.isAndroid && await isAndroidEmulator()) {
        lastActivationReturn = -101;
        return;
      }
      final license = Platform.isAndroid ? _licenseAndroid() : _licenseIos();
      final activated = await _plugin.setActivation(license) ?? -1;
      lastActivationReturn = activated;
      if (activated == 0) {
        final initResult = await _plugin.init() ?? -1;
        lastInitReturn = initResult;
        _initialized = initResult == 0;
        if (_initialized && Platform.isAndroid) {
          try {
            await _plugin.setParam({'check_liveness_level': 2});
          } catch (e) {
            lastInitException = e.toString();
          }
        }
      }
    } catch (e) {
      lastInitException = e.toString();
    }
  }

  Future<void> _bakeOrientation(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return;
      final oriented = img.bakeOrientation(image);
      await file.writeAsBytes(img.encodeJpg(oriented, quality: 90));
    } catch (_) {}
  }

  Uint8List? _parseTemplates(Object? raw) {
    if (raw is Uint8List) return raw;
    if (raw is List) {
      try {
        return Uint8List.fromList(raw.cast<int>());
      } catch (_) {}
    }
    return null;
  }

  /// Extracts templates and liveness from an image file path.
  Future<KbyFaceExtraction?> extractFace(String imagePath) async {
    if (!_initialized) await init();
    if (!_initialized) return null;
    try {
      await _bakeOrientation(imagePath);
      final faces = await _plugin.extractFaces(imagePath);
      if (faces == null || (faces as List).isEmpty) return null;
      final map = Map<String, dynamic>.from(faces[0] as Map);
      final templates = _parseTemplates(map['templates']);
      if (templates == null) return null;
      final live = (map['liveness'] as num?)?.toDouble() ?? 0.0;
      return KbyFaceExtraction(templates: templates, liveness: live);
    } catch (_) {
      return null;
    }
  }

  /// Backwards-compatible helper (no liveness check).
  Future<Uint8List?> extractTemplates(String imagePath) async {
    final r = await extractFace(imagePath);
    return r?.templates;
  }

  Future<double> compareFaces(Uint8List t1, Uint8List t2) async {
    try {
      return await _plugin.similarityCalculation(t1, t2) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  static String templatesToJson(Uint8List templates) {
    return jsonEncode({
      'method': 'kby',
      'templates': base64Encode(templates),
    });
  }

  static Uint8List? templatesFromJson(String faceJson) {
    try {
      final data = jsonDecode(faceJson) as Map<String, dynamic>;
      if (data['method'] != 'kby') return null;
      return base64Decode(data['templates'] as String);
    } catch (_) {
      return null;
    }
  }
}
