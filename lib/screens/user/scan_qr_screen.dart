import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/attendance_service.dart';
import '../../utils/constants.dart';
import 'face_verify_screen.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  MobileScannerController? _controller;
  bool _processing = false;
  bool _scanned = false;
  bool _permissionGranted = false;
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.status;
    if (status.isDenied) {
      await Permission.camera.request();
    }
    if (!mounted) return;
    final current = await Permission.camera.status;
    if (current.isPermanentlyDenied) {
      setState(() {
        _permissionGranted = false;
        _permissionChecked = true;
      });
      return;
    }
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() {
      _permissionGranted = true;
      _permissionChecked = true;
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() {
      _processing = true;
      _scanned = true;
    });
    await _controller?.stop();

    final qrData = barcode!.rawValue!;
    final session = await AttendanceService().resolveSession(qrData);

    if (!mounted) return;

    if (session == null) {
      _showError('Invalid QR code. Please scan a valid attendance QR code.');
      setState(() {
        _processing = false;
        _scanned = false;
      });
      await _controller?.start();
      return;
    }

    if (!session.isCurrentlyActive) {
      _showError(
          'This attendance session is not currently active.\nSession: ${session.sessionName}');
      setState(() {
        _processing = false;
        _scanned = false;
      });
      await _controller?.start();
      return;
    }

    setState(() => _processing = false);

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceVerifyScreen(session: session),
      ),
    );

    if (mounted) {
      if (result == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _scanned = false);
        await _controller?.start();
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(msg),
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
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_permissionGranted && _controller != null)
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller?.toggleTorch(),
              tooltip: 'Toggle flash',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_permissionChecked) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (!_permissionGranted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
              const SizedBox(height: 20),
              const Text(
                'Camera permission is required to scan QR codes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _controller!,
          onDetect: _onDetect,
          errorBuilder: (ctx, err) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Camera error: ${err.errorCode}',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        // Scan overlay
        CustomPaint(
          painter: _ScanOverlayPainter(),
          child: const SizedBox.expand(),
        ),
        // Instructions
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
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
            child: Column(
              children: [
                if (_processing)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  const Icon(Icons.qr_code_scanner,
                      color: Colors.white54, size: 36),
                const SizedBox(height: 12),
                const Text(
                  'Point your camera at the QR code\ndisplayed by your lecturer',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final scanSize = size.width * 0.65;
    final left = (size.width - scanSize) / 2;
    final top = size.height * 0.25;
    final scanRect = Rect.fromLTWH(left, top, scanSize, scanSize);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final cornerPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const cl = 24.0;
    const r = 4.0;

    canvas.drawLine(Offset(left, top + cl), Offset(left, top + r), cornerPaint);
    canvas.drawLine(Offset(left + r, top), Offset(left + cl, top), cornerPaint);
    canvas.drawLine(Offset(left + scanSize - cl, top),
        Offset(left + scanSize - r, top), cornerPaint);
    canvas.drawLine(Offset(left + scanSize, top + r),
        Offset(left + scanSize, top + cl), cornerPaint);
    canvas.drawLine(Offset(left, top + scanSize - cl),
        Offset(left, top + scanSize - r), cornerPaint);
    canvas.drawLine(Offset(left + r, top + scanSize),
        Offset(left + cl, top + scanSize), cornerPaint);
    canvas.drawLine(Offset(left + scanSize - cl, top + scanSize),
        Offset(left + scanSize - r, top + scanSize), cornerPaint);
    canvas.drawLine(Offset(left + scanSize, top + scanSize - cl),
        Offset(left + scanSize, top + scanSize - r), cornerPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
