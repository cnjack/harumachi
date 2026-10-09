"""Round 2 voice candidates for 春 (Haru, a grandmother in her seventies).

    cd /Users/jack/workpath/opensource/mlx-audio
    uv run python "<repo>/art/tools/voice/make_haru_v2.py" <out_dir>

Round 1 used young speakers told to "sound old"; the instruction changed the delivery but not the
timbre. This round changes the timbre itself:
  V*: Qwen3-TTS VoiceDesign, a voice built from a written description of an elderly woman;
  W*: WORLD vocoder aging (pyworld) of a CustomVoice take: lower F0 with slow jitter, more aperiodic
      (breathy / hoarse) energy, formants pulled down a little; then the Base model clones it;
  X:  Uncle Fu (older male) moved up into an old woman's range with WORLD, then cloned.
"""
import json, os, re, sys, time
import numpy as np
import pyworld as pw
from scipy.io import wavfile
from scipy.signal import resample

OUT = os.path.abspath(sys.argv[1])
os.makedirs(OUT, exist_ok=True)
SR = 24000
LINES = ["你看这丛紫阳花，今年开得特别蓝。土里埋了几根旧铁钉，颜色就会变蓝。这是我家老头子教我的。",
         "膝盖说要下雨了……可是天空说不会。我信天空。"]
REF_ZH = "我今天去河边走了走，风很舒服，花也开得很好。"
DESIGN = {
    "V1": ("VoiceDesign · 慈祥", "一位七十多岁的老奶奶，声音苍老，音调偏低，略带沙哑和气声，说话很慢，温柔慈祥，句尾轻轻上扬，带着笑意。"),
    "V2": ("VoiceDesign · 沙哑", "年迈的老太太，嗓音低沉粗糙，有明显的沙哑和一点颤音，气息有些不稳，语调平和，不紧不慢。"),
    "V3": ("VoiceDesign · 乡下外婆", "乡下小镇里爱种花的外婆，七十五岁，声音干净但明显苍老，音色偏暗，说话慢悠悠的，像在院子里和孙辈聊天。"),
}
AGING = {  # id: (label, source speaker, source instruct, f0 factor, formant factor, breath, jitter)
    "W1": ("Serena · WORLD 老化", "Serena", "温和、慢慢地说话的女性。", 0.80, 0.95, 0.35, 0.025),
    "W2": ("Vivian · WORLD 老化（更沙哑）", "Vivian", "温和、慢慢地说话的女性，带着笑意。", 0.76, 0.93, 0.5, 0.035),
    "X": ("Uncle Fu → 老奶奶（跨性别老化）", "Uncle_Fu", "温和、缓慢的老人。", 1.42, 1.10, 0.3, 0.02),
}


def to_np(a):
    return np.array(a, dtype=np.float32).reshape(-1)


def save(path, a):
    a = a / max(1e-6, np.abs(a).max()) * 0.85
    wavfile.write(path, SR, a.astype(np.float32))


def age(x, f0f, fmt, breath, jitter, tempo=0.93):
    x = x.astype(np.float64)
    f0, t = pw.harvest(x, SR, f0_floor=60, f0_ceil=600, frame_period=5.0)
    sp = pw.cheaptrick(x, f0, t, SR)
    ap = pw.d4c(x, f0, t, SR)
    n = len(f0)
    # slow wobble + a little random jitter: an older voice does not hold its pitch still
    wob = 1.0 + jitter * (np.sin(np.arange(n) * 2 * np.pi * 5.5 * 0.005) * 0.6 + np.random.default_rng(3).standard_normal(n) * 0.4)
    f0 = f0 * f0f * wob
    # formant shift: warp the spectral envelope along frequency
    bins = sp.shape[1]
    src = np.clip(np.arange(bins) / fmt, 0, bins - 1)
    lo = np.floor(src).astype(int); hi = np.minimum(lo + 1, bins - 1); w = src - lo
    sp = sp[:, lo] * (1 - w) + sp[:, hi] * w
    # breathiness: raise aperiodicity, most in the upper bands
    ramp = np.linspace(0.3, 1.0, bins)[None, :]
    ap = np.clip(ap + breath * ramp * (1 - ap), 0, 0.999)
    # slower delivery: stretch the frames
    m = int(n / tempo)
    idx = np.linspace(0, n - 1, m)
    f0 = np.interp(idx, np.arange(n), f0)
    sp = np.array([np.interp(idx, np.arange(n), sp[:, k]) for k in range(bins)]).T
    ap = np.array([np.interp(idx, np.arange(n), ap[:, k]) for k in range(bins)]).T
    y = pw.synthesize(np.ascontiguousarray(f0), np.ascontiguousarray(sp), np.ascontiguousarray(ap), SR, 5.0)
    return y.astype(np.float32)


