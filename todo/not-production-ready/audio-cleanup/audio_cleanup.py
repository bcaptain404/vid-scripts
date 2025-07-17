#!/usr/bin/env python3
"""
audio_cleanup.py - Smarter-than-your-ex music/audio fixer
Usage:
    python3 audio_cleanup.py [-h] [--normalize] [--normalize-extra] [--compress] [--compress-extra] [--eq] [--eq-extra] [--deess] [--preset PRESET] [--all] [--auto-suggest] [--auto-apply] [--dry-run] [--mp3] [--no-vid] [--out OUT] [--overwrite] [--verbose] [--debug] [--install-deps] [--install-deps-full] input

positional arguments:
  input                 Input file (.wav, .mp4, .mov, .mkv, .flac)

options:
  --normalize           Apply basic peak normalization
  --normalize-extra     LUFS loudness normalization
  --compress            Light compression
  --compress-extra      Aggressive compression
  --eq                  Cut sub-bass (<80Hz) & fizz (>12kHz)
  --eq-extra            Slight midrange boost
  --deess               Apply de-essing (reduce harsh S sounds)
  --preset PRESET       Preset: vocals, inst, music, podcast, audience, bar, loud-bar
  --all                 EQ -> Compress -> Normalize
  --auto-suggest        Smart AF analysis only (shows recommended flags)
  --auto-apply          Smart AF full-auto (analyze + apply)
  --dry-run             Show what would be done
  --mp3                 Output as MP3 (implies --no-vid)
  --no-vid              Skip video reattachment
  --out OUT             Custom output filename
  --overwrite           Allow overwriting existing output
  --verbose             Print what's happening
  --debug               Print debug stuff
  --install-deps        Install basic dependencies
  --install-deps-full   Install basic dependencies + Python + librosa (for --auto-*)
  -h, --help            Show this help
"""

import sys
import os
import subprocess
import tempfile
import shutil
import argparse

from audio_analysis import analyze_audio, suggest_filters, auto_filters, print_stats



def install_deps(full=False):
    import platform
    print("Installing dependencies...")
    cmds = [
        ["sudo", "apt", "update"],
        ["sudo", "apt", "install", "-y", "ffmpeg"]
    ]
    if full:
        cmds.append(["sudo", "apt", "install", "-y", "python3-pip"])
        cmds.append(["pip3", "install", "numpy", "librosa", "soundfile"])
    for cmd in cmds:
        subprocess.run(cmd, check=True)
    print("✅ Dependencies installed.")

def ffmpeg_cmd(args, verbose=False):
    if verbose:
        print("[ffmpeg]", " ".join(args))
    result = subprocess.run(args, capture_output=not verbose)
    if result.returncode != 0:
        print("❌ FFmpeg failed:", result.stderr.decode() if result.stderr else "Unknown error")
        sys.exit(1)
    return result

