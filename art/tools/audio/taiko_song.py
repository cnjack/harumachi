"""Taiko mini-game song and its note chart, generated together so they always line up.

    <venv>/python art/tools/audio/taiko_song.py

Writes game/assets/audio/music/taiko.ogg and game/data/taiko_chart.json. The chart is a list of
{"t": seconds from the start of the file, "k": "don" | "ka"}. The track carries the fue melody,
the shime-daiko pulse, the chanchiki bell and a soft guide drum on every chart note; the loud
hit sounds come from the game when the player strikes.
"""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from synth_core import SR, Mix, flute, taiko, ka, bell, reverb, master, write, hz, butter, noise, tt  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BPM = 132
BEAT = 60.0 / BPM
E8 = BEAT / 2
COUNT_IN_BARS = 2
T0 = COUNT_IN_BARS * 4 * BEAT

CHART = [
    # A: quarter notes, first ka
    "D...D...", "D...D...", "D.D.D...", "D...K...", "D...D...", "D.D.D.D.",
    # B: don / ka alternation
    "D.K.D.K.", "D.D.K...", "D.K.D.K.", "DDD.K...", "D.K.D.K.", "D.D.KK..",
    # C: eighth-note figures
    "DKD.DKD.", "D.K.DDK.", "DKDKD...", "K.K.D.D.", "DKD.DKD.", "DDKKDD..",
    # D: finale
    "D.DKD.DK", "DKDKD.K.", "D.D.DKDK", "KDKDD...", "DDDDKKKK", "D...D...",
]
# fue phrases: (midi, eighths), two bars each
YO = {"D5": 74, "E5": 76, "G5": 79, "A5": 81, "B5": 83, "D6": 86, "E6": 88}
P = {
    1: [("A5", 2), ("B5", 1), ("A5", 1), ("G5", 2), ("E5", 2), ("D5", 3), ("E5", 1), ("G5", 4)],
    2: [("A5", 2), ("D6", 2), ("B5", 1), ("A5", 1), ("G5", 2), ("A5", 2), ("G5", 1), ("E5", 1), ("D5", 4)],
    3: [("D6", 1), ("E6", 1), ("D6", 2), ("B5", 2), ("A5", 2), ("B5", 1), ("A5", 1), ("G5", 2), ("A5", 4)],
    4: [("G5", 2), ("A5", 1), ("B5", 1), ("D6", 2), ("B5", 2), ("A5", 2), ("G5", 2), ("E5", 2), ("D5", 2)],
}
PHRASES = [1, 2, 1, 3, 4, 3, 1, 3, 4, 2, 3, 4]


def shime(vel):
    n = int(0.16 * SR)
    t = tt(n)
    f = 520 + 160 * np.exp(-t / 0.01)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05)
    snap = butter(noise(n), "band", [1800, 5000]) * np.exp(-t / 0.008) * 0.5
    return (body + snap) * vel * 0.18


def main():
    bars = len(CHART)
    dur = T0 + bars * 4 * BEAT + 4 * BEAT + 2.5
    mx = Mix(dur)
    notes = []
    # count-in: shime clicks on beats, chanchiki on the last bar
    for b in range(COUNT_IN_BARS * 4):
        mx.add(shime(0.9 if b % 4 == 0 else 0.6), b * BEAT, 0.1)
    # chart + guide drum
    for bi, row in enumerate(CHART):
        for si, c in enumerate(row):
            t = T0 + bi * 4 * BEAT + si * E8
            if c == "D":
                notes.append({"t": round(t, 4), "k": "don"})
                mx.add(taiko(0.5), t, -0.05, 0.55)
            elif c == "K":
                notes.append({"t": round(t, 4), "k": "ka"})
                mx.add(ka(0.5), t, 0.05, 0.6)
    # final big hit
    end_t = T0 + bars * 4 * BEAT
    notes.append({"t": round(end_t, 4), "k": "don"})
    mx.add(taiko(0.9), end_t, 0.0, 0.8)
    # pulse: shime on every eighth (accent on beats), odaiko on bar starts, chanchiki bell
    for e in range(bars * 8 + 2):
        t = T0 + e * E8
        mx.add(shime(0.55 if e % 2 == 0 else 0.3), t, 0.25)
        if e % 8 == 0:
            mx.add(taiko(0.35), t, 0.0, 0.5)
        if e % 8 in (2, 3, 6):
            mx.add(bell(hz(96) if e % 8 != 3 else hz(91), 0.35, 0.18, "glock"), t, -0.35, 0.5)
    # fue melody over the chart bars
    t = T0
    for ph in PHRASES:
        for name, ln in P[ph]:
            mx.add(flute(hz(YO[name]), ln * E8 * 0.94, 0.55), t, -0.15, 0.9)
            t += ln * E8
    # ending phrase ring-out
    mx.add(flute(hz(YO["D6"]), BEAT * 2.5, 0.5), end_t, -0.15, 0.9)
    st = reverb(mx.buf, 1.6, 0.22)
    st = master(st[:, :int(dur * SR)], -17.0, -1.0)
    fade_n = int(1.2 * SR)
    st[:, -fade_n:] *= np.linspace(1, 0, fade_n)
    write(os.path.join(ROOT, "game", "assets", "audio", "music", "taiko.ogg"), st)
    chart = {"title": "晴町祭囃子", "bpm": BPM, "offset": round(T0, 4), "duration": round(dur, 3),
             "notes": notes}
    with open(os.path.join(ROOT, "game", "data", "taiko_chart.json"), "w") as f:
        json.dump(chart, f, ensure_ascii=False, indent=1)
    print("taiko", round(dur, 1), "s", len(notes), "notes")


if __name__ == "__main__":
    main()
