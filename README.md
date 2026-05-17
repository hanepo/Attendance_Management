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
git clone https://github.com/hanepo/Attendance_Management.git
cd Attendance_Management
```

**After cloning:** `google-services.json` and `GoogleService-Info.plist` are **not** in the repo (they are listed in `.gitignore` to avoid leaking Firebase credentials on a public GitHub project). Download them from your [Firebase Console](https://console.firebase.google.com/) and place them as described in [Firebase setup](#firebase-setup-required). If you use a different Firebase project than the one used to generate `lib/firebase_options.dart`, run `flutterfire configure` to regenerate that file.

If you already have the project folder locally, open it from there instead of cloning.

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

**Client handoff (simplest):** `flutter build apk --release` is enough — the app **bundles demo AES keys** when you do not pass `--dart-define`, so the APK starts and matches Firestore data encrypted with those same demo keys.

**Stronger AES (optional):** pass **`ATTENDANCE_AES_KEY`** / **`ATTENDANCE_AES_IV`** at build time, or use **`dart_define.client.json`** (committed demo keys) / **`dart_define.secrets.json`** (gitignored, your own keys). See [Encryption (AES) explained](#encryption-aes-explained).

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
| App name, roles | `lib/utils/constants.dart` |
| AES key / IV resolution (`--dart-define`, bundled demo fallback) | `lib/config/app_secrets.dart` |
| Blink liveness (ML Kit) | `lib/services/blink_liveness_service.dart` |
| KBY face templates + SDK liveness | `lib/services/kby_face_service.dart` |

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
- **Key source:** `lib/config/app_secrets.dart`:
  - If you pass **`ATTENDANCE_AES_KEY`** and **`ATTENDANCE_AES_IV`** at compile time (each **32** and **16** UTF‑8 bytes), those are used.
  - Otherwise the app uses the **bundled demo key/IV** in **all** modes (including release), so **`flutter build apk --release`** works for client demos without extra flags.
- **KBY Face SDK license (optional):** **`KBY_LICENSE_ANDROID`** / **`KBY_LICENSE_IOS`** override the bundled strings. Use a vendor-supplied license when your **release** APK is signed with a different keystore than the trial (activation **-2** = app ID / certificate mismatch; see [Troubleshooting](#troubleshooting)).

Example **custom** release build (your own keys):

```bash
flutter build apk --release \
  --dart-define=ATTENDANCE_AES_KEY=YOUR_32_CHARACTER_SECRET_KEY! \
  --dart-define=ATTENDANCE_AES_IV=YOUR_16_CHAR_IV!
