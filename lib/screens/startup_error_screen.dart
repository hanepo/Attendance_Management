import 'package:flutter/material.dart';

/// Shown when [main] cannot finish initialization (so the user never sees a blank screen).
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1565C0),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'App could not start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'If this mentions AES key length, fix ATTENDANCE_AES_KEY (32 UTF‑8 bytes) '
                  'and ATTENDANCE_AES_IV (16). Otherwise check Firebase config and logs.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
