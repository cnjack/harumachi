#!/usr/bin/env python3
"""Trim real Movie Maker frames and make labeled A/B review clips (no retouching)."""
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
LABELS = {"farm": "农园 · 正午", "street": "商店街 · 夕阳", "plaza_festival_night": "夏祭 · 夜景", "store_interior": "商店 · 室内"}


def run(cmd):
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=300)
    if result.returncode:
        raise RuntimeError(result.stderr[-4000:])


def probe(path):
    return json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], text=True))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("out", type=Path)
    ap.add_argument("--reuse-solos", action="store_true", help="Resume comparison encoding using the eight solo videos already encoded from this capture")
    args = ap.parse_args()
    out = args.out.resolve(); stage = Path(json.loads((out / "stage.json").read_text())["stage"])
    target = out / "videos"; target.mkdir(exist_ok=True)
    manifests = {look: json.loads((out / "record" / look / "clips.json").read_text())["clips"] for look in ["before", "poc"]}
    assert [x["view"] for x in manifests["before"]] == [x["view"] for x in manifests["poc"]]
    settings = ["profile", "fps_cap", "scale", "msaa", "shadow_size", "physics_hz"]
    for before, after in zip(manifests["before"], manifests["poc"]):
        assert before["camera"] == after["camera"] and before["minute"] == after["minute"]
        assert {k: before["graphics"][k] for k in settings} == {k: after["graphics"][k] for k in settings}
    ff = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-threads", "4"]
    output_options = ["-an", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-threads", "4", "-pix_fmt", "yuv420p",
                      "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-movflags", "+faststart"]
    records = []
    for look, clips in manifests.items():
        source = stage / (look + ".avi"); info = probe(source); stream = next(s for s in info["streams"] if s["codec_type"] == "video")
        assert stream["width"] == 1920 and stream["height"] == 1080 and stream["r_frame_rate"] == "30/1"
        matrix = "bt709" if stream.get("color_space") == "bt709" else "bt601"
        color_range = "pc" if stream.get("color_range") == "pc" or stream["pix_fmt"].startswith("yuvj") else "tv"
        for clip in clips:
            first = clip["trim_start"]; end = first + clip["frames"]
            assert end <= clip["end_frame"]
            path = target / (clip["view"] + "-" + look + ".mp4")
            vf = f"trim=start_frame={first}:end_frame={end},setpts=PTS-STARTPTS,scale=in_color_matrix={matrix}:out_color_matrix=bt709:in_range={color_range}:out_range=tv,format=yuv420p,setsar=1"
            if args.reuse_solos:
                existing = next(s for s in probe(path)["streams"] if s["codec_type"] == "video")
                assert [existing["width"], existing["height"], existing["r_frame_rate"], int(existing["nb_frames"])] == [1920, 1080, "30/1", 360]
            else:
                run(ff + ["-i", str(source), "-vf", vf] + output_options + [str(path)])
            print("Reused" if args.reuse_solos else "Encoded", path.name, flush=True)
            records.append({"file": str(path.relative_to(out)), "kind": look, "view": clip["view"], "source_frame_start": first,
                            "frames": clip["frames"], "source_color_space": matrix, "source_color_range": color_range})
    font = ImageFont.truetype(str(ROOT / "game/assets/fonts/LXGWWenKai-Medium.ttf"), 27)
    comparisons = []
    for id, label in LABELS.items():
        before = target / (id + "-before.mp4"); after = target / (id + "-poc.mp4"); path = target / (id + "-compare.mp4")
        # Pillow keeps labels independent of optional FFmpeg drawtext/libfreetype builds.
        banner = Image.new("RGB", (2560, 56), "#101b25")
        draw = ImageDraw.Draw(banner)
        draw.text((24, 28), "当前均衡 · " + label, font=font, fill="white", anchor="lm")
        draw.text((1304, 28), "光影 POC · " + label, font=font, fill="#b9e0d7", anchor="lm")
        banner_path = stage / (id + "-labels.png"); banner.save(banner_path)
        filters = ("[0:v]scale=1280:720[a];[1:v]scale=1280:720[b];"
                   "[a][b]hstack=inputs=2,pad=2560:776:0:56:color=0x101b25[scene];"
                   "[2:v]scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p[labels];"
                   "[scene][labels]overlay=0:0:shortest=1:format=yuv420[v]")
        run(ff + ["-i", str(before), "-i", str(after), "-loop", "1", "-framerate", "30", "-i", str(banner_path),
                  "-filter_complex", filters, "-map", "[v]"] + output_options + [str(path)])
        comparisons.append(path); records.append({"file": str(path.relative_to(out)), "kind": "compare", "view": id})
        print("Compared", path.name, flush=True)
    listing = target / "concat.txt"; listing.write_text("".join("file '" + p.name + "'\n" for p in comparisons))
    summary = target / "lighting-poc-comparison.mp4"
    run(ff + ["-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", "-movflags", "+faststart", str(summary)])
    listing.unlink(); records.append({"file": str(summary.relative_to(out)), "kind": "summary"})
    for record in records:
        path = out / record["file"]; info = probe(path); stream = next(s for s in info["streams"] if s["codec_type"] == "video")
        run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "null", "-"])
        expected = 48.0 if record["kind"] == "summary" else 12.0
        assert abs(float(info["format"]["duration"]) - expected) < .05
        assert stream["pix_fmt"] == "yuv420p" and stream["color_range"] == "tv" and stream["color_space"] == "bt709"
        record.update({"duration": float(info["format"]["duration"]), "dimensions": [stream["width"], stream["height"]],
                       "fps": stream["r_frame_rate"], "bytes": path.stat().st_size, "decode_passed": True})
    (out / "media-validation.json").write_text(json.dumps({"passed": True, "camera_paths_identical": True,
        "graphics_settings_identical": True, "clips": records, "notes": ["Native Godot rendering; no image generation or post-production relighting", "30 FPS fixed-time movie, not runtime FPS evidence", "Game time and camera paths match; wind/NPC animation phases may vary between processes"]}, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__": main()
