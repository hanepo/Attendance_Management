# Windows setup — Secure Attendance

Use this guide on **Windows 10/11** (PowerShell or Command Prompt). iOS builds require a Mac; on Windows you build and run **Android only**.

---

## 1. Install tools (one time)

1. **Flutter** — [Install Flutter on Windows](https://docs.flutter.dev/get-started/install/windows)  
   Add Flutter to `PATH`, then open a **new** terminal:
   ```powershell
   flutter doctor
   ```
   Fix anything marked with ✗ (especially **Android toolchain** and **Android Studio**).

2. **Android Studio** — install **Android SDK**, **SDK Platform** (API 34+), and **Android SDK Build-Tools**.

3. **USB driver** — for your phone brand (Samsung, Xiaomi, etc.) if `flutter devices` does not list the phone.

4. **Git** — [git-scm.com](https://git-scm.com/download/win)

---

## 2. Get the project

```powershell
cd $env:USERPROFILE\Desktop
git clone https://github.com/hanepo/Attendance_Management.git
cd Attendance_Management
```

Or open your existing folder, e.g. `C:\Users\admin\Desktop\Attendance_Management`.

---

## 3. Firebase file (required)

1. [Firebase Console](https://console.firebase.google.com/) → your project → Project settings → Your apps → Android.  
2. Package name must be: **`com.attendance.attendance_app`**  
3. Download **`google-services.json`**.  
4. Copy to:
   ```
   android\app\google-services.json
   ```
   (This file is **not** on GitHub.)

---

## 4. Check Face SDK files

These must exist after clone (~35 MB total):

```
facesdk_plugin\android\libs\facesdk.aar
facesdk_plugin\android\libs\fotoapparat-2.7.0.aar
```

If missing, run `git pull` again or re-clone. Without them the app cannot do face recognition.

---

## 5. Automated check (recommended)

In **PowerShell** from the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-setup.ps1
```

Or double-click **`scripts\windows\check-setup.cmd`**.

Fix any **FAIL** lines before continuing.

---

## 6. Run on a real Android phone (required for face)

> **Do not use a normal x86/x86_64 emulator.** The face SDK only supports **ARM** phones.  
> x86 emulators cause **“Lost connection to device”** and **“Secure Attendance keeps stopping”**.

1. On the phone: **Settings → Developer options → USB debugging** ON.  
2. Connect USB; on the phone tap **Allow** when asked to trust the PC.  
3. Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\run-on-phone.ps1
```

Or: **`scripts\windows\run-on-phone.cmd`**

First build can take **10–20 minutes** (`Running Gradle task 'assembleDebug'...`). Wait until you see `Built build\app\outputs\flutter-apk\app-debug.apk`.

---

## 7. Build release APK for testing (face demo)

For face recognition with the **bundled license**, do **not** use a custom release keystore yet.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\build-demo-apk.ps1
```

APK output:

```
build\app\outputs\flutter-apk\app-release.apk
```

Copy that file to the phone and install. If you see **activation code -2**, you built with `android\key.properties` — use the script above (it temporarily disables that file).

---

## 8. Common Windows issues

| Problem | Fix |
|--------|-----|
| **Lost connection to device** | App crashed. Use a **physical phone**, not x86 emulator. |
| **keeps stopping** | Same — use ARM phone; add `google-services.json`. |
| Gradle very slow / red Notes | Normal on first build; wait for `Built ... apk`. |
| `flutter` not recognized | Re-open terminal after installing Flutter; check PATH. |
| Phone not in `flutter devices` | Install USB driver; try another cable/port; allow USB debugging. |
| Face **activation -2** | Run `build-demo-apk.ps1` or delete `android\key.properties` and rebuild. |
| Path too long errors | Move project closer to `C:\dev\Attendance_Management`. |

---

## 9. Manual commands (if you prefer)

```powershell
flutter pub get
flutter devices
flutter run
flutter build apk --release
```

---

## Ringkasan (Bahasa Malaysia)

- **Lost connection** = app **crash**, bukan internet.  
- Guna **telefon Android sebenar**, jangan emulator x86.  
- Letak **`google-services.json`** dalam `android\app\`.  
- Build pertama **lama** — tunggu sampai siap.  
- Face error **-2** → jangan guna `key.properties`; guna script `build-demo-apk.ps1`.
