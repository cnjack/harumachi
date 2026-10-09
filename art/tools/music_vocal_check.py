"""Check that supposedly instrumental music has no singing, humming or speech in it.

    <py> art/tools/music_vocal_check.py take1.wav [take2.wav ...]

Two independent signals per file:
  * demucs htdemucs separates a vocal stem; `hot` lists the seconds where that stem is within
    12 dB of the full mix (a bowed-string or flute lead can land here too, so this alone is not proof);
  * the AudioSet AST classifier (MIT/ast-finetuned-audioset-10-10-0.4593) scores 4 s windows of the
    vocal stem and of the mix for Singing / Humming / Choir / Speech / Whistling / ... .
A take is accepted when stem_voice_max < 0.15 (or the flagged window sits >25 dB under the mix)
and mix_voice_max < 0.08. Whisper alone missed the wordless humming these checks caught.

<py> is a Python with torch, numpy, scipy and huggingface_hub (the music project's .venv-align).
The rest goes into a side directory, given by VOCAL_CHECK_SITE (default /tmp/dm):
  pip install --target $VOCAL_CHECK_SITE --no-deps demucs julius einops openunmix pyyaml dora-search \
      omegaconf antlr4-python3-runtime retrying submitit treetable cloudpickle transformers tokenizers \
      safetensors regex tqdm packaging
The htdemucs weights (955717e8-8726e21a.th) go into ~/.cache/torch/hub/checkpoints/ (fetch with curl
from dl.fbaipublicfiles.com/demucs/hybrid_transformer/ if Python's SSL store rejects the download).
"""
import sys, types, os, json, numpy as np, torch
sys.path.insert(0, os.environ.get("VOCAL_CHECK_SITE", "/tmp/dm"))
if "torchaudio" not in sys.modules:
    try:
        import torchaudio
    except ImportError:
        ta = types.ModuleType("torchaudio"); ta.__path__ = []
        tf = types.ModuleType("torchaudio.transforms"); ta.transforms = tf
        sys.modules["torchaudio"] = ta; sys.modules["torchaudio.transforms"] = tf
from scipy.io import wavfile
from scipy.signal import resample_poly
from demucs.pretrained import get_model
from demucs.apply import apply_model
for _m in ("torchaudio", "torchaudio.transforms"):
    if getattr(sys.modules.get(_m), "__spec__", 1) is None: del sys.modules[_m]
from transformers import ASTFeatureExtractor, ASTForAudioClassification
dm = get_model("htdemucs").eval()
dev = "mps" if torch.backends.mps.is_available() else "cpu"
AN = "MIT/ast-finetuned-audioset-10-10-0.4593"
fe = ASTFeatureExtractor.from_pretrained(AN); ast = ASTForAudioClassification.from_pretrained(AN).eval()
lab = ast.config.id2label; idx = {v: k for k, v in lab.items()}
VOC = [idx[v] for v in ["Singing","Humming","Choir","Speech","Male singing","Female singing","Child singing","Chant","A capella","Whistling","Synthetic singing","Yodeling","Mantra"] if v in idx]
def ast_voice(x16, win=4.0):
    out = []
    for i in range(int(len(x16)/16000/win)):
        seg = x16[int(i*win*16000):int((i+1)*win*16000)]
        if np.sqrt(np.mean(seg**2)) < 1e-4: out.append(0.0); continue
        with torch.no_grad(): pr = torch.sigmoid(ast(**fe(seg, sampling_rate=16000, return_tensors="pt")).logits)[0].numpy()
        out.append(float(max(pr[k] for k in VOC)))
    return out
res = {}
for p in sys.argv[1:]:
    sr, x = wavfile.read(p); x = x.astype(np.float32)/32768
    if x.ndim == 1: x = np.stack([x, x], 1)
    dur = len(x)/sr
    if sr != dm.samplerate: x = resample_poly(x, dm.samplerate, sr, axis=0).astype(np.float32); sr = dm.samplerate
    wav = torch.from_numpy(x.T.copy())[None]
    with torch.no_grad(): st = apply_model(dm, wav, device=dev, split=True, overlap=0.25, progress=False)[0].numpy()
    v = st[dm.sources.index("vocals")]; tot = x.T
    rel = [20*np.log10(np.sqrt(np.mean(v[:, i*sr:(i+1)*sr]**2))/(np.sqrt(np.mean(tot[:, i*sr:(i+1)*sr]**2))+1e-9)+1e-9) for i in range(v.shape[1]//sr)]
    hot = [i for i, r in enumerate(rel) if r > -12]
    stem16 = resample_poly(v.mean(0), 16000, sr).astype(np.float32)
    mix16 = resample_poly(tot.mean(0), 16000, sr).astype(np.float32)
    a_stem = ast_voice(stem16); a_mix = ast_voice(mix16)
    r = {"dur": round(dur,1), "voc_hot_s": len(hot), "hot": hot, "stem_voice_max": round(max(a_stem or [0]),2),
         "stem_voice_win_gt015": [i*4 for i, a in enumerate(a_stem) if a > 0.15], "mix_voice_max": round(max(a_mix or [0]),2),
         "mix_voice_win_gt008": [i*4 for i, a in enumerate(a_mix) if a > 0.08]}
    res[os.path.basename(p)] = r
    print(os.path.basename(p), json.dumps(r), flush=True)
