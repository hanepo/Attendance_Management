import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/session_model.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/encryption_service.dart';
import '../../services/kby_face_service.dart';
import '../../utils/constants.dart';

class FaceVerifyScreen extends StatefulWidget {
  final SessionModel session;
  const FaceVerifyScreen({super.key, required this.session});

  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen>
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
      final ctrl = CameraController(front, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      _ctrl = ctrl;
      setState(() { _cameraReady = true; _cameraError = null; });
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _captureAndVerify() async {
    if (_processing || !_cameraReady || _ctrl == null) return;
    setState(() { _processing = true; _status = 'Capturing face...'; });

    try {
      final user = AuthService().currentUser!;
      if (user.faceData == null || user.faceData!.isEmpty) {
        if (!mounted) return;
        await _showAlert('No face registered. Please register your face first.');
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Verify'; });
        return;
      }

      final decrypted = EncryptionService().decryptFaceData(user.faceData);
      if (decrypted == null || decrypted.isEmpty) {
        if (!mounted) return;
        await _showAlert('Face data corrupted. Please re-register your face.');
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Verify'; });
        return;
      }

      final storedTemplates = KbyFaceService.templatesFromJson(decrypted);
      if (storedTemplates == null) {
        if (!mounted) return;
        await _showAlert('Please re-register your face (format updated).');
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Verify'; });
        return;
      }

      final file = await _ctrl!.takePicture();
      if (mounted) setState(() => _status = 'Extracting face data...');

      final currentTemplates = await KbyFaceService().extractTemplates(file.path);
      if (currentTemplates == null) {
        if (mounted) setState(() { _processing = false; _status = 'No face detected. Please centre your face and try again.'; });
        return;
      }

      if (mounted) setState(() => _status = 'Matching face...');
      final similarity = await KbyFaceService().compareFaces(storedTemplates, currentTemplates);

      if (similarity < KbyFaceService.matchThreshold) {
        if (!mounted) return;
        await _showAlert('Face verification failed.\n\nYour face does not match the registered face. Please try again.');
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Verify'; });
        return;
      }

      if (mounted) setState(() => _status = 'Submitting attendance...');
      final error = await AttendanceService().submitAttendance(
        session: widget.session,
        user: user,
      );

      if (!mounted) return;
      if (error != null) {
        await _showAlert(error);
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Verify'; });
        return;
      }

      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      await _showAlert('Something went wrong. Please try again.');
      if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Verify'; });
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

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 50),
              ),
              const SizedBox(height: 20),
              const Text(
                'Attendance Marked!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your attendance for\n${widget.session.sessionName}\nhas been recorded.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _captureAndVerify,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                        ),
                        child: const Icon(Icons.face, color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tap to verify and mark attendance',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
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
