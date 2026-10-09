"""Render only the three outdoor additions; retain all existing music and ambience."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from scipy import signal
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
SR = 44100
RNG = np.random.default_rng(606106)

def loop_noise(seconds, lower, upper, modulation):
    count = int(seconds * SR)
    frequencies = np.fft.rfftfreq(count, 1 / SR)
    spectrum = np.fft.rfft(RNG.standard_normal(count))
    envelope = np.exp(-np.square(frequencies / upper)) * (1 - np.exp(-np.square(frequencies / lower)))
    # FFT filtering is periodic by construction, including both channel endpoints.
    time = np.arange(count) / SR
    wave = np.fft.irfft(spectrum * envelope, count)
    wave *= 1 + modulation * np.sin(2 * np.pi * time / seconds * 3)
    return wave / max(np.sqrt(np.mean(wave * wave)), 1e-9)

def build():
    output = ROOT / 'game/assets/audio'
    files = {}
    for name, lo, hi, depth, rms in [('river_close', 180, 4600, .15, .060), ('leaves_wind', 1000, 6200, .52, .026)]:
        left = loop_noise(24, lo, hi, depth)
        right = loop_noise(24, lo, hi, depth)
        stereo = np.column_stack((left, .75 * left + .25 * right)) * rms
        path = output / 'amb' / (name + '.ogg')
        sf.write(path, stereo, SR, format='OGG', subtype='VORBIS')
        files[name] = {'file': str(path.relative_to(ROOT)), 'seconds': 24, 'loop': True,
                       'rms': float(np.sqrt(np.mean(stereo * stereo))), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    time = np.arange(int(2.1 * SR)) / SR
    wave = np.zeros_like(time)
    for frequency, amplitude, decay in [(2580, 1, .65), (3910, .36, .38), (5260, .18, .26)]:
        wave += amplitude * np.sin(2 * np.pi * frequency * time) * np.exp(-time / decay)
    wave *= np.clip(time / .003, 0, 1) * np.clip((2.1 - time) / .15, 0, 1)
    wave *= .24 / np.max(np.abs(wave))
    path = output / 'sfx/wind_chime.wav'
    sf.write(path, wave, SR, subtype='PCM_16')
    files['wind_chime'] = {'file': str(path.relative_to(ROOT)), 'seconds': 2.1, 'loop': False,
                           'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    manifest = {'generator': 'art/tools/synth_environment_audio.py', 'seed': 606106,
                'sample_rate': SR, 'source': 'procedural synthesis, no recordings', 'files': files}
    (ROOT / 'art/manifests/audio_environment_20261006.json').write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))

if __name__ == '__main__':
    build()
