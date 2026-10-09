"""Voice every dialogue line with the cast chosen in art/manifests/voice_cast.json (Qwen3-TTS, mlx-audio).

    cd /Users/jack/workpath/opensource/mlx-audio
    uv run python "<repo>/art/tools/voice/gen_voice_lines.py" [--only mio,ren] [--limit N]

Lines come from game/data/dialogue.json, the prologue monologue (game/data/prologue.json) and from every say("who", "mood", "text") call in the game's
scripts (lines built at runtime with % or a ternary are skipped and stay unvoiced). Each clip is written
to game/assets/audio/voice/<who>/<md5 of the text>.ogg, which is exactly what Audio.voice() looks up.
Every clip is transcribed back with Qwen3-ASR; a clip whose character error rate is above 0.3 is
regenerated (up to two more seeds) and the best take is kept. Results: art/manifests/voice_lines.json.
"""
import argparse, glob, hashlib, json, os, re, subprocess, sys, time
import numpy as np
from scipy.io import wavfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GAME, "assets", "audio", "voice")
MAN = os.path.join(ROOT, "art", "manifests", "voice_lines.json")
FF = "/opt/homebrew/bin/ffmpeg"
SR = 24000
# characters the TTS does not know, replaced by a common character with the same reading (the clip's
# file name still comes from the original text, so the game finds it)
PRON = {"澪": "玲", "晴町": "晴挺"}     # names the TTS does not know: 澪 líng, 町 tǐng
MOOD = {"happy": "，语气开心，带着笑意。", "sad": "，语气有点难过，轻声慢慢说。", "surprised": "，语气惊讶。", "neutral": ""}
PAT = re.compile(r'(?:_say|say)\(\s*"(\w+)"\s*,\s*"(\w*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)')


def unescape(t):
    return t.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def collect():
    lines = {}
    d = json.load(open(os.path.join(GAME, "data", "dialogue.json")))
    for e in d["entries"]:
        for ln in e["lines"]:
            lines.setdefault((ln[0], ln[2]), ln[1])
        for reply in e.get("choice", {}).get("replies", []):
            for ln in reply:
                lines.setdefault((ln[0], ln[2]), ln[1])
    for f in glob.glob(os.path.join(GAME, "scripts", "**", "*.gd"), recursive=True):
        for m in PAT.finditer(open(f).read()):
            lines.setdefault((m.group(1), unescape(m.group(3))), m.group(2))
    # the prologue slideshow's monologue (game/data/prologue.json)
    pro = json.load(open(os.path.join(GAME, "data", "prologue.json")))
    for pn in pro["panels"]:
        lines.setdefault((pro["voice"], pn["text"]), "neutral")
    fragments = json.load(open(os.path.join(GAME, "data", "story_fragments.json")))
    for entry in fragments["items"]:
        lines.setdefault((entry["who"], entry["text"]), "neutral")
    shop_life = os.path.join(GAME, "data", "shop_life.json")
    if os.path.exists(shop_life):
        for entry in json.load(open(shop_life))["lines"]:
            lines.setdefault((entry["who"], entry["text"]), entry["mood"])
    return [(w, mood, t) for (w, t), mood in lines.items() if "%" not in t and t.strip()]


def md5(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


def cer(ref, hyp):
    strip = lambda s: re.sub(r"[\s，。！？、…—\-,.!?「」“”‘’：；:;（）()《》]", "", s)
    r, h = strip(ref), strip(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))


