#!/bin/bash
# audio-cleanup.sh - Quick & dirty audio processing script for live music

set -e

show_help() {
  echo "Usage: $0 input.wav [options]"
  echo ""
  echo "Options:"
  echo "  --normalize          Apply basic peak normalization"
  echo "  --normalize-extra    Apply loudness normalization (LUFS)"
  echo "  --compress           Apply light compression"
  echo "  --compress-extra     Apply aggressive compression"
  echo "  --eq                 Cut sub-bass (<80Hz) and high fizz (>12kHz)"
  echo "  --eq-extra           Add slight midrange boost (1-5kHz)"
  echo "  --all                Do all basic cleanup (normalize, compress, eq)"
  echo ""
  echo "Output will be saved as output_cleaned.wav"
}

# Argument parsing
INPUT=""
NORMALIZE=0
NORM_EXTRA=0
COMPRESS=0
COMPRESS_EXTRA=0
EQ=0
EQ_EXTRA=0

for arg in "$@"; do
  case $arg in
    *.wav) INPUT="$arg" ;;
    --normalize) NORMALIZE=1 ;;
    --normalize-extra) NORM_EXTRA=1 ;;
    --compress) COMPRESS=1 ;;
    --compress-extra) COMPRESS_EXTRA=1 ;;
    --eq) EQ=1 ;;
    --eq-extra) EQ_EXTRA=1 ;;
    --all)
      NORMALIZE=1
      COMPRESS=1
      EQ=1
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo "Error: No input file specified."
  show_help
  exit 1
fi

OUTPUT="output_cleaned.wav"
FILTERS=""

# EQ filter
if [[ $EQ -eq 1 ]]; then
  FILTERS+="highpass=f=80,lowpass=f=12000"
fi
if [[ $EQ_EXTRA -eq 1 ]]; then
  FILTERS+=",equalizer=f=2000:t=q:w=1:g=3"
fi

# Compression
if [[ $COMPRESS -eq 1 ]]; then
  FILTERS+=",acompressor=threshold=-18dB:ratio=3:attack=20:release=250"
fi
if [[ $COMPRESS_EXTRA -eq 1 ]]; then
  FILTERS+=",acompressor=threshold=-24dB:ratio=6:attack=5:release=100"
fi

# Normalization
if [[ $NORMALIZE -eq 1 ]]; then
  FILTERS+=",dynaudnorm"
fi
if [[ $NORM_EXTRA -eq 1 ]]; then
  FILTERS+=",loudnorm=I=-14:TP=-1.5:LRA=11"
fi

# Strip leading comma if needed
FILTERS="${FILTERS#,}"

# Final ffmpeg command
if [[ -z "$FILTERS" ]]; then
  echo "No filters specified. Use --help for options."
  exit 1
fi

ffmpeg -y -i "$INPUT" -af "$FILTERS" "$OUTPUT"
echo "✅ Cleaned audio saved to $OUTPUT"
