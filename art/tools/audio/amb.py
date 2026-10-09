"""Ambience loops: sunny town (sparrows, breeze, leaves), evening market (higurashi cicadas,
crowd murmur, wind chimes) and the quiet room."""
from synth_core import *

LOOP = 60.0


def loop_xfade(st, loop_n, xf_n):
    """Equal-power crossfade of the overrun back onto the start."""
    out = st[:, :loop_n].copy()
    k = min(xf_n, st.shape[1] - loop_n)
    w = np.linspace(0, 1, k)
    out[:, :k] = out[:, :k] * np.sin(w * np.pi / 2) + st[:, loop_n:loop_n + k] * np.cos(w * np.pi / 2)
    return out


def bed(seconds, lo, hi, depth=0.5, rate=0.08):
    n = int(seconds * SR)
    x = butter(pink(n), "band", [lo, hi])
    mod = 1 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * rate * tt(n) + rng.uniform(0, 6.28)))
    mod *= 1 + 0.35 * slow(n, 0.3)
    return x * np.clip(mod, 0.05, 2)


def sparrow(vel):
    """'chun': a short downward chirp with a harmonic."""
    d = rng.uniform(0.035, 0.07)
    n = int(d * SR)
    t = tt(n)
    f = rng.uniform(4800, 6200) - rng.uniform(1200, 2200) * t / d
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.sin(np.pi * t / d) ** 1.5
    return (np.sin(ph) + 0.2 * np.sin(2 * ph)) * env * vel


def warbler(vel):
    """A longer rising-falling whistle (bush warbler-ish) for variety."""
    d = rng.uniform(0.6, 1.0)
    n = int(d * SR)
    t = tt(n)
    f = 1800 + 900 * np.sin(np.pi * t / d) + 120 * np.sin(2 * np.pi * 18 * t)
    env = np.clip(t / 0.08, 0, 1) * np.clip((d - t) / 0.06, 0, 1)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env * vel


def higurashi(vel):
    """'kana-kana-kana': pulsed trill whose pitch and rate fall over the call."""
    units = int(rng.integers(12, 20))
    f0 = rng.uniform(4300, 4700)
    out = []
    for u in range(units):
        k = u / units
        d = 0.11 + 0.05 * k
        n = int(d * SR)
        t = tt(n)
        f = f0 * (1 - 0.12 * k) * (1 + 0.04 * np.exp(-t / 0.02))
        trill = 0.5 + 0.5 * np.sin(2 * np.pi * (48 - 12 * k) * t)
        env = np.sin(np.pi * t / d) ** 0.8 * trill
        amp = math.sin(math.pi * min(1, (u + 1) / (units * 0.35))) if u < units * 0.35 else 1 - 0.7 * (u - units * 0.35) / (units * 0.65)
        out.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * env * amp)
        out.append(np.zeros(int(0.03 * SR)))
    return np.concatenate(out) * vel


VOWELS = [(700, 1200), (300, 2300), (350, 800), (500, 1800), (450, 900)]


def voice_babble(seconds):
    n = int(seconds * SR)
    t = tt(n)
    f0 = rng.uniform(110, 240) * (1 + 0.06 * slow(n, 1.5))
    ph = np.cumsum(f0) / SR
    src = 2 * (ph % 1) - 1
    layers = [butter(src, "band", [a * 0.8, a * 1.25]) + 0.6 * butter(src, "band", [b * 0.85, b * 1.2]) for a, b in VOWELS]
    syl = rng.uniform(3.5, 6.0)
    sel = np.floor(t * syl).astype(int)
    pick = rng.integers(0, len(VOWELS), sel.max() + 1)
    x = np.zeros(n)
    for i in range(len(VOWELS)):
        w = butter((pick[sel] == i).astype(float), "low", 25)
        x += layers[i] * w
    on = np.clip(slow(n, 0.8) * 2 + 0.6, 0, 1)
    env = np.clip(on, 0, 1) * (0.5 + 0.5 * np.abs(np.sin(np.pi * t * syl)))
    return butter(x * env, "low", 2800)


