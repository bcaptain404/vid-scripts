#!/bin/bash
# todo: add 'set -e' as long as ffmpeg/mkvmerge/etc don't use stderr for non-fatal messages.

# todo -v/--verbose: sets verbose mode for ffmpeg, mkvmerge, etc
# todo: -q/--quiet: sets quiet mode for ffmpeg, mkvmerge, etc; surpress this scripts notes, error messages, etc
# todo: -ff="arg" add a single argument to pass to ffmpeg
# todo: -mk="arg" add a single argument to pass to mkvmerge

INPUT="the-input-file.mp4" # todo: required arg: --in="filename" (instead of baked in)
OUTPUT="${INPUT}_out.mp4" # todo: optional arg: --out="filename" (error and bail if doens't have a .mp4 extension)
START="02:25:48" # todo: required arg: --start="" (instead of baked in)
END="02:29:27" # todo: required arg: --end="" (instead of baked in)

# todo: print a handy message that we're starting mkvmerge via FIFO+pipe
PIPE="/tmp/temp_pipe.mkv" # todo: bail script if pipe errs
[ -p "$PIPE" ] && rm "$PIPE" # Remove the FIFO if it already exists
mkfifo "$PIPE" || exit 1 # todo: pring an error to stderr
{
    mkvmerge -o "$PIPE" --split parts:"$START"-"$END" "$INPUT" || exit 2 # todo: print error to stderr
} &

# todo: print a handy message that we're starting ffmpeg to read from the FIFO
{
    ffmpeg -i "$PIPE" \
      -c:v libx264 -preset fast -crf 26 \
      -c:a aac -b:a 128k \
      -movflags +faststart \
      -y "${OUTPUT}" || exit 3 # todo: print a handy error to stderr
}
# todo: print a handy message that we're performing cleanup steps
rm "$PIPE"

# todo: -h/--help

