"""Render several MiniMax Music 3 takes (different seeds) per request.

    python3 art/tools/gen_music_takes.py <takes-per-track> name [name ...]

Requests come from art/manifests/music_minimax/<name>.json; take k uses seed + 100*k.
Output: art/audio/music_takes/<name>_<seed>.wav. The local server must be running
(/Users/jack/workpath/research/music/run-server.sh, port 11438).
"""
import json, os, subprocess, sys, time, urllib.request
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
REQ = os.path.join(ROOT, "art", "manifests", "music_minimax")
OUT = os.path.join(ROOT, "art", "audio", "music_takes")
os.makedirs(OUT, exist_ok=True)
n = int(sys.argv[1])
for k in range(n):
    for name in sys.argv[2:]:
        r = json.load(open(os.path.join(REQ, name + ".json")))
        r["seed"] = int(r["seed"]) + 100 * k
        dst = os.path.join(OUT, f"{name}_{r['seed']}.wav")
        if os.path.exists(dst):
            continue
        t0 = time.time()
        q = urllib.request.Request("http://127.0.0.1:11438/v1/audio/music-generations", data=json.dumps(r).encode(),
                                   headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(q, timeout=3600) as resp, open(dst + ".part", "wb") as f:
            f.write(resp.read())
        os.replace(dst + ".part", dst)
        d = subprocess.run(["/opt/homebrew/bin/ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", dst],
                           capture_output=True, text=True).stdout.strip()
        print(f"{name} seed {r['seed']}: {d} s audio in {time.time() - t0:.0f} s", flush=True)
print("ALLDONE", flush=True)
