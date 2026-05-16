import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_service.dart';

/// Lightweight challenge: eyes open → closed → open (blink) using ML Kit.
class BlinkLivenessService {
  BlinkLivenessService._();
  static final BlinkLivenessService _instance = BlinkLivenessService._();
  factory BlinkLivenessService() => _instance;

  /// Stops any active image stream before returning so [takePicture] is safe.
  Future<bool> runBlinkChallenge({
    required CameraController camera,
    required ValueChanged<String> onStatus,
    Duration timeout = const Duration(seconds: 22),
  }) async {
    await FaceService().init();

    if (camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {}
    }

    final result = Completer<bool>();
    var settled = false;

    Future<void> stopStream() async {
      try {
        await camera.stopImageStream();
      } catch (_) {}
    }

    void settle(bool ok) {
      if (settled) return;
      settled = true;
      stopStream().whenComplete(() {
        if (!result.isCompleted) result.complete(ok);
      });
    }

    final timer = Timer(timeout, () {
      onStatus('Timed out. Face the camera and try a clear blink.');
      settle(false);
    });

    var busy = false;
    var frame = 0;
    var phase = _BlinkPhase.needFaceAndOpenEyes;
    var closedStreak = 0;
    var openAfterBlinkStreak = 0;
    final rotation = _rotationFor(camera.description);

    try {
      onStatus('Look at the camera with eyes open');
      await camera.startImageStream((CameraImage image) {
        if (settled || result.isCompleted || busy) return;
        frame++;
        if (frame % 2 != 0) return;
        busy = true;
        FaceService()
            .detectFromCameraImage(image, rotation)
            .then((faces) {
              busy = false;
              if (settled || result.isCompleted) return;

              if (faces.isEmpty) {
                onStatus('Position your face in the frame');
                return;
              }

              final f = faces.first;
              final open = _eyesOpen(f);
              final closed = _eyesClosed(f);

              switch (phase) {
                case _BlinkPhase.needFaceAndOpenEyes:
                  if (open == true) {
                    phase = _BlinkPhase.needBlink;
                    onStatus('Great. Now blink once (close both eyes briefly).');
                  } else if (open == null) {
                    onStatus('Hold still — eyes visible, good lighting.');
                  } else {
                    onStatus('Open your eyes normally');
                  }
                  break;
                case _BlinkPhase.needBlink:
                  if (closed == true) {
                    closedStreak++;
                    if (closedStreak >= 2) {
                      phase = _BlinkPhase.needOpenAgain;
                      onStatus('Nice. Open your eyes again.');
                      closedStreak = 0;
                    }
                  } else {
                    closedStreak = 0;
                  }
                  break;
                case _BlinkPhase.needOpenAgain:
                  if (open == true) {
                    openAfterBlinkStreak++;
                    if (openAfterBlinkStreak >= 2) {
                      timer.cancel();
                      onStatus('Liveness OK');
                      settle(true);
                    }
                  } else {
                    openAfterBlinkStreak = 0;
                  }
                  break;
              }
            })
            .catchError((_) {
              busy = false;
            });
      });

      return await result.future;
    } catch (e) {
      if (kDebugMode) debugPrint('BlinkLivenessService: $e');
      timer.cancel();
      settle(false);
      return await result.future;
    } finally {
      timer.cancel();
      if (!settled) {
        settle(false);
      }
    }
  }

  static InputImageRotation _rotationFor(CameraDescription d) {
    if (Platform.isIOS) return InputImageRotation.rotation0deg;
    switch (d.sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  static bool? _eyesOpen(Face f) {
    final l = f.leftEyeOpenProbability;
    final r = f.rightEyeOpenProbability;
    if (l == null || r == null) return null;
    return l > 0.55 && r > 0.55;
  }

  static bool? _eyesClosed(Face f) {
    final l = f.leftEyeOpenProbability;
    final r = f.rightEyeOpenProbability;
    if (l == null || r == null) return null;
    return l < 0.35 && r < 0.35;
  }
}

enum _BlinkPhase {
  needFaceAndOpenEyes,
  needBlink,
  needOpenAgain,
}
