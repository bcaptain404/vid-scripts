#!/bin/bash
set -e

echo "## $0" >&2

function go() {
    if [[ $# < 1 ]] ; then
        echo "usage: $0 [file]" >&2
        exit 1
    fi
    local IN="$1"

    local OUT
    OUT="/tmp/rev-${RANDOM}_$(basename "${1}")"

    local LOG
    LOG="/tmp/ffmpeg.vid.log"
    
    echo "## $0: reversing from: $IN" >&2
    echo "## $0: reversing to: $OUT" >&2
    ffmpeg -i "$IN" -vf reverse "$OUT" 2>"$LOG"
    echo "## $0: saved reverse: $OUT" >&2
    echo "$OUT"
    rm "$LOG" || true
}

go "$@"

