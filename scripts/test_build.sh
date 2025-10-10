#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-install}"
FFMPEG="${INSTALL_DIR}/bin/ffmpeg"

# Windows 平台检测
if [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN) ]]; then
  FFMPEG="${FFMPEG}.exe"
fi

if [[ ! -f "${FFMPEG}" ]]; then
  echo "Error: ffmpeg not found at ${FFMPEG}" >&2
  exit 1
fi

echo "=== Testing FFmpeg Audio Processing ==="
echo

# 创建测试目录
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

echo "Test directory: ${TEST_DIR}"
echo

# 1. 生成测试音频（1 秒 440Hz 正弦波）
echo "1. Generating test audio..."
"${FFMPEG}" -f lavfi -i "sine=frequency=440:duration=1" -ar 44100 \
  "${TEST_DIR}/test.wav" -y >/dev/null 2>&1
echo "✓ Generated: test.wav"

# 2. 转码为 AAC
echo "2. Transcoding to AAC..."
"${FFMPEG}" -i "${TEST_DIR}/test.wav" -c:a aac -b:a 128k \
  "${TEST_DIR}/test.m4a" -y >/dev/null 2>&1
echo "✓ Transcoded to: test.m4a"

# 3. 转码为 MP3
echo "3. Transcoding to MP3..."
"${FFMPEG}" -i "${TEST_DIR}/test.wav" -c:a mp3 -b:a 192k \
  "${TEST_DIR}/test.mp3" -y >/dev/null 2>&1
echo "✓ Transcoded to: test.mp3"

# 4. 转码为 FLAC
echo "4. Transcoding to FLAC..."
"${FFMPEG}" -i "${TEST_DIR}/test.wav" -c:a flac \
  "${TEST_DIR}/test.flac" -y >/dev/null 2>&1
echo "✓ Transcoded to: test.flac"

# 5. 应用音量滤镜
echo "5. Applying volume filter..."
"${FFMPEG}" -i "${TEST_DIR}/test.wav" -af "volume=0.5" \
  "${TEST_DIR}/test_quiet.wav" -y >/dev/null 2>&1
echo "✓ Applied filter: test_quiet.wav"

# 6. 检查文件
echo
echo "Generated files:"
ls -lh "${TEST_DIR}" | grep -E '\.(wav|m4a|mp3|flac)$' | \
  awk '{print "  " $9 " (" $5 ")"}'

echo
echo "=== All Tests Passed ==="