```

**Using a JSON file:** committed **`dart_define.client.json`** contains the same demo key/IV for builds like:

```bash
flutter build apk --release --dart-define-from-file=dart_define.client.json
```

For **private** keys, use **`dart_define.secrets.json`** (gitignored — copy from `dart_define.secrets.json.example`).

Changing the AES key makes existing Firestore ciphertext **undecryptable**; plan key rotation with care.

> **Security warning for production:** Compile-time keys still ship inside the binary; a determined attacker can extract them. For high-sensitivity deployments, prefer **per-user keys** from a backend, **KMS**, or device-bound storage, and rely on **Firestore rules** and least-privilege access.

---

## Face recognition flow

Attendance uses the **KBY Face SDK** (`facesdk_plugin`): templates are extracted from a captured photo, **encrypted**, and stored in Firestore. Verification compares template similarity against a threshold.

**Liveness (defence against static photos):**

1. **Blink challenge (ML Kit):** before each capture, the user must complete an **eyes open → blink → eyes open** sequence using live camera frames (`BlinkLivenessService` + `FaceService` / ML Kit classification).  
2. **Passive SDK liveness:** each extraction returns a **liveness score** from the native SDK; scores below `KbyFaceService.minSdkLivenessScore` are rejected. Android also sets **`check_liveness_level`** on the SDK when supported.

`FaceService` + **MobileFaceNet** remain in the project for other / legacy flows; the primary student flows above use **KBY templates**.

---

## Demonstrating encryption to a client

1. In the app (as **admin**): **Dashboard** → **Show Encryption Demo**.  
   - **Live Demo:** encrypt twice—two different ciphertexts for the same plaintext (random IV).  
   - **My Data:** ciphertext as stored vs decrypted in the app.  
   - **Specs:** where AES runs (client vs Firebase).  
2. In **Firebase Console** → **Firestore** → open a `users` document: fields should look like opaque base64 strings (ciphertext), not readable names or IC numbers.

---

## Client setup (Windows / first clone)

Send this checklist to anyone cloning the repo:

1. **Clone + dependencies**
   ```bash
   git clone https://github.com/hanepo/Attendance_Management.git
   cd Attendance_Management
   flutter pub get
   ```
2. **Firebase (required)** — download `google-services.json` from Firebase Console and place at `android/app/google-services.json` (not in Git).
3. **Face SDK native libs** — after clone, confirm these exist (large files, ~35 MB):
   `facesdk_plugin/android/libs/facesdk.aar` and `fotoapparat-2.7.0.aar`.
4. **Run on a real phone (recommended)** — enable USB debugging, connect the phone, then:
   ```bash
   flutter devices
   flutter run
   ```
5. **Do not use an x86 emulator** — the KBY SDK only includes **ARM** native libraries. An x86/x86_64 emulator often crashes with **“Lost connection to device”** / **Secure Attendance keeps stopping**. Use a **physical device** or an emulator with an **ARM64** system image.
6. **First Android build is slow** — `Running Gradle task 'assembleDebug'...` for **5–15+ minutes** on first run is normal (Gradle downloads). Wait until you see `Built ... app-debug.apk`.
7. **Release APK + face license** — if the app shows **activation code -2**, delete/rename `android/key.properties` and rebuild, **or** get a KBY release license (see troubleshooting row below).

---

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| **`Lost connection to device`** during `flutter run` | The app **crashed** (not Wi‑Fi). On Windows this is often an **x86 emulator** without ARM libs — use a **real phone** or **ARM64** emulator. Check `flutter run -v` / Android Studio Logcat for `UnsatisfiedLinkError` / `libfacesdk.so`. |
| **`Secure Attendance keeps stopping`** | Same as above — native face SDK failed to load, or missing `google-services.json`. |
| Gradle stuck / red `llvm-strip` notes then `Built app-debug.apk` | First build can take **10+ minutes**; red compiler **Notes** are usually harmless. If the app crashes on open, use a **physical ARM phone**. |
| Build fails on Android | Ensure `google-services.json` is under `android/app/`. This project uses **minSdk 29** (Android 10+). |
| iOS build / pod errors | `cd ios && pod install --repo-update`; open `.xcworkspace`; use a real device for camera. |
| `flutter run` hangs on “Dart VM Service…” | Unlock the phone, trust the computer, disable VPN/proxy; rerun. Often succeeds on second run after install. |
| Firestore “permission denied” | Check **Firestore rules** allow authenticated access for your test rules. |
| Face not detected | Good light, face centred, remove coverings; grant camera permission in system Settings. |
| Release build fails at startup with AES / `FlutterError` | Key/IV length must be **32** / **16** UTF‑8 bytes. If you passed `--dart-define`, fix lengths; otherwise the app uses bundled demo keys. |
| Encrypted names look like garbage in the app | The APK was built with a **different AES key** than the Firestore data. Rebuild with the **same** key (default demo, or match your `dart_define` file). |
| Passive liveness always fails | Try better lighting; tune `minSdkLivenessScore` in `kby_face_service.dart` after testing on target devices. |
| Face SDK / dialog: **not ready**, **activation -2**, works in `flutter run` but not release APK | **-2** = vendor **SDK_LICENSE_APPID_ERROR** (license ≠ this app’s **package + signing cert**). Bundled KBY license matches **debug** signing. If `android/key.properties` exists, release uses your keystore → fail. **Demo:** remove/rename `key.properties`, rebuild (`build.gradle.kts` then signs release with debug keystore). **Production:** get a KBY license for `com.attendance.attendance_app` + your release SHA-1 (or Play App Signing cert), set **`KBY_LICENSE_ANDROID`** in `--dart-define` / define JSON. |
| Wrong Firebase project / login fails | Verify `firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist` all belong to the **same** Firebase project. |

---

## MobSF-style Android hardening (applied in repo)

The following mitigations address common **MobSF Static Analysis** findings for the Android build:

| Finding (typical) | What we changed |
|-------------------|-----------------|
| `allowBackup` default true | `android:allowBackup="false"` in `AndroidManifest.xml` (no ADB backup of app data). |
| Cleartext / network | `network_security_config.xml` + `usesCleartextTraffic="false"` (HTTPS-only expectation). |
| Old `minSdk` | `minSdk = max(flutter.minSdkVersion, 29)` in `android/app/build.gradle.kts` (Android 10+). |
| Debug signing in release | If `android/key.properties` exists (see `android/key.properties.example`), **release** builds use that keystore; otherwise they still use debug signing until you configure one. |
| Merged permissions | `READ_PHONE_STATE` and `RECORD_AUDIO` removed via `tools:node="remove"` when merged from dependencies (not used by this app). |
| Sensitive logging | Removed license `print` in `facesdk_plugin` iOS; removed camera error `Log` in Android plugin. |

**Still vendor / framework noise in MobSF:** Firebase `exported` activities, MD5/SHA-1 in third-party libs, SQLite/RNG/clipboard flags from Flutter or ML Kit — those are not realistically “fixed” inside your app code; document as **accepted risk** or dependency limitation for your report.

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
