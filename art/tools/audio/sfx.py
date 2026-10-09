"""Sound effects for 晴町日常: footsteps per surface, UI, quest stingers and foley."""
from synth_core import *


def st(x, pan=0.0):
    a = (pan + 1) * math.pi / 4
    return np.stack([x * math.cos(a), x * math.sin(a)])


def grains(n, count, lo, hi, dec=0.004, spread=1.0):
    """Many tiny filtered clicks spread over n samples (gravel, soil, droplets)."""
    x = np.zeros(n)
    g = int(0.02 * SR)
    for _ in range(count):
        s = int(rng.beta(1.6, 3.0 * spread) * (n - g))
        c = rng.uniform(lo, hi)
        x[s:s + g] += butter(noise(g), "band", [c * 0.7, min(c * 1.4, 18000)]) * np.exp(-tt(g) / dec) * rng.uniform(0.3, 1)
    return x


# ------------------------------------------------------------------ footsteps
def step(surface):
    n = int(0.28 * SR)
    t = tt(n)
    x = np.zeros(n)
    heel = int(0.004 * SR)
    toe = int(rng.uniform(0.055, 0.075) * SR)
    if surface == "stone":
        thump = np.sin(2 * np.pi * rng.uniform(85, 115) * t) * np.exp(-t / 0.025)
        tap = butter(noise(n), "band", [rng.uniform(1300, 1800), 5200]) * np.exp(-t / 0.012)
        x += 0.6 * thump + 0.5 * tap
        sc = butter(noise(n - toe), "band", [2500, 7500]) * np.exp(-tt(n - toe) / 0.022) * np.clip(tt(n - toe) / 0.004, 0, 1)
        x[toe:] += 0.22 * sc
    elif surface == "gravel":
        x += 0.35 * np.sin(2 * np.pi * 90 * t) * np.exp(-t / 0.03)
        x += grains(n, 70, 1500, 7000, 0.003)
        x[toe:] += 0.7 * grains(n - toe, 40, 2000, 8000, 0.0025)
    elif surface == "grass":
        env = np.clip(t / 0.018, 0, 1) * np.exp(-t / 0.07)
        x += butter(noise(n), "band", [1800, 7000]) * env * 0.5
        x += 0.25 * grains(n, 25, 2500, 9000, 0.004)
        x += 0.25 * np.sin(2 * np.pi * 80 * t) * np.exp(-t / 0.03)
    elif surface == "tatami":  # soft woven straw: a muffled thud and a dry brush of rush
        x += 0.5 * np.sin(2 * np.pi * rng.uniform(95, 120) * t) * np.exp(-t / 0.035)
        env = np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.05)
        x += butter(noise(n), "band", [700, 3200]) * env * 0.35
        x[toe:] += 0.18 * butter(noise(n - toe), "band", [1500, 5000]) * np.exp(-tt(n - toe) / 0.03)
    else:  # wood floor, indoors
        f0 = rng.uniform(150, 190)
        x += (np.sin(2 * np.pi * f0 * t) + 0.4 * np.sin(2 * np.pi * f0 * 2.4 * t)) * np.exp(-t / 0.045)
        x += 0.25 * butter(noise(n), "band", [900, 3500]) * np.exp(-t / 0.008)
        x[toe:] += 0.3 * np.sin(2 * np.pi * f0 * 1.3 * tt(n - toe)) * np.exp(-tt(n - toe) / 0.03)
    x[:heel] *= np.linspace(0, 1, heel)
    return fade(x, 0, 0.05)


