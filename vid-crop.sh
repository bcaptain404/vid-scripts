#!/bin/bash

set -e

show_help() {
  cat <<EOF
Usage: $(basename "$0") --in=FILE --start=TIME --end=TIME [options]

Required:
  --in=FILE         Input video file
  --start=TIME      Start time (e.g., 02:25:48)
  --end=TIME        End time (e.g., 02:29:27)

Optional:
  --out=FILE        Output filename (.mp4 only; defaults to input name + '_out.mp4')
  -v, --verbose     Verbose mode (ffmpeg/mkvmerge info, script messages)
  -q, --quiet       Quiet mode (minimal output, only fatal errors)
  -ff="ARGS"        Extra argument to ffmpeg (may repeat)
  -mk="ARGS"        Extra argument to mkvmerge (may repeat)
  -h, --help        Show this help and exit

Notes:
  - Both --in, --start, and --end are required.
  - Output file must end with .mp4.
  - Cleans up FIFO pipe on exit.
EOF
}

# Defaults
QUIET=0
VERBOSE=0
FF_ARGS=()
MK_ARGS=()
INPUT=""
OUTPUT=""
START=""
END=""
PIPE="/tmp/temp_pipe.mkv"

log() {
  [ "$QUIET" -eq 0 ] && echo "$@" >&2
}

err() {
  echo "ERROR: $*" >&2
}

# Parse args
for arg in "$@"; do
  case $arg in
    --in=*)      INPUT="${arg#*=}" ;;
    --out=*)     OUTPUT="${arg#*=}" ;;
    --start=*)   START="${arg#*=}" ;;
    --end=*)     END="${arg#*=}" ;;
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

# Check required args
if [[ -z "$INPUT" || -z "$START" || -z "$END" ]]; then
  err "Missing required arguments."
  show_help
  exit 1
fi

# Output name logic
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${INPUT%.*}_out.mp4"
fi

if [[ "$OUTPUT" != *.mp4 ]]; then
  err "Output file must have .mp4 extension."
  exit 1
fi

# Remove pre-existing FIFO
if [ -p "$PIPE" ]; then
  rm "$PIPE"
fi

# Cleanup on exit, even if error
trap 'rm -f "$PIPE"' EXIT

log "Creating FIFO pipe at $PIPE"
if ! mkfifo "$PIPE"; then
  err "Could not create FIFO pipe ($PIPE)"
  exit 1
fi

MKV_CMD=(mkvmerge -o "$PIPE" --split parts:"$START"-"$END" "$INPUT" "${MK_ARGS[@]}")
FFMPEG_CMD=(ffmpeg -i "$PIPE" -c:v libx264 -preset fast -crf 26 -c:a aac -b:a 128k -movflags +faststart -y "$OUTPUT" "${FF_ARGS[@]}")

if [ "$VERBOSE" -eq 1 ]; then
  log "Starting mkvmerge with: ${MKV_CMD[*]}"
fi

# Start mkvmerge
{
  "${MKV_CMD[@]}" || {
    err "mkvmerge failed!"
    exit 2
  }
} &

MKV_PID=$!

if [ "$VERBOSE" -eq 1 ]; then
  log "Starting ffmpeg with: ${FFMPEG_CMD[*]}"
fi

# Run ffmpeg, bail on error
{
  "${FFMPEG_CMD[@]}" || {
    err "ffmpeg failed!"
    kill $MKV_PID 2>/dev/null || true
    exit 3
  }
}

log "Video processing completed successfully."
