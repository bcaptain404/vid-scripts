#!/bin/bash
# audio-cleanup.sh - Live music quick-cleaning utility

set -e

show_help() {
  echo "Usage: $0 input.wav|input.mp4 [options]"
  echo ""
  echo "Options:"
  echo "  --normalize          Apply basic peak normalization"
  echo "  --normalize-extra    Apply LUFS loudness normalization"
  echo "  --compress           Light compression"
  echo "  --compress-extra     Aggressive compression"
  echo "  --eq                 Cut sub-bass (<80Hz) & high fizz (>12kHz)"
  echo "  --eq-extra           Slight midrange boost (1-5kHz)"
  echo "  --no-vid             Don’t reattach video stream"
  echo "  --mp3                Output to MP3 (implies --no-vid)"
  echo "  --all                Do all: EQ → Compress → Normalize"
  echo "  --out=FILE.xxx       Set output filename"
  echo "  --overwrite          Allow overwrite of existing output"
  echo "  --verbose            Print progress"
  echo "  --debug              Show full ffmpeg commands"
  echo "  --dry-run            Simulate execution without making changes"
  echo "  --preset=TYPE        Use a preset: vocals, inst, music, podcast, audience, bar, loud-bar"
  echo "  --auto               Placeholder for future intelligent analysis"
  echo "  --install-deps       Installs ffmpeg via apt"
  echo ""
  echo "Default output: output_cleaned.wav or output_cleaned.mp3"
}

install_deps() {
  sudo apt update
  sudo apt install -y ffmpeg
  echo "✅ Dependencies installed."
  exit 0
}

# --- Vars ---
INPUT=""
OUTPUT_TYPE="wav"
NO_VID=0
DO_ALL=0
DEBUG=0
VERBOSE=0
OVERWRITE=0
DRY_RUN=0
AUTO=0
PRESET=""
OUTPUT=""
ORDERED_FILTERS=()

# --- Parse args ---
for arg in "$@"; do
  case $arg in
    --install-deps) install_deps ;;
    --normalize) ORDERED_FILTERS+=("dynaudnorm") ;;
    --normalize-extra) ORDERED_FILTERS+=("loudnorm=I=-14:TP=-1.5:LRA=11") ;;
    --compress) ORDERED_FILTERS+=("acompressor=threshold=-18dB:ratio=3:attack=20:release=250") ;;
    --compress-extra) ORDERED_FILTERS+=("acompressor=threshold=-24dB:ratio=6:attack=5:release=100") ;;
    --eq) ORDERED_FILTERS+=("highpass=f=80" "lowpass=f=12000") ;;
    --eq-extra) ORDERED_FILTERS+=("equalizer=f=2000:t=q:w=1:g=3") ;;
    --no-vid) NO_VID=1 ;;
    --mp3) OUTPUT_TYPE="mp3"; NO_VID=1 ;;
    --overwrite) OVERWRITE=1 ;;
    --verbose) VERBOSE=1 ;;
    --debug) DEBUG=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --auto) AUTO=1 ;;
    --all)
      ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" \
                       "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" \
                       "dynaudnorm")
      DO_ALL=1
      ;;
    --preset=*) PRESET="${arg#--preset=}" ;;
    --out=*) OUTPUT="${arg#--out=}" ;;
    *.wav|*.mp4|*.mov|*.mkv|*.flac) INPUT="$arg" ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "❌ Unknown argument: $arg"; show_help; exit 1 ;;
  esac
done

# --- Presets ---
if [[ -n "$PRESET" ]]; then
  case "$PRESET" in
    vocals) ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "equalizer=f=2000:t=q:w=1:g=3" "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" "dynaudnorm") ;;
    inst)   ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" "dynaudnorm") ;;
    music)  ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "equalizer=f=2000:t=q:w=1:g=3" "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" "dynaudnorm") ;;
    podcast) ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "acompressor=threshold=-24dB:ratio=6:attack=5:release=100" "loudnorm=I=-14:TP=-1.5:LRA=11") ;;
    audience) ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "acompressor=threshold=-24dB:ratio=6:attack=5:release=100") ;;
    bar)     ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "acompressor=threshold=-24dB:ratio=6:attack=5:release=100" "dynaudnorm") ;;
    loud-bar) ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "equalizer=f=2000:t=q:w=1:g=3" "acompressor=threshold=-24dB:ratio=6:attack=5:release=100" "loudnorm=I=-14:TP=-1.5:LRA=11") ;;
    *) echo "❌ Unknown preset: $PRESET"; exit 1 ;;
  esac
fi

# --- Auto analysis (placeholder) ---
if [[ "$AUTO" -eq 1 ]]; then
  echo "⚠️  --auto not implemented yet. Smarter than a monkey? Maybe. Smarter than an FFT? Not yet."
  exit 1
fi

# --- Validate ---
if [[ -z "$INPUT" ]]; then
  echo "❌ No input file specified."
  show_help
  exit 1
fi

if [[ ${#ORDERED_FILTERS[@]} -eq 0 ]]; then
  echo "❌ No processing steps specified."
  show_help
  exit 1
fi

OUT_EXT="$OUTPUT_TYPE"
[[ -z "$OUTPUT" ]] && OUTPUT="output_cleaned.$OUT_EXT"

if [[ -e "$OUTPUT" && $OVERWRITE -ne 1 ]]; then
  echo "❌ Output file '$OUTPUT' exists. Use --overwrite to override."
  exit 1
fi

[[ $VERBOSE -eq 1 ]] && echo "🎧 Processing $INPUT → $OUTPUT"

FILTER_CHAIN=$(IFS=, ; echo "${ORDERED_FILTERS[*]}")
[[ $DEBUG -eq 1 ]] && echo "🔍 FFmpeg audio filters: $FILTER_CHAIN"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "🧪 Dry run mode active:"
  echo "Input: $INPUT"
  echo "Output: $OUTPUT"
  echo "Filters: $FILTER_CHAIN"
  echo "Video retained: $((1 - NO_VID))"
  echo "Output type: $OUTPUT_TYPE"
  exit 0
fi

TEMP_AUDIO="temp_audio.wav"
FILTERED_AUDIO="filtered_audio.wav"

[[ $VERBOSE -eq 1 ]] && echo "🔄 Extracting audio..."
ffmpeg -y -i "$INPUT" -vn -acodec pcm_s16le -ar 44100 -ac 2 "$TEMP_AUDIO" ${DEBUG:+-loglevel debug}

[[ $VERBOSE -eq 1 ]] && echo "🎛️  Applying filters..."
ffmpeg -y -i "$TEMP_AUDIO" -af "$FILTER_CHAIN" "$FILTERED_AUDIO" ${DEBUG:+-loglevel debug}

[[ $VERBOSE -eq 1 ]] && echo "💾 Writing output..."
if [[ "$OUTPUT_TYPE" == "mp3" ]]; then
  ffmpeg -y -i "$FILTERED_AUDIO" -codec:a libmp3lame -qscale:a 2 "$OUTPUT" ${DEBUG:+-loglevel debug}
elif [[ "$NO_VID" -eq 1 ]]; then
  mv "$FILTERED_AUDIO" "$OUTPUT"
else
  ffmpeg -y -i "$INPUT" -i "$FILTERED_AUDIO" -c:v copy -map 0:v:0 -map 1:a:0 -shortest "$OUTPUT" ${DEBUG:+-loglevel debug}
fi

rm -f "$TEMP_AUDIO" "$FILTERED_AUDIO"
[[ $VERBOSE -eq 1 ]] && echo "✅ Done. Output saved to $OUTPUT"