def main():
    parser = argparse.ArgumentParser(description="Audio Cleanup Tool")
    parser.add_argument("input", help="Input file (.wav, .mp4, .mov, .mkv, .flac)")
    parser.add_argument("--normalize", action="store_true")
    parser.add_argument("--normalize-extra", action="store_true")
    parser.add_argument("--compress", action="store_true")
    parser.add_argument("--compress-extra", action="store_true")
    parser.add_argument("--eq", action="store_true")
    parser.add_argument("--eq-extra", action="store_true")
    parser.add_argument("--deess", action="store_true", help="Apply de-essing (reduce harsh S sounds)")
    parser.add_argument("--preset", type=str)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--auto-suggest", action="store_true")
    parser.add_argument("--auto-apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--mp3", action="store_true")
    parser.add_argument("--no-vid", action="store_true")
    parser.add_argument("--out", type=str, default=None)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--install-deps", action="store_true")
    parser.add_argument("--install-deps-full", action="store_true")
    parser.add_argument("--report", action="store_true", help="Show before/after audio stats")
    args = parser.parse_args()

    # Install deps and exit if asked
    if args.install_deps:
        install_deps()
        return
    if args.install_deps_full:
        install_deps(full=True)
        return

    input_file = args.input
    if not os.path.exists(input_file):
        print(f"❌ Input file '{input_file}' not found.")
        sys.exit(1)

    basename, in_ext = os.path.splitext(os.path.basename(input_file))
    output_type = "mp3" if args.mp3 else "wav"
    output_file = args.out or f"{basename}_cleaned.{output_type}"
    if os.path.exists(output_file) and not args.overwrite:
        print(f"❌ Output file '{output_file}' exists. Use --overwrite.")
        sys.exit(1)

    filters = []
    # Handle flags to build filter list
    if args.all:
        filters = ["highpass=f=80", "lowpass=f=12000",
                   "acompressor=threshold=-18dB:ratio=3:attack=20:release=250",
                   "loudnorm=I=-14:TP=-1.5:LRA=11"]
    if args.normalize:
        filters.append("dynaudnorm")
    if args.normalize_extra:
        filters.append("loudnorm=I=-14:TP=-1.5:LRA=11")
    if args.compress:
        filters.append("acompressor=threshold=-18dB:ratio=3:attack=20:release=250")
    if args.compress_extra:
        filters.append("acompressor=threshold=-24dB:ratio=6:attack=5:release=100")
    if args.eq:
        filters.extend(["highpass=f=80", "lowpass=f=12000"])
    if args.eq_extra:
        filters.append("equalizer=f=2000:t=q:w=1:g=3")
    if args.deess:
        filters.append("deesser")

    if args.auto_suggest or args.auto_apply:
        audio_stats = analyze_audio(input_file)
        if args.auto_suggest:
            suggest_filters(audio_stats)
            sys.exit(0)
        filters = auto_filters(audio_stats)
        if args.verbose:
            print(f"Auto-applied filters: {filters}")

    if not filters:
        print("❌ No filters specified/applied. Use --all or other flags.")
        sys.exit(1)

    if args.dry_run:
        print(f"🎧 Input: {input_file}")
        print(f"📤 Output: {output_file}")
        print(f"⚙️ Filters to apply:")
        for f in filters:
            print(f"  - {f}")
        sys.exit(0)

    # Temp files
    with tempfile.TemporaryDirectory() as tmpdir:
        temp_audio = os.path.join(tmpdir, "audio.wav")
        temp_processed = os.path.join(tmpdir, "processed.wav")

        # Extract audio (if input is video)
        ffmpeg_cmd([
            "ffmpeg", "-y", "-i", input_file, "-vn",
            "-acodec", "pcm_s16le", "-ar", "44100", temp_audio
        ], verbose=args.verbose)

        filter_chain = ",".join(filters)
        ffmpeg_cmd([
            "ffmpeg", "-y", "-i", temp_audio, "-af", filter_chain, temp_processed
        ], verbose=args.verbose)

        # Handle reattachment or output type
        if args.no_vid or in_ext.lower() == ".wav":
            final_out = output_file
            if args.mp3:
                # Convert to mp3
                ffmpeg_cmd([
                    "ffmpeg", "-y", "-i", temp_processed, "-codec:a", "libmp3lame", "-q:a", "2", final_out
                ], verbose=args.verbose)
            else:
                shutil.copy(temp_processed, final_out)
        else:
            # Reattach to video
            ffmpeg_cmd([
                "ffmpeg", "-y", "-i", input_file, "-i", temp_processed,
                "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-shortest", output_file
            ], verbose=args.verbose)

        # After output, if report is requested
        if args.report:
            in_stats = analyze_audio(input_file)
            print_stats(in_stats, label="Input (Before Processing)")
            # Figure out actual audio file for output:
            out_analyze = output_file
            if not args.no_vid and in_ext.lower() != ".wav" and not args.mp3:
                # Output is video, need to extract audio to temp
                temp_out_audio = os.path.join(tmpdir, "final_out.wav")
                ffmpeg_cmd([
                    "ffmpeg", "-y", "-i", output_file, "-vn", "-acodec", "pcm_s16le", "-ar", "44100", temp_out_audio
                ], verbose=args.verbose)
                out_analyze = temp_out_audio
            out_stats = analyze_audio(out_analyze)
            print_stats(out_stats, label="Output (After Processing)")


        print(f"✅ Output saved to: {output_file}")

if __name__ == "__main__":
    main()
