#!/usr/bin/env bash
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.2}"
WORKDIR="${WORKDIR:-$PWD}"
SRC_DIR="${WORKDIR}/ffmpeg-${FFMPEG_VERSION}"
INSTALL_DIR="${WORKDIR}/install"
ARTIFACT_DIR="${WORKDIR}/artifacts"
CONFIGURE_FLAGS_EXTRA=${CONFIGURE_FLAGS_EXTRA:-}
DOWNLOAD_RETRIES=${DOWNLOAD_RETRIES:-5}
DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT:-30}
CURL_OPTS=(
  --fail
  --location
  --retry "${DOWNLOAD_RETRIES}"
  --retry-all-errors
  --retry-delay 5
  --connect-timeout "${DOWNLOAD_TIMEOUT}"
  --max-time $((DOWNLOAD_TIMEOUT * (DOWNLOAD_RETRIES + 1)))
)

OS_NAME=$(uname -s)
case "$OS_NAME" in
  Linux*)
    PLATFORM_TAG="linux-x64"
    MAKE_JOBS=${MAKE_JOBS:-$(nproc)}
    ARCHIVE_FORMAT="tar.gz"
    ARCHIVE_CMD=(tar -C "${INSTALL_DIR}" -czf)
    CHECKSUM_CMD=(sha256sum)
    ;;
  Darwin*)
    PLATFORM_TAG="macos-x64"
    MAKE_JOBS=${MAKE_JOBS:-$(sysctl -n hw.ncpu)}
    ARCHIVE_FORMAT="tar.gz"
    ARCHIVE_CMD=(tar -C "${INSTALL_DIR}" -czf)
    CHECKSUM_CMD=(shasum -a 256)
    ;;
  MINGW*|MSYS*|CYGWIN*)
    PLATFORM_TAG="windows-x64"
    MAKE_JOBS=${MAKE_JOBS:-${NUMBER_OF_PROCESSORS:-1}}
    ARCHIVE_FORMAT="zip"
    ARCHIVE_CMD=(zip -r)
    CHECKSUM_CMD=(sha256sum)
    ;;
  *)
    echo "Unsupported platform: ${OS_NAME}" >&2
    exit 1
    ;;
esac

rm -rf "${SRC_DIR}" "${INSTALL_DIR}" "${ARTIFACT_DIR}"
mkdir -p "${WORKDIR}" "${INSTALL_DIR}" "${ARTIFACT_DIR}"

ARCHIVE_PATH="${WORKDIR}/ffmpeg-src"
rm -f "${ARCHIVE_PATH}.tar.xz" "${ARCHIVE_PATH}.tar.gz"

download_sources=(
  "tar.xz|https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
  "tar.xz|https://download.ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
  "tar.gz|https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz"
)

ARCHIVE_EXT=""
ARCHIVE_FILE=""
DOWNLOAD_SUCCESS="false"

for entry in "${download_sources[@]}"; do
  IFS='|' read -r ext url <<<"${entry}"
  ARCHIVE_FILE="${ARCHIVE_PATH}.${ext}"
  echo "Attempting download: ${url}" >&2
  if curl "${CURL_OPTS[@]}" -o "${ARCHIVE_FILE}" "${url}"; then
    ARCHIVE_EXT="${ext}"
    DOWNLOAD_SUCCESS="true"
    break
  else
    echo "Download failed for ${url}, trying next mirror..." >&2
  fi
done

if [[ "${DOWNLOAD_SUCCESS}" != "true" ]]; then
  echo "Failed to download FFmpeg ${FFMPEG_VERSION} from all mirrors." >&2
  exit 1
fi

case "${ARCHIVE_EXT}" in
  tar.xz)
    tar -xf "${ARCHIVE_FILE}" -C "${WORKDIR}"
    ;;
  tar.gz)
    tar -xzf "${ARCHIVE_FILE}" -C "${WORKDIR}"
    # GitHub archive name differs, adjust source directory
    SRC_DIR="${WORKDIR}/FFmpeg-n${FFMPEG_VERSION}"
    ;;
  *)
    echo "Unsupported archive extension: ${ARCHIVE_EXT}" >&2
    exit 1
    ;;
esac

pushd "${SRC_DIR}" >/dev/null

CONFIGURE_OPTS=(
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
  --enable-filter=aformat,anull,aresample,asetpts,atempo,channelmap,channelsplit,loudnorm,pan,volume
  --enable-protocol=file,pipe,concat,data
  --enable-demuxer=aac,ac3,flac,matroska,mp3,ogg,wav,opus,aiff,pcm_s16le,pcm_s24le,mov,mp4,m4a,3gp,3g2
  --enable-muxer=adts,flac,matroska,mp3,ogg,wav,aiff,opus,mp4,mov
  --enable-parser=aac,ac3,flac,mpegaudio,opus,vorbis
  --enable-decoder=aac,ac3,flac,mp3,opus,vorbis,pcm_alaw,pcm_f32le,pcm_mulaw,pcm_s16be,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8
  --enable-encoder=aac,ac3_fixed,flac,pcm_f32le,pcm_s16be,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8
  --enable-bsf=aac_adtstoasc
)

if [[ "${PLATFORM_TAG}" == "windows-x64" ]]; then
  CONFIGURE_OPTS+=(
    --target-os=mingw32
    --arch=x86_64
    --enable-cross-compile
    --pkg-config=pkg-config
  )
fi

if [[ -n "${CONFIGURE_FLAGS_EXTRA}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FLAGS=(${CONFIGURE_FLAGS_EXTRA})
  CONFIGURE_OPTS+=("${EXTRA_FLAGS[@]}")
fi

./configure "${CONFIGURE_OPTS[@]}"

make -j"${MAKE_JOBS}"
make install

popd >/dev/null

ARTIFACT_BASENAME="ffmpeg-audio-only-${FFMPEG_VERSION}-${PLATFORM_TAG}"
OUTPUT_PATH="${ARTIFACT_DIR}/${ARTIFACT_BASENAME}.${ARCHIVE_FORMAT}"

case "${ARCHIVE_FORMAT}" in
  tar.gz)
    "${ARCHIVE_CMD[@]}" "${OUTPUT_PATH}" .
    ;;
  zip)
    pushd "${INSTALL_DIR}" >/dev/null
    "${ARCHIVE_CMD[@]}" "${OUTPUT_PATH}" .
    popd >/dev/null
    ;;
  *)
    echo "Unsupported archive format: ${ARCHIVE_FORMAT}" >&2
    exit 1
    ;;
esac

"${CHECKSUM_CMD[@]}" "${OUTPUT_PATH}" > "${OUTPUT_PATH}.sha256"

echo "Artifacts generated at ${ARTIFACT_DIR}: ${ARTIFACT_BASENAME}.${ARCHIVE_FORMAT}"