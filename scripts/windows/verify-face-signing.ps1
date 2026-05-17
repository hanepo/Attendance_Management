# Run on client PC after git clone — checks face signing setup before flutter run.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

Write-Host "=== Face signing check ===" -ForegroundColor Cyan

$ks = Join-Path $Root "android\team-debug.keystore"
if (-not (Test-Path $ks)) {
    Write-Host "FAIL: android\team-debug.keystore missing. Run: git pull" -ForegroundColor Red
    exit 1
}
Write-Host "OK: team-debug.keystore found" -ForegroundColor Green

$gradle = Join-Path $Root "android\app\build.gradle.kts"
$content = Get-Content $gradle -Raw
if ($content -notmatch "teamDebug") {
    Write-Host "FAIL: build.gradle.kts has no teamDebug signing. Run: git pull" -ForegroundColor Red
    exit 1
}
Write-Host "OK: build.gradle.kts uses teamDebug" -ForegroundColor Green

Write-Host ""
Write-Host "Gradle signing report (check debug SHA-1):" -ForegroundColor Cyan
Set-Location (Join-Path $Root "android")
.\gradlew signingReport 2>&1 | Select-String -Pattern "SHA1|Variant: debug" -Context 0,2

Write-Host ""
Write-Host "Expected debug SHA-1: 0E:9D:41:77:0C:34:3D:6C:E0:E7:D8:1B:43:81:08:77:8E:F7:3C:3F" -ForegroundColor Yellow
Write-Host "Then: adb uninstall com.attendance.attendance_app ; flutter clean ; flutter pub get ; flutter run" -ForegroundColor Green