def scatter(mx, seconds, rate, make, pans=(-0.9, 0.9), far=(0.0, 0.6)):
    t = rng.uniform(0, 2)
    while t < seconds:
        x = make()
        d = rng.uniform(*far)
        if d > 0.3:
            x = butter(x, "low", 5000 - 3500 * d)
        mx.add(x, t, rng.uniform(*pans), 1 - 0.7 * d)
        t += rng.exponential(1 / rate)


def day():
    L = LOOP + 5
    mx = Mix(L)
    mx.add(bed(L, 60, 500, 0.6, 0.05), 0, -0.3, 0.30)
    mx.add(bed(L, 60, 500, 0.6, 0.06), 0, 0.3, 0.30)
    mx.add(bed(L, 2500, 8000, 0.8, 0.11), 0, -0.5, 0.05)
    mx.add(bed(L, 2500, 8000, 0.8, 0.09), 0, 0.5, 0.05)

    def chirps():
        k = int(rng.integers(2, 5))
        parts = []
        for _ in range(k):
            parts += [sparrow(rng.uniform(0.5, 1.0)), np.zeros(int(rng.uniform(0.08, 0.2) * SR))]
        return np.concatenate(parts)
    scatter(mx, LOOP, 0.35, chirps)
    scatter(mx, LOOP, 0.05, lambda: warbler(0.35), far=(0.4, 0.8))
    st = reverb(mx.buf, 1.2, 0.18, 0.7)
    return master(loop_xfade(st, int(LOOP * SR), int(4 * SR)), -30, -6)


def evening():
    L = LOOP + 5
    mx = Mix(L)
    mx.add(bed(L, 60, 400, 0.5, 0.04), 0, 0.0, 0.25)
    for i in range(18):
        mx.add(voice_babble(L), 0, rng.uniform(-0.8, 0.8), rng.uniform(0.012, 0.03))
    scatter(mx, LOOP, 0.09, lambda: higurashi(rng.uniform(0.25, 0.45)), far=(0.3, 0.8))

    def chime():
        x = np.zeros(int(3.5 * SR))
        for _ in range(int(rng.integers(1, 4))):
            s = int(rng.uniform(0, 0.9) * SR)
            b = bell(rng.choice([2093.0, 2349.3, 2637.0, 3136.0]), 2.6, rng.uniform(0.3, 0.6), "glass")
            x[s:s + len(b)] += b[:len(x) - s]
        return x
    scatter(mx, LOOP, 0.08, chime, pans=(0.2, 0.7), far=(0.0, 0.3))
    st = reverb(mx.buf, 1.5, 0.22, 0.8)
    return master(loop_xfade(st, int(LOOP * SR), int(4 * SR)), -29, -6)


def room():
    L = LOOP + 5
    mx = Mix(L)
    mx.add(bed(L, 40, 250, 0.3, 0.03), 0, 0.0, 0.18)
    scatter(mx, LOOP, 0.2, lambda: butter(np.concatenate([sparrow(0.6), np.zeros(int(0.12 * SR)), sparrow(0.5)]), "low", 1600), pans=(0.3, 0.8), far=(0.3, 0.6))
    st = reverb(mx.buf, 0.6, 0.15, 0.5)
    return master(loop_xfade(st, int(LOOP * SR), int(4 * SR)), -38, -10)


def river_bed(seconds):
    """Gentle river: several band-limited noise streams with slow random swells and small gurgles."""
    n = int(seconds * SR)
    x = np.zeros(n)
    for lo, hi, g in ((120, 700, 0.5), (500, 2200, 0.35), (1800, 6000, 0.12)):
        x += bed(seconds, lo, hi, 0.45, rng.uniform(0.05, 0.14)) * g
    return x


def gurgle(vel):
    d = rng.uniform(0.05, 0.14)
    nn = int(d * SR)
    t = tt(nn)
    f = rng.uniform(500, 900) + rng.uniform(300, 900) * t / d
    env = np.sin(np.pi * t / d) ** 2
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env * vel


