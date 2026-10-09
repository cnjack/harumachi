"""Compositions for 晴町日常. One leitmotif (royal-road progression IV-V-iii-vi) runs through
the title, town and ending cues; the evening market has its own pentatonic festival tune.
"""
from synth_core import *

QUAL = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
        "6": [0, 4, 7, 9], "7sus4": [0, 5, 7, 10], "sus4": [0, 5, 7], "sus2": [0, 2, 7], "add9": [0, 4, 7, 14]}


def pc(name):
    v = NOTE[name[0]]
    for ch in name[1:]:
        v += 1 if ch == "#" else -1 if ch == "b" else 0
    return v % 12


def chord(sym, transpose=0):
    """'G/B' -> (root pc, intervals, bass pc)."""
    bass_name = None
    if "/" in sym:
        sym, bass_name = sym.split("/")
    k = 2 if len(sym) > 1 and sym[1] in "#b" else 1
    r = (pc(sym[:k]) + transpose) % 12
    b = (pc(bass_name) + transpose) % 12 if bass_name else r
    return r, QUAL[sym[k:]], b


def voice(ch, lo):
    r, iv, _ = ch
    return sorted(lo + ((r + i - lo) % 12) for i in iv)


def low(pcv, lo):
    return lo + ((pcv - lo) % 12)


def mel(bars, transpose=0):
    out = []
    for i, bar in enumerate(bars):
        for tok in bar.split(","):
            n, b, d = tok.split()
            out.append((i, float(b), float(d), m(n) + transpose))
    return out


def segs(ch_row, transpose=0):
    """Bar chord list -> [(bar, beat, beats, chord)]."""
    out = []
    for i, c in enumerate(ch_row):
        cs = c if isinstance(c, list) else [c]
        span = 4 / len(cs)
        for j, s in enumerate(cs):
            out.append((i, j * span, span, chord(s, transpose)))
    return out


def hum(v, spread=0.06):
    return v * rng.uniform(1 - spread, 1 + spread / 2)


def jit(t, s=0.006):
    return t + rng.normal(0, s)


# ------------------------------------------------------------------ the leitmotif (G major)
CH_A = ["Cmaj7", "D6", "Bm7", "Em7", "Am7", ["D7sus4", "D7"], "Gmaj7", "G6"]
CH_B = ["Em7", "Cmaj7", "G/B", "Am7", "Cmaj7", "D", ["Bm7", "E7"], ["Am7", "D7"]]
MEL_A = [
    "E5 0 1.5, D5 1.5 .5, E5 2 1, G5 3 1",
    "F#5 0 1.5, E5 1.5 .5, D5 2 2",
    "D5 0 1, B4 1 .5, D5 1.5 .5, F#5 2 1.5, E5 3.5 .5",
    "E5 0 2.5, D5 2.5 .5, B4 3 1",
    "C5 0 1, E5 1 1, A5 2 1.5, G5 3.5 .5",
    "G5 0 1, F#5 1 1, E5 2 1, F#5 3 1",
    "D5 0 1.5, B4 1.5 .5, D5 2 1, G5 3 1",
    "F#5 0 1, G5 1 3",
]
MEL_B = [
    "B5 0 1.5, A5 1.5 .5, G5 2 1, B5 3 1",
    "A5 0 1.5, G5 1.5 .5, E5 2 2",
    "D5 0 1, G5 1 1, B5 2 1.5, A5 3.5 .5",
    "G5 0 2, E5 2 1, C5 3 1",
    "E5 0 1, G5 1 1, C6 2 1.5, B5 3.5 .5",
    "A5 0 2, F#5 2 1, D5 3 1",
    "F#5 0 1, D5 1 1, G#5 2 1, B5 3 1",
    "A5 0 1.5, G5 1.5 .5, F#5 2 1, A5 3 1",
]


