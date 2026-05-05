import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/session_model.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/encryption_service.dart';
import '../../services/face_service.dart';
import '../../utils/constants.dart';

class FaceVerifyScreen extends StatefulWidget {
  final SessionModel session;
  const FaceVerifyScreen({super.key, required this.session});

  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraCtrl;
  bool _cameraReady = false;
  bool _isDetecting = false;
  bool _faceFound = false;
  bool _verifying = false;
  bool _permissionGranted = false;
  String _statusText = 'Position your face in the oval';
  String? _cameraError;

  // Last confirmed-good frame & face for embedding
  CameraImage? _lastGoodFrame;
  Face? _lastDetectedFace;

  final _faceService = FaceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _faceService.init();
    final status = await Permission.camera.status;
    if (status.isDenied) await Permission.camera.request();
    if (!mounted) return;
    final current = await Permission.camera.status;
    if (current.isPermanentlyDenied) {
      setState(() {
        _cameraError = 'Camera permission denied.';
        _permissionGranted = false;
      });
      return;
    }
    _permissionGranted = true;
    await _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera found.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: FaceService.cameraImageFormat,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _cameraCtrl = ctrl;
      setState(() => _cameraReady = true);
      ctrl.startImageStream(_processFrame);
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  void _processFrame(CameraImage image) {
    if (_isDetecting || _verifying) return;
    _isDetecting = true;
    _faceService
        .detectFromCameraImage(image, _getRotation())
        .then((faces) {
      if (!mounted) return;
      final found = faces.length == 1;
      if (found) {
        _lastGoodFrame = image;
        _lastDetectedFace = faces.first;
      }
      setState(() {
        _faceFound = found;
        if (!_verifying) {
          if (faces.isEmpty) {
            _statusText = 'No face detected — look at the camera';
          } else if (faces.length > 1) {
            _statusText = 'Multiple faces detected';
          } else {
            _statusText = 'Face detected ✓  Tap to verify';
          }
        }
      });
    }).catchError((_) {}).whenComplete(() => _isDetecting = false);
  }

