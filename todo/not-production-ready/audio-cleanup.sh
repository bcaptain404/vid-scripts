#!/bin/bash
# audio-cleanup.sh - Smarter-than-your-ex music/audio fixer

set -e

# Argument containers
ARGS=()
PARAMS=()

# Separate positional args from flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --*=*) PARAMS+=("$1"); shift;;
    --*) PARAMS+=("$1"); shift;;
    -*) PARAMS+=("$1"); shift;;
    *) ARGS+=("$1"); shift;;
  esac
done

# Defaults
INPUT=""
OUTPUT_TYPE="wav"
NO_VID=0
DO_ALL=0
DEBUG=0
VERBOSE=0
OVERWRITE=0
DRY_RUN=0
PRESET=""
OUTPUT=""
AUTO_SUGGEST=0
AUTO_APPLY=0
ORDERED_FILTERS=()

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
  echo "  --auto-suggest          Smart AF analysis only (shows recommended flags)"
  echo "  --auto-apply            Smart AF full-auto (analyze + apply)"
  echo "  --dry-run               Show what would be done"
  echo "  --mp3                   Output as MP3 (implies --no-vid)"
  echo "  --no-vid                Skip video reattachment"
  echo "  --out=filename.ext      Custom output filename"
  echo "  --overwrite             Allow overwriting existing output"
  echo "  --verbose               Print what's happening"
  echo "  --debug                 Print debug stuff"
  echo "  --install-deps          Install basic dependencies"
  echo "  --install-deps-full     Install basic dependencies + Python + librosa (for --auto-*)"
  echo "  -h, --help              Show this help"
  echo ""
}

smart_auto_suggest() {
  python3 - "$INPUT" <<EOF
import librosa, sys
f = sys.argv[1]
y, sr = librosa.load(f)
rms = float(librosa.feature.rms(y=y).mean())
zcr = float(librosa.feature.zero_crossing_rate(y).mean())
centroid = float(librosa.feature.spectral_centroid(y=y, sr=sr).mean())
print(f"# Smart-AF Auto Analysis:")
print(f"RMS loudness: {rms:.5f}")
print(f"Zero-crossing rate: {zcr:.5f}")
print(f"Spectral centroid: {centroid:.2f} Hz")
if rms < 0.03: print("--normalize")
if rms > 0.3: print("--compress")
if centroid > 4000: print("--eq")
EOF
  exit 0
}

smart_auto_apply() {
  local analysis
  analysis=$(python3 - "$INPUT" <<EOF
import librosa, sys
f = sys.argv[1]
y, sr = librosa.load(f)
rms = float(librosa.feature.rms(y=y).mean())
zcr = float(librosa.feature.zero_crossing_rate(y).mean())
centroid = float(librosa.feature.spectral_centroid(y=y, sr=sr).mean())
filters = []
# ALWAYS normalize, no matter what!
filters.append("dynaudnorm")
if rms > 0.15:
    filters.append("acompressor=threshold=-18dB:ratio=3:attack=20:release=250")
if centroid > 3500:
    filters.extend(["highpass=f=80", "lowpass=f=12000"])
print("\\n".join(filters))
EOF
  )

  if [[ -z "$analysis" ]]; then
    echo "❌ No filters determined by --auto-apply"
    exit 1
  fi

  IFS=$'\n' read -r -a ORDERED_FILTERS <<<"$analysis"

}


