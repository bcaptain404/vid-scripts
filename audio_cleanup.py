#!/usr/bin/env python3

#todo allow --rotate* even if filters aren't supplied in arguments

"""
audio_cleanup.py - Smarter-than-your-ex music/audio fixer

Usage:
    python3 audio_cleanup.py input.wav|input.mp4 [options]

Options:
    --normalize             Apply basic peak normalization
    --normalize-extra       LUFS loudness normalization
    --compress              Light compression
    --compress-extra        Aggressive compression
    --eq                    Cut sub-bass (<80Hz) & fizz (>12kHz)
    --eq-extra              Slight midrange boost
    --deess                 Apply de-essing (reduce harsh S sounds)
    --preset=TYPE           Apply a preset filter chain:
                          vocals     = highpass, lowpass, de-ess, LUFS normalize
                          inst       = highpass, extended lowpass, LUFS normalize
                          music      = EQ, light compression, LUFS normalize
                          podcast    = narrow EQ, LUFS normalize (speech focus)
                          (Note: aliases like 'audience', 'bar', 'loud-bar' may be added later)
    --all                   EQ -> Compress -> Normalize
    --auto-suggest          Smart AF analysis only (shows recommended flags)
    --auto-apply            Smart AF full-auto (analyze + apply)
    --classify              Print a guess for content type and recommended preset
    --dry-run               Show what would be done (no output written)
    --mp3                   Output as MP3 (implies --no-vid)
    --no-vid                Skip video reattachment (audio-only output)
    --rotate-cw=X           Rotate video clockwise by X degrees (supports 90, 180, 270 or any float; only for video)
    --rotate-ccw=X          Rotate video counterclockwise by X degrees (same)
    --out=filename.ext      Custom output filename
    --overwrite             Allow overwriting existing output
    --verbose               Print what's happening
    --debug                 Print debug stuff
    --install-deps          Install basic dependencies (ffmpeg)
    --install-deps-full     Install ffmpeg + Python audio deps (librosa, numpy, soundfile)
    --report                Show before/after audio stats for input and output
    -h, --help              Show this help

Supported formats: .wav, .mp4, .mov, .mkv, .flac

Examples:
    python3 audio_cleanup.py song.mp4 --auto-apply --rotate-cw=90 --out=cleaned.mp4
    python3 audio_cleanup.py gig.wav --preset=vocals --mp3 --out=final.mp3
    python3 audio_cleanup.py jam.wav --classify
"""

import sys
import os
import subprocess
import tempfile
import shutil
import argparse

