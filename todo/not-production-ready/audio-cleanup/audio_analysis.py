import librosa

def analyze_audio(file):
    y, sr = librosa.load(file)
    rms = float(librosa.feature.rms(y=y).mean())
    zcr = float(librosa.feature.zero_crossing_rate(y).mean())
    centroid = float(librosa.feature.spectral_centroid(y=y, sr=sr).mean())
    return dict(rms=rms, zcr=zcr, centroid=centroid)

def suggest_filters(stats):
    print("# Smart-AF Auto Analysis:")
    print(f"RMS loudness: {stats['rms']:.5f}")
    print(f"Zero-crossing rate: {stats['zcr']:.5f}")
    print(f"Spectral centroid: {stats['centroid']:.2f} Hz")
    if stats['rms'] < 0.03: print("--normalize")
    if stats['rms'] > 0.3: print("--compress")
    if stats['centroid'] > 4000: print("--eq")

def auto_filters(stats):
    filters = []
    # ALWAYS normalize
    filters.append("loudnorm=I=-14:TP=-1.5:LRA=11")
    if stats['rms'] > 0.15:
        filters.append("acompressor=threshold=-18dB:ratio=3:attack=20:release=250")
    if stats['centroid'] > 3500:
        filters.extend(["highpass=f=80", "lowpass=f=12000"])
    return filters