def day():
    """Town theme: nylon guitar, piano melody, bass, pad; 92 BPM, 32 bars, loops."""
    bpm = 92
    B = 60 / bpm
    bars = 32
    mx = Mix(bars * 4 * B + 6)
    for sec in range(4):
        rows = (CH_A, MEL_A) if sec % 2 == 0 else (CH_B, MEL_B)
        b0 = sec * 8
        for bar, beat, span, ch in segs(rows[0]):
            t0 = (b0 + bar) * 4 * B + beat * B
            r, iv, bp = ch
            tones = voice(ch, 52)
            root = low(bp, 43)
            pat = [root] + tones + [tones[0] + 12, tones[-1], tones[1], tones[0]]
            for k in range(int(span * 2)):
                v = 0.4 if k == 0 else 0.36
                mx.add(pluck(hz(pat[k % len(pat)]), 1.4, hum(v), 0.45, 2.4), jit(t0 + k * B / 2), -0.3, 0.9)
            # bass
            bl = low(bp, 36)
            if sec == 0:
                mx.add(bass(hz(bl), span * B * 0.95, 0.42), t0, 0.0)
            elif sec == 1 or span < 4:
                mx.add(bass(hz(bl), span * B * 0.48, 0.45), t0, 0.0)
                mx.add(bass(hz(bl + 7), span * B * 0.45, 0.4), t0 + span * B / 2, 0.0)
            else:
                for bt, dd, off in ((0, 1.4, 0), (1.5, 0.45, 0), (2, 0.9, 7), (3, 0.9, 12)):
                    mx.add(bass(hz(bl + off), dd * B, 0.44), t0 + bt * B, 0.0)
            pv = [0.07, 0.14, 0.15, 0.2][sec]
            mx.add(pad([hz(x) for x in voice(ch, 57)], span * B, pv, 0.6, 1.2), t0, 0.15)
            if sec == 3 and beat == 0:
                mx.add(bell(hz(voice(ch, 57)[-1] + 24), 2.0, 0.12, "glock"), t0, 0.4)
        for bar, beat, dur, n in mel(rows[1]):
            t0 = (b0 + bar) * 4 * B + beat * B
            v = [0.55, 0.6, 0.58, 0.64][sec]
            mx.add(piano(hz(n), dur * B * 1.05, hum(v)), jit(t0, 0.004), 0.12)
            if sec == 2:
                mx.add(bell(hz(n + 12), 1.2, 0.16, "glock"), t0, 0.35)
            if sec == 3:
                mx.add(piano(hz(n - 12), dur * B, hum(0.3)), jit(t0, 0.004), 0.05)
        if sec in (1, 3):
            for k in range(64):
                mx.add(shaker(0.2 if k % 2 else 0.11), jit(b0 * 4 * B + k * B / 2, 0.004), 0.45)
        if sec >= 2:
            for bar in range(8):
                mx.add(kick(0.22), (b0 + bar) * 4 * B, 0.0)
    st = reverb(mx.buf, 1.9, 0.26)
    return master(wrap_loop(st, int(bars * 4 * B * SR)), -20)


