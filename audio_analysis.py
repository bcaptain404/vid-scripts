import librosa

def print_stats(stats, label=""):
    if label:
        print(f"\n--- {label} ---")
    print(f"RMS loudness:       {stats['rms']:.5f}")
    print(f"Zero-crossing rate: {stats['zcr']:.5f}")
    print(f"Spectral centroid:  {stats['centroid']:.2f} Hz")

def analyze_audio(file):
    y, sr = librosa.load(file)
    rms = float(librosa.feature.rms(y=y).mean())
    zcr = float(librosa.feature.zero_crossing_rate(y=y).mean())
    centroid = float(librosa.feature.spectral_centroid(y=y, sr=sr).mean())
    return dict(rms=rms, zcr=zcr, centroid=centroid)

def classify_content(stats):
    """
    Simple rule-based classifier for audio content.
    Returns one of: vocals, instrumental, music/mixed, speech/podcast, sibilant/harsh (maybe live vocals)
    """
    zcr = stats['zcr']
    centroid = stats['centroid']
    rms = stats['rms']
    if zcr > 0.08 and centroid > 4000:
        return "vocals"
    elif zcr < 0.04 and centroid < 2500:
        return "instrumental"
    elif rms < 0.02:
        return "speech/podcast"
    elif centroid > 6000:
        return "sibilant/harsh (maybe live vocals)"
    else:
        return "music/mixed"

def suggest_preset(content_type):
    presets = {
        "vocals": "vocals",
        "instrumental": "inst",
        "music/mixed": "music",
        "speech/podcast": "podcast",
        "sibilant/harsh (maybe live vocals)": "vocals + de-ess"
    }
    return presets.get(content_type, "music")

def suggest_filters(stats):
    print("# Smart-AF Auto Analysis:")
    print_stats(stats)
    ctype = classify_content(stats)
    print(f"Guessed content: {ctype}")
    print(f"Suggested preset: --preset={suggest_preset(ctype)}")
    if stats['rms'] < 0.03: print("--normalize")
    if stats['rms'] > 0.3: print("--compress")
    if stats['centroid'] > 3500: print("--eq")
    if stats['centroid'] > 5000: print("--deess  # (sibilance detected)")

def auto_filters(stats):
    filters = []
    ctype = classify_content(stats)
    if ctype == "vocals":
        filters.extend([
            "highpass=f=80", "lowpass=f=12000",
            "deesser",
            "loudnorm=I=-14:TP=-1.5:LRA=11"
        ])
    elif ctype == "instrumental":
        filters.extend([
            "highpass=f=60", "lowpass=f=16000",
            "loudnorm=I=-14:TP=-1.5:LRA=11"
        ])
    elif ctype == "speech/podcast":
        filters.extend([
            "highpass=f=100", "lowpass=f=8000",
            "loudnorm=I=-16:TP=-2:LRA=10"
        ])
    else:  # music/mixed/unknown
        filters.extend([
            "highpass=f=80", "lowpass=f=14000",
            "acompressor=threshold=-18dB:ratio=3:attack=20:release=250",
            "loudnorm=I=-14:TP=-1.5:LRA=11"
        ])
    if stats['centroid'] > 6000:
        filters.extend([
            "equalizer=f=6000:t=q:w=1.5:g=-6",
            "equalizer=f=10000:t=q:w=1.5:g=-8"
        ])
    # Add broad EQ if centroid > 3500 Hz and not already in filters
    if stats['centroid'] > 3500 and "highpass=f=80" not in filters:
        filters.extend(["highpass=f=80", "lowpass=f=12000"])
    # Add de-esser for sibilance
    if stats['centroid'] > 5000 and "deesser" not in filters:
        filters.append("deesser")
    return filters
