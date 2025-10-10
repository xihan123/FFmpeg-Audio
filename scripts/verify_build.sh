#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-install}"
FFMPEG="${INSTALL_DIR}/bin/ffmpeg"
FFPROBE="${INSTALL_DIR}/bin/ffprobe"

if [[ ! -f "${FFMPEG}" ]]; then
  echo "Error: ffmpeg not found at ${FFMPEG}" >&2
  exit 1
fi

echo "=== Verifying FFmpeg Audio-Only Build ==="
echo

echo "1. Checking audio codecs..."
"${FFMPEG}" -hide_banner -codecs 2>/dev/null | grep -E "^ DEA" | head -20
echo

echo "2. Checking audio formats..."
"${FFMPEG}" -hide_banner -formats 2>/dev/null | grep -E "^ (DE|E |D )" | grep -v "video" | head -20
echo

echo "3. Checking audio filters..."
"${FFMPEG}" -hide_banner -filters 2>/dev/null | grep "^  A" | head -20
echo

echo "4. Verifying no video support..."
if "${FFMPEG}" -hide_banner -codecs 2>/dev/null | grep -q "^ DEV"; then
  echo "WARNING: Video codecs found (should be disabled)" >&2
  exit 1
else
  echo "✓ No video codecs (as expected)"
fi
echo

echo "5. Binary size:"
ls -lh "${FFMPEG}" | awk '{print $5, $9}'
echo

echo "=== Verification Complete ==="