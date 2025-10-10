#!/usr/bin/env bash
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:-6.1.1}"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
WORKDIR="${WORKDIR:-$PWD}"
SRC_DIR="${WORKDIR}/ffmpeg-${FFMPEG_VERSION}"
INSTALL_DIR="${WORKDIR}/install"
ARTIFACT_DIR="${WORKDIR}/artifacts"
CONFIGURE_FLAGS_EXTRA=${CONFIGURE_FLAGS_EXTRA:-}

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

curl -fsSL -o "${WORKDIR}/ffmpeg.tar.xz" "${SOURCE_URL}"
tar -xf "${WORKDIR}/ffmpeg.tar.xz" -C "${WORKDIR}"

pushd "${SRC_DIR}" >/dev/null

CONFIGURE_OPTS=(
  "--prefix=${INSTALL_DIR}"
  --disable-debug
  --disable-doc
  --enable-small
  --disable-programs
  --enable-ffmpeg
  --enable-ffprobe
  --disable-ffplay
  --disable-avdevice
  --disable-swscale
  --disable-postproc
  --disable-network
  --disable-everything
  --enable-swresample
  --enable-avfilter
  --enable-filter=aformat,anull,aresample,asetpts,atempo,channelmap,channelsplit,loudnorm,pan,volume
  --enable-protocol=file,pipe,concat
  --enable-demuxer=aac,ac3,flac,matroska,mp3,ogg,wav,opus
  --enable-muxer=adts,flac,matroska,mp3,ogg,wav
  --enable-parser=aac,ac3,flac,mpegaudio,opus,vorbis
  --enable-decoder=aac,ac3,flac,mp3,opus,vorbis,pcm_alaw,pcm_f32le,pcm_mulaw,pcm_s16be,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8
  --enable-encoder=aac,ac3_fixed,flac,pcm_f32le,pcm_s16be,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8
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