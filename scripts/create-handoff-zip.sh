#!/usr/bin/env bash
# Creates Attendance_Management-handoff.zip (macOS/Linux). Run from repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(dirname "$ROOT")/Attendance_Management-handoff.zip"

if [[ ! -f "$ROOT/android/app/google-services.json" ]]; then
  echo "ERROR: android/app/google-services.json missing."
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

rsync -a "$ROOT/" "$STAGE/" \
  --exclude '.git' \
  --exclude '.dart_tool' \
  --exclude 'build' \
  --exclude '.idea' \
  --exclude 'android/.gradle' \
  --exclude 'android/app/build' \
  --exclude 'android/build' \
  --exclude 'ios/Pods' \
  --exclude 'ios/.symlinks'

rm -f "$OUT"
(cd "$STAGE" && zip -r "$OUT" . -x "*.DS_Store")
echo ""
echo "Created: $OUT"
echo "Client: unzip → read START_HERE.txt → flutter clean / pub get / run"