def tidy(a):
    """Trim silence at both ends (keep 80 ms), peak-normalise to -3 dBFS."""
    a = np.asarray(a, dtype=np.float32).reshape(-1)
    env = np.abs(a)
    thr = max(1e-3, env.max() * 0.02)
    idx = np.where(env > thr)[0]
    if len(idx):
        pad = int(0.08 * SR)
        a = a[max(0, idx[0] - pad): min(len(a), idx[-1] + pad)]
    return a / max(1e-6, np.abs(a).max()) * 0.7


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--include-file", default="", help="render only explicit lines from a JSON file")
    ap.add_argument("--redo", default="", help="regenerate lines whose text contains this string (or a who/md5 key)")
    ap.add_argument("--redo-pauses", action="store_true", help="also regenerate every line pause_check flags")
    args = ap.parse_args()
    import mlx.core as mx
    from mlx_audio.tts.utils import load_model
    cast = json.load(open(os.path.join(ROOT, "art", "manifests", "voice_cast.json")))["cast"]
    lines = [(entry["who"],entry.get("mood","neutral"),entry["text"]) for entry in json.load(open(args.include_file))["lines"]] if args.include_file else collect()
    only = set(args.only.split(",")) if args.only else None
    lines = [l for l in lines if l[0] in cast and cast[l[0]] and (not only or l[0] in only)]
    if args.limit:
        lines = lines[:args.limit]
    man = json.load(open(MAN)) if os.path.exists(MAN) else {"lines": {}}
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from pause_check import moved
    redo = set()
    for k, v in man["lines"].items():
        if args.redo and (args.redo in v["text"] or args.redo == k):
            redo.add(k)
        if args.redo_pauses and moved(v["text"], v["asr"]):
            redo.add(k)
    if redo:
        lines = [l for l in lines if (l[0] + "/" + md5(l[2])) in redo]
        print("redo", len(lines), "lines", flush=True)
    cv = base = None
    from mlx_audio.stt import load as load_stt
    asr = load_stt("mlx-community/Qwen3-ASR-0.6B-8bit")
    t0 = time.time()
    done = 0
    for who, mood, text in lines:
        key = md5(text)
        dst = os.path.join(OUT, who, key + ".ogg")
        if not redo and os.path.exists(dst) and man["lines"].get(who + "/" + key):
            continue
        say = text
        for k2, v2 in PRON.items():
            say = say.replace(k2, v2)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        c = cast[who]
        best = None
        for attempt in range(5):
            mx.random.seed(1000 + attempt * 77 + len(text))
            if c["kind"] == "custom":
                if cv is None:
                    cv = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit")
                ins = c["instruct"].rstrip("。") + MOOD.get(mood, "")
                r = list(cv.generate_custom_voice(text=say, speaker=c["speaker"], language="Chinese", instruct=ins))
            else:
                if base is None:
                    base = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit")
                r = list(base.generate(text=say, ref_audio=os.path.join(ROOT, c["ref_audio"]), ref_text=c["ref_text"], lang_code="chinese"))
            a = tidy(np.concatenate([np.asarray(x.audio, dtype=np.float32).reshape(-1) for x in r]))
            tmp = "/tmp/_voice_line.wav"
            wavfile.write(tmp, SR, a)
            hyp = asr.generate(tmp, language="Chinese").text
            e = cer(say, hyp)
            # a take with a sentence break in the wrong place counts as worse than any misread character
            score = e + (1.0 if moved(say, hyp) else 0.0)
            if best is None or score < best[0]:
                best = (score, a, hyp, attempt, e)
            if score <= 0.3:
                break
        score, a, hyp, attempt, e = best
        import soundfile as sf
        sf.write(dst, a, SR, format="OGG", subtype="VORBIS")
        man["lines"][who + "/" + key] = {"who": who, "mood": mood, "text": text, "file": os.path.relpath(dst, ROOT),
                                         "seconds": round(len(a) / SR, 2), "cer": round(e, 3), "asr": hyp, "attempts": attempt + 1,
                                         "tts_text": say if say != text else None, "pause_ok": score - e < 0.5}
        done += 1
        if done % 10 == 0:
            json.dump(man, open(MAN, "w"), ensure_ascii=False, indent=1)
            print(f"{done} lines, {time.time() - t0:.0f} s", flush=True)
    json.dump(man, open(MAN, "w"), ensure_ascii=False, indent=1)
    bad = [v for v in man["lines"].values() if v["cer"] > 0.3 or not v.get("pause_ok", True)]
    print(f"DONE {done} new, {len(man['lines'])} total, {len(bad)} above CER 0.3, {time.time() - t0:.0f} s", flush=True)


if __name__ == "__main__":
    main()
