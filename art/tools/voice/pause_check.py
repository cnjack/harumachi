"""Find voice lines whose pauses sit in the wrong place (a sentence break the TTS dropped and put
somewhere else nearby). The character error rate misses these: every character is right, only the
phrasing is wrong, e.g. "我是习惯了，不来反而睡不着" read as "我是习惯了不来，反而睡不着".

    python3 art/tools/voice/pause_check.py            # report on art/manifests/voice_lines.json
Uses the Qwen3-ASR transcript stored with each line (its punctuation follows the audio's pauses).
"""
import json, os, sys

P = "，。！？、…—,.!?；;：:「」“”（）()《》 "
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def breaks(t):
    out, k = set(), 0
    for ch in t:
        if ch in P:
            out.add(k)
        else:
            k += 1
    return out, k


def moved(text, asr):
    """Breaks of `text` that the reading dropped and moved 2-3 characters away."""
    rb, rn = breaks(text)
    ab, an = breaks(asr)
    if abs(rn - an) > 1:
        return []
    rb = {b for b in rb if 0 < b < rn}
    ab = {b for b in ab if 0 < b < an}
    lost = [r for r in rb if not any(abs(a - r) <= 1 for a in ab)]
    out = []
    for r in lost:
        near = [a for a in ab if 2 <= abs(a - r) <= 3 and not any(abs(a - x) <= 1 for x in rb)]
        if near:
            out.append((r, near[0]))
    return out


if __name__ == "__main__":
    d = json.load(open(os.path.join(ROOT, "art", "manifests", "voice_lines.json")))["lines"]
    bad = [(k, v) for k, v in d.items() if moved(v["text"], v["asr"])]
    for k, v in bad:
        print(k, "|", v["text"], "|", v["asr"])
    print(len(bad), "of", len(d))