# ------------------------------------------------------------------ UI
def ui(kind):
    if kind == "hover":
        return fade(np.sin(2 * np.pi * 2600 * tt(int(0.03 * SR))) * np.exp(-tt(int(0.03 * SR)) / 0.006), 0.0005, 0.005)
    if kind == "click":
        n = int(0.09 * SR)
        t = tt(n)
        f = 1150 - 350 * np.clip(t / 0.03, 0, 1)
        return fade(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.02) + 0.2 * butter(noise(n), "high", 3000) * np.exp(-t / 0.004), 0.0005, 0.01)
    if kind in ("open", "close"):
        n = int(0.32 * SR)
        t = tt(n)
        shape = np.clip(t / 0.12, 0, 1) * np.exp(-t / 0.09) if kind == "open" else np.exp(-t / 0.06)
        swish = butter(noise(n), "band", [900, 6000]) * shape * 0.35
        note = marimba(hz(79 if kind == "open" else 74), 0.32, 0.45)
        k = int(0.05 * SR) if kind == "open" else 0
        swish[k:] += note[:n - k]
        return fade(swish, 0.002, 0.03)
    if kind == "next":
        return marimba(hz(81), 0.18, 0.4)
    if kind == "select":
        a = marimba(hz(76), 0.3, 0.4)
        b = marimba(hz(81), 0.3, 0.45)
        k = int(0.06 * SR)
        a[k:] += b[:len(a) - k]
        return a
    if kind == "invalid":
        n = int(0.32 * SR)
        x = np.zeros(n)
        for k, (f, at) in enumerate(((330, 0.0), (262, 0.13))):
            s = int(at * SR)
            m_ = int(0.12 * SR)
            tone = np.tanh(1.8 * np.sin(2 * np.pi * f * tt(m_))) * np.exp(-tt(m_) / 0.05)
            x[s:s + m_] += tone
        return butter(x, "low", 2500)
    if kind == "rotate":
        n = int(0.12 * SR)
        x = np.zeros(n)
        for at in (0.0, 0.045):
            s = int(at * SR)
            x[s:s + int(0.02 * SR)] += butter(noise(int(0.02 * SR)), "band", [2000, 6000]) * np.exp(-tt(int(0.02 * SR)) / 0.003)
        return x
    raise KeyError(kind)


def arp(notes, gap, kind="celesta", dur=1.2, vel=0.5, tail=1.0):
    n = int((gap * len(notes) + dur + tail) * SR)
    x = np.zeros(n)
    for k, nt in enumerate(notes):
        s = int(k * gap * SR)
        b = bell(hz(nt), dur, vel, kind)
        x[s:s + len(b)] += b
    return x


def stinger(kind):
    if kind == "item":
        x = arp([84, 88, 91], 0.06, "celesta", 0.9, 0.5, 0.3)
        g = bell(hz(96), 0.8, 0.3, "glock")
        k = int(0.14 * SR)
        x[k:k + len(g)] += g[:len(x) - k]
        return x
    if kind == "quest_accept":
        return arp([79, 86], 0.12, "glock", 1.2, 0.5, 0.3)
    if kind == "step":
        return arp([88], 0.0, "celesta", 0.8, 0.4, 0.2)
    if kind == "quest_done":
        mx = Mix(3.2)
        for k, nt in enumerate([72, 76, 79, 84]):
            mx.add(piano(hz(nt), 0.4, 0.55), k * 0.085, -0.2 + 0.13 * k)
            mx.add(bell(hz(nt + 12), 1.2, 0.25, "celesta"), k * 0.085, 0.2)
        for k, nt in enumerate([60, 67, 71, 74, 76]):
            mx.add(piano(hz(nt), 1.6, 0.4), 0.38 + 0.02 * k, -0.2 + 0.1 * k)
        mx.add(pad([hz(x) for x in (64, 67, 71, 74)], 1.2, 0.2, 0.2, 1.2, 0.35), 0.38, 0.0)
        mx.add(arp([96, 100, 103, 108], 0.05, "glock", 0.8, 0.22, 0.3), 0.5, 0.35)
        return reverb(mx.buf, 1.6, 0.28)
    if kind == "coin":
        x = np.zeros(int(0.6 * SR))
        for nt, at in ((95, 0.0), (100, 0.07)):
            b = bell(hz(nt), 0.45, 0.6, "metal")
            s = int(at * SR)
            x[s:s + len(b)] += b[:len(x) - s]
        return x
    if kind == "save":
        return arp([79, 86, 91], 0.09, "glass", 1.0, 0.35, 0.4)
    if kind == "sparkle":
        return arp([84, 86, 88, 91, 93, 96, 98, 100], 0.045, "celesta", 0.8, 0.28, 0.6)
    if kind == "fanfare":
        mx = Mix(3.6)
        mx.add(taiko(0.8), 0.0, -0.1)
        mx.add(taiko(0.7), 0.28, -0.1)
        for k, nt in enumerate([72, 74, 76, 79, 81, 84]):
            mx.add(flute(hz(nt), 0.1 if k < 5 else 0.9, 0.55), 0.55 + k * 0.075, 0.1)
        mx.add(clap(0.6), 1.0, -0.4)
        mx.add(clap(0.6), 1.25, 0.4)
        mx.add(bell(hz(96), 1.6, 0.25, "glock"), 1.0, 0.3)
        mx.add(taiko(0.6), 1.0, -0.1)
        return reverb(mx.buf, 1.4, 0.25)
    raise KeyError(kind)


