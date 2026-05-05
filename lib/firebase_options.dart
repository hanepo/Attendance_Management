import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web platform is not supported.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAwQAonZzm4RRBFx-T__VOtCl9iKDWNNo4',
    appId: '1:780482289351:android:75c8241d6eade11ab5e8e2',
    messagingSenderId: '780482289351',
    projectId: 'attendance-app-a8433',
    storageBucket: 'attendance-app-a8433.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB6InMnjs1SDYl3XhXgj_Bqmyz7ruLgkuI',
    appId: '1:780482289351:ios:2c55c4fe84c34b4cb5e8e2',
    messagingSenderId: '780482289351',
    projectId: 'attendance-app-a8433',
    storageBucket: 'attendance-app-a8433.firebasestorage.app',
    iosClientId: null,
    iosBundleId: 'com.attendance.attendanceapp',
  );
}
