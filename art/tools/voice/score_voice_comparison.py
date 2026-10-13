"""Score evidence audio with one cached speaker encoder and ASR; never auto-approve voices."""
import argparse
import json
import math
import os
import pathlib

from compare_voice_models import REFERENCE, ROOT, fresh_evidence_file, sha


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--manifest", action="append", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    output = fresh_evidence_file(args.out)
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    import mlx.core as mx
    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly
    from huggingface_hub import snapshot_download
    from mlx_audio.tts.utils import load_model
    from gen_voice_lines import cer
    model = load_model(snapshot_download(repo_id="mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit", local_files_only=True))
    def embedding(path):
        audio, rate = sf.read(path, dtype="float32")
        if audio.ndim > 1: audio = audio.mean(axis=1)
        if rate != 24000:
            factor = math.gcd(rate, 24000)
            audio = resample_poly(audio, 24000 // factor, rate // factor)
        return np.asarray(model.extract_speaker_embedding(mx.array(audio), 24000)).reshape(-1)
    reference = embedding(REFERENCE)
    def cosine(a, b):
        return round(float(np.dot(a, b) / max(np.linalg.norm(a) * np.linalg.norm(b), 1e-8)), 5)
    controls = []
    for label, path in [("same selected Mio voice, different casting sentence", ROOT / "art/audio/voice_samples/mio_B_1.wav"),
                        ("different character Ren casting sample", ROOT / "art/audio/voice_samples/ren_A_0.wav")]:
        controls.append({"label": label, "file": str(path), "sha256": sha(path), "cosine": cosine(reference, embedding(path))})
    rows = []
    features = []
    for manifest in args.manifest:
        source = json.loads(pathlib.Path(manifest).read_text())
        entries = source if isinstance(source, list) else source["results"]
        for entry in entries:
            path = entry.get("copied_file", entry["file"])
            feature = embedding(path)
            rows.append({"source_manifest": manifest, "mode": entry.get("mode", "indextts2" if "indextts2" in path else "existing_production"),
                         "text": entry["text"], "mood": entry["mood"], "file": path, "sha256": sha(path),
                         "speaker_cosine_reference": cosine(reference, feature)})
            features.append(feature)
    del model
    mx.clear_cache()
    from mlx_audio.stt import load as load_stt
    asr = load_stt(snapshot_download(repo_id="mlx-community/Qwen3-ASR-0.6B-8bit", local_files_only=True))
    for row in rows:
        row["asr"] = asr.generate(row["file"], language="Chinese").text
        row["cer"] = round(cer(row["text"], row["asr"]), 4)
        print(row["mode"], row["cer"], row["speaker_cosine_reference"], row["asr"], flush=True)
    groups = {}
    for mode in dict.fromkeys(row["mode"] for row in rows):
        indexes = [index for index, row in enumerate(rows) if row["mode"] == mode]
        pairs = [cosine(features[left], features[right]) for offset, left in enumerate(indexes) for right in indexes[offset + 1:]]
        groups[mode] = {"samples": len(indexes), "all_cer_zero": all(rows[index]["cer"] == 0 for index in indexes),
                        "mean_cosine_reference": round(float(np.mean([rows[index]["speaker_cosine_reference"] for index in indexes])), 5),
                        "minimum_pairwise_cosine": min(pairs) if pairs else None}
    result = {"reference": str(REFERENCE), "reference_sha256": sha(REFERENCE), "encoder": "Qwen3-TTS Base 1.7B 8bit speaker encoder",
              "controls": controls, "groups": groups, "results": rows,
              "limitation": "Cosine is a diagnostic on three lines and this encoder; no perceptual quality or production identity pass is claimed. Human listening is required."}
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