  InputImageRotation _getRotation() {
    switch (_cameraCtrl?.description.sensorOrientation ?? 0) {
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

  Future<void> _captureAndVerify() async {
    if (!_faceFound || _verifying) return;
    if (_lastGoodFrame == null || _lastDetectedFace == null) return;

    setState(() {
      _verifying = true;
      _statusText = 'Verifying identity...';
    });

    // Stop stream while processing
    try {
      await _cameraCtrl?.stopImageStream();
    } catch (_) {}

    try {
      final user = AuthService().currentUser!;
      if (user.faceData == null || user.faceData!.isEmpty) {
        await _showAlert(
            'No face registered. Please register your face first.');
        _restartStream();
        return;
      }

      final decrypted = EncryptionService().decryptFaceData(user.faceData);
      if (decrypted == null || decrypted.isEmpty) {
        await _showAlert(
            'Stored face data is corrupted. Please re-register your face.');
        _restartStream();
        return;
      }

      setState(() => _statusText = 'Matching face...');

      final frame = _lastGoodFrame!;
      final face = _lastDetectedFace!;

      bool verified = false;
      final storedEmbedding = _faceService.jsonToEmbedding(decrypted);

      if (storedEmbedding != null) {
        final currentEmbedding =
            _faceService.getFaceEmbeddingFromRawFrame(frame, face);
        if (currentEmbedding != null) {
          verified = _faceService.isMatch(storedEmbedding, currentEmbedding);
        } else {
          verified = _landmarkFallback(decrypted, face);
        }
      } else {
        verified = _landmarkFallback(decrypted, face);
      }

      if (!verified) {
        await _showAlert(
            'Face verification failed.\n\nYour face does not match the registered face. Please try again or re-register.');
        _restartStream();
        return;
      }

      final error = await AttendanceService().submitAttendance(
        session: widget.session,
        user: user,
      );

      if (!mounted) return;
      if (error != null) {
        await _showAlert(error);
        _restartStream();
        return;
      }

      _showSuccess();
    } catch (e) {
      await _showAlert('Something went wrong: $e\n\nPlease try again.');
      _restartStream();
    }
  }

  bool _landmarkFallback(String storedJson, Face currentFace) {
    try {
      final stored = jsonDecode(storedJson) as Map<String, dynamic>;
      final storedBBWidth = (stored['boundingBoxRight'] as num).toDouble() -
          (stored['boundingBoxLeft'] as num).toDouble();
      final currentBBWidth =
          currentFace.boundingBox.right - currentFace.boundingBox.left;
      double totalScore = 0;
      int count = 0;
      for (final entry in currentFace.landmarks.entries) {
        final lm = entry.value;
        if (lm == null) continue;
        final kx = 'lm_${entry.key.name}_x';
        final ky = 'lm_${entry.key.name}_y';
        if (!stored.containsKey(kx) || !stored.containsKey(ky)) continue;
        final sx =
            (stored[kx] as num).toDouble() / (storedBBWidth > 0 ? storedBBWidth : 1);
        final sy =
            (stored[ky] as num).toDouble() / (storedBBWidth > 0 ? storedBBWidth : 1);
        final cx = lm.position.x / (currentBBWidth > 0 ? currentBBWidth : 1);
        final cy = lm.position.y / (currentBBWidth > 0 ? currentBBWidth : 1);
        final diff = ((sx - cx).abs() + (sy - cy).abs()) / 2;
        totalScore += (1.0 - (diff * 2)).clamp(0.0, 1.0);
        count++;
      }
      if (count == 0) return false;
      return (totalScore / count) >= 0.55;
    } catch (_) {
      return false;
    }
  }

  void _restartStream() {
    if (!mounted) return;
    // Null out controller BEFORE setState so CameraPreview is never
    // asked to render a disposed controller.
    final oldCtrl = _cameraCtrl;
    setState(() {
      _verifying = false;
      _cameraReady = false;
      _cameraCtrl = null;
      _lastGoodFrame = null;
      _lastDetectedFace = null;
      _faceFound = false;
      _statusText = 'Position your face in the oval';
    });
    oldCtrl?.dispose().then((_) {
      if (mounted) _startCamera();
    });
  }

  Future<void> _showAlert(String message) async {
    if (!mounted) return;
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Notice'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    color: AppColors.success, size: 50),
              ),
              const SizedBox(height: 20),
              const Text(
                'Attendance Marked!',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your attendance for\n${widget.session.sessionName}\nhas been recorded.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final oldCtrl = _cameraCtrl;
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _cameraCtrl = null;
        });
      }
      oldCtrl?.dispose();
    } else if (state == AppLifecycleState.resumed && _permissionGranted) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Face Verification'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _cameraError != null
          ? _buildError()
          : (!_cameraReady || _cameraCtrl == null)
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : _buildCamera(),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
              const SizedBox(height: 16),
              Text(_cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              if (!_permissionGranted) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildCamera() => Stack(
        children: [
          SizedBox.expand(child: CameraPreview(_cameraCtrl!)),
          CustomPaint(
            painter: _VerifyOvalPainter(faceFound: _faceFound),
            child: const SizedBox.expand(),
          ),
          // Session label
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Session: ${widget.session.sessionName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_verifying)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _statusText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          if (!_verifying)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 44),
                child: Column(
                  children: [
                    Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _faceFound ? Colors.greenAccent : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: (_faceFound && _lastGoodFrame != null)
                          ? _captureAndVerify
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_faceFound && _lastGoodFrame != null)
                              ? AppColors.success
                              : Colors.grey[700],
                          boxShadow: (_faceFound && _lastGoodFrame != null)
                              ? [
                                  BoxShadow(
                                    color: AppColors.success
                                        .withValues(alpha: 0.5),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                        ),
                        child: const Icon(Icons.face,
                            color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (_faceFound && _lastGoodFrame != null)
                          ? 'Tap to verify and mark attendance'
                          : 'Waiting for face...',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

class _VerifyOvalPainter extends CustomPainter {
  final bool faceFound;
  const _VerifyOvalPainter({required this.faceFound});

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.72,
      height: size.height * 0.50,
    );
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addOval(ovalRect)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black54,
    );
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = faceFound ? Colors.greenAccent : Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_VerifyOvalPainter old) => old.faceFound != faceFound;
}
