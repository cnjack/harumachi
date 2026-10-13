"""Small, reproducible offline casting comparison; never writes production voice files.

Run with the existing mlx-audio Python environment and --out pointing at evidence.
Both Qwen models and ASR must already be cached. Fixed-reference cloning uses the
previously selected synthetic Mio casting sample, with its exact transcript.
Speaker cosine is diagnostic only: it does not replace listening or intelligibility.
"""
import argparse
import hashlib
import importlib.metadata
import json
import os
import pathlib
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
MODELS = {
    "custom_voice": "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
    "fixed_reference": "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
}
REFERENCE = ROOT / "art/audio/voice_samples/mio_B_0.wav"
REFERENCE_TEXT = "早上好！今天也要加油哦。……啊，我是说我自己。每天早上都要这么给自己打一下气。"
LINES = [
    {"name": "short", "mood": "neutral", "text": "好，傍晚见！"},
    {"name": "long", "mood": "neutral", "text": "早上的公告栏最好看了，阳光正好照在海报上。我每天都第一个来把它擦一擦。"},
    {"name": "happy", "mood": "happy", "text": "谢谢你总是来听我说话。以前我总觉得，是我一个人在瞎忙。"},
]


def sha(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def fresh_evidence_file(path):
    """Keep diagnostics inside evidence and refuse existing files or symlink targets."""
    destination = pathlib.Path(path).resolve()
    evidence = (ROOT / "evidence").resolve()
    if evidence not in destination.parents:
        raise ValueError("Comparison output must be inside this repository's evidence directory")
    if destination.exists():
        raise FileExistsError(f"Use a fresh evidence destination: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    return destination


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = pathlib.Path(args.out).resolve()
    for name in ["comparison.json"] + [mode + "_" + entry["name"] + ".wav" for mode in MODELS for entry in LINES]:
        fresh_evidence_file(out / name)
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    import mlx.core as mx
    import numpy as np
    import soundfile as sf
    from huggingface_hub import snapshot_download
    from mlx_audio.tts.utils import load_model
    from gen_voice_lines import cer, tidy

    snapshots = {key: snapshot_download(repo_id=model, local_files_only=True) for key, model in MODELS.items()}
    asr_path = snapshot_download(repo_id="mlx-community/Qwen3-ASR-0.6B-8bit", local_files_only=True)
    cast = json.loads((ROOT / "art/manifests/voice_cast.json").read_text())["cast"]["mio"]
    manifest = {"character": "mio", "speaker": cast["speaker"], "reference": str(REFERENCE),
                "reference_sha256": sha(REFERENCE), "reference_text": REFERENCE_TEXT,
                "models": {key: {"id": MODELS[key], "revision": pathlib.Path(path).name} for key, path in snapshots.items()},
                "runtime": {name: importlib.metadata.version(name) for name in ["mlx", "mlx-audio", "numpy", "soundfile"]},
                "sampling": {"temperature": 0.9, "top_k": 50, "top_p": 1.0, "max_tokens": 1024},
                "evaluation_limit": "A three-line pipeline comparison, not a model ranking. Cosine does not measure naturalness or guarantee the same voice.",
                "results": []}
    for mode, snapshot in snapshots.items():
        started = time.perf_counter()
        model = load_model(snapshot)
        manifest["models"][mode]["load_seconds"] = round(time.perf_counter() - started, 3)
        for entry in LINES:
            seed = 1000 + len(entry["text"]) if mode == "custom_voice" else 1984
            mx.random.seed(seed)
            started = time.perf_counter()
            kwargs = dict(text=entry["text"], temperature=0.9, max_tokens=1024, top_k=50, top_p=1.0)
            if mode == "custom_voice":
                from gen_voice_lines import MOOD
                instruct = cast["instruct"].rstrip("。") + MOOD.get(entry["mood"], "")
                chunks = list(model.generate_custom_voice(speaker=cast["speaker"], language="Chinese", instruct=instruct, **kwargs))
            else:
                instruct = None
                chunks = list(model.generate(ref_audio=str(REFERENCE), ref_text=REFERENCE_TEXT, lang_code="chinese", **kwargs))
            audio = tidy(np.concatenate([np.asarray(chunk.audio, dtype=np.float32).reshape(-1) for chunk in chunks]))
            mx.synchronize()
            elapsed = time.perf_counter() - started
            path = out / (mode + "_" + entry["name"] + ".wav")
            sf.write(path, audio, model.sample_rate, subtype="PCM_16")
            manifest["results"].append({**entry, "mode": mode, "seed": seed, "instruct": instruct,
                "file": str(path), "sha256": sha(path), "seconds": len(audio) / model.sample_rate,
                "generation_seconds": round(elapsed, 3), "sample_rate": model.sample_rate,
                "real_time_factor": round(elapsed / (len(audio) / model.sample_rate), 3)})
            (out / "comparison.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
            print(mode, entry["name"], round(elapsed, 2), "s", flush=True)
        del model
        mx.clear_cache()

    # Use the exact same encoder for every sample and the reference.
    model = load_model(snapshots["fixed_reference"])
    def embedding(path):
        audio, sample_rate = sf.read(path, dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        return np.asarray(model.extract_speaker_embedding(mx.array(audio), sample_rate)).reshape(-1)
    reference_embedding = embedding(REFERENCE)
    for result in manifest["results"]:
        feature = embedding(result["file"])
        result["speaker_cosine_to_reference"] = round(float(np.dot(feature, reference_embedding) /
            max(np.linalg.norm(feature) * np.linalg.norm(reference_embedding), 1e-8)), 5)
    del model
    mx.clear_cache()
    from mlx_audio.stt import load as load_stt
    asr = load_stt(asr_path)
    manifest["reference_asr"] = asr.generate(str(REFERENCE), language="Chinese").text
    manifest["reference_cer"] = round(cer(REFERENCE_TEXT, manifest["reference_asr"]), 4)
    for result in manifest["results"]:
        hypothesis = asr.generate(result["file"], language="Chinese").text
        result["asr"] = hypothesis
        result["cer"] = round(cer(result["text"], hypothesis), 4)
        print("ASR", result["mode"], result["name"], result["cer"], result["speaker_cosine_to_reference"], flush=True)
    (out / "comparison.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