def title():
    """Title theme: solo piano with a string pad; the leitmotif in D major at 70 BPM, 16 bars, loops."""
    bpm, tr = 70, -5
    B = 60 / bpm
    bars = 16
    mx = Mix(bars * 4 * B + 8)
    for sec in range(2):
        rows = (CH_A, MEL_A) if sec == 0 else (CH_B, MEL_B)
        b0 = sec * 8
        for bar, beat, span, ch in segs(rows[0], tr):
            t0 = (b0 + bar) * 4 * B + beat * B
            tones = voice(ch, 50)
            root = low(ch[2], 38)
            pat = [root, tones[0], tones[1], tones[-1], tones[1] + 12, tones[-1], tones[1], tones[0]]
            for k in range(int(span * 2)):
                mx.add(piano(hz(pat[k % 8]), B * 1.6, hum(0.36 if k == 0 else 0.28)), jit(t0 + k * B / 2, 0.005), -0.2)
            if sec == 1:
                mx.add(pad([hz(x) for x in voice(ch, 57)], span * B, 0.11, 1.2, 1.8, 0.28), t0, 0.1)
            if beat == 0 and bar in (0, 4):
                mx.add(bell(hz(voice(ch, 57)[-1] + 24), 2.4, 0.1, "celesta"), t0, 0.4)
        for bar, beat, dur, n in mel(rows[1], tr):
            t0 = (b0 + bar) * 4 * B + beat * B
            mx.add(piano(hz(n), dur * B * 1.1, hum(0.5 if sec == 0 else 0.56)), jit(t0, 0.005), 0.15)
            if sec == 1:
                mx.add(piano(hz(n + 12), dur * B, hum(0.2)), jit(t0, 0.005), 0.25)
    st = reverb(mx.buf, 2.4, 0.32)
    return master(wrap_loop(st, int(bars * 4 * B * SR)), -21)


def ending():
    """End-of-weekend cue: the leitmotif's last phrase slowed down, resolving on a held Dadd9."""
    bpm, tr = 64, -5
    B = 60 / bpm
    ch_row = CH_A[4:8]
    mel_rows = MEL_A[4:8]
    mx = Mix(4 * 4 * B + 12)
    for bar, beat, span, ch in segs(ch_row, tr):
        t0 = bar * 4 * B + beat * B
        tones = voice(ch, 50)
        root = low(ch[2], 38)
        pat = [root, tones[0], tones[1], tones[-1], tones[1] + 12, tones[-1], tones[1], tones[0]]
        for k in range(int(span * 2)):
            mx.add(piano(hz(pat[k % 8]), B * 1.8, hum(0.3)), jit(t0 + k * B / 2, 0.005), -0.2)
        mx.add(pad([hz(x) for x in voice(ch, 57)], span * B, 0.12, 0.9, 1.6, 0.3), t0, 0.1)
    for bar, beat, dur, n in mel(mel_rows, tr):
        mx.add(piano(hz(n), dur * B * 1.1, hum(0.55)), jit(bar * 4 * B + beat * B, 0.005), 0.15)
    tf = 4 * 4 * B
    for k, n in enumerate([38, 50, 57, 62, 66, 69, 76]):
        mx.add(piano(hz(n), 5.5, 0.45 if k else 0.5, 1.2), tf + k * 0.07, -0.3 + k * 0.1)
    mx.add(pad([hz(x) for x in (62, 66, 69, 76)], 5.0, 0.16, 1.0, 3.0, 0.3), tf, 0.0)
    for k, n in enumerate([81, 86, 90, 93]):
        mx.add(bell(hz(n), 3.0, 0.14, "celesta"), tf + 0.6 + k * 0.16, 0.2 + k * 0.1)
    st = reverb(mx.buf, 2.6, 0.34)
    st = master(st, -20)
    loud = np.nonzero(np.max(np.abs(st), axis=0) > dbv(-50))[0]
    st = st[:, :loud[-1] + int(0.3 * SR)]
    k = int(2.0 * SR)
    st[:, -k:] *= np.linspace(1, 0, k) ** 2
    return st


