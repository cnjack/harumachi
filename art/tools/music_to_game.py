"""Turn raw MiniMax Music 3 renders into game music: trim silence, match loudness, write Ogg Vorbis.

    <venv>/python art/tools/music_to_game.py [name ...]      (default: title day market ending)

Reads art/audio/music_raw/<name>.wav (from gen_music_minimax.sh), writes
game/assets/audio/music/<name>.ogg and art/manifests/music_minimax/render_stats.json.
Loudness is matched to -20 LUFS integrated (true peak capped at -1.5 dBTP), so the in-game
music level stays consistent between tracks.
"""
import json, os, re, subprocess, sys
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAW = os.path.join(ROOT, "art", "audio", "music_raw")
OUT = os.path.join(ROOT, "game", "assets", "audio", "music")
FF = "/opt/homebrew/bin/ffmpeg"
TARGET_I, TARGET_TP = -20.0, -1.5


def loudness(path):
    r = subprocess.run([FF, "-hide_banner", "-i", path, "-af", "loudnorm=print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    j = json.loads(re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S).group(0))
    return float(j["input_i"]), float(j["input_tp"])


def main(names):
    os.makedirs(OUT, exist_ok=True)
    stats_path = os.path.join(ROOT, "art", "manifests", "music_minimax", "render_stats.json")
    stats = json.load(open(stats_path)) if os.path.exists(stats_path) else {}
    for n in names:
        src = os.path.join(RAW, n + ".wav")
        x, sr = sf.read(src, always_2d=True)
        env = np.max(np.abs(x), axis=1)
        loud = np.nonzero(env > 10 ** (-55 / 20))[0]
        a, b = int(loud[0]), int(min(len(x), loud[-1] + 0.5 * sr))
        x = x[a:b].copy()
        k = int(0.01 * sr)
        x[:k] *= np.linspace(0, 1, k)[:, None]
        k = int(0.3 * sr)
        x[-k:] *= np.linspace(1, 0, k)[:, None]
        tmp = f"/tmp/_music_{n}.wav"
        sf.write(tmp, x, sr, subtype="FLOAT")
        li, tp = loudness(tmp)
        gain = min(TARGET_I - li, TARGET_TP - tp)
        y = np.clip(x * 10 ** (gain / 20), -1, 1).astype(np.float32)
        dst = os.path.join(OUT, n + ".ogg")
        with sf.SoundFile(dst, "w", sr, y.shape[1], format="OGG", subtype="VORBIS", compression_level=0.3) as f:
            for i in range(0, len(y), 8192):
                f.write(y[i:i + 8192])
        stats[n] = {"source": f"art/audio/music_raw/{n}.wav", "file": f"game/assets/audio/music/{n}.ogg",
                    "seconds": round(len(y) / sr, 2), "sample_rate": sr, "input_lufs": li, "gain_db": round(gain, 2)}
        print(n, stats[n])
        os.remove(tmp)
    json.dump(stats, open(stats_path, "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1:] or ["title", "day", "market", "ending"])