def cer(ref, hyp):
    strip = lambda s: re.sub(r"[\s，。！？、…—\-,.!?「」“”‘’：；:;（）()]", "", s)
    r, h = strip(ref), strip(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))


def main():
    from mlx_audio.tts.utils import load_model
    rows = []
    vd = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit")
    for vid, (label, ins) in DESIGN.items():
        files = []
        # a reference take in the designed voice keeps every line in the same voice (cloned below)
        r = list(vd.generate_voice_design(text=REF_ZH, language="Chinese", instruct=ins))
        ref = f"{OUT}/_ref_haru_{vid}.wav"
        save(ref, np.concatenate([to_np(x.audio) for x in r]))
        for k, tx in enumerate(LINES):
            r = list(vd.generate_voice_design(text=tx, language="Chinese", instruct=ins))
            p = f"haru2_{vid}_{k}.wav"
            save(f"{OUT}/{p}", np.concatenate([to_np(x.audio) for x in r]))
            files.append(p)
        rows.append({"char": "haru", "voice": vid, "label": label, "kind": "voice_design", "instruct": ins, "files": files, "texts": LINES,
                     "ref_audio": os.path.basename(ref), "ref_text": REF_ZH})
        print("done", vid, flush=True)
    del vd
    cv = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit")
    base = load_model("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit")
    for vid, (label, spk, ins, f0f, fmt, br, jit) in AGING.items():
        r = list(cv.generate_custom_voice(text=REF_ZH, speaker=spk, language="Chinese", instruct=ins))
        raw = np.concatenate([to_np(x.audio) for x in r])
        ref = f"{OUT}/_ref_haru_{vid}.wav"
        save(ref, age(raw, f0f, fmt, br, jit))
        files = []
        for k, tx in enumerate(LINES):
            r = list(base.generate(text=tx, ref_audio=ref, ref_text=REF_ZH, lang_code="chinese"))
            p = f"haru2_{vid}_{k}.wav"
            save(f"{OUT}/{p}", np.concatenate([to_np(x.audio) for x in r]))
            files.append(p)
        # also the aged take itself, un-cloned, for comparison
        rows.append({"char": "haru", "voice": vid, "label": label, "kind": "world_aged_clone", "speaker": spk, "instruct": ins,
                     "f0": f0f, "formant": fmt, "breath": br, "jitter": jit, "files": files, "texts": LINES,
                     "ref_audio": os.path.basename(ref), "ref_text": REF_ZH})
        print("done", vid, flush=True)
    del cv, base
    from mlx_audio.stt import load as load_stt
    asr = load_stt("mlx-community/Qwen3-ASR-0.6B-8bit")
    for row in rows:
        row["asr"] = [asr.generate(f"{OUT}/{f}", language="Chinese").text for f in row["files"]]
        row["cer"] = [round(cer(t, a), 3) for t, a in zip(row["texts"], row["asr"])]
        # median pitch of the result, to check it really sits lower than the round-1 voices
        sr, a = wavfile.read(f"{OUT}/{row['files'][0]}")
        f0, _ = pw.dio(a.astype(np.float64), sr, f0_floor=60, f0_ceil=600)
        row["median_f0_hz"] = round(float(np.median(f0[f0 > 0])), 1) if (f0 > 0).any() else 0
        print("asr", row["voice"], row["cer"], row["median_f0_hz"], flush=True)
    json.dump(rows, open(f"{OUT}/haru_v2.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
