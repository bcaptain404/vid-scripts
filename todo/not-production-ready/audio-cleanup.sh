#!/bin/bash
# audio-cleanup.sh - Smarter-than-your-ex music/audio fixer

set -e

show_help() {
  echo "Usage: $0 input.wav|input.mp4 [options]"
  echo ""
  echo "Options:"
  echo "  --normalize             Apply basic peak normalization"
  echo "  --normalize-extra       LUFS loudness normalization"
  echo "  --compress              Light compression"
  echo "  --compress-extra        Aggressive compression"
  echo "  --eq                    Cut sub-bass (<80Hz) & fizz (>12kHz)"
  echo "  --eq-extra              Slight midrange boost"
  echo "  --preset=TYPE           Preset: vocals, inst, music, podcast, audience, bar, loud-bar"
  echo "  --all                   EQ -> Compress -> Normalize"
  echo "  --auto                  Smart AF auto-detect via Python (requires --install-deps-full)"
  echo "  --dry-run               Show what would be done"
  echo "  --mp3                   Output as MP3 (implies --no-vid)"
  echo "  --no-vid                Skip video reattachment"
  echo "  --out=filename.ext      Custom output filename"
  echo "  --overwrite             Allow overwriting existing output"
  echo "  --verbose               Print what's happening"
  echo "  --debug                 Print ffmpeg commands"
  echo "  --install-deps          Install ffmpeg"
  echo "  --install-deps-full     Install full stack (ffmpeg, python3, pip, numpy, librosa)"
  echo "  -h, --help              Show this help"
  echo ""
  echo "Smart auto mode uses Python and librosa for real signal analysis."
  echo ""
}

install_deps() {
  sudo apt update && sudo apt install -y ffmpeg
  echo "✅ Basic dependencies installed."
  exit 0
}

install_deps_full() {
  sudo apt update && sudo apt install -y ffmpeg python3 python3-pip
  pip3 install numpy librosa soundfile --break-system-packages
  echo "✅ Full dependencies installed (ffmpeg + Python + librosa)"
  exit 0
}

smart_auto_detect() {
  python3 - "$1" <<'EOF'
import sys
import librosa
import numpy as np

path = sys.argv[1]
y, sr = librosa.load(path, sr=None)
rms = np.mean(librosa.feature.rms(y=y))
zcr = np.mean(librosa.feature.zero_crossing_rate(y))
centroid = np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))

print("# Smart-AF Auto Analysis:")
print(f"RMS loudness: {rms:.5f}")
print(f"Zero-crossing rate: {zcr:.5f}")
print(f"Spectral centroid: {centroid:.2f} Hz")

if rms < 0.02:
    print("--compress-extra")
elif rms < 0.04:
    print("--compress")
else:
    print("--no-compression-needed")

if centroid < 1500:
    print("--eq-extra")
else:
    print("--eq")

print("--normalize")
EOF
  exit 0
}

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

for arg in "$@"; do
  case $arg in
    --install-deps) install_deps ;;
    --install-deps-full) install_deps_full ;;
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
    --all) ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" "dynaudnorm") ;;
    --preset=*) PRESET="${arg#--preset=}" ;;
    --out=*) OUTPUT="${arg#--out=}" ;;
    *.wav|*.mp4|*.mov|*.mkv|*.flac) INPUT="$arg" ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "❌ Unknown argument: $arg"; show_help; exit 1 ;;
  esac
done

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

if [[ "$AUTO" -eq 1 ]]; then
  smart_auto_detect "$INPUT"
  exit 0
fi

if [[ -z "$INPUT" ]]; then echo "❌ No input file specified."; show_help; exit 1; fi
if [[ ${#ORDERED_FILTERS[@]} -eq 0 ]]; then echo "❌ No processing steps specified."; show_help; exit 1; fi

OUT_EXT="$OUTPUT_TYPE"
[[ -z "$OUTPUT" ]] && OUTPUT="output_cleaned.$OUT_EXT"

if [[ -e "$OUTPUT" && $OVERWRITE -ne 1 ]]; then echo "❌ Output file '$OUTPUT' exists. Use --overwrite to override."; exit 1; fi
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
