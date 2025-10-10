#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-install}"
FFMPEG="${INSTALL_DIR}/bin/ffmpeg"
FFPROBE="${INSTALL_DIR}/bin/ffprobe"

# Windows 平台检测
if [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
  FFMPEG="${FFMPEG}.exe"
  FFPROBE="${FFPROBE}.exe"
fi

echo "=== Verifying FFmpeg Audio-Only Build ==="
echo

# 1. Check if binaries exist
echo "1. Checking binary files..."
if [[ ! -f "${FFMPEG}" ]]; then
  echo "Error: ffmpeg not found at ${FFMPEG}" >&2
  exit 1
fi
echo "✓ ffmpeg found: ${FFMPEG}"

if [[ ! -f "${FFPROBE}" ]]; then
  echo "Error: ffprobe not found at ${FFPROBE}" >&2
  exit 1
fi
echo "✓ ffprobe found: ${FFPROBE}"
echo

# 2. Test execution
echo "2. Testing binary execution..."
if ! "${FFMPEG}" -version >/dev/null 2>&1; then
  echo "Error: ffmpeg failed to execute" >&2
  echo "Showing dependencies:"
  case "$(uname -s)" in
    Linux*)
      ldd "${FFMPEG}" || true
      ;;
    Darwin*)
      otool -L "${FFMPEG}" || true
      ;;
    MINGW*|MSYS*|CYGWIN*)
      objdump -p "${FFMPEG}" | grep "DLL Name:" || true
      ;;
  esac
  exit 1
fi
echo "✓ ffmpeg executes successfully"

if ! "${FFPROBE}" -version >/dev/null 2>&1; then
  echo "Error: ffprobe failed to execute" >&2
  exit 1
fi
echo "✓ ffprobe executes successfully"
echo

# 3. Check version info
echo "3. Version information:"
"${FFMPEG}" -version 2>&1 | head -1
echo

# 4. Check audio codecs
echo "4. Checking audio codecs..."
"${FFMPEG}" -hide_banner -codecs 2>/dev/null | grep -E "^ DEA" | head -20
echo

# 5. Check audio formats
echo "5. Checking audio formats..."
"${FFMPEG}" -hide_banner -formats 2>/dev/null | grep -E "^ (DE|E |D )" | grep -v "video" | head -20
echo

# 6. Check audio filters
echo "6. Checking audio filters..."
"${FFMPEG}" -hide_banner -filters 2>/dev/null | grep "^  A" | head -20
echo

# 7. Verify no video support
echo "7. Verifying no video support..."
if "${FFMPEG}" -hide_banner -codecs 2>/dev/null | grep -q "^ DEV"; then
  echo "WARNING: Video codecs found (should be disabled)" >&2
  exit 1
else
  echo "✓ No video codecs (as expected)"
fi
echo

# 8. Binary size
echo "8. Binary sizes:"
ls -lh "${FFMPEG}" | awk '{print "  ffmpeg:  " $5}'
ls -lh "${FFPROBE}" | awk '{print "  ffprobe: " $5}'
echo

# 9. Check dependencies (informational)
echo "9. Binary dependencies:"
case "$(uname -s)" in
  Linux*)
    echo "  Linux dependencies:"
    ldd_output=$(ldd "${FFMPEG}" 2>&1)
    if echo "${ldd_output}" | grep -q "not a dynamic executable"; then
      echo "    ✓ Static build - no external dependencies"
    else
      echo "${ldd_output}" | head -10 | sed 's/^/    /'
    fi
    ;;
  Darwin*)
    echo "  macOS dependencies:"
    otool -L "${FFMPEG}" | head -10 | sed 's/^/    /'
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "  Windows dependencies:"
    if dll_output=$(objdump -p "${FFMPEG}" 2>/dev/null | grep "DLL Name:" | head -10); then
      echo "${dll_output}" | sed 's/^/    /'
    else
      echo "    ✓ Static build - no external DLLs"
    fi
    ;;
esac
echo

echo "=== Verification Complete ==="