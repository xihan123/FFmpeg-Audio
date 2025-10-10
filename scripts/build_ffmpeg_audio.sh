#!/usr/bin/env bash
set -euo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/audio_config.sh"

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.2}"
WORKDIR="${WORKDIR:-$PWD}"
SRC_DIR="${WORKDIR}/ffmpeg-${FFMPEG_VERSION}"
INSTALL_DIR="${WORKDIR}/install"
ARTIFACT_DIR="${WORKDIR}/artifacts"
CONFIGURE_FLAGS_EXTRA=${CONFIGURE_FLAGS_EXTRA:-}
DOWNLOAD_RETRIES=${DOWNLOAD_RETRIES:-5}
DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT:-30}

# Logging functions
log_info() { echo "[INFO] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*" >&2; }

CURL_OPTS=(
  --fail
  --location
  --retry "${DOWNLOAD_RETRIES}"
  --retry-all-errors
  --retry-delay 5
  --connect-timeout "${DOWNLOAD_TIMEOUT}"
  --max-time $((DOWNLOAD_TIMEOUT * (DOWNLOAD_RETRIES + 1)))
  --progress-bar
)

# Platform detection
detect_platform() {
  local os_name
  os_name=$(uname -s)
  
  case "$os_name" in
    Linux*)
      echo "PLATFORM_TAG=linux-x64"
      echo "MAKE_JOBS=${MAKE_JOBS:-$(nproc)}"
      echo "ARCHIVE_FORMAT=tar.gz"
      echo "ARCHIVE_EXT=tar.gz"
      echo "ENABLE_STATIC=yes"
      ;;
    Darwin*)
      echo "PLATFORM_TAG=macos-x64"
      echo "MAKE_JOBS=${MAKE_JOBS:-$(sysctl -n hw.ncpu)}"
      echo "ARCHIVE_FORMAT=tar.gz"
      echo "ARCHIVE_EXT=tar.gz"
      echo "ENABLE_STATIC=yes"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "PLATFORM_TAG=windows-x64"
      echo "MAKE_JOBS=${MAKE_JOBS:-${NUMBER_OF_PROCESSORS:-1}}"
      echo "ARCHIVE_FORMAT=zip"
      echo "ARCHIVE_EXT=zip"
      echo "ENABLE_STATIC=yes"
      ;;
    *)
      log_error "Unsupported platform: ${os_name}"
      exit 1
      ;;
  esac
}

# Load platform variables
eval "$(detect_platform)"

log_info "Building for platform: ${PLATFORM_TAG}"
log_info "Using ${MAKE_JOBS} parallel jobs"

# Cleanup
cleanup_dirs() {
  log_info "Cleaning up previous build artifacts..."
  rm -rf "${SRC_DIR}" "${INSTALL_DIR}" "${ARTIFACT_DIR}"
  mkdir -p "${WORKDIR}" "${INSTALL_DIR}" "${ARTIFACT_DIR}"
}

# Download source
download_ffmpeg_source() {
  local archive_path="${WORKDIR}/ffmpeg-src"
  rm -f "${archive_path}.tar.xz" "${archive_path}.tar.gz"
  
  local download_sources=(
    "tar.xz|https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    "tar.xz|https://download.ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    "tar.gz|https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz"
  )
  
  local archive_ext=""
  local archive_file=""
  local download_success="false"
  
  for entry in "${download_sources[@]}"; do
    IFS='|' read -r ext url <<<"${entry}"
    archive_file="${archive_path}.${ext}"
    log_info "Attempting download: ${url}"
    
    if curl "${CURL_OPTS[@]}" -o "${archive_file}" "${url}"; then
      archive_ext="${ext}"
      download_success="true"
      log_success "Downloaded from ${url}"
      break
    else
      log_error "Download failed for ${url}, trying next mirror..."
    fi
  done
  
  if [[ "${download_success}" != "true" ]]; then
    log_error "Failed to download FFmpeg ${FFMPEG_VERSION} from all mirrors."
    exit 1
  fi
  
  log_info "Extracting source archive..."
  case "${archive_ext}" in
    tar.xz)
      tar -xf "${archive_file}" -C "${WORKDIR}"
      ;;
    tar.gz)
      tar -xzf "${archive_file}" -C "${WORKDIR}"
      SRC_DIR="${WORKDIR}/FFmpeg-n${FFMPEG_VERSION}"
      ;;
    *)
      log_error "Unsupported archive extension: ${archive_ext}"
      exit 1
      ;;
  esac
  
  log_success "Source extracted to ${SRC_DIR}"
}