# ------------------------------------------------------------------ foley
def foley(kind):
    if kind == "door":  # sliding wooden door with a paper screen: roll, rattle, soft clack
        n = int(0.9 * SR)
        t = tt(n)
        roll_env = np.clip(t / 0.06, 0, 1) * np.clip((0.6 - t) / 0.08, 0, 1)
        rattle = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 23 * t + 2 * np.sin(2 * np.pi * 3 * t)))
        x = butter(noise(n), "band", [180, 1200]) * roll_env * rattle * 0.5
        x += 0.25 * grains(n, 30, 800, 3000, 0.004) * roll_env
        k = int(0.6 * SR)
        m_ = n - k
        x[k:] += (np.sin(2 * np.pi * 210 * tt(m_)) + 0.5 * np.sin(2 * np.pi * 530 * tt(m_))) * np.exp(-tt(m_) / 0.04) * 0.8
        x[k:] += butter(noise(m_), "band", [1000, 4000]) * np.exp(-tt(m_) / 0.006) * 0.5
        return fade(x, 0.005, 0.05)
    if kind == "mailbox":
        x = np.zeros(int(0.7 * SR))
        for at, v in ((0.0, 0.7), (0.24, 1.0)):
            b = bell(rng.uniform(480, 560), 0.4, v, "metal") + 0.3 * butter(noise(int(0.4 * SR)), "band", [2000, 6000]) * np.exp(-tt(int(0.4 * SR)) / 0.005)
            s = int(at * SR)
            x[s:s + len(b)] += b[:len(x) - s]
        return x
    if kind in ("water_tap", "water_pour"):
        n = int(1.8 * SR)
        t = tt(n)
        env = np.clip(t / 0.15, 0, 1) * np.clip((1.8 - t) / 0.35, 0, 1)
        if kind == "water_tap":
            x = butter(noise(n), "band", [400, 3500]) * (0.7 + 0.3 * butter(noise(n), "low", 12)) * 0.6
            for _ in range(60):
                s = int(rng.uniform(0, 1.7) * SR)
                d = int(0.03 * SR)
                f0 = rng.uniform(900, 2500)
                x[s:s + d] += np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.8 * tt(d) / 0.03)) / SR) * np.exp(-tt(d) / 0.008) * 0.25
        else:
            x = butter(noise(n), "high", 2200) * 0.35 + 0.7 * grains(n, 260, 2500, 9000, 0.002, 0.3)
            x += butter(noise(n), "band", [300, 900]) * 0.12
        return fade(x * env, 0.01, 0.1)
    if kind == "soil":
        n = int(0.8 * SR)
        x = grains(n, 120, 200, 1800, 0.006, 0.6) + 0.3 * butter(noise(n), "low", 700) * np.exp(-tt(n) / 0.25)
        return fade(x, 0.005, 0.1)
    if kind == "paper":
        n = int(0.55 * SR)
        t = tt(n)
        crinkle = (butter(noise(n), "low", 30) > 0.3).astype(float) * 0.6 + 0.4
        x = butter(noise(n), "band", [1200, 8000]) * crinkle * np.clip(t / 0.05, 0, 1) * np.exp(-t / 0.2)
        x += 0.5 * grains(n, 40, 2000, 7000, 0.003)
        return fade(x, 0.005, 0.05)
    if kind == "place":
        n = int(0.35 * SR)
        t = tt(n)
        x = (np.sin(2 * np.pi * 130 * t) + 0.5 * np.sin(2 * np.pi * 320 * t)) * np.exp(-t / 0.06)
        x += 0.4 * np.sin(2 * np.pi * 620 * t) * np.exp(-t / 0.02) + 0.3 * butter(noise(n), "band", [800, 4000]) * np.exp(-t / 0.01)
        return fade(x, 0.0005, 0.05)
    if kind == "pickup":
        n = int(0.18 * SR)
        t = tt(n)
        f = 380 + 600 * np.clip(t / 0.09, 0, 1)
        return fade(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05), 0.002, 0.03)
    if kind == "basket":
        n = int(0.4 * SR)
        t = tt(n)
        x = 0.6 * np.sin(2 * np.pi * 110 * t) * np.exp(-t / 0.05) + 0.5 * grains(n, 50, 1200, 5000, 0.004)
        return fade(x, 0.001, 0.05)
    if kind == "flap":  # a small flock taking off: fast feathery flutters
        n = int(0.9 * SR)
        t = tt(n)
        x = np.zeros(n)
        for _ in range(5):
            s0 = rng.uniform(0.0, 0.25)
            rate = rng.uniform(14, 20)
            beat = np.clip(np.sin(2 * np.pi * rate * (t - s0)), 0, 1) ** 3 * (t > s0) * np.exp(-np.clip(t - s0, 0, None) / 0.35)
            x += butter(noise(n), "band", [700, 5000]) * beat * rng.uniform(0.3, 0.6)
        return fade(x, 0.005, 0.15)
    if kind == "hoe":  # blade into soil: thunk plus crumbling clods
        n = int(0.6 * SR)
        t = tt(n)
        x = (np.sin(2 * np.pi * 95 * t) + 0.4 * np.sin(2 * np.pi * 210 * t)) * np.exp(-t / 0.05) * 0.8
        x += butter(noise(n), "band", [300, 2500]) * np.exp(-t / 0.03) * 0.5 + 0.8 * grains(n, 90, 250, 2000, 0.006, 0.7)
        return fade(x, 0.001, 0.08)
    if kind == "pump":  # squeaky iron handle strokes, then the water gush
        n = int(1.9 * SR)
        t = tt(n)
        x = np.zeros(n)
        for at in (0.0, 0.42, 0.84):
            s0 = int(at * SR)
            d = int(0.3 * SR)
            tt_ = tt(d)
            f = 900 + 500 * np.sin(np.pi * tt_ / 0.3)
            sq = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt_ / 0.3) ** 2 * 0.25
            x[s0:s0 + d] += sq + 0.3 * np.sin(2 * np.pi * 140 * tt_) * np.exp(-tt_ / 0.05)
        g0 = int(0.95 * SR)
        m_ = n - g0
        env = np.clip(tt(m_) / 0.05, 0, 1) * np.clip((m_ / SR - tt(m_)) / 0.3, 0, 1)
        x[g0:] += butter(noise(m_), "band", [300, 3000]) * env * 0.55
        return fade(x, 0.003, 0.1)
    if kind == "boom":  # a distant firework: deep thump, then a shimmering crackle tail
        n = int(2.4 * SR)
        t = tt(n)
        x = butter(noise(n), "low", 180) * np.exp(-t / 0.35) * 1.4 + np.sin(2 * np.pi * 48 * t) * np.exp(-t / 0.25) * 0.8
        k = int(0.25 * SR)
        x[k:] += grains(n - k, 260, 2000, 8000, 0.003, 0.4) * np.exp(-tt(n - k) / 0.8) * 0.5
        return fade(reverb(np.stack([x, x]), 1.6, 0.3, 0.8)[0][:n] if False else x, 0.002, 0.3)
    if kind == "harvest":  # a plant pulled from the soil: rustle and a soft pop
        n = int(0.5 * SR)
        t = tt(n)
        x = butter(noise(n), "band", [1500, 7000]) * np.exp(-t / 0.12) * 0.4 + 0.6 * grains(n, 40, 300, 1500, 0.006, 0.5)
        k = int(0.18 * SR)
        f = 300 + 500 * np.clip(tt(n - k) / 0.04, 0, 1)
        x[k:] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt(n - k) / 0.04) * 0.7
        return fade(x, 0.002, 0.06)
    raise KeyError(kind)


