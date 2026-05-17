import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';
import '../../services/blink_liveness_service.dart';
import '../../services/face_service.dart';
import '../../services/face_engine_facade.dart';
import '../../utils/constants.dart';

class FaceRegisterScreen extends StatefulWidget {
  final bool redirectToHome;
  final bool redirectToAdminHome;
  const FaceRegisterScreen({
    super.key,
    this.redirectToHome = false,
    this.redirectToAdminHome = false,
  });

  @override
  State<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends State<FaceRegisterScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _cameraReady = false;
  bool _processing = false;
  String _status = 'Position your face in the oval and tap Capture';
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FaceEngineFacade.prime();
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _ctrl?.dispose();
      if (mounted) setState(() { _cameraReady = false; _ctrl = null; });
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      if (mounted) setState(() => _cameraError = 'Camera permission denied.');
      return;
    }
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
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: FaceService.cameraImageFormat,
      );
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      _ctrl = ctrl;
      setState(() {
        _cameraReady = true;
        _cameraError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _capture() async {
    if (_processing || !_cameraReady || _ctrl == null) return;
    setState(() {
      _processing = true;
      _status = 'Liveness: follow the on-screen steps';
    });
    try {
      final blinkOk = await BlinkLivenessService().runBlinkChallenge(
        camera: _ctrl!,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!blinkOk) {
        if (!mounted) return;
        setState(() {
          _processing = false;
          _status = 'Position your face in the oval and tap Capture';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Blink liveness check failed or timed out. Please try again.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _status = 'Capturing face...');
      final file = await _ctrl!.takePicture();
      setState(() => _status = 'Extracting face data...');
      final outcome = await FaceEngineFacade.extractFromPhoto(file.path);
      if (outcome == null) {
        setState(() {
          _processing = false;
          _status = 'No face detected. Please centre your face and try again.';
        });
        return;
      }
      setState(() => _status = 'Saving face data...');
      final faceJson = outcome.storageJson;
      await AuthService().updateFaceData(faceJson);
      if (!mounted) return;
      setState(() { _processing = false; _status = 'Face registered!'; });
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (widget.redirectToAdminHome) {
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.adminHome, (_) => false);
      } else if (widget.redirectToHome) {
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.userHome, (_) => false);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _status = 'Something went wrong. Please try again.';
      });
    }
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
        actions: [
          if (widget.redirectToHome && !widget.redirectToAdminHome)
            TextButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, AppRoutes.userHome, (_) => false),
              child: const Text('Skip', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: _cameraError != null
          ? _buildError()
          : !_cameraReady
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
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
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );

  Widget _buildCamera() => Stack(
        children: [
          SizedBox.expand(child: CameraPreview(_ctrl!)),
          CustomPaint(
            painter: _OvalPainter(),
            child: const SizedBox.expand(),
          ),
          if (_processing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(_status,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          if (!_processing)
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
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _capture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Tap to capture your face',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      );
}

class _OvalPainter extends CustomPainter {
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
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_OvalPainter old) => false;
}