def minmin(vel):
    """Distant min-min cicada: a pulsing buzz that rises and settles."""
    d = rng.uniform(3.0, 5.0)
    nn = int(d * SR)
    t = tt(nn)
    carrier = butter(pink(nn), "band", [3200, 6000])
    pulse = 0.5 + 0.5 * np.sin(2 * np.pi * (5 + 2 * np.sin(np.pi * t / d)) * t)
    env = np.clip(t / 0.6, 0, 1) * np.clip((d - t) / 0.8, 0, 1)
    return carrier * pulse * env * vel


def suzumushi(vel):
    """Bell cricket 'riin': a pure ~4.4 kHz tone in a short pulsed burst."""
    d = rng.uniform(0.25, 0.45)
    nn = int(d * SR)
    t = tt(nn)
    f = rng.uniform(4200, 4600)
    trem = 0.55 + 0.45 * np.sin(2 * np.pi * 42 * t)
    env = np.sin(np.pi * t / d) ** 0.6
    return np.sin(2 * np.pi * f * t) * trem * env * vel


def frog(vel):
    """Rice-field frog 'kero-kero': two or three low rattly croaks."""
    parts = []
    for _ in range(int(rng.integers(2, 4))):
        d = rng.uniform(0.09, 0.14)
        nn = int(d * SR)
        t = tt(nn)
        src = np.sign(np.sin(2 * np.pi * rng.uniform(55, 75) * t)) * 0.5 + butter(pink(nn), "band", [300, 900]) * 0.6
        tone = butter(src, "band", [350, 1400])
        env = np.sin(np.pi * t / d) ** 1.2
        parts += [tone * env, np.zeros(int(rng.uniform(0.06, 0.12) * SR))]
    return np.concatenate(parts) * vel


def farm():
    L = LOOP + 5
    mx = Mix(L)
    mx.add(river_bed(L), 0, -0.25, 0.42)
    mx.add(river_bed(L), 0, 0.25, 0.42)
    scatter(mx, LOOP, 0.8, lambda: gurgle(rng.uniform(0.05, 0.14)), pans=(-0.6, 0.6), far=(0.1, 0.5))
    scatter(mx, LOOP, 0.1, lambda: minmin(rng.uniform(0.05, 0.1)), far=(0.5, 0.9))

    def chirps():
        return np.concatenate([sparrow(rng.uniform(0.4, 0.8)), np.zeros(int(0.12 * SR)), sparrow(rng.uniform(0.4, 0.7))])
    scatter(mx, LOOP, 0.22, chirps, far=(0.2, 0.7))
    st = reverb(mx.buf, 1.4, 0.2, 0.7)
    return master(loop_xfade(st, int(LOOP * SR), int(4 * SR)), -30, -6)


def night():
    L = LOOP + 5
    mx = Mix(L)
    mx.add(bed(L, 50, 300, 0.4, 0.03), 0, 0.0, 0.16)
    scatter(mx, LOOP, 1.6, lambda: suzumushi(rng.uniform(0.05, 0.12)), far=(0.1, 0.7))
    scatter(mx, LOOP, 0.35, lambda: frog(rng.uniform(0.08, 0.16)), far=(0.4, 0.9))
    st = reverb(mx.buf, 1.8, 0.25, 0.8)
    return master(loop_xfade(st, int(LOOP * SR), int(4 * SR)), -32, -8)


def rain():
    L = LOOP + 5
    mx = Mix(L)
    for pan in (-0.4, 0.4):
        mx.add(bed(L, 400, 9000, 0.25, 0.07), 0, pan, 0.5)
        mx.add(bed(L, 80, 500, 0.3, 0.04), 0, pan, 0.2)

    def drip():
        d = rng.uniform(0.02, 0.05)
        nn = int(d * SR)
        t = tt(nn)
        f = rng.uniform(1200, 2600) * (1 + 0.8 * t / d)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (d * 0.3))
    scatter(mx, LOOP, 3.0, lambda: drip() * rng.uniform(0.05, 0.2), far=(0.0, 0.5))
    st = reverb(mx.buf, 1.0, 0.2, 0.6)
    return master(loop_xfade(st, int(LOOP * SR), int(4 * SR)), -28, -6)


AMB = {"day": day, "evening": evening, "room": room, "farm": farm, "night": night, "rain": rain}
