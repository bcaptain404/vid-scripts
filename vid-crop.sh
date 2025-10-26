#!/bin/bash
# vid-crop.sh — hybrid mkvmerge/ffmpeg cropper with fallback
# v0.5  (2025-10-26)

set -o errexit -o pipefail -o nounset

# ---- UUID and Paths ----
UUID="$(cat /proc/sys/kernel/random/uuid)"
TMPFILE="/tmp/vidcrop_${UUID}.mkv"
LOG="/tmp/vidcrop_${UUID}.log"

# ---- Logging ----
log()   { echo "[$(date +'%F %T')] $*" | tee -a "$LOG" >&2; }
err()   { echo "[$(date +'%F %T')] ERROR: $*" | tee -a "$LOG" >&2; }
debug() { [ "${VERBOSE:-0}" -eq 1 ] && log "DEBUG: $*"; }

# ---- Defaults ----
QUIET=0
VERBOSE=0
FF_ARGS=()
MK_ARGS=()
INPUT=""
OUTPUT=""
START=""
END=""
OVERWRITE=0
MKV_PID=""
FFMPEG_PID=""

# ---- Cleanup ----
cleanup() {
    debug "Running cleanup"
    [[ -f "$TMPFILE" ]] && rm -f "$TMPFILE"
    if [[ -n "$MKV_PID" ]]; then
        kill "$MKV_PID" 2>/dev/null || true
        wait "$MKV_PID" 2>/dev/null || true
    fi
    if [[ -n "$FFMPEG_PID" ]]; then
        kill "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

handle_signal() {
    err "Interrupted, killing subprocesses…"
    cleanup
    exit 2
}
trap handle_signal SIGINT SIGTERM SIGHUP

# ---- Help ----
show_help() {
  cat <<EOF
$0 v0.5
Usage: $(basename "$0") -in FILE -start TIME -end TIME [options]

Required:
  -in FILE          Input video file
  -start TIME       Start time (e.g., 02:25:48)
  -end TIME         End time (e.g., 02:29:27)

Optional:
  -out FILE         Output filename (defaults to input name + '_out.EXT')
  -overwrite        Allow overwrite of output file (else will bail)
  -v, --verbose     Verbose mode
  -q, --quiet       Quiet mode
  -ff ARG           Extra argument to ffmpeg (repeatable)
  -mk ARG           Extra argument to mkvmerge (repeatable)
  -h, --help        Show this help and exit

Notes:
  - Old GNU-style flags like --in=file are deprecated but still accepted (with warning).
EOF
}

# ---- Path Expansion ----
expand_path() {
  local path="$1"
  [[ "$path" == "~/"* ]] && echo "${HOME}/${path#~/}" || echo "$path"
}

# ---- Arg Parsing ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    # Modern syntax
    -in|--in)        INPUT="$2"; shift 2 ;;
    -out|--out)      OUTPUT="$2"; shift 2 ;;
    -start|--start)  START="$2"; shift 2 ;;
    -end|--end|--stop) END="$2"; shift 2 ;;
    -overwrite|--overwrite) OVERWRITE=1; shift ;;
    -v|--verbose)    VERBOSE=1; shift ;;
    -q|--quiet)      QUIET=1; shift ;;
    -ff|--ff)        FF_ARGS+=("$2"); shift 2 ;;
    -mk|--mk)        MK_ARGS+=("$2"); shift 2 ;;
    -h|--help)       show_help; exit 0 ;;

    # Legacy syntax with =
    --*=*)
      warn_flag="${1%%=*}"
      err "Warning: Old-style $warn_flag=value syntax is deprecated. Use -flag value instead."
      key="${1%%=*}"
      val="${1#*=}"
      case "$key" in
        --in)      INPUT="$val" ;;
        --out)     OUTPUT="$val" ;;
        --start)   START="$val" ;;
        --end)     END="$val" ;;
        --ff)      FF_ARGS+=("$val") ;;
        --mk)      MK_ARGS+=("$val") ;;
        *) err "Unknown legacy argument: $key"; show_help; exit 1 ;;
      esac
      shift ;;
    *)
      err "Unknown argument: $1"
      show_help
      exit 1
      ;;
  esac
