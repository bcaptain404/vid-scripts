#!/bin/bash
set -e

echo "## $0" >&2

function go() {
    if [[ $# < 1 ]] ; then
        echo "usage: $0 [files]..." >&2
        exit 1
    fi
    local OUT

    local LST="/tmp/${RANDOM}.vid.lst"
    rm "$LST" 2>/dev/null || true

    for file in "$@" ; do
        echo file \'$(realpath "$file")\' >> "$LST"
    done

    local OUT
    OUT="/tmp/cat-${RANDOM}_$(basename "$1")"

    local FILE
    for FILE in "${IN[@]}" ; do
        echo "## $0: concatenating from: $INFILE" >&2
    done
    echo "## $0: concatenating to: $OUT" >&2

    local LOG
    LOG="/tmp/ffmpeg.vid.log"
    ffmpeg -f concat -safe 0 -i "$LST" -c copy "$(realpath "$OUT")" 2>"$LOG"
    cat "$LST"
    rm "$LST"
    rm "$LOG" || true
    echo "## $0: saved concat: $OUT" >&2
    echo "$OUT"
}

go "$@"

