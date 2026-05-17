# Build release APK with debug signing (face demo license) — Windows
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

Write-Host "=== Build demo release APK (Windows) ===" -ForegroundColor Cyan
Write-Host "Uses debug signing so bundled KBY face license works (no activation -2)." -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path "android\app\google-services.json")) {
    Write-Host "Missing android\app\google-services.json" -ForegroundColor Red
    exit 1
}

$keyProps = "android\key.properties"
$backup = "android\key.properties.demo-bak"
if (Test-Path $keyProps) {
    if (Test-Path $backup) { Remove-Item $backup -Force }
    Rename-Item $keyProps $backup
    Write-Host "Temporarily moved key.properties -> key.properties.demo-bak" -ForegroundColor Yellow
}

try {
    flutter clean
    flutter pub get
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $apk = "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apk) {
        Write-Host ""
        Write-Host "SUCCESS: $((Resolve-Path $apk).Path)" -ForegroundColor Green
        Write-Host "Install on a physical Android phone (not x86 emulator)." -ForegroundColor Green
    }
} finally {
    if ((Test-Path $backup) -and -not (Test-Path $keyProps)) {
        Rename-Item $backup $keyProps
        Write-Host "Restored android\key.properties" -ForegroundColor Gray
    }
}
