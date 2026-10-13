"""Generate only three evidence samples with pinned, pre-downloaded IndexTTS2.

Use the isolated IndexTTS2 Python environment. --state is the local environment
record; --out must be separate from production audio. No model downloads occur.
"""
import argparse
import importlib.metadata
import json
import os
import pathlib
import random
import sys
import time

from compare_voice_models import LINES, REFERENCE, REFERENCE_TEXT, fresh_evidence_file, sha


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--state", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    state_file = pathlib.Path(args.state).resolve()
    state = json.loads(state_file.read_text())
    source = pathlib.Path(state["source"])
    raw = pathlib.Path(state["raw"])
    models = raw / "models"
    out = pathlib.Path(args.out).resolve()
    for name in ["comparison.json"] + ["indextts2_" + entry["name"] + ".wav" for entry in LINES]:
        fresh_evidence_file(out / name)
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HOME"] = str(raw / "hf-runtime")
    os.environ["NLTK_DATA"] = str(raw / "nltk-data")
    os.environ["MPLCONFIGDIR"] = str(raw / "matplotlib-cache")
    os.environ["XDG_CACHE_HOME"] = str(raw / "runtime-cache")
    sys.path.insert(0, str(source))
    import numpy as np
    import soundfile as sf
    import torch
    from indextts.infer_v2 import IndexTTS2
    if not torch.backends.mps.is_available():
        raise RuntimeError("The native MPS device is required for this local comparison")
    torch.set_num_threads(8)
    paths = {
        "w2v_bert": str(models / "auxiliary/w2v-bert-2.0"),
        "semantic_codec": str(models / "auxiliary/semantic_codec/semantic_codec/model.safetensors"),
        "campplus": str(models / "auxiliary/campplus/campplus_cn_common.bin"),
        "bigvgan": str(models / "auxiliary/bigvgan"),
    }
    manifest = {"model": "IndexTeam/IndexTTS-2", "code_revision": state["code_revision"],
        "model_revision": json.loads((state_file.parent / "index_model_info.json").read_text())["sha"],
        "character": "mio", "reference": str(REFERENCE), "reference_sha256": sha(REFERENCE),
        "reference_text": REFERENCE_TEXT, "device": "mps", "dtype": "float32",
        "use_cuda_kernel": False, "use_deepspeed": False, "use_qwen_emo": False,
        "seed": 1984, "sampling": {"do_sample": True, "top_p": 0.8, "top_k": 30,
            "temperature": 0.8, "num_beams": 3, "repetition_penalty": 10.0},
        "runtime": {name: importlib.metadata.version(name) for name in ["torch", "torchaudio", "numpy", "transformers", "indextts"]},
        "results": []}
    started = time.perf_counter()
    model = IndexTTS2(cfg_path=str(models / "config.yaml"), model_dir=str(models), device="mps",
        use_fp16=False, use_cuda_kernel=False, use_deepspeed=False, use_qwen_emo=False, aux_paths=paths)
    manifest["load_seconds"] = round(time.perf_counter() - started, 3)
    (out / "comparison.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    for entry in LINES:
        random.seed(1984)
        np.random.seed(1984)
        torch.manual_seed(1984)
        path = out / ("indextts2_" + entry["name"] + ".wav")
        emotion = [0.25, 0, 0, 0, 0, 0, 0, 0.5] if entry["mood"] == "happy" else None
        started = time.perf_counter()
        model.infer(spk_audio_prompt=str(REFERENCE), text=entry["text"], output_path=str(path),
            emo_vector=emotion, use_random=False, **manifest["sampling"])
        torch.mps.synchronize()
        elapsed = time.perf_counter() - started
        audio, sample_rate = sf.read(path)
        manifest["results"].append({**entry, "file": str(path), "sha256": sha(path),
            "seconds": len(audio) / sample_rate, "sample_rate": sample_rate,
            "generation_seconds": round(elapsed, 3), "real_time_factor": round(elapsed / (len(audio) / sample_rate), 3),
            "emo_vector": emotion, "use_random": False})
        (out / "comparison.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        print("IndexTTS2", entry["name"], round(elapsed, 2), "s", flush=True)


if __name__ == "__main__":
    main()