# ------------------------------------------------------------------ mini-games
def _sweep(n, f0, f1, dec, shape="sin"):
    t = tt(n)
    f = f0 + (f1 - f0) * np.clip(t / (n / SR), 0, 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    w = np.sin(ph) if shape == "sin" else np.sign(np.sin(ph)) * 0.4
    return w * np.exp(-t / dec)


def _at(x, y, at):
    s = int(at * SR)
    x[s:s + len(y)] += y[:max(0, len(x) - s)]
    return x


def mg(kind):
    """Short, soft cues for the five house mini-games (count-in, judgements and actions)."""
    if kind == "count":
        return bell(hz(81), 0.5, 0.5, "glock")
    if kind == "go":
        return arp([84, 91], 0.07, "glock", 0.8, 0.55, 0.3)
    if kind == "good":
        return bell(hz(88), 0.45, 0.45, "celesta")
    if kind == "perfect":
        return arp([88, 93, 100], 0.045, "celesta", 0.7, 0.45, 0.3)
    if kind == "miss":
        n = int(0.28 * SR)
        return fade(_sweep(n, 320, 190, 0.09) * 0.7 + 0.2 * butter(noise(n), "low", 600) * np.exp(-tt(n) / 0.04), 0.002, 0.05)
    if kind == "result":
        return reverb(st(arp([72, 76, 79, 84, 88], 0.08, "celesta", 1.1, 0.4, 0.6)), 1.4, 0.25)
    # onigiri
    if kind == "rice_scoop":
        n = int(0.32 * SR)
        x = grains(n, 60, 500, 2600, 0.006, 0.7) + 0.3 * butter(noise(n), "low", 500) * np.exp(-tt(n) / 0.08)
        return fade(x, 0.004, 0.05)
    if kind == "rice_press":
        n = int(0.22 * SR)
        t = tt(n)
        x = 0.5 * np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.04) + 0.5 * grains(n, 35, 400, 1800, 0.005)
        return fade(x, 0.002, 0.04)
    if kind == "filling":
        n = int(0.25 * SR)
        t = tt(n)
        x = 0.6 * np.sin(2 * np.pi * (260 - 120 * np.clip(t / 0.05, 0, 1)) * t) * np.exp(-t / 0.05)
        x += 0.3 * butter(noise(n), "band", [300, 1500]) * np.exp(-t / 0.03)
        return fade(x, 0.002, 0.05)
    if kind == "nori":
        n = int(0.3 * SR)
        t = tt(n)
        crinkle = (butter(noise(n), "low", 60) > 0.2).astype(float) * 0.6 + 0.4
        x = butter(noise(n), "band", [2000, 9000]) * crinkle * np.clip(t / 0.02, 0, 1) * np.exp(-t / 0.08)
        return fade(x * 0.8, 0.002, 0.04)
    if kind == "serve":
        x = arp([79, 84, 88], 0.06, "glock", 0.8, 0.45, 0.3)
        return _at(x, foley("place") * 0.4, 0.0)
    if kind == "order_bad":
        n = int(0.4 * SR)
        x = _sweep(n, 420, 300, 0.12) * 0.5
        return fade(_at(x, _sweep(int(0.25 * SR), 360, 250, 0.1) * 0.5, 0.13), 0.002, 0.05)
    if kind == "customer_leave":
        return arp([76, 72, 67], 0.1, "celesta", 0.7, 0.35, 0.4)
    # unpack
    if kind == "place_good":
        return _at(foley("place") * 0.7, bell(hz(91), 0.5, 0.35, "celesta"), 0.03)
    if kind == "bump":
        n = int(0.2 * SR)
        t = tt(n)
        return fade(0.8 * np.sin(2 * np.pi * 95 * t) * np.exp(-t / 0.035) + 0.2 * butter(noise(n), "low", 900) * np.exp(-t / 0.02), 0.001, 0.04)
    if kind == "box_open":
        n = int(0.5 * SR)
        t = tt(n)
        x = butter(noise(n), "band", [300, 2500]) * np.clip(t / 0.05, 0, 1) * np.exp(-t / 0.12) * 0.6
        x = _at(x, grains(int(0.2 * SR), 20, 800, 3000, 0.004), 0.12)
        return fade(x, 0.003, 0.05)
    if kind == "box_fold":
        n = int(0.45 * SR)
        x = np.zeros(n)
        for at in (0.0, 0.16):
            m_ = int(0.18 * SR)
            _at(x, butter(noise(m_), "band", [200, 1400]) * np.exp(-tt(m_) / 0.04) * 0.6 + 0.4 * np.sin(2 * np.pi * 120 * tt(m_)) * np.exp(-tt(m_) / 0.03), at)
        return fade(x, 0.002, 0.05)
    if kind == "rotate":
        return ui("click") * 0.7
    # puzzle
    if kind == "slide":
        n = int(0.16 * SR)
        t = tt(n)
        x = butter(noise(n), "band", [500, 2500]) * np.clip(t / 0.02, 0, 1) * np.exp(-t / 0.05) * 0.5
        x += 0.5 * np.sin(2 * np.pi * 330 * t) * np.exp(-np.maximum(t - 0.1, 0) / 0.02) * (t > 0.1)
        return fade(x, 0.002, 0.03)
    if kind == "slide_blocked":
        n = int(0.14 * SR)
        t = tt(n)
        return fade(0.7 * np.sin(2 * np.pi * 150 * t) * np.exp(-t / 0.03), 0.001, 0.03)
    if kind == "hint":
        return arp([86, 93], 0.08, "glass", 0.7, 0.35, 0.3)
    if kind == "solved":
        return stinger("quest_done")
    # goldfish
    if kind in ("water_in", "water_out", "splash"):
        n = int((0.35 if kind != "splash" else 0.5) * SR)
        t = tt(n)
        base = butter(noise(n), "band", [600, 5000]) * np.exp(-t / (0.06 if kind != "splash" else 0.1)) * 0.45
        x = base + grains(n, 70 if kind == "splash" else 35, 1500, 7000, 0.003, 0.5)
        f0 = 900 if kind == "water_in" else 600
        for _ in range(4 if kind != "splash" else 7):
            d = int(0.04 * SR)
            s0 = int(rng.uniform(0.0, n / SR - 0.05) * SR)
            fr = rng.uniform(f0, f0 * 2.2)
            x[s0:s0 + d] += np.sin(2 * np.pi * np.cumsum(fr * (1 + 0.9 * tt(d) / 0.04)) / SR) * np.exp(-tt(d) / 0.01) * 0.3
        return fade(x, 0.003, 0.06)
    if kind == "catch":
        return _at(mg("water_out") * 0.6, arp([84, 88, 91], 0.05, "celesta", 0.7, 0.4, 0.3), 0.08)
    if kind == "tear":
        n = int(0.35 * SR)
        t = tt(n)
        rip = (butter(noise(n), "low", 90) > 0.0).astype(float) * 0.7 + 0.3
        x = butter(noise(n), "band", [1500, 8000]) * rip * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.1)
        return fade(x * 0.8, 0.001, 0.05)
    if kind == "escape":
        return _at(mg("water_in") * 0.5, _sweep(int(0.2 * SR), 700, 1400, 0.06) * 0.25, 0.0)
    if kind == "new_poi":
        return _at(foley("paper") * 0.4, bell(hz(84), 0.4, 0.3, "glock"), 0.1)
    # taiko (the drum itself; judgement pings come from good / perfect)
    if kind == "don":
        return taiko(0.95)
    if kind == "ka":
        return ka(0.9)
    if kind == "combo":
        return arp([91, 96], 0.05, "glock", 0.6, 0.35, 0.3)
    if kind == "full_combo":
        return stinger("fanfare")
    raise KeyError(kind)


