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
      ;;
    Darwin*)
      echo "PLATFORM_TAG=macos-x64"
      echo "MAKE_JOBS=${MAKE_JOBS:-$(sysctl -n hw.ncpu)}"
      echo "ARCHIVE_FORMAT=tar.gz"
      echo "ARCHIVE_EXT=tar.gz"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "PLATFORM_TAG=windows-x64"
      echo "MAKE_JOBS=${MAKE_JOBS:-${NUMBER_OF_PROCESSORS:-1}}"
      echo "ARCHIVE_FORMAT=zip"
      echo "ARCHIVE_EXT=zip"
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
  
  # Add platform-specific options
  if [[ "${PLATFORM_TAG}" == "windows-x64" ]]; then
    configure_opts+=(
      --target-os=mingw32
      --arch=x86_64
      --enable-cross-compile
      --pkg-config=pkg-config
    )
  fi
  
  # Add codec flags from configuration
  mapfile -t codec_flags < <(build_codec_flags)
  configure_opts+=("${codec_flags[@]}")
  
  # Add extra flags if provided
  if [[ -n "${CONFIGURE_FLAGS_EXTRA}" ]]; then
    # shellcheck disable=SC2206
    local extra_flags=(${CONFIGURE_FLAGS_EXTRA})
    configure_opts+=("${extra_flags[@]}")
  fi
  
  ./configure "${configure_opts[@]}"
  
  log_info "Building FFmpeg (using ${MAKE_JOBS} jobs)..."
  make -j"${MAKE_JOBS}"
  
  log_info "Installing FFmpeg..."
  make install
  
  popd >/dev/null
  log_success "FFmpeg build completed"
}

# Create archive
create_archive() {
  local artifact_basename="ffmpeg-audio-only-${FFMPEG_VERSION}-${PLATFORM_TAG}"
  local output_path="${ARTIFACT_DIR}/${artifact_basename}.${ARCHIVE_FORMAT}"
  
  log_info "Creating ${ARCHIVE_FORMAT} archive..."
  
  case "${ARCHIVE_FORMAT}" in
    tar.gz)
      tar -C "${INSTALL_DIR}" -czf "${output_path}" .
      ;;
    zip)
      pushd "${INSTALL_DIR}" >/dev/null
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
      shasum -a 256 "${output_path}" > "${output_path}.sha256"
      ;;
    *)
      sha256sum "${output_path}" > "${output_path}.sha256"
      ;;
  esac
  
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
  create_archive
  
  log_success "Build process completed successfully!"
}

main "$@"