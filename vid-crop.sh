#!/bin/bash

set -o errexit -o pipefail -o nounset

# ---- UUID and Paths ----
UUID="$(cat /proc/sys/kernel/random/uuid)"
PIPE="/tmp/vidcrop_${UUID}.pipe"
LOG="/tmp/vidcrop_${UUID}.log"

# ---- Logging ----
log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOG" >&2; }
err() { echo "[$(date +'%F %T')] ERROR: $*" | tee -a "$LOG" >&2; }
debug() { [ "$VERBOSE" -eq 1 ] && log "DEBUG: $*"; }

# ---- Cleanup ----
cleanup() {
    debug "Running cleanup"
    [[ -p "$PIPE" ]] && rm -f "$PIPE"
    [[ -n "${MKV_PID:-}" ]] && kill "$MKV_PID" 2>/dev/null || true
    wait "${MKV_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'err "Interrupted"; exit 2' SIGINT SIGTERM SIGHUP

# ---- Help ----
show_help() {
  cat <<EOF
Usage: $(basename "$0") --in=FILE --start=TIME --end=TIME [options]

Required:
  --in=FILE         Input video file
  --start=TIME      Start time (e.g., 02:25:48)
  --end=TIME        End time (e.g., 02:29:27)

Optional:
  --out=FILE        Output filename (defaults to input name + '_out.EXT' where EXT from --out or input)
  --overwrite       Allow overwrite of output file (else will bail)
  -v, --verbose     Verbose mode (ffmpeg/mkvmerge info, script messages)
  -q, --quiet       Quiet mode (minimal output, only fatal errors)
  -ff=ARG           Extra argument to ffmpeg (repeat for multiple)
  -mk=ARG           Extra argument to mkvmerge (repeat for multiple)
  -h, --help        Show this help and exit

Notes:
  - All multi-word ffmpeg/mkvmerge options must be supplied as multiple -ff=... or -mk=... flags.
  - Output format is determined by your output filename (e.g., .mp4, .mkv, .mov, etc).
  - A temp FIFO and log will be created using a UUID, to avoid clobbering other runs.
  - Log is at $LOG
EOF
}

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

# ---- Arg Parsing ----
for arg in "$@"; do
  case $arg in
    --in=*)      INPUT="${arg#*=}" ;;
    --out=*)     OUTPUT="${arg#*=}" ;;
    --start=*)   START="${arg#*=}" ;;
    --end=*)     END="${arg#*=}" ;;
    --overwrite) OVERWRITE=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    -q|--quiet)   QUIET=1 ;;
    -ff=*)       FF_ARGS+=("${arg#*=}") ;;
    -mk=*)       MK_ARGS+=("${arg#*=}") ;;
    -h|--help)   show_help; exit 0 ;;
    *)
      err "Unknown argument: $arg"
      show_help
      exit 1
      ;;
  esac
done

# ---- Check Dependencies ----
for cmd in ffmpeg mkvmerge mkfifo; do
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
  err "Output file $OUTPUT exists. Use --overwrite to allow replacing it."
  exit 1
fi

# ---- FIFO Pipe ----
if [[ -p "$PIPE" ]]; then
  log "Removing pre-existing FIFO pipe $PIPE"
  rm -f "$PIPE"
fi

log "Creating FIFO pipe at $PIPE"
if ! mkfifo "$PIPE"; then
  err "Could not create FIFO pipe ($PIPE)"
  exit 1
fi

# ---- Build Commands ----
MKV_CMD=(mkvmerge -o "$PIPE" --split parts:"$START"-"$END" "$INPUT")
for mk in "${MK_ARGS[@]}"; do MKV_CMD+=("$mk"); done

FFMPEG_CMD=(ffmpeg -hide_banner -loglevel error -y -i "$PIPE" -c:v libx264 -preset fast -crf 26 -c:a aac -b:a 128k -movflags +faststart "$OUTPUT")
for ff in "${FF_ARGS[@]}"; do FFMPEG_CMD+=("$ff"); done

if [ "$VERBOSE" -eq 1 ]; then
  log "Starting mkvmerge: ${MKV_CMD[*]}"
  log "Will run ffmpeg: ${FFMPEG_CMD[*]}"
fi

# ---- Start mkvmerge ----
"${MKV_CMD[@]}" > /dev/null 2>>"$LOG" &
MKV_PID=$!

# ---- Wait for FIFO to become writable (avoids race/hang) ----
timeout=10
while ! (exec 3<>"$PIPE") 2>/dev/null; do
  ((timeout--))
  if [ $timeout -le 0 ]; then
    err "FIFO $PIPE not available after 10 seconds."
    kill $MKV_PID 2>/dev/null || true
    exit 1
  fi
  sleep 1
done
exec 3>&-  # Close test FD

# ---- Start ffmpeg ----
if ! "${FFMPEG_CMD[@]}" 2>>"$LOG"; then
  err "ffmpeg failed."
  kill $MKV_PID 2>/dev/null || true
  exit 3
fi

# ---- Reap mkvmerge, Check for Fail ----
wait $MKV_PID
mkv_status=$?
if [ "$mkv_status" -ne 0 ]; then
  err "mkvmerge exited with status $mkv_status"
  exit 2
fi

log "Video processing completed successfully."
