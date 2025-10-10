#!/usr/bin/env bash

# Audio codecs
AUDIO_DECODERS=(
  aac ac3 alac ape dca eac3 flac mp1 mp2 mp3 
  opus vorbis wavpack wmav1 wmav2
  pcm_alaw pcm_f32le pcm_mulaw pcm_s16be pcm_s16le 
  pcm_s24le pcm_s32le pcm_u8
)

AUDIO_ENCODERS=(
  aac ac3 ac3_fixed alac flac opus vorbis wavpack
  pcm_f32le pcm_s16be pcm_s16le pcm_s24le pcm_s32le pcm_u8
)

# Audio filters
AUDIO_FILTERS=(
  aformat anull aresample asetpts atempo
  channelmap channelsplit loudnorm pan volume
  adelay aecho afade amerge amix ashowinfo
  compand dynaudnorm highpass lowpass
)

# Demuxers
DEMUXERS=(
  aac ac3 aiff ape eac3 flac matroska mp3 ogg wav 
  opus mov mp4 m4a 3gp 3g2
  pcm_s16le pcm_s24le pcm_f32le
)

# Muxers
MUXERS=(
  adts ac3 aiff flac matroska mp3 ogg wav opus 
  mp4 mov ipod
)

# Parsers
PARSERS=(
  aac ac3 flac mpegaudio opus vorbis
)

# BSF (Bitstream Filters)
BSFS=(
  aac_adtstoasc
)

# Protocols
PROTOCOLS=(
  file pipe concat data
)

# Build array of configure flags
build_codec_flags() {
  local flags=()
  
  for decoder in "${AUDIO_DECODERS[@]}"; do
    flags+=("--enable-decoder=${decoder}")
  done
  
  for encoder in "${AUDIO_ENCODERS[@]}"; do
    flags+=("--enable-encoder=${encoder}")
  done
  
  for filter in "${AUDIO_FILTERS[@]}"; do
    flags+=("--enable-filter=${filter}")
  done
  
  for demuxer in "${DEMUXERS[@]}"; do
    flags+=("--enable-demuxer=${demuxer}")
  done
  
  for muxer in "${MUXERS[@]}"; do
    flags+=("--enable-muxer=${muxer}")
  done
  
  for parser in "${PARSERS[@]}"; do
    flags+=("--enable-parser=${parser}")
  done
  
  for bsf in "${BSFS[@]}"; do
    flags+=("--enable-bsf=${bsf}")
  done
  
  for protocol in "${PROTOCOLS[@]}"; do
    flags+=("--enable-protocol=${protocol}")
  done
  
  printf '%s\n' "${flags[@]}"
}