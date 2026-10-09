"""DSP core for the 晴町日常 soundtrack: instruments, reverb, mixing and file output.

Everything is synthesized; no samples or third-party recordings are used.
"""
import math
import numpy as np
from scipy import signal
import soundfile as sf

SR = 44100
rng = np.random.default_rng(20260927)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def m(name):
    """'F#5' -> MIDI number."""
    base = NOTE[name[0]]
    i = 1
    while i < len(name) and name[i] in "#b":
        base += 1 if name[i] == "#" else -1
        i += 1
    return base + 12 * (int(name[i:]) + 1)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def dbv(x):
    return 10 ** (x / 20)


def tt(n):
    return np.arange(n) / SR


def butter(x, kind, f, order=2):
    if isinstance(f, (list, tuple)):
        w = [min(max(v / (SR / 2), 1e-4), 0.999) for v in f]
    else:
        w = min(max(f / (SR / 2), 1e-4), 0.999)
    sos = signal.butter(order, w, btype=kind, output="sos")
    return signal.sosfilt(sos, x)


def noise(n):
    return rng.standard_normal(n)


def pink(n):
    w = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    x = np.fft.irfft(w / np.sqrt(f), n)
    return x / (np.std(x) + 1e-12)


def slow(n, rate):
    """Smooth random control signal in about [-1, 1] changing at roughly `rate` Hz."""
    k = max(4, int(n / SR * rate) + 3)
    knots = rng.uniform(-1, 1, k)
    x = np.interp(np.linspace(0, k - 1, n), np.arange(k), knots)
    w = max(1, int(SR / rate / 2))
    return np.convolve(x, np.ones(w) / w, mode="same")


def fade(x, a=0.005, r=0.02):
    x = x.copy()
    na, nr = int(a * SR), int(r * SR)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nr:
        x[-nr:] *= np.linspace(1, 0, nr)
    return x


# ------------------------------------------------------------------ instruments
def piano(f, dur, vel=0.6, rel=0.3):
    """Additive piano: stretched partials, two detuned strings, two-stage decay, hammer noise."""
    n = int((dur + rel + 0.05) * SR)
    t = tt(n)
    out = np.zeros(n)
    B = 0.0003
    nmax = int(min(14, 8000 // f))
    t60 = float(np.clip(8.0 * (110.0 / f) ** 0.6, 0.9, 9.0))
    for k in range(1, nmax + 1):
        fk = k * f * math.sqrt(1 + B * k * k)
        amp = (1.0 / k ** 1.15) * abs(math.sin(math.pi * k * 0.13)) * (0.45 + 0.55 * vel) ** (0.35 * (k - 1))
        tk = t60 / (1 + 0.45 * (k - 1) ** 1.1)
        env = 0.55 * np.exp(-6.9 * t / (0.22 * tk)) + 0.45 * np.exp(-6.9 * t / tk)
        for det in (-0.00035, 0.00035):
            out += 0.5 * amp * env * np.sin(2 * np.pi * fk * (1 + det) * t + rng.uniform(0, 6.28))
    out *= 1 - np.exp(-t / 0.0015)
    hn = min(n, int(0.02 * SR))
    out[:hn] += 0.05 * vel * butter(noise(hn), "band", [1500, 5000]) * np.exp(-tt(hn) / 0.003)
    k0 = int(dur * SR)
    out[k0:] *= np.exp(-(t[k0:] - dur) / (rel / 4))
    return out * vel * 0.32


BELLS = {
    "glock": ([1, 2.76, 5.40, 8.93], [1, 0.35, 0.18, 0.08], [1.0, 0.45, 0.22, 0.12]),
    "celesta": ([1, 2.0, 3.0, 4.2], [1, 0.25, 0.1, 0.05], [0.9, 0.35, 0.2, 0.1]),
    "glass": ([1, 2.32, 4.25, 6.63], [1, 0.45, 0.25, 0.12], [1.0, 0.6, 0.35, 0.2]),
    "metal": ([1, 2.52, 4.37, 6.95], [1, 0.8, 0.6, 0.4], [0.35, 0.2, 0.12, 0.08]),
}


def bell(f, dur=1.6, vel=0.5, kind="glock"):
    """Glockenspiel / celesta / glass chime / metal clank from inharmonic partials."""
    n = int(dur * SR)
    t = tt(n)
    out = np.zeros(n)
    for r, a, d in zip(*BELLS[kind]):
        if f * r > SR * 0.45:
            continue
        out += a * np.exp(-t / (d * dur * 0.6)) * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28))
    out *= 1 - np.exp(-t / 0.0008)
    return fade(out, 0.0, 0.05) * vel * 0.35


def marimba(f, dur=0.6, vel=0.5):
    n = int(dur * SR)
    t = tt(n)
    out = (np.sin(2 * np.pi * f * t) * np.exp(-t / 0.28)
           + 0.28 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / 0.06)
           + 0.06 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / 0.02))
    out *= 1 - np.exp(-t / 0.001)
    return fade(out, 0, 0.03) * vel * 0.45


def pluck(f, dur, vel=0.5, bright=0.5, decay=2.2):
    """Karplus-Strong string with an all-pass tuned loop (guitar / koto)."""
    nf = SR / f - 0.5
    N = int(math.floor(nf - 0.1))
    d = nf - N
    c = (1 - d) / (1 + d)
    g = 10 ** (-3 / (f * decay))
    a = np.zeros(N + 3)
    a[0] = 1.0
    a[1] += c
    a[N] -= g / 2 * c
    a[N + 1] -= g / 2 * (1 + c)
    a[N + 2] -= g / 2
    b = np.array([1.0, c])
    n = int((dur + 0.25) * SR)
    x = np.zeros(n)
    p = 0.85 - 0.6 * bright
    burst = signal.lfilter([1 - p], [1, -p], noise(N))
    burst -= np.roll(burst, int(N * 0.18))
    x[:N] = burst / (np.max(np.abs(burst)) + 1e-9)
    y = signal.lfilter(b, a, x)
    k0 = int(dur * SR)
    y[k0:] *= np.exp(-tt(n - k0) / 0.05)
    return fade(y, 0.001, 0.02) * vel * 0.5


def pad(freqs, dur, vel=0.2, att=0.9, rel=1.6, bright=0.35):
    n = int((dur + rel) * SR)
    t = tt(n)
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.0045, 0.0, 0.0045):
            lfo = 1 + 0.0018 * np.sin(2 * np.pi * rng.uniform(4.5, 5.5) * t + rng.uniform(0, 6.28))
            ph = 2 * np.pi * np.cumsum(f * (1 + det) * lfo) / SR
            for k in range(1, 9):
                if f * k > 7000:
                    break
                out += (1 / k) * bright ** (0.5 * (k - 1)) * np.sin(k * ph + rng.uniform(0, 6.28))
    env = np.clip(t / att, 0, 1) ** 1.5
    k0 = int(dur * SR)
    env[k0:] *= np.exp(-(t[k0:] - dur) / (rel / 4))
    return butter(out * env, "low", 2600) * vel * 0.12 / max(1, len(freqs)) ** 0.5


def bass(f, dur, vel=0.5):
    n = int((dur + 0.12) * SR)
    t = tt(n)
    out = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.12 * np.sin(6 * np.pi * f * t)
    env = (1 - np.exp(-t / 0.006)) * (0.65 + 0.35 * np.exp(-t / 0.25))
    k0 = int(dur * SR)
    env[k0:] *= np.exp(-(t[k0:] - dur) / 0.03)
    return butter(out * env, "low", 900) * vel * 0.2


def flute(f, dur, vel=0.55, breath=0.12):
    """Breathy transverse flute (shinobue-like in the upper register)."""
    n = int((dur + 0.18) * SR)
    t = tt(n)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.3 * t + rng.uniform(0, 6.28)) * np.clip((t - 0.2) / 0.3, 0, 1)
    scoop = 1 - 0.015 * np.exp(-t / 0.04)
    ph = 2 * np.pi * np.cumsum(f * vib * scoop) / SR
    tone = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.07 * np.sin(3 * ph) + 0.03 * np.sin(4 * ph)
    air = butter(noise(n), "band", [f * 1.3, min(f * 3.5, 16000)]) * breath
    chiff = butter(noise(n), "band", [1500, 6000]) * np.exp(-t / 0.025) * 0.25
    env = np.clip(t / 0.05, 0, 1) * (0.92 + 0.08 * np.clip(t / max(dur, 0.1), 0, 1))
    k0 = int(dur * SR)
    env[k0:] *= np.exp(-(t[k0:] - dur) / 0.05)
    return (tone + air + chiff) * env * vel * 0.28


# ------------------------------------------------------------------ percussion
def taiko(vel=0.6):
    n = int(0.9 * SR)
    t = tt(n)
    f = 55 + 75 * np.exp(-t / 0.045)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.42)
    skin = butter(noise(n), "low", 900) * np.exp(-t / 0.03) * 0.35
    return fade((0.7 * body + skin) * (1 - np.exp(-t / 0.002)), 0, 0.05) * vel * 0.4


def ka(vel=0.4):
    n = int(0.12 * SR)
    t = tt(n)
    x = butter(noise(n), "band", [1300, 2600]) * np.exp(-t / 0.018) + 0.5 * np.sin(2 * np.pi * 1900 * t) * np.exp(-t / 0.025)
    return x * vel * 0.4


def shaker(vel=0.3):
    n = int(0.09 * SR)
    t = tt(n)
    return butter(noise(n), "high", 5500) * np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.03) * vel * 0.25


def clap(vel=0.35):
    n = int(0.2 * SR)
    x = np.zeros(n)
    for k, off in enumerate((0.0, 0.009, 0.017)):
        s = int(off * SR)
        x[s:] += noise(n - s) * np.exp(-tt(n - s) / (0.006 if k < 2 else 0.05))
    return butter(x, "band", [900, 3000]) * vel * 0.35


def kick(vel=0.4):
    n = int(0.3 * SR)
    t = tt(n)
    f = 48 + 60 * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16) * vel * 0.25


# ------------------------------------------------------------------ reverb, mixing, output
def reverb_ir(rt60=1.8, predelay=0.018, bright=1.0):
    n = int(rt60 * 1.1 * SR)
    t = tt(n)
    irs = []
    for ch in range(2):
        ir = (butter(noise(n), "low", 600) * np.exp(-6.9 * t / (rt60 * 1.1))
              + butter(noise(n), "band", [600, 3000]) * np.exp(-6.9 * t / rt60)
              + butter(noise(n), "high", 3000) * np.exp(-6.9 * t / (rt60 * 0.55 * bright)))
        for _ in range(8):
            ir[int(rng.uniform(0.006, 0.07) * SR)] += rng.uniform(-1, 1) * 3
        ir *= np.clip(t / 0.01, 0, 1)
        irs.append(np.concatenate([np.zeros(int(predelay * SR) + ch * 23), ir]))
    L = max(len(i) for i in irs)
    irs = [np.pad(i, (0, L - len(i))) for i in irs]
    e = math.sqrt(sum(float(np.sum(i ** 2)) for i in irs) / 2)
    return [i / e for i in irs]


class Mix:
    """Stereo buffer with constant-power panning."""

    def __init__(self, seconds):
        self.buf = np.zeros((2, int(seconds * SR) + 1))

    def add(self, x, at, pan=0.0, gain=1.0):
        s = max(0, int(round(at * SR)))
        e = min(self.buf.shape[1], s + len(x))
        if e <= s:
            return
        a = (pan + 1) * math.pi / 4
        self.buf[0, s:e] += x[:e - s] * math.cos(a) * gain
        self.buf[1, s:e] += x[:e - s] * math.sin(a) * gain


def reverb(st, rt60=1.8, wet=0.25, bright=1.0):
    ir = reverb_ir(rt60, bright=bright)
    out = np.zeros((2, st.shape[1] + len(ir[0]) - 1))
    for ch in range(2):
        out[ch, :st.shape[1]] += st[ch]
        out[ch] += wet * signal.fftconvolve(st[ch] * 0.7 + st[(ch + 1) % 2] * 0.3, ir[ch])
    return out


def wrap_loop(st, loop_n):
    """Fold everything past the loop end back onto the start so the loop repeats without a seam."""
    out = st[:, :loop_n].copy()
    rest = st[:, loop_n:]
    while rest.shape[1]:
        k = min(loop_n, rest.shape[1])
        out[:, :k] += rest[:, :k]
        rest = rest[:, k:]
    return out


def master(st, rms_db=-19.0, peak_db=-1.0):
    x = st - np.mean(st, axis=-1, keepdims=True)
    x = x * dbv(rms_db) / (math.sqrt(float(np.mean(x ** 2))) + 1e-12)
    lim = dbv(peak_db)
    knee = 0.7 * lim
    over = np.abs(x) > knee
    x[over] = np.sign(x[over]) * (knee + (lim - knee) * np.tanh((np.abs(x[over]) - knee) / (lim - knee)))
    return x


def peak_norm(x, peak_db):
    return x * dbv(peak_db) / (np.max(np.abs(x)) + 1e-12)


def write(path, st, ogg=True):
    data = st.T if st.ndim == 2 else st
    data = np.clip(data, -1, 1).astype(np.float32)
    if ogg:
        # libsndfile's Vorbis encoder crashes on very large single writes; stream it in blocks
        ch = 1 if data.ndim == 1 else data.shape[1]
        with sf.SoundFile(path, "w", SR, ch, format="OGG", subtype="VORBIS", compression_level=0.3) as f:
            for i in range(0, len(data), 8192):
                f.write(data[i:i + 8192])
    else:
        sf.write(path, data, SR, subtype="PCM_16")