# Configure and build
build_ffmpeg() {
  pushd "${SRC_DIR}" >/dev/null
  
  log_info "Configuring FFmpeg with audio-only settings..."
  
  # Base configuration
  local configure_opts=(
    "--prefix=${INSTALL_DIR}"
    --disable-debug
    --disable-doc
    --enable-ffmpeg
    --enable-ffprobe
    --disable-ffplay
    --disable-avdevice
    --disable-swscale
    --disable-network
    --disable-everything
    --enable-swresample
    --enable-avfilter
  )
  
  # Static linking configuration
  if [[ "${ENABLE_STATIC}" == "yes" ]]; then
    configure_opts+=(
      --enable-static
      --disable-shared
      --pkg-config-flags="--static"
    )
    log_info "Enabling static linking"
  fi
  
  # Add platform-specific options
  case "${PLATFORM_TAG}" in
    windows-x64)
      configure_opts+=(
        --target-os=mingw32
        --arch=x86_64
        --enable-cross-compile
        --pkg-config=pkg-config
        --extra-cflags="-static"
        --extra-ldflags="-static"
      )
      ;;
    linux-x64)
      configure_opts+=(
        --extra-ldexeflags="-static"
      )
      ;;
    macos-x64)
      # macOS 不完全支持静态链接，但我们可以最小化动态依赖
      configure_opts+=(
        --extra-ldflags="-Wl,-dead_strip"
      )
      ;;
  esac
  
  # Add codec flags from configuration
  # Use a while loop instead of mapfile for Bash 3.x compatibility (macOS)
  local codec_flags=()
  while IFS= read -r line; do
    codec_flags+=("$line")
  done < <(build_codec_flags)
  configure_opts+=("${codec_flags[@]}")
  
  # Add extra flags if provided
  if [[ -n "${CONFIGURE_FLAGS_EXTRA}" ]]; then
    # shellcheck disable=SC2206
    local extra_flags=(${CONFIGURE_FLAGS_EXTRA})
    configure_opts+=("${extra_flags[@]}")
  fi
  
  log_info "Configure options:"
  printf '%s\n' "${configure_opts[@]}" | sed 's/^/  /'
  
  ./configure "${configure_opts[@]}"
  
  log_info "Building FFmpeg (using ${MAKE_JOBS} jobs)..."
  make -j"${MAKE_JOBS}"
  
  log_info "Installing FFmpeg..."
  make install
  
  # Strip binaries to reduce size
  if command -v strip &>/dev/null; then
    log_info "Stripping binaries..."
    if [[ "${PLATFORM_TAG}" == "windows-x64" ]]; then
      strip "${INSTALL_DIR}/bin/ffmpeg.exe" || true
      strip "${INSTALL_DIR}/bin/ffprobe.exe" || true
    else
      strip "${INSTALL_DIR}/bin/ffmpeg" || true
      strip "${INSTALL_DIR}/bin/ffprobe" || true
    fi
  fi
  
  popd >/dev/null
  log_success "FFmpeg build completed"
}

# Verify binaries
verify_binaries() {
  log_info "Verifying built binaries..."
  
  local ffmpeg_bin="${INSTALL_DIR}/bin/ffmpeg"
  local ffprobe_bin="${INSTALL_DIR}/bin/ffprobe"
  
  if [[ "${PLATFORM_TAG}" == "windows-x64" ]]; then
    ffmpeg_bin="${ffmpeg_bin}.exe"
    ffprobe_bin="${ffprobe_bin}.exe"
  fi
  
  if [[ ! -f "${ffmpeg_bin}" ]]; then
    log_error "ffmpeg binary not found at ${ffmpeg_bin}"
    exit 1
  fi
  
  if [[ ! -f "${ffprobe_bin}" ]]; then
    log_error "ffprobe binary not found at ${ffprobe_bin}"
    exit 1
  fi
  
  log_info "Testing ffmpeg binary..."
  if "${ffmpeg_bin}" -version >/dev/null 2>&1; then
    log_success "ffmpeg binary works"
  else
    log_error "ffmpeg binary failed to execute"
    # Show dependencies for debugging
    case "${PLATFORM_TAG}" in
      linux-x64)
        ldd "${ffmpeg_bin}" || true
        ;;
      macos-x64)
        otool -L "${ffmpeg_bin}" || true
        ;;
      windows-x64)
        # Windows 下显示 DLL 依赖（如果有 objdump）
        objdump -p "${ffmpeg_bin}" | grep "DLL Name:" || true
        ;;
    esac
    exit 1
  fi
  
  log_info "Testing ffprobe binary..."
  if "${ffprobe_bin}" -version >/dev/null 2>&1; then
    log_success "ffprobe binary works"
  else
    log_error "ffprobe binary failed to execute"
    exit 1
  fi
  
  # Display binary info
  log_info "Binary information:"
  log_info "  ffmpeg size: $(du -h "${ffmpeg_bin}" | cut -f1)"
  log_info "  ffprobe size: $(du -h "${ffprobe_bin}" | cut -f1)"
}

