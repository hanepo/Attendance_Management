# Creates Attendance_Management-handoff.zip for your client (Windows).
# Run from repo root:  powershell -ExecutionPolicy Bypass -File scripts\create-handoff-zip.ps1

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$OutZip = Join-Path (Split-Path $Root -Parent) "Attendance_Management-handoff.zip"
$Stage = Join-Path $env:TEMP "Attendance_Management_handoff_$(Get-Random)"

if (-not (Test-Path (Join-Path $Root "android\app\google-services.json"))) {
    Write-Host "ERROR: android\app\google-services.json missing. Cannot create handoff zip." -ForegroundColor Red
    exit 1
}

Write-Host "Staging to $Stage ..."
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Path $Stage | Out-Null

$excludeDirs = @(
    ".git", ".dart_tool", "build", ".idea", ".vscode",
    "android\.gradle", "android\app\build", "android\build",
    "ios\Pods", "ios\.symlinks", "ios\Flutter\ephemeral"
)

robocopy $Root $Stage /E /XD $excludeDirs /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with $LASTEXITCODE" }

if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $OutZip -Force
Remove-Item $Stage -Recurse -Force

Write-Host ""
Write-Host "Created: $OutZip" -ForegroundColor Green
Write-Host "Send this zip to your client. They unzip and follow START_HERE.txt" -ForegroundColor Green
