# vid-scrupts
This will contain many scripts to hack up video files. for now, there is only vid-crop.sh
The rest of this readme will pertain to vid-crop.sh until more scripts are added.

A robust, production-grade Bash script for extracting a video segment from any file supported by `mkvmerge` and `ffmpeg`—with no race conditions, no zombie processes, no stale pipes, and unique log files for every run.

- **Concurrent-safe:** You can run it as many times in parallel as you want.
- **Signal-safe:** No orphans—kills all children (ffmpeg, mkvmerge) on Ctrl+C or kill.
- **Flexible output:** Any file format `ffmpeg` supports.
- **Clear logging:** Each run logs to `/tmp/vidcrop-UUID.log`.

---

## Features

- Crop any video file using start/end timestamps.
- Supports any output format: `.mp4`, `.mkv`, `.mov`, `.webm`, etc.
- User-friendly CLI with thorough error-checking.
- Pass arbitrary arguments to `ffmpeg` and `mkvmerge` for advanced workflows.
- No accidental overwrites unless you use `--overwrite`.
- Cleans up all temporary files and FIFOs—even on error or interruption.
- Unique log file per run for debugging.

---

## Requirements

- **Linux or WSL** with:
  - `bash`
  - `ffmpeg`
  - `mkvmerge` (part of mkvtoolnix)
  - `mkfifo`

---

## Usage

```bash
./vid-crop.sh --in=INPUT --start=START --end=END [options]
