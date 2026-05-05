# Secure Attendance

Cross-platform **Flutter** mobile app (**iOS** & **Android**) for class attendance using **face verification**, **Firebase** (Authentication + Cloud Firestore), and **client-side AES-256-CBC** encryption for personally identifiable information stored in the cloud.

---

## Table of contents

1. [What this app does](#what-this-app-does)
2. [Architecture overview](#architecture-overview)
3. [Tech stack](#tech-stack)
4. [Prerequisites](#prerequisites)
5. [Firebase setup (required)](#firebase-setup-required)
6. [Install & run on your machine](#install--run-on-your-machine)
7. [Building release binaries](#building-release-binaries)
8. [First-time usage walkthrough](#first-time-usage-walkthrough)
9. [Where things live in the code](#where-things-live-in-the-code)
10. [Firestore data model](#firestore-data-model)
11. [Encryption (AES) explained](#encryption-aes-explained)
12. [Face recognition flow](#face-recognition-flow)
13. [Demonstrating encryption to a client](#demonstrating-encryption-to-a-client)
14. [Troubleshooting](#troubleshooting)

---

## What this app does

| Role | Capabilities |
|------|----------------|
| **Admin** | Dashboard stats, create/edit/delete **classes** and **sessions**, enrol or remove students, view attendance, manage **all users** (edit role/PII, delete), open **Encryption Demo** screen, edit own **profile** |
| **Student (user)** | Edit **profile** (name, IC, matrix number, profile picture), join a class with **class code**, register **face biometric**, **mark attendance** for an active session via **face verification** (no QR required for the main student flow) |

Passwords are handled by **Firebase Auth** (not stored as plain text in Firestore). Sensitive profile and operational text fields are encrypted **on the device** before being written to Firestore.

---

## Architecture overview

```
┌─────────────────┐     TLS (HTTPS)      ┌──────────────────────┐
│  Flutter app    │ ───────────────────► │ Firebase Auth        │
│  (iOS/Android)  │                       │ (email/password)      │
└────────┬────────┘                       └──────────────────────┘
         │
         │  AES-256 encrypt (client)  →  ciphertext only
         ▼
┌─────────────────┐
│ Cloud Firestore │  users, classes, sessions, attendance, enrollments
└─────────────────┘
```

- **AES encryption does not run inside Firebase.** It runs in the Flutter app. Firestore only stores ciphertext for configured fields.
- **Face embeddings** (numeric vectors from **MobileFaceNet** TFLite) are encrypted before storage.

---

## Tech stack

| Area | Technology |
|------|------------|
| UI / app | Flutter (Dart), Material 3 |
| Backend | Firebase Auth, Cloud Firestore |
| Face detection | Google ML Kit Face Detection |
| Face embedding | TensorFlow Lite (**MobileFaceNet**), `mobilefacenet.tflite` in `assets/` |
| Field encryption | Package `encrypt`, **AES-256-CBC**, random 16-byte IV per value |
| Camera / permissions | `camera`, `permission_handler` |
| Profile photos | `image_picker` (+ `image` for resize/compress) |

---

## Prerequisites

- **Flutter SDK** (project uses Dart SDK `^3.11.1` per `pubspec.yaml`). Check with:
  ```bash
  flutter doctor
  ```
- **Xcode** + **CocoaPods** (for iOS), **Android Studio** + Android SDK (for Android)
- A **Firebase project** with **Authentication (Email/Password)** and **Cloud Firestore** enabled
- Physical device recommended for **camera** and **ML** performance (simulator has limitations)

---

## Firebase setup (required)

### 1. Create a Firebase project

1. Open [Firebase Console](https://console.firebase.google.com/).
2. Create a project (or use an existing one).
3. Enable **Authentication** → **Sign-in method** → **Email/Password**.

### 2. Register your apps

#### Android

1. Add an Android app with package name: **`com.attendance.attendance_app`**  
   (matches `applicationId` in `android/app/build.gradle.kts`).
2. Download **`google-services.json`** and place it at:
   ```
   android/app/google-services.json
   ```

#### iOS

1. Add an Apple app with bundle ID: **`com.attendance.attendanceapp`**  
   (matches `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project).
2. Download **`GoogleService-Info.plist`** and place it at:
   ```
   ios/Runner/GoogleService-Info.plist
   ```

### 3. Enable Firestore

1. In Firebase Console → **Firestore Database** → create database (start in **test mode** only for local development; lock down for production).

### 4. Align `firebase_options.dart`

This repo includes `lib/firebase_options.dart` generated for a specific Firebase project. If you use **your own** Firebase project:

- Either run [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup) from the app folder:
  ```bash
  dart pub global activate flutterfire_cli
  flutterfire configure
  ```
- Or replace `firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist` with files from **your** project—**all three must match the same Firebase project.**

### 5. Firestore security rules (important)

For production, replace open test rules with rules that require authentication and restrict reads/writes appropriately. The app expects authenticated users to read/write their data according to your policies. See [Firestore security rules](https://firebase.google.com/docs/firestore/security/get-started).

---

## Install & run on your machine

### 1. Clone / open the project

```bash
cd "/path/to/Attendance management/attendance_app"
```

### 2. Get dependencies

```bash
flutter pub get
```

### 3. iOS (first time on a Mac)

```bash
cd ios
pod install
cd ..
```

If you see CocoaPods warnings about `EXCLUDED_ARCHS`, they are often non-fatal on simulators; testing on a **real iPhone** is recommended for camera/ML.

### 4. Run the app

```bash
flutter devices          # list phones/emulators
flutter run              # pick device, or:
flutter run -d <device_id>
```

**Permissions:** on first use, allow **Camera** (and **Photos** if you pick a profile picture). iOS strings are in `ios/Runner/Info.plist`.

---

## Building release binaries

### Android APK / App Bundle

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

Configure **release signing** in Android Studio / `key.properties`—do not ship with debug keys for production.

### iOS

Open `ios/Runner.xcworkspace` in Xcode, select a **Signing Team**, archive, and distribute via App Store Connect or ad hoc.

---

## First-time usage walkthrough

1. **Register**  
   - Open the app → Register.  
   - Choose role **Admin** or **User** (student).  
   - After success, you land on the correct home (admin cannot “go back” to login without logging out—by design).

2. **Admin**  
   - Create a **class** (and note the **class code**).  
   - Create **sessions** (time window, active flag).  
   - **Users** tab: manage accounts.  
   - **Encryption Demo** (Dashboard): live AES demo + “my data” vs Firestore ciphertext.  

3. **Student**  
   - **Join class** with the **class code**.  
   - **Register face** once (good lighting, face inside the guide).  
   - **Mark attendance**: pick an **active** session for a class you’re enrolled in → **face verify**.

4. **Profile**  
   - Both roles can update **name**, **IC**, **matrix number**, and **profile picture** (stored encrypted).

---

## Where things live in the code

| Concern | Location |
|---------|----------|
| App entry, Firebase init | `lib/main.dart` |
| Firebase options | `lib/firebase_options.dart` |
| AES encrypt/decrypt | `lib/services/encryption_service.dart` |
| Firestore CRUD + field encryption | `lib/services/database_service.dart` |
| Login, register, profile, face update | `lib/services/auth_service.dart` |
| Attendance orchestration | `lib/services/attendance_service.dart` |
| Face ML + TFLite embeddings | `lib/services/face_service.dart` (and related) |
| Admin UI | `lib/screens/admin/` |
| Student UI | `lib/screens/user/` |
| Auth UI | `lib/screens/auth/` |
| App name, roles, **encryption key strings** | `lib/utils/constants.dart` |

---

## Firestore data model

Collections used (see `database_service.dart`):

| Collection | Purpose |
|------------|---------|
| `users` | Profile: encrypted PII, encrypted `face_data`, `role`, links to Auth `uid` |
| `classes` | Class metadata + encrypted names/codes |
| `sessions` | Sessions per class (times, `is_active`) |
| `enrollments` | Student ↔ class membership |
| `attendance` | One record per mark; encrypted display fields as implemented |

Document field names match the app’s `toMap`/`fromMap` conventions (snake_case in Firestore).

---

## Encryption (AES) explained

- **Algorithm:** **AES-256-CBC** (`encrypt` package).
- **IV:** A new **random 16-byte IV** is generated for **each** encrypt call. Stored form: `base64(iv) : base64(ciphertext)`.
- **Key source:** `AppStrings.encryptionKey` in `lib/utils/constants.dart` (must be **32 bytes** when UTF-8 encoded for AES-256).

> **Security warning for production:** Embedding a long-term AES key in source code is acceptable only for coursework or demos. For real deployments, use secure key distribution (e.g. per-user keys from a backend, Android Keystore / iOS Keychain, or KMS) and **never** commit production secrets to git.

---

## Face recognition flow

1. **Google ML Kit** finds a face in the **live camera** stream.  
2. The app crops/normalizes the face region and runs **`mobilefacenet.tflite`** to produce a **192-dimensional embedding**.  
3. On **register**, that embedding (as JSON) is **encrypted** and saved to Firestore.  
4. On **verify**, a new embedding is compared to the stored one using **Euclidean distance** under a configured threshold.  

The app avoids relying on `takePicture()` for embedding on some devices; it uses **cached live frames** after a successful detection for more reliable iOS/Android behaviour.

---

## Demonstrating encryption to a client

1. In the app (as **admin**): **Dashboard** → **Show Encryption Demo**.  
   - **Live Demo:** encrypt twice—two different ciphertexts for the same plaintext (random IV).  
   - **My Data:** ciphertext as stored vs decrypted in the app.  
   - **Specs:** where AES runs (client vs Firebase).  
2. In **Firebase Console** → **Firestore** → open a `users` document: fields should look like opaque base64 strings (ciphertext), not readable names or IC numbers.

---

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Build fails on Android | Ensure `minSdk` is **23+** (Firebase Auth). `google-services.json` must be under `android/app/`. |
| iOS build / pod errors | `cd ios && pod install --repo-update`; open `.xcworkspace`; use a real device for camera. |
| `flutter run` hangs on “Dart VM Service…” | Unlock the phone, trust the computer, disable VPN/proxy; rerun. Often succeeds on second run after install. |
| Firestore “permission denied” | Check **Firestore rules** allow authenticated access for your test rules. |
| Face not detected | Good light, face centred, remove coverings; grant camera permission in system Settings. |
| Wrong Firebase project / login fails | Verify `firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist` all belong to the **same** Firebase project. |

---

## License / academic use

Use and adapt per your institution’s policies. Third-party packages and **MobileFaceNet** / ML Kit are subject to their respective licenses.

---

## Quick command reference

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

For questions about extending features, start from `lib/services/` (data + security) and `lib/screens/` (UI).
