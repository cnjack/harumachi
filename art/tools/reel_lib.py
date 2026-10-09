"""Shared cutting code for the gameplay reels.

The autoplay / showcase drivers print `AP  mark <name>  frame=<n>` right before each screenshot.
A movie written with `--write-movie ... --fixed-fps 30` has one picture per drawn frame, so a mark
sits at n / 30 seconds in the movie. Segments are given relative to those marks, which keeps the
cuts right when the autoplay script changes.
"""
import os, re, subprocess, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MUSIC = os.path.join(ROOT, "game", "assets", "audio", "music")
FONT = os.path.join(ROOT, "game", "assets", "fonts", "LXGWWenKai-Medium.ttf")
FFMPEG = "/opt/homebrew/bin/ffmpeg"
FPS = 30.0
XF = 0.4


def marks(log_path: str) -> dict:
    out = {}
    for line in open(log_path, encoding="utf-8", errors="replace"):
        m = re.search(r"AP  mark (\S+)\s+frame=(\d+)", line)
        if m:
            out[m.group(1)] = int(m.group(2)) / FPS
    return out


def duration(path: str) -> float:
    r = subprocess.run(["/opt/homebrew/bin/ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "csv=p=0", path], capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def caption_png(text: str, sub: str, path: str, w: int = 1600, h: int = 900) -> None:
    """A lower-left caption on a transparent 1600x900 canvas (paper band + ink text)."""
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f1 = ImageFont.truetype(FONT, 46)
    f2 = ImageFont.truetype(FONT, 26)
    tw = max(d.textlength(text, font=f1), d.textlength(sub, font=f2) if sub else 0)
    x, y = 70, h - 190
    d.rounded_rectangle([x - 28, y - 22, x + tw + 32, y + (104 if sub else 70)], 18, fill=(250, 244, 230, 225))
    d.rectangle([x - 28, y - 22, x - 20, y + (104 if sub else 70)], fill=(214, 96, 78, 255))
    d.text((x, y), text, font=f1, fill=(58, 48, 42, 255))
    if sub:
        d.text((x + 2, y + 62), sub, font=f2, fill=(110, 96, 84, 255))
    im.save(path)


def build(segs: list, bed: list, out: str, fx_gain_db: float = 2.0, bed_gain_db: float = -4.0,
          crf: int = 19) -> float:
    """segs: [(file, start_s, dur_s, caption_or_None)], caption = (title, subtitle).
    bed: [(music_file, first_seg_index)] — each track starts at that segment and runs to the next.
    Clips are joined with 0.4 s cross-fades; the in-game sound effects stay under the music bed."""
    tmp = tempfile.mkdtemp(prefix="reel_")
    starts, t = [], 0.0
    for s in segs:
        starts.append(t)
        t += s[2] - XF
    total = t + XF
    args = [FFMPEG, "-loglevel", "error", "-y"]
    for f, s, d, _ in segs:
        args += ["-ss", "%.3f" % s, "-t", "%.3f" % d, "-i", f]
    n = len(segs)
    caps = {}
    for i, s in enumerate(segs):
        if s[3]:
            p = os.path.join(tmp, "cap%02d.png" % i)
            caption_png(s[3][0], s[3][1] if len(s[3]) > 1 else "", p)
            caps[i] = len(caps)
            args += ["-loop", "1", "-t", "%.3f" % s[2], "-i", p]
    nb = n + len(caps)
    for f, _ in bed:
        args += ["-i", os.path.join(MUSIC, f)]
    fc = []
    for i, (f, s, d, cap) in enumerate(segs):
        fc.append(f"[{i}:v]scale=1600:900,fps=30,format=yuv420p,setpts=PTS-STARTPTS[v{i}r]")
        if i in caps:
            ci = n + caps[i]
            fc.append(f"[{ci}:v]format=rgba,fade=t=in:st=0.3:d=0.4:alpha=1,"
                      f"fade=t=out:st={d - 0.7:.3f}:d=0.4:alpha=1,setpts=PTS-STARTPTS[c{i}]")
            fc.append(f"[v{i}r][c{i}]overlay=0:0:shortest=1,format=yuv420p[v{i}]")
        else:
            fc.append(f"[v{i}r]null[v{i}]")
        if f.endswith(".avi") and not os.path.basename(f).startswith("title"):
            fc.append(f"[{i}:a]aresample=48000,asetpts=PTS-STARTPTS[a{i}]")
        else:
            fc.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{d:.3f}[a{i}]")
    pv, pa, off = "v0", "a0", segs[0][2] - XF
    for i in range(1, n):
        fc.append(f"[{pv}][v{i}]xfade=transition=fade:duration={XF}:offset={off:.3f}[x{i}]")
        fc.append(f"[{pa}][a{i}]acrossfade=d={XF}:c1=tri:c2=tri[y{i}]")
        pv, pa = f"x{i}", f"y{i}"
        off += segs[i][2] - XF
    names = []
    for k, (f, si) in enumerate(bed):
        a = max(0.0, starts[si] - (0.4 if k else 0.0))
        b = starts[bed[k + 1][1]] + 1.2 if k + 1 < len(bed) else total
        dur = b - a
        fo = 1.6 if k + 1 < len(bed) else 1.2
        fc.append(f"[{nb + k}:a]aresample=48000,atrim=0:{dur:.3f},asetpts=PTS-STARTPTS,"
                  f"afade=t=in:d={0.3 if k == 0 else 1.0},afade=t=out:st={dur - fo:.3f}:d={fo},"
                  f"adelay={int(a * 1000)}|{int(a * 1000)},volume={bed_gain_db}dB[m{k}]")
        names.append(f"[m{k}]")
    fc.append("".join(names) + f"amix=inputs={len(bed)}:normalize=0,atrim=0:{total:.3f}[bed]")
    fc.append(f"[{pa}]volume={fx_gain_db}dB[fx]")
    fc.append(f"[bed][fx]amix=inputs=2:normalize=0,afade=t=out:st={total - 1.0:.3f}:d=1.0,"
              f"loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]")
    fc.append(f"[{pv}]fade=t=in:st=0:d=0.5,fade=t=out:st={total - 0.8:.3f}:d=0.8[vout]")
    args += ["-filter_complex", ";".join(fc), "-map", "[vout]", "-map", "[aout]", "-c:v", "libx264",
             "-crf", str(crf), "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
             "-movflags", "+faststart", out]
    subprocess.run(args, check=True)
    return total
