import 'dart:convert';

import 'face_service.dart';
import 'kby_face_service.dart';

/// Result of extracting face biometrics from a photo.
class FaceCaptureOutcome {
  const FaceCaptureOutcome({
    required this.storageJson,
    required this.usedKbySdk,
  });

  final String storageJson;
  final bool usedKbySdk;
}

/// KBY when licensed; otherwise MobileFaceNet + ML Kit (no vendor key required).
class FaceEngineFacade {
  FaceEngineFacade._();

  static Future<void> prime() async {
    await FaceService().init();
    await KbyFaceService().init();
  }

  static bool get isKbyActive => KbyFaceService().isInitialized;

  static Future<FaceCaptureOutcome?> extractFromPhoto(String imagePath) async {
    await prime();

    if (isKbyActive) {
      final face = await KbyFaceService().extractFace(imagePath);
      if (face != null && face.passesSdkLiveness) {
        return FaceCaptureOutcome(
          storageJson: KbyFaceService.templatesToJson(face.templates),
          usedKbySdk: true,
        );
      }
    }

    final embedding = await FaceService().extractEmbeddingFromFile(imagePath);
    if (embedding == null) return null;

    return FaceCaptureOutcome(
      storageJson: jsonEncode({'method': 'ml', 'embedding': embedding}),
      usedKbySdk: false,
    );
  }

  static Future<bool> verifyPhotoAgainstStored(
    String storedJson,
    String imagePath,
  ) async {
    final live = await extractFromPhoto(imagePath);
    if (live == null) return false;
    return verifyStoredAgainstCapture(storedJson, live);
  }

  static Future<bool> verifyStoredAgainstCapture(
    String storedJson,
    FaceCaptureOutcome live,
  ) async {
    await prime();

    final kbyStored = KbyFaceService.templatesFromJson(storedJson);
    if (kbyStored != null && live.usedKbySdk && isKbyActive) {
      final liveTemplates = KbyFaceService.templatesFromJson(live.storageJson);
      if (liveTemplates == null) return false;
      final similarity = await KbyFaceService().compareFaces(
        kbyStored,
        liveTemplates,
      );
      return similarity >= KbyFaceService.matchThreshold;
    }

    final storedEmbedding = _embeddingFromStorage(storedJson);
    final liveEmbedding = _embeddingFromStorage(live.storageJson);
    if (storedEmbedding == null || liveEmbedding == null) return false;

    return FaceService().isMatch(storedEmbedding, liveEmbedding);
  }

  static List<double>? _embeddingFromStorage(String storedJson) {
    try {
      final decoded = jsonDecode(storedJson);
      if (decoded is Map<String, dynamic>) {
        if (decoded['method'] == 'ml' && decoded['embedding'] is List) {
          return (decoded['embedding'] as List)
              .map((e) => (e as num).toDouble())
              .toList();
        }
      }
      if (decoded is List) {
        return decoded.map((e) => (e as num).toDouble()).toList();
      }
    } catch (_) {}
    return FaceService().jsonToEmbedding(storedJson);
  }
}
