# Secure Attendance — Windows environment check
$ErrorActionPreference = "Continue"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

Write-Host ""
Write-Host "=== Secure Attendance — Windows setup check ===" -ForegroundColor Cyan
Write-Host "Project: $Root"
Write-Host ""

function Test-Ok($label, $ok, $hint) {
    if ($ok) {
        Write-Host "[OK]   $label" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label" -ForegroundColor Red
        if ($hint) { Write-Host "       $hint" -ForegroundColor Yellow }
        $script:Failed = $true
    }
}

$Failed = $false

# Flutter
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
Test-Ok "Flutter in PATH" ($null -ne $flutter) "Install Flutter and reopen PowerShell."
if ($flutter) {
    flutter --version 2>&1 | Select-Object -First 1
}

# Face SDK AARs
$facesdk = Join-Path $Root "facesdk_plugin\android\libs\facesdk.aar"
$foto = Join-Path $Root "facesdk_plugin\android\libs\fotoapparat-2.7.0.aar"
Test-Ok "facesdk.aar present" (Test-Path $facesdk) "Re-clone repo; file is ~35 MB."
Test-Ok "fotoapparat AAR present" (Test-Path $foto) "Re-clone repo."

# Firebase
$gs = Join-Path $Root "android\app\google-services.json"
Test-Ok "google-services.json" (Test-Path $gs) "Download from Firebase Console -> android\app\"

# Release keystore warning (face demo)
$keyProps = Join-Path $Root "android\key.properties"
if (Test-Path $keyProps) {
    Write-Host "[WARN] android\key.properties exists — release APK may show face activation -2." -ForegroundColor Yellow
    Write-Host "       For demo APK use: scripts\windows\build-demo-apk.ps1" -ForegroundColor Yellow
} else {
    Write-Host "[OK]   No key.properties (good for demo face license)" -ForegroundColor Green
}

Write-Host ""
Write-Host "--- flutter doctor (summary) ---" -ForegroundColor Cyan
flutter doctor

Write-Host ""
Write-Host "--- flutter devices ---" -ForegroundColor Cyan
flutter devices

Write-Host ""
Write-Host "IMPORTANT: Use a physical Android phone (ARM). x86 emulators crash the face SDK." -ForegroundColor Yellow
Write-Host ""

if ($Failed) {
    Write-Host "Fix FAIL items above, then run: scripts\windows\run-on-phone.ps1" -ForegroundColor Red
    exit 1
}
Write-Host "Setup looks good. Next: scripts\windows\run-on-phone.ps1" -ForegroundColor Green
exit 0