from audio_analysis import analyze_audio, suggest_filters, auto_filters, print_stats, classify_content, suggest_preset
from vid_tools import get_video_rotation_filter

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
    parser.add_argument("--tame-treble", type=int, choices=range(1, 11), metavar="[1-10]",
                    help="Reduce harsh treble (6kHz+). 1 = subtle, 10 = aggressive")
    parser.add_argument("--preset", type=str)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--auto-suggest", action="store_true")
    parser.add_argument("--auto-apply", action="store_true")
    parser.add_argument("--classify", action="store_true", help="Print content type guess and recommended preset")
    parser.add_argument("--img", type=str, help="Use a still image to generate video with input audio (outputs .mp4)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--mp3", action="store_true")
    parser.add_argument("--no-vid", action="store_true")
    parser.add_argument("--rotate-cw", type=float, default=None, help="Rotate video clockwise by X degrees")
    parser.add_argument("--rotate-ccw", type=float, default=None, help="Rotate video counterclockwise by X degrees")
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

    allowed_ext = (".wav", ".mp4", ".mov", ".mkv", ".flac")
    basename, in_ext = os.path.splitext(os.path.basename(input_file))
    if in_ext.lower() not in allowed_ext:
        print(f"❌ Unsupported input file format: {in_ext}")
        sys.exit(1)

    output_type = "mp3" if args.mp3 else "wav"
    output_file = args.out or f"{basename}_cleaned.{output_type}"
    if os.path.exists(output_file) and not args.overwrite:
        print(f"❌ Output file '{output_file}' exists. Use --overwrite.")
        sys.exit(1)

    # Classification (on request)
    if args.classify:
        stats = analyze_audio(input_file)
        ctype = classify_content(stats)
        preset = suggest_preset(ctype)
        print(f"Guessed content type: {ctype}")
        print(f"Suggested preset: --preset={preset}")
        sys.exit(0)

    if args.img:
        if not os.path.exists(args.img):
            print(f"❌ Image file '{args.img}' not found.")
            sys.exit(1)
        if not input_file.lower().endswith((".mp3", ".wav", ".flac")):
            print("❌ --img can only be used with audio files.")
            sys.exit(1)

    filters = []
    if args.all:
        filters = [
            "highpass=f=80", "lowpass=f=12000",
            "acompressor=threshold=-18dB:ratio=3:attack=20:release=250",
            "loudnorm=I=-14:TP=-1.5:LRA=11"
        ]
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
    if args.tame_treble:
        # Map level to EQ gain (more negative = more cut)
        level = args.tame_treble
        if level < 1 or level > 10:
            print("❌ --tame-treble must be between 1 and 10")
            sys.exit(1)

        # Gain values scale linearly (you can tweak this mapping)
        g6000 = round(-1 * level, 1)    # e.g., -1 to -10 dB
        g10000 = round(-1.5 * level, 1) # e.g., -1.5 to -15 dB
        g14000 = round(-0.75 * level, 1) if level >= 6 else 0  # Optional high-end smoothing at higher levels

        filters.append(f"equalizer=f=6000:t=q:w=1.5:g={g6000}")
        filters.append(f"equalizer=f=10000:t=q:w=1.5:g={g10000}")
        if g14000 < 0:
            filters.append(f"equalizer=f=14000:t=q:w=1.2:g={g14000}")
    if args.preset:
        if args.preset == "vocals":
            filters = ["highpass=f=80", "lowpass=f=12000", "deesser", "loudnorm=I=-14:TP=-1.5:LRA=11"]
        elif args.preset == "inst":
            filters = ["highpass=f=60", "lowpass=f=16000", "loudnorm=I=-14:TP=-1.5:LRA=11"]
        elif args.preset == "music":
            filters = [
                "highpass=f=80", "lowpass=f=14000",
                "acompressor=threshold=-18dB:ratio=3:attack=20:release=250",
                "loudnorm=I=-14:TP=-1.5:LRA=11"
            ]
        elif args.preset == "podcast":
            filters = ["highpass=f=100", "lowpass=f=8000", "loudnorm=I=-16:TP=-2:LRA=10"]

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
        rotation = None
        direction = "cw"
        if args.rotate_cw is not None and args.rotate_ccw is not None:
            print("❌ Only one of --rotate-cw or --rotate-ccw may be used at a time.")
            sys.exit(1)
        elif args.rotate_cw is not None:
            rotation = args.rotate_cw
            direction = "cw"
        elif args.rotate_ccw is not None:
            rotation = args.rotate_ccw
            direction = "ccw"
        if rotation is not None:
            print(f"  - Video rotation: {rotation} degrees {direction}")
        sys.exit(0)

    with tempfile.TemporaryDirectory() as tmpdir:
        temp_audio = os.path.join(tmpdir, "audio.wav")
        temp_processed = os.path.join(tmpdir, "processed.wav")
        temp_video = os.path.join(tmpdir, "video.mp4")
        temp_rotated = os.path.join(tmpdir, "video_rotated.mp4")

        # Extract audio (if input is video)
        ffmpeg_cmd([
            "ffmpeg", "-y", "-i", input_file, "-vn",
            "-acodec", "pcm_s16le", "-ar", "44100", temp_audio
        ], verbose=args.verbose)

        filter_chain = ",".join(filters)
        ffmpeg_cmd([
            "ffmpeg", "-y", "-i", temp_audio, "-af", filter_chain, temp_processed
        ], verbose=args.verbose)

        # Handle output based on options
        if args.no_vid or in_ext.lower() == ".wav":
            final_out = output_file
            if args.mp3:
                ffmpeg_cmd([
                    "ffmpeg", "-y", "-i", temp_processed, "-codec:a", "libmp3lame", "-q:a", "2", final_out
                ], verbose=args.verbose)
            else:
                shutil.copy(temp_processed, final_out)
        else:
            ffmpeg_cmd([
                "ffmpeg", "-y", "-i", input_file, "-an", "-c:v", "copy", temp_video
            ], verbose=args.verbose)

            # Rotation debug/logic
            rotation = None
            direction = "cw"
            if args.rotate_cw is not None and args.rotate_ccw is not None:
                print("❌ Only one of --rotate-cw or --rotate-ccw may be used at a time.")
                sys.exit(1)
            elif args.rotate_cw is not None:
                rotation = args.rotate_cw
                direction = "cw"
            elif args.rotate_ccw is not None:
                rotation = args.rotate_ccw
                direction = "ccw"

            if rotation is not None:
                rot_filter = get_video_rotation_filter(rotation, direction)
                print(f"Rotating video: {rotation} degrees {direction}, filter: {rot_filter}")
                if rot_filter is None:
                    print(f"❌ Invalid rotation: {rotation} {direction}")
                    sys.exit(1)
                ffmpeg_cmd([
                    "ffmpeg", "-y", "-i", temp_video, "-vf", rot_filter, "-an", "-c:v", "libx264", "-preset", "ultrafast", temp_rotated
                ], verbose=args.verbose)
                temp_video_out = temp_rotated
            else:
                temp_video_out = temp_video

            print(f"Combining video ({temp_video_out}) + audio ({temp_processed}) to -> {output_file}")
            ffmpeg_cmd([
                "ffmpeg", "-y", "-i", temp_video_out, "-i", temp_processed,
                "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-shortest", output_file
            ], verbose=args.verbose)

        if args.report:
            in_stats = analyze_audio(input_file)
            print_stats(in_stats, label="Input (Before Processing)")
            out_analyze = output_file
            if not args.no_vid and in_ext.lower() != ".wav" and not args.mp3:
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