MG_SFX = ("count", "go", "good", "perfect", "miss", "result",
          "rice_scoop", "rice_press", "filling", "nori", "serve", "order_bad", "customer_leave",
          "pickup", "place", "place_good", "bump", "box_open", "box_fold", "rotate",
          "slide", "slide_blocked", "hint", "solved",
          "water_in", "water_out", "catch", "tear", "escape", "splash", "new_poi",
          "don", "ka", "combo", "full_combo")


def purr():
    """A cat's purr: ~26 Hz pulses of low filtered noise with a slow breath."""
    n = int(1.6 * SR)
    t = tt(n)
    pulse = 0.5 + 0.5 * np.sin(2 * np.pi * 26 * t)
    breath = 0.6 + 0.4 * np.sin(2 * np.pi * 0.9 * t - 1.2)
    x = butter(noise(n), "low", 380) * pulse ** 2 * breath
    x += 0.3 * np.sin(2 * np.pi * 52 * t) * pulse * breath
    return fade(x, 0.08, 0.3)


FARM_FX = ("flap", "hoe", "pump", "harvest", "boom")


def build_farm(outdir):
    """v0.4 additions only, so the existing effects are not re-rendered."""
    files = {}
    for k in FARM_FX:
        y = peak_norm(foley(k), -5)
        write(f"{outdir}/sfx/fx_{k}.wav", y, ogg=False)
        files[f"fx_{k}"] = {"file": f"sfx/fx_{k}.wav", "seconds": round(y.shape[-1] / SR, 3), "peak_db": -5}
    return files


