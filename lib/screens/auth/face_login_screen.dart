import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/encryption_service.dart';
import '../../services/kby_face_service.dart';
import '../../utils/constants.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _cameraReady = false;
  bool _processing = false;
  String _status = 'Position your face in the oval and tap Scan';
  String? _cameraError;

  List<UserModel> _usersWithFaces = [];
  bool _usersLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUsers();
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

  Future<void> _loadUsers() async {
    final all = await DatabaseService().getAllUsers();
    final withFaces = all.where((u) => u.faceData != null && u.faceData!.isNotEmpty).toList();
    if (mounted) setState(() { _usersWithFaces = withFaces; _usersLoaded = true; });
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

  Future<void> _captureAndLogin() async {
    if (_processing || !_cameraReady || _ctrl == null) return;
    if (!_usersLoaded) {
      if (mounted) setState(() => _status = 'Still loading users, please wait...');
      return;
    }

    setState(() { _processing = true; _status = 'Capturing face...'; });

    try {
      final file = await _ctrl!.takePicture();
      if (mounted) setState(() => _status = 'Extracting face data...');

      final currentTemplates = await KbyFaceService().extractTemplates(file.path);
      if (currentTemplates == null) {
        if (mounted) setState(() { _processing = false; _status = 'No face detected. Please centre your face and try again.'; });
        return;
      }

      if (mounted) setState(() => _status = 'Searching for match...');

      final enc = EncryptionService();
      UserModel? matchedUser;

      for (final user in _usersWithFaces) {
        final decrypted = enc.decryptFaceData(user.faceData);
        if (decrypted == null || decrypted.isEmpty) continue;

        final storedTemplates = KbyFaceService.templatesFromJson(decrypted);
        if (storedTemplates == null) continue;

        final similarity = await KbyFaceService().compareFaces(storedTemplates, currentTemplates);
        if (similarity >= KbyFaceService.matchThreshold) {
          matchedUser = user;
          break;
        }
      }

      if (matchedUser == null) {
        if (!mounted) return;
        await _showAlert('Face not recognised.\n\nNo matching account found. Please login with email and password.');
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Scan'; });
        return;
      }

      if (mounted) setState(() => _status = 'Match found! Logging in...');
      final error = await AuthService().loginWithUser(matchedUser);

      if (!mounted) return;
      if (error != null) {
        await _showAlert(error);
        if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Scan'; });
        return;
      }

      Navigator.pushNamedAndRemoveUntil(
        context,
        matchedUser.role == AppStrings.roleAdmin ? AppRoutes.adminHome : AppRoutes.userHome,
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      await _showAlert('Something went wrong. Please try again.');
      if (mounted) setState(() { _processing = false; _status = 'Position your face in the oval and tap Scan'; });
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
        title: const Text('Login with Face'),
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
                      _usersLoaded ? _status : 'Loading users...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _usersLoaded ? _captureAndLogin : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _usersLoaded ? AppColors.primary : Colors.grey[700],
                          boxShadow: _usersLoaded
                              ? [BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                )]
                              : [],
                        ),
                        child: const Icon(Icons.face, color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _usersLoaded ? 'Tap to login with your face' : 'Loading...',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
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