# Parse flags
for param in "${PARAMS[@]}"; do
  case $param in
    --install-deps) sudo apt update && sudo apt install -y ffmpeg; echo "✅ Basic dependencies installed."; exit 0;;
    --install-deps-full) sudo apt update && sudo apt install -y ffmpeg python3 python3-pip; pip3 install numpy librosa soundfile --break-system-packages; echo "✅ Full dependencies installed."; exit 0;;
    --normalize) ORDERED_FILTERS+=("dynaudnorm");;
    --normalize-extra) ORDERED_FILTERS+=("loudnorm=I=-14:TP=-1.5:LRA=11");;
    --compress) ORDERED_FILTERS+=("acompressor=threshold=-18dB:ratio=3:attack=20:release=250");;
    --compress-extra) ORDERED_FILTERS+=("acompressor=threshold=-24dB:ratio=6:attack=5:release=100");;
    --eq) ORDERED_FILTERS+=("highpass=f=80" "lowpass=f=12000");;
    --eq-extra) ORDERED_FILTERS+=("equalizer=f=2000:t=q:w=1:g=3");;
    --no-vid) NO_VID=1;;
    --mp3) OUTPUT_TYPE="mp3"; NO_VID=1;;
    --overwrite) OVERWRITE=1;;
    --verbose) VERBOSE=1;;
    --debug) DEBUG=1;;
    --dry-run) DRY_RUN=1;;
    --auto-suggest) AUTO_SUGGEST=1;;
    --auto-apply) AUTO_APPLY=1;;
    --all) DO_ALL=1;;
    --preset=*) PRESET="${param#--preset=}";;
    --out=*) OUTPUT="${param#--out=}";;
    -h|--help) show_help; exit 0;;
    *) echo "❌ Unknown option: $param"; show_help; exit 1;;
  esac
done

# Assign positional input
for a in "${ARGS[@]}"; do
  case $a in
    *.wav|*.mp4|*.mov|*.mkv|*.flac) INPUT="$a";;
    *) echo "❌ Unknown input argument: $a"; show_help; exit 1;;
  esac
done

[[ -z "$INPUT" ]] && echo "❌ No input file specified." && show_help && exit 1

[[ $AUTO_SUGGEST -eq 1 ]] && smart_auto_suggest "$INPUT"
[[ $AUTO_APPLY -eq 1 ]] && smart_auto_apply "$INPUT"

# If --all was requested and no custom flags exist
if [[ $DO_ALL -eq 1 && ${#ORDERED_FILTERS[@]} -eq 0 ]]; then
  ORDERED_FILTERS=("highpass=f=80" "lowpass=f=12000" "acompressor=threshold=-18dB:ratio=3:attack=20:release=250" "dynaudnorm")
fi

# Dry run output
[[ $DRY_RUN -eq 1 ]] && {
  echo "🎧 Input: $INPUT"
  echo "📤 Output: ${OUTPUT:-[autogen]}"
  echo "⚙️ Filters to apply:"
  for f in "${ORDERED_FILTERS[@]}"; do echo "  - $f"; done
  exit 0
}

# Determine output
BASENAME="${INPUT%.*}"
EXT="${OUTPUT_TYPE}"
[[ -z "$OUTPUT" ]] && OUTPUT="${BASENAME}_cleaned.${EXT}"
[[ -f "$OUTPUT" && $OVERWRITE -ne 1 ]] && echo "❌ Output file '$OUTPUT' exists. Use --overwrite." && exit 1

FILTER_CHAIN=$(IFS=","; echo "${ORDERED_FILTERS[*]}")
[[ $VERBOSE -eq 1 ]] && echo "🔧 Filter chain: $FILTER_CHAIN"


echo "INPUT: $INPUT"
echo "TEMP_AUDIO: $TEMP_AUDIO"
echo "FILTER_CHAIN: $FILTER_CHAIN"
echo "TEMP_PROCESSED: $TEMP_PROCESSED"
echo "OUTPUT: $OUTPUT"


TEMP_AUDIO="/tmp/audio_$$.wav"
ffmpeg -y -i "$INPUT" -vn -acodec pcm_s16le -ar 44100 "$TEMP_AUDIO"

TEMP_PROCESSED="/tmp/processed_$$.wav"
ffmpeg -y -i "$TEMP_AUDIO" -af "$FILTER_CHAIN" "$TEMP_PROCESSED"

# Handle reattachment
if [[ $NO_VID -eq 1 ]]; then
  ffmpeg -y -i "$TEMP_PROCESSED" "$OUTPUT"
else
  ffmpeg -y -i "$INPUT" -i "$TEMP_PROCESSED" -map 0:v -map 1:a -c:v copy -shortest "$OUTPUT"
fi

rm -f "$TEMP_AUDIO" "$TEMP_PROCESSED"
echo "✅ Output saved to: $OUTPUT"