def build(outdir):
    files = {}
    def put(name, x, peak, mono=True):
        path = f"{outdir}/sfx/{name}.wav"
        y = peak_norm(x, peak)
        write(path, y, ogg=False)
        files[name] = {"file": f"sfx/{name}.wav", "seconds": round((y.shape[-1]) / SR, 3), "peak_db": peak}
    for s in ("stone", "gravel", "grass", "wood", "tatami"):
        for i in range(4):
            put(f"step_{s}_{i}", step(s), -6)
    for k in ("hover", "click", "open", "close", "next", "select", "invalid", "rotate"):
        put(f"ui_{k}", ui(k), {"hover": -14, "next": -8, "rotate": -8}.get(k, -5))
    for k in ("item", "quest_accept", "step", "quest_done", "coin", "save", "sparkle", "fanfare"):
        put(f"sting_{k}", stinger(k), {"step": -8, "sparkle": -8}.get(k, -3), mono=False)
    for k in ("door", "mailbox", "water_tap", "water_pour", "soil", "paper", "place", "pickup", "basket"):
        put(f"fx_{k}", foley(k), -4)
    for k in FARM_FX:
        put(f"fx_{k}", foley(k), -5)
    put("fx_purr", purr(), -6)
    for k in MG_SFX:
        pk = {"don": -2, "ka": -4, "full_combo": -3, "solved": -3, "result": -4}.get(k, -5)
        if k in ("pickup", "place"):
            y = foley(k)
        else:
            y = mg(k)
        put(f"mg_{k}", y, pk, mono=False)
    return files
