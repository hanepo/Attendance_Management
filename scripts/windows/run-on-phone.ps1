# Run app on connected Android device (Windows)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

Write-Host "=== Run Secure Attendance on Android (Windows) ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path "android\app\google-services.json")) {
    Write-Host "Missing android\app\google-services.json — see SETUP_WINDOWS.md" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "facesdk_plugin\android\libs\facesdk.aar")) {
    Write-Host "Missing facesdk_plugin\android\libs\facesdk.aar — re-clone the repo." -ForegroundColor Red
    exit 1
}

Write-Host "Use a PHYSICAL Android phone (USB debugging). x86 emulators will crash." -ForegroundColor Yellow
Write-Host ""

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Connected devices:" -ForegroundColor Cyan
flutter devices
Write-Host ""

$devices = flutter devices 2>&1 | Out-String
if ($devices -match "emulator") {
    Write-Host "WARNING: An emulator is listed. Prefer a real phone for face recognition." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Starting flutter run (first build may take 10-20 minutes)..." -ForegroundColor Cyan
flutter run
