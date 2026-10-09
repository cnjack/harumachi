"""Generate every sound in 晴町日常 from code (no samples, no third-party recordings).

    <venv>/python art/tools/synth_audio.py [out_dir] [only...]

out_dir defaults to game/assets/audio. Needs numpy, scipy and soundfile (libsndfile with Vorbis).
Ambience loops are Ogg Vorbis with their tails folded back onto the start, so they repeat without
a seam; sound effects are 16-bit WAV. A manifest is written to art/manifests/audio_synth.json.

The game's music comes from MiniMax Music 3 (gen_music_minimax.sh + music_to_game.py). The
synthesized music in audio/music.py is only a fallback and is rendered only when asked for by
name ("music" for all four, or title/day/market/ending), so a default run never overwrites the
MiniMax tracks.
"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "audio"))
from synth_core import SR, write  # noqa: E402
import music, amb, sfx  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game", "assets", "audio")
only = set(sys.argv[2:])
for d in ("music", "amb", "sfx"):
    os.makedirs(os.path.join(out, d), exist_ok=True)
man = {"generator": "art/tools/synth_audio.py", "sample_rate": SR,
       "game_music": "MiniMax Music 3, see art/manifests/music_minimax/render_stats.json",
       "music": {}, "ambience": {}, "sfx": {}}
for name, (fn, loop) in music.MUSIC.items():
    if "music" not in only and name not in only:
        continue
    t0 = time.time()
    st = fn()
    write(os.path.join(out, "music", name + ".ogg"), st)
    man["music"][name] = {"file": f"music/{name}.ogg", "seconds": round(st.shape[1] / SR, 2), "loop": loop}
    print("music", name, round(st.shape[1] / SR, 1), "s", round(time.time() - t0, 1), "s render")
for name, fn in amb.AMB.items():
    if only and name not in only and "amb" not in only:
        continue
    st = fn()
    write(os.path.join(out, "amb", name + ".ogg"), st)
    man["ambience"][name] = {"file": f"amb/{name}.ogg", "seconds": round(st.shape[1] / SR, 2), "loop": True}
    print("amb", name)
if not only or "sfx" in only:
    man["sfx"] = sfx.build(out)
    print("sfx", len(man["sfx"]))
if not only:
    with open(os.path.join(ROOT, "art", "manifests", "audio_synth.json"), "w") as f:
        json.dump(man, f, ensure_ascii=False, indent=1)