done

# ---- Expand ~ in paths ----
INPUT=$(expand_path "$INPUT")
OUTPUT=$(expand_path "$OUTPUT")

# ---- Check Dependencies ----
for cmd in ffmpeg mkvmerge; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command '$cmd' not found in PATH."
    exit 1
  fi
done

# ---- Required Args ----
if [[ -z "$INPUT" || -z "$START" || -z "$END" ]]; then
  err "Missing required arguments."
  show_help
  exit 1
fi

# ---- Output Name Logic ----
if [[ -z "${OUTPUT:-}" ]]; then
  ext="${INPUT##*.}"
  OUTPUT="${INPUT%.*}_out.${ext}"
fi

# ---- Overwrite Check ----
if [[ -e "$OUTPUT" && "$OVERWRITE" -eq 0 ]]; then
  err "Output file $OUTPUT exists. Use -overwrite to allow replacing it."
  exit 1
fi

# ---- Determine Input Type ----
ext="${INPUT##*.}"

# Non-MKV inputs use ffmpeg directly
if [[ "$ext" != "mkv" ]]; then
  log "Input is not MKV; using ffmpeg directly for trim."
  ffmpeg -hide_banner -loglevel error -y \
    -ss "$START" -to "$END" \
    -i "$INPUT" \
    -c:v libx264 -preset fast -crf 26 \
    -c:a aac -b:a 128k -movflags +faststart "$OUTPUT" >>"$LOG" 2>&1
  log "Trim completed (ffmpeg direct)."
  exit 0
fi

# ---- Build Commands ----
debug "Building Commands..."
MKV_CMD=(mkvmerge -o "$TMPFILE" --split parts:"$START"-"$END" "$INPUT")
for mk in "${MK_ARGS[@]}"; do MKV_CMD+=("$mk"); done

FFMPEG_CMD=(ffmpeg -hide_banner -loglevel error -y -i "$TMPFILE" \
    -c:v libx264 -preset fast -crf 26 \
    -c:a aac -b:a 128k -movflags +faststart "$OUTPUT")
for ff in "${FF_ARGS[@]}"; do FFMPEG_CMD+=("$ff"); done

if [ "$VERBOSE" -eq 1 ]; then
  log "Starting mkvmerge: ${MKV_CMD[*]}"
  log "Then running ffmpeg: ${FFMPEG_CMD[*]}"
fi

# ---- Run mkvmerge ----
"${MKV_CMD[@]}" >>"$LOG" 2>&1 &
MKV_PID=$!
wait "$MKV_PID"
mkv_status=$?

if [ "$mkv_status" -ne 0 ]; then
  err "mkvmerge failed with exit code $mkv_status"
  exit 2
fi

# ---- Sanity Check ----
if [[ ! -s "$TMPFILE" ]]; then
  err "mkvmerge produced no output; falling back to ffmpeg direct trim."
  ffmpeg -hide_banner -loglevel error -y \
    -ss "$START" -to "$END" \
    -i "$INPUT" \
    -c:v libx264 -preset fast -crf 26 \
    -c:a aac -b:a 128k -movflags +faststart "$OUTPUT" >>"$LOG" 2>&1
  log "Trim completed (fallback)."
  exit 0
fi

# ---- Run ffmpeg ----
debug "Starting ffmpeg..."
"${FFMPEG_CMD[@]}" >>"$LOG" 2>&1 &
FFMPEG_PID=$!
wait "$FFMPEG_PID"
ffmpeg_status=$?

if [ "$ffmpeg_status" -ne 0 ]; then
  err "ffmpeg failed with exit code $ffmpeg_status"
  exit 3
fi

log "Video processing completed successfully."
