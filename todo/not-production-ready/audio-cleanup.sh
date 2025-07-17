#!/bin/bash
# audio-cleanup.sh - Quick & dirty audio processing script for live music

set -e

show_help() {
  echo "Usage: $0 input.wav|input.mp4 [options]"
  echo ""
  echo "Options:"
  echo "  --normalize          Apply basic peak normalization"
  echo "  --normalize-extra    Apply loudness normalization (LUFS)"
  echo "  --compress           Apply light compression"
  echo "  --compress-extra     Apply aggressive compression"
  echo "  --eq                 Cut sub-bass (<80Hz) and high fizz (>12kHz)"
  echo "  --eq-extra           Add slight midrange boost (1-5kHz)"
  echo "  --no-vid             Do not include original video (default: preserve it if input is video)"
  echo "  --mp3                Output to MP3 format (implies --no-vid)"
  echo "  --all                Do all basic cleanup (eq → compress → normalize)"
  echo "  --install-deps       Install ffmpeg and required packages via apt"
  echo ""
  echo "Output will be saved as output_cleaned.wav or output_cleaned.mp3"
}

# Dependencies
install_deps() {
  sudo apt update
  sudo apt install -y ffmpeg
  echo "✅ Dependencies installed."
  exit 0
}

# Initialize flags and arrays
INPUT=""
OUTPUT_TYPE="wav"
NO_VID=0
DO_ALL=0
ORDERED_FILTERS=()

# Parse args
for arg in "$@"; do
  case $arg in
    --install-deps) install_deps ;;
    *.wav|*.mp4|*.mov|*.mkv|*.flac) INPUT="$arg" ;;
    --normalize) ORDERED_FILTERS+=("dynaudnorm") ;;
    --normalize-extra) ORDERED_FILTERS+=("loudnorm=I=-14:TP=-1.5:LRA=11") ;;
    --compress) ORDERED_FILTERS+=("acompressor=threshold=-18dB:ratio=3:attack=20:release=250") ;;
    --compress-extra) ORDERED_FILTERS+=("acompressor=threshold=-24dB:ratio=6:attack=5:release=100") ;;
    --eq) ORDERED_FILTERS+=("highpass=f=80" "lowpass=f=12000") ;;
    --eq-extra) ORDERED_FILTERS+=("equalizer=f=2000:t=q:w=1:g=3") ;;
    --no-vid) NO_VID=1 ;;
    --mp3) OUTPUT_TYPE="mp3"; NO_VID=1 ;;
    --all)
      ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" \
                       "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" \
                       "dynaudnorm")
      DO_ALL=1
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
  esac
done

# Sanity checks
if [[ -z "$INPUT" ]]; then
  echo "❌ No input file specified."
  show_help
  exit 1
fi

if [[ ${#ORDERED_FILTERS[@]} -eq 0 ]]; then
  echo "❌ No filters specified."
  show_help
  exit 1
fi

# Construct filter string
FILTER_CHAIN=$(IFS=, ; echo "${ORDERED_FILTERS[*]}")

# Derive output filename
OUT_EXT="$OUTPUT_TYPE"
OUTPUT="output_cleaned.$OUT_EXT"
TEMP_AUDIO="temp_audio.wav"

# Extract and process audio
ffmpeg -y -i "$INPUT" -vn -acodec pcm_s16le -ar 44100 -ac 2 "$TEMP_AUDIO"
ffmpeg -y -i "$TEMP_AUDIO" -af "$FILTER_CHAIN" "filtered_audio.wav"

# Recombine or convert
if [[ "$OUTPUT_TYPE" == "mp3" ]]; then
  ffmpeg -y -i "filtered_audio.wav" -codec:a libmp3lame -qscale:a 2 "$OUTPUT"
elif [[ "$NO_VID" -eq 1 ]]; then
  mv "filtered_audio.wav" "$OUTPUT"
else
  ffmpeg -y -i "$INPUT" -i "filtered_audio.wav" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "$OUTPUT"
fi

# Cleanup
rm -f "$TEMP_AUDIO" "filtered_audio.wav"
echo "✅ Output saved as $OUTPUT"
