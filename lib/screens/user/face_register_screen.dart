import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';
import '../../services/face_service.dart';
import '../../utils/constants.dart';

class FaceRegisterScreen extends StatefulWidget {
  const FaceRegisterScreen({super.key});

  @override
  State<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends State<FaceRegisterScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraCtrl;
  bool _cameraReady = false;
  bool _isDetecting = false;
  bool _faceFound = false;
  bool _capturing = false;
  bool _permissionGranted = false;
  String _statusText = 'Initializing camera...';
  String? _cameraError;

  // Last confirmed-good frame & face for embedding (avoids takePicture issues)
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
        _cameraError = 'Camera permission denied. Please enable in Settings.';
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
      setState(() {
        _cameraReady = true;
        _statusText = 'Position your face in the oval';
      });
      ctrl.startImageStream(_processFrame);
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  void _processFrame(CameraImage image) {
    if (_isDetecting || _capturing) return;
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
        if (!_capturing) {
          if (faces.isEmpty) {
            _statusText = 'No face detected — look at the camera';
          } else if (faces.length > 1) {
            _statusText = 'Multiple faces — only you should be visible';
          } else {
            final angle = faces.first.headEulerAngleY ?? 0.0;
            _statusText = angle.abs() > 25
                ? 'Look straight at the camera'
                : 'Face detected ✓  Tap to register';
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

  Future<void> _captureAndRegister() async {
    if (!_faceFound || _capturing) return;
    if (_lastGoodFrame == null || _lastDetectedFace == null) return;

    setState(() {
      _capturing = true;
      _statusText = 'Processing face data...';
    });

    // Stop stream while processing, but keep controller alive
    try {
      await _cameraCtrl?.stopImageStream();
    } catch (_) {}

    try {
      final frame = _lastGoodFrame!;
      final face = _lastDetectedFace!;

      setState(() => _statusText = 'Generating face embedding...');

      // Get embedding directly from the saved live-stream frame
      final embedding = _faceService.getFaceEmbeddingFromRawFrame(frame, face);

      String faceJson;
      if (embedding != null) {
        faceJson = _faceService.embeddingToJson(embedding);
      } else {
        // Fallback: store landmark geometry
        faceJson = _landmarkDescriptor(face);
      }

      setState(() => _statusText = 'Saving face data...');

      // Pass plain JSON — AuthService handles encryption
      await AuthService().updateFaceData(faceJson);

      if (mounted) {
        setState(() => _statusText = 'Face registered successfully! ✓');
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      await _showAlert('Something went wrong: $e\n\nPlease try again.');
      _restartStream();
    }
  }

  String _landmarkDescriptor(Face face) {
    final Map<String, dynamic> d = {
      'method': 'landmarks',
      'headEulerAngleX': face.headEulerAngleX,
      'headEulerAngleY': face.headEulerAngleY,
      'boundingBoxLeft': face.boundingBox.left,
      'boundingBoxTop': face.boundingBox.top,
      'boundingBoxRight': face.boundingBox.right,
      'boundingBoxBottom': face.boundingBox.bottom,
    };
    for (final e in face.landmarks.entries) {
      if (e.value != null) {
        d['lm_${e.key.name}_x'] = e.value!.position.x;
        d['lm_${e.key.name}_y'] = e.value!.position.y;
      }
    }
    return jsonEncode(d);
  }

  void _restartStream() {
    if (!mounted) return;
    // Grab old controller and null it out BEFORE setState to prevent
    // CameraPreview from trying to render a disposed controller.
    final oldCtrl = _cameraCtrl;
    setState(() {
      _capturing = false;
      _cameraReady = false;
      _cameraCtrl = null;
      _lastGoodFrame = null;
      _lastDetectedFace = null;
      _faceFound = false;
      _statusText = 'Restarting camera...';
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
        title: const Text('Register Face'),
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
            painter: _OvalPainter(faceFound: _faceFound),
            child: const SizedBox.expand(),
          ),
          if (_capturing)
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
          if (!_capturing)
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
                          ? _captureAndRegister
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (_faceFound && _lastGoodFrame != null)
                              ? AppColors.primary
                              : Colors.grey[700],
                          boxShadow: (_faceFound && _lastGoodFrame != null)
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.5),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (_faceFound && _lastGoodFrame != null)
                          ? 'Tap to register your face'
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

class _OvalPainter extends CustomPainter {
  final bool faceFound;
  const _OvalPainter({required this.faceFound});

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
  bool shouldRepaint(_OvalPainter old) => old.faceFound != faceFound;
}