# Create archive with proper structure
create_archive() {
  local artifact_basename="ffmpeg-audio-only-${FFMPEG_VERSION}-${PLATFORM_TAG}"
  local output_path="${ARTIFACT_DIR}/${artifact_basename}.${ARCHIVE_FORMAT}"
  local temp_dir="${WORKDIR}/package"
  
  log_info "Preparing package structure..."
  rm -rf "${temp_dir}"
  mkdir -p "${temp_dir}/bin"
  
  # Copy binaries
  if [[ "${PLATFORM_TAG}" == "windows-x64" ]]; then
    cp "${INSTALL_DIR}/bin/ffmpeg.exe" "${temp_dir}/bin/"
    cp "${INSTALL_DIR}/bin/ffprobe.exe" "${temp_dir}/bin/"
  else
    cp "${INSTALL_DIR}/bin/ffmpeg" "${temp_dir}/bin/"
    cp "${INSTALL_DIR}/bin/ffprobe" "${temp_dir}/bin/"
  fi
  
  # Create README
  cat > "${temp_dir}/README.txt" <<'EOF'
FFmpeg Audio-Only Build
=======================

This is a minimal FFmpeg build containing only audio processing capabilities.

Contents:
- bin/ffmpeg   : Audio transcoding tool
- bin/ffprobe  : Audio analysis tool

Usage Examples:
  # Convert WAV to AAC
  ./bin/ffmpeg -i input.wav -c:a aac -b:a 192k output.m4a
  
  # Convert MP3 to FLAC
  ./bin/ffmpeg -i input.mp3 output.flac
  
  # Probe audio file
  ./bin/ffprobe input.mp3
  
  # Adjust volume
  ./bin/ffmpeg -i input.mp3 -af "volume=1.5" output.mp3

For more information, visit: https://ffmpeg.org/documentation.html
EOF
  
  log_info "Creating ${ARCHIVE_FORMAT} archive..."
  
  case "${ARCHIVE_FORMAT}" in
    tar.gz)
      tar -C "${temp_dir}" -czf "${output_path}" .
      ;;
    zip)
      pushd "${temp_dir}" >/dev/null
      zip -r "${output_path}" .
      popd >/dev/null
      ;;
    *)
      log_error "Unsupported archive format: ${ARCHIVE_FORMAT}"
      exit 1
      ;;
  esac
  
  log_info "Generating SHA256 checksum..."
  case "${PLATFORM_TAG}" in
    *darwin*|*macos*)
      shasum -a 256 "${output_path}" | tee "${output_path}.sha256"
      ;;
    *)
      sha256sum "${output_path}" | tee "${output_path}.sha256"
      ;;
  esac
  
  # Cleanup temp directory
  rm -rf "${temp_dir}"
  
  log_success "Artifacts generated at ${ARTIFACT_DIR}:"
  log_success "  - ${artifact_basename}.${ARCHIVE_FORMAT}"
  log_success "  - ${artifact_basename}.${ARCHIVE_FORMAT}.sha256"
}

# Main execution
main() {
  log_info "Starting FFmpeg audio-only build"
  log_info "Version: ${FFMPEG_VERSION}"
  log_info "Platform: ${PLATFORM_TAG}"
  
  cleanup_dirs
  download_ffmpeg_source
  build_ffmpeg
  verify_binaries
  create_archive
  
  log_success "Build process completed successfully!"
}

main "$@"