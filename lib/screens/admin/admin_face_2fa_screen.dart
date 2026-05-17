import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';
import '../../services/blink_liveness_service.dart';
import '../../services/encryption_service.dart';
import '../../services/face_service.dart';
import '../../services/face_engine_facade.dart';
import '../../utils/constants.dart';

/// Face verification 2FA gate for admin login.
/// On success → navigates to admin home and clears the stack.
/// On failure or cancel → logs out and returns to login.
class AdminFace2faScreen extends StatefulWidget {
  const AdminFace2faScreen({super.key});

  @override
  State<AdminFace2faScreen> createState() => _AdminFace2faScreenState();
}

class _AdminFace2faScreenState extends State<AdminFace2faScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _cameraReady = false;
  bool _processing = false;
  String _status = 'Position your face in the oval and tap Verify';
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      setState(() { _cameraReady = true; _cameraError = null; });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _verify() async {
    if (_processing || !_cameraReady || _ctrl == null) return;
    setState(() { _processing = true; _status = 'Preparing...'; });

    try {
      final user = AuthService().currentUser!;
      final decrypted = EncryptionService().decryptFaceData(user.faceData);
      if (decrypted == null || decrypted.isEmpty) {
        if (!mounted) return;
        await _showAlert('Face data corrupted. Please re-register your face.');
        await _logout();
        return;
      }
      if (!mounted) return;
      setState(() => _status = 'Liveness: follow the on-screen steps');

      final blinkOk = await BlinkLivenessService().runBlinkChallenge(
        camera: _ctrl!,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!blinkOk) {
        if (!mounted) return;
        await _showAlert('Blink liveness failed or timed out. Please try again.');
        if (mounted) {
          setState(() {
            _processing = false;
            _status = 'Position your face in the oval and tap Verify';
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() => _status = 'Capturing face...');
      final file = await _ctrl!.takePicture();
      if (mounted) setState(() => _status = 'Extracting face data...');

      if (mounted) setState(() => _status = 'Matching face...');
      final matched = await FaceEngineFacade.verifyPhotoAgainstStored(
        decrypted,
        file.path,
      );

      if (!matched) {
        if (!mounted) return;
        await _showAlert(
          'Face verification failed.\n\n'
          'Your face does not match the registered admin face.',
        );
        if (mounted) {
          setState(() {
            _processing = false;
            _status = 'Position your face in the oval and tap Verify';
          });
        }
        return;
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.adminHome,
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      await _showAlert('Something went wrong. Please try again.');
      if (mounted) {
        setState(() {
          _processing = false;
          _status = 'Position your face in the oval and tap Verify';
        });
      }
    }
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (_) => false,
      );
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Admin Face Verification'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _logout,
            child: const Text('Cancel & Logout',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: _cameraError != null
          ? _buildError()
          : !_cameraReady
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
              child: const Text(
                '2FA: Verify your identity to continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
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
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _verify,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                        child: const Icon(Icons.face,
                            color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tap to verify your face',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 12),
                    ),
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