# ------------------------------------------------------------------ evening market (C major pentatonic)
MK_CH = ["C", "Am", "F", "G", "C", "Am", ["Dm7", "G"], "C", "F", "G", "Em7", "Am", "F", "G", "F", ["G7sus4", "G"]]
MK_MEL = [
    "E5 0 .5, G5 .5 .5, A5 1 1, G5 2 .5, E5 2.5 .5, D5 3 1",
    "C5 0 .5, D5 .5 .5, E5 1 1, A4 2 2",
    "C5 0 1, A4 1 .5, C5 1.5 .5, D5 2 1, E5 3 1",
    "D5 0 2.5, G4 2.5 .5, A4 3 .5, C5 3.5 .5",
    "E5 0 .5, G5 .5 .5, A5 1 1, C6 2 1, A5 3 1",
    "G5 0 1, E5 1 1, A5 2 1.5, G5 3.5 .5",
    "E5 0 1, D5 1 1, C5 2 1, D5 3 1",
    "C5 0 3",
    "A5 0 1, C6 1 1, A5 2 .5, G5 2.5 .5, E5 3 1",
    "G5 0 1.5, E5 1.5 .5, D5 2 2",
    "E5 0 .5, G5 .5 .5, E5 1 .5, D5 1.5 .5, B4 2 1, D5 3 1",
    "A4 0 2, C5 2 1, D5 3 1",
    "E5 0 1, G5 1 1, A5 2 1, C6 3 1",
    "D6 0 2, C6 2 1, A5 3 1",
    "C6 0 1, A5 1 1, G5 2 1, E5 3 1",
    "D5 0 2, E5 2 .5, G5 2.5 1.5",
]


def market():
    """Evening market: shinobue-like flute, koto plucks, taiko and hand percussion; 100 BPM, 32 bars, loops."""
    bpm = 100
    B = 60 / bpm
    bars = 32
    mx = Mix(bars * 4 * B + 6)
    for part in range(2):
        b0 = part * 16
        for bar, beat, span, ch in segs(MK_CH):
            t0 = (b0 + bar) * 4 * B + beat * B
            tones = voice(ch, 60)
            pat = [tones[0], tones[1], tones[-1], tones[1] + 12, tones[-1] + 12, tones[-1], tones[1], tones[-1]]
            for k in range(int(span * 2)):
                mx.add(pluck(hz(pat[k % 8]), 0.9, hum(0.34 if k % 2 == 0 else 0.26), 0.8, 1.3), jit(t0 + k * B / 2), 0.35, 0.8)
            bl = low(ch[2], 36)
            mx.add(bass(hz(bl), span * B * 0.45, 0.46), t0, 0.0)
            mx.add(bass(hz(bl + 7), span * B * 0.35, 0.4), t0 + span * B / 2, 0.0)
            mx.add(pad([hz(x) for x in voice(ch, 55)], span * B, 0.1, 0.5, 1.0, 0.3), t0, -0.2)
        for bar in range(16):
            t0 = (b0 + bar) * 4 * B
            mx.add(taiko(0.42), jit(t0, 0.003), -0.05)
            mx.add(taiko(0.24), jit(t0 + 2 * B, 0.003), -0.05)
            if bar % 8 == 7:
                mx.add(taiko(0.3), t0 + 3 * B, -0.05)
                mx.add(taiko(0.34), t0 + 3.5 * B, -0.05)
            for bt in (1, 3):
                mx.add(ka(0.3), jit(t0 + bt * B, 0.003), 0.25)
            if part == 1:
                mx.add(ka(0.18), jit(t0 + 3.5 * B, 0.003), 0.25)
                for bt in (1, 3):
                    mx.add(clap(0.2), jit(t0 + bt * B, 0.006), -0.35)
            for k in range(8):
                mx.add(shaker(0.18 if k % 2 else 0.1), jit(t0 + k * B / 2, 0.004), 0.5)
        for bar, beat, dur, n in mel(MK_MEL):
            t0 = (b0 + bar) * 4 * B + beat * B
            mx.add(flute(hz(n), dur * B * 0.95, hum(0.5)), jit(t0, 0.004), 0.05)
            if part == 1:
                mx.add(marimba(hz(n - 12), 0.7, hum(0.32)), jit(t0, 0.004), -0.25)
                if bar >= 8:
                    mx.add(bell(hz(n + 12), 1.0, 0.1, "glock"), t0, 0.4)
    st = reverb(mx.buf, 1.5, 0.2)
    return master(wrap_loop(st, int(bars * 4 * B * SR)), -19)


MUSIC = {"title": (title, True), "day": (day, True), "market": (market, True), "ending": (ending, False)}
