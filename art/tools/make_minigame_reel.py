"""Cut the mini-game showcase (~70 s) from the five sandbox recordings.

    python3 art/tools/make_minigame_reel.py <movie_dir>

<movie_dir> holds mg_<id>.avi for onigiri, unpack, puzzle, goldfish and taiko, each recorded with
    godot --path game --resolution 1600x900 --write-movie <dir>/mg_<id>.avi --fixed-fps 30 \\
        res://scenes/mg_sandbox.tscn -- --mg=<id> --auto
Every game gets its rules card, two stretches of play and the result card. A title card (drawn
here with the game's font and the five icons) opens the reel. Sound is the games' own effects;
the town's daytime music runs quietly underneath and steps aside for the taiko song. The mix is
normalised to -16 LUFS. Needs ffmpeg and Pillow.
"""
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "evidence", "minigames_showcase.mp4")
FF = "/opt/homebrew/bin/ffmpeg"
T = 0.4
os.chdir(sys.argv[1] if len(sys.argv) > 1 else ".")

# id, name, place, play stretches [(start, length)]
GAMES = [
    ("onigiri", "捏饭团", "厨房 · 电饭煲", [(30.0, 5.0), (55.0, 4.0)]),
    ("unpack", "拆箱整理", "客厅 · 纸箱堆", [(40.0, 5.0), (70.0, 4.0)]),
    ("puzzle", "晴町地图拼图", "卧室 · 书桌", [(20.0, 5.0), (60.0, 4.0)]),
    ("goldfish", "捞金鱼", "共享庭院 · 水槽", [(25.0, 5.0), (45.0, 4.0)]),
    ("taiko", "祭典太鼓", "共享庭院 · 小舞台", [(18.0, 5.0), (36.0, 4.0)]),
]


def duration(path):
    r = subprocess.run(["/opt/homebrew/bin/ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                       capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def title_card(path):
    W, H = 1600, 900
    im = Image.new("RGB", (W, H), (246, 238, 222))
    d = ImageDraw.Draw(im)
    font = os.path.join(GAME, "assets", "fonts", "LXGWWenKai-Medium.ttf")
    big, mid, small = ImageFont.truetype(font, 86), ImageFont.truetype(font, 40), ImageFont.truetype(font, 30)
    ink, soft, accent = (74, 52, 38), (128, 104, 84), (214, 120, 60)
    d.rounded_rectangle([60, 60, W - 60, H - 60], 36, outline=(190, 160, 120), width=4)
    d.text((W / 2, 200), "晴町日常", font=big, fill=ink, anchor="mm")
    d.text((W / 2, 290), "新家里的五个小游戏", font=mid, fill=accent, anchor="mm")
    x0 = (W - 5 * 260) / 2
    for i, (gid, name, place, _) in enumerate(GAMES):
        cx = x0 + 130 + i * 260
        icon = Image.open(os.path.join(GAME, "assets", "minigames", gid, "icon.png")).convert("RGBA").resize((170, 170))
        im.paste(icon, (int(cx - 85), 390), icon)
        d.text((cx, 600), name, font=mid, fill=ink, anchor="mm")
        d.text((cx, 650), place, font=small, fill=soft, anchor="mm")
    d.text((W / 2, 770), "拿到星星换生活币 · 首次通关还有专属奖励", font=small, fill=soft, anchor="mm")
    im.save(path)


title_card("mg_title.png")
segs = [("mg_title.png", 0.0, 3.2, None)]
for gid, _, _, plays in GAMES:
    f = f"mg_{gid}.avi"
    d = duration(f)
    segs.append((f, 0.5, 2.4, gid))
    for s, l in plays:
        segs.append((f, s, l, gid))
    segs.append((f, d - 3.0, 2.8, gid))

starts, t = [], 0.0
for s in segs:
    starts.append(t)
    t += s[2] - T
total = t + T

args = [FF, "-loglevel", "error", "-y"]
for f, s, d, _ in segs:
    if f.endswith(".png"):
        args += ["-loop", "1", "-t", str(d), "-i", f]
    else:
        args += ["-ss", str(s), "-t", str(d), "-i", f]
n = len(segs)
args += ["-i", os.path.join(GAME, "assets", "audio", "music", "day.ogg")]
fc = []
for i, (f, s, d, _) in enumerate(segs):
    fc.append(f"[{i}:v]scale=1600:900,fps=30,format=yuv420p,setpts=PTS-STARTPTS[v{i}]")
    if f.endswith(".png"):
        fc.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{d}[a{i}]")
    else:
        fc.append(f"[{i}:a]aresample=48000,asetpts=PTS-STARTPTS[a{i}]")
pv, pa, off = "v0", "a0", segs[0][2] - T
for i in range(1, n):
    fc.append(f"[{pv}][v{i}]xfade=transition=fade:duration={T}:offset={off:.3f}[x{i}]")
    fc.append(f"[{pa}][a{i}]acrossfade=d={T}:c1=tri:c2=tri[y{i}]")
    pv, pa = f"x{i}", f"y{i}"
    off += segs[i][2] - T
# music bed: day theme from the start until the taiko block, back for nothing after (taiko is last)
t_taiko = starts[next(i for i, s in enumerate(segs) if s[3] == "taiko")]
fc.append(f"[{n}:a]aresample=48000,atrim=0:{t_taiko + 0.8:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.8,"
          f"afade=t=out:st={t_taiko - 0.6:.3f}:d=1.4,volume=-9dB[bed]")
fc.append(f"[{pa}]volume=1dB[fx]")
fc.append(f"[bed][fx]amix=inputs=2:normalize=0:duration=longest,atrim=0:{total:.3f},afade=t=out:st={total - 1.0:.3f}:d=1.0,"
          f"loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]")
fc.append(f"[{pv}]fade=t=in:st=0:d=0.5,fade=t=out:st={total - 0.8:.3f}:d=0.8[vout]")
args += ["-filter_complex", ";".join(fc), "-map", "[vout]", "-map", "[aout]", "-c:v", "libx264", "-crf", "20",
         "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", OUT]
subprocess.run(args, check=True)
# one-pass loudnorm lands within ~1.5 LU; measure and trim the level so the file sits at -16 LUFS
r = subprocess.run([FF, "-hide_banner", "-i", OUT, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True)
lufs = float(r.stderr.split("Integrated loudness:")[1].split("I:")[1].split("LUFS")[0])
if abs(lufs + 16.0) > 0.3:
    tmp = OUT.replace(".mp4", "_tmp.mp4")
    subprocess.run([FF, "-loglevel", "error", "-y", "-i", OUT, "-c:v", "copy", "-af", f"volume={-16.0 - lufs:.2f}dB",
                    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", tmp], check=True)
    os.replace(tmp, OUT)
print("loudness %.1f LUFS before trim" % lufs)
print("total %.2f s, %d segments, taiko from %.1f s" % (total, n, t_taiko))
