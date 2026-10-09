"""A short voiced meow with vowel formants, pitch glide and a soft breath tail."""
from pathlib import Path
import json
import numpy as np
import soundfile as sf
from scipy.signal import butter,sosfilt
ROOT=Path(__file__).resolve().parents[2]
sr=48000;t=np.arange(int(.78*sr))/sr
pitch=np.interp(t,[0,.10,.23,.49,.78],[470,640,690,510,340])*(1+.008*np.sin(t*2*np.pi*27))
phase=2*np.pi*np.cumsum(pitch)/sr
formant1=np.interp(t,[0,.20,.60,.78],[680,870,560,480])
formant2=np.interp(t,[0,.20,.60,.78],[2300,1500,1300,1100])
voice=np.zeros_like(t)
for harmonic in range(1,11):
 freq=pitch*harmonic
 gain=(np.exp(-((freq-formant1)/260)**2)+.40*np.exp(-((freq-formant2)/480)**2)+.08)/harmonic
 voice+=np.sin(phase*harmonic)*gain
envelope=np.sin(np.pi*np.clip(t/.78,0,1))**1.4*np.clip(t/.045,0,1)
noise=np.random.default_rng(71).normal(0,1,len(t));noise=sosfilt(butter(2,[650,4200],fs=sr,btype='band',output='sos'),noise)
sound=(voice+.025*noise)*envelope;sound=sound/max(abs(sound))*.42
out=ROOT/'game/assets/audio/sfx/cat_meow.wav';sf.write(out,sound,sr,subtype='PCM_16')
manifest=ROOT/'art/manifests/audio_synth.json';data=json.loads(manifest.read_text());data['sfx']['cat_meow']={'file':'sfx/cat_meow.wav','seconds':.78,'peak_db':-7.5,'generator':'art/tools/synth_cat_meow.py'};manifest.write_text(json.dumps(data,ensure_ascii=False,indent=1)+'\n')
print(out)
