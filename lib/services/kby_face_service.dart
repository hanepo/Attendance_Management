import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:facesdk_plugin/facesdk_plugin.dart';
import 'package:image/image.dart' as img;

class KbyFaceService {
  static final KbyFaceService _instance = KbyFaceService._internal();
  factory KbyFaceService() => _instance;
  KbyFaceService._internal();

  final _plugin = FacesdkPlugin();
  bool _initialized = false;

  static const _androidLicense =
      "PjnUMBHfBhtT/oa8ySF6mwinqAj2oBls4vSsDmsdrpL/xHwPLtq9Dll/4IIe2KIkXQEh81/21yQhK"
      "AUQOmCvuuNcaZX+DS/EBhinprH+Y+XBzdGz2KWKEZjeDnhoSo8ql1CDDmMiCdRleZ7PbcPv10/dkdI"
      "mwGLFerErQxL/qKIz+8CQqOryw/7RjpNgkbpufY+Nd635HN3dbG4Z+AKdpsl2hB+hl/16O1IhQiGia"
      "4V2+1q9PsFfj6HFST+CQD17kXfsXkoQzMsFwQn4BSuyiiPUdHfJ+EFYMoeF96Jhqfe1CH3af41l0wK"
      "LNqXthBE24m96v06lDFPXkxDOCZCzug==";

  static const _iosLicense =
      "LvqLS/kUqek3yNzQYaskd7H2oQZeZ/9msTJ16au/DAz0ZcDtnJUqlY6Du5YffkGKZ2oWlCrE8JBJfb"
      "rVcPvchPnZv6ZDOSZ9R1JCg+KlmyCQ2s6Xre6nhcjoAjvKbVhY3wFpwWOeKuvsCzv6hmKf5YBUMa6I"
      "yTwcqsoCKbcVq5mJDWbWpQXwKOiFXwhmyXHBruWzI1Jd6i6cNzYRixgqLWi1sS3Kak5EiHhc91TKPd"
      "LmZkLQQwWxr2OFSS8s3MRhrooAxxRU7XVglU+cg7tpqjvMcUSfbcLE8OYCV8DDIZfbBpEp5y1YN/gg"
      "OpX04tojhkSIhX9l5MRTiZfMdovaZg==";

  static const double matchThreshold = 0.8;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final license = Platform.isAndroid ? _androidLicense : _iosLicense;
      final activated = await _plugin.setActivation(license) ?? -1;
      if (activated == 0) {
        final initResult = await _plugin.init() ?? -1;
        _initialized = initResult == 0;
      }
    } catch (_) {}
  }

  /// Bakes EXIF orientation into the image file so the SDK sees an upright face.
  /// Front cameras store raw sensor data (landscape) with an EXIF tag — the SDK
  /// ignores that tag and sees a rotated image, causing detection to fail.
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

  /// Extracts face templates from an image file path.
  /// Returns null if no face detected or SDK not initialised.
  Future<Uint8List?> extractTemplates(String imagePath) async {
    if (!_initialized) await init();
    if (!_initialized) return null;
    try {
      await _bakeOrientation(imagePath);
      final faces = await _plugin.extractFaces(imagePath);
      if (faces == null || (faces as List).isEmpty) return null;
      return faces[0]['templates'] as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  /// Compares two face template byte arrays and returns a similarity score (0–1).
  Future<double> compareFaces(Uint8List t1, Uint8List t2) async {
    try {
      return await _plugin.similarityCalculation(t1, t2) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Encodes templates to a JSON string suitable for storage via AuthService.updateFaceData().
  static String templatesToJson(Uint8List templates) {
    return jsonEncode({
      'method': 'kby',
      'templates': base64Encode(templates),
    });
  }

  /// Decodes templates from a JSON string returned by AuthService / decryptFaceData().
  /// Returns null if the data is not KBY format.
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
