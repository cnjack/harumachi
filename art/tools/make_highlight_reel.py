"""Cut the gameplay highlight reel from an autoplay movie recorded with --no-music.

    python3 art/tools/make_highlight_reel.py <movie_dir>

<movie_dir> holds play.avi (`--write-movie play.avi --fixed-fps 30 -- --autoplay --no-music`),
play_log.txt (that run's stdout, for the `AP  mark` lines) and title.avi (the title screen).
Each segment is placed relative to an autoplay mark, so the cuts follow the script when it changes.
One continuous music bed runs underneath; the mix is normalised to -16 LUFS.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reel_lib as R

os.chdir(sys.argv[1] if len(sys.argv) > 1 else ".")
M = R.marks("play_log.txt")
OUT = os.path.join(R.ROOT, "evidence", "gameplay_highlights.mp4")
# (mark, seconds relative to the mark, duration)
PLAN = [
    ("arrival", -5.0, 4.5), ("room", -1.8, 3.6), ("house_living", -2.2, 3.6),
    ("onigiri_play", -3.0, 4.4), ("onigiri_done", -1.6, 3.0), ("meet_mio", -3.6, 4.0),
    ("bakery", -3.6, 4.0), ("goldfish_play", -2.0, 4.0), ("watered", -3.0, 3.6),
    ("placement", -3.6, 4.0), ("general_store", -3.4, 4.0), ("farm_arrival", -2.2, 4.2),
    ("first_seeds", -3.0, 3.6), ("river_sunset", -3.8, 7.4), ("night_home", -2.2, 3.2),
    ("kitchen_cooking", -0.8, 4.2), ("meet_aoi", -3.2, 3.6), ("tanaka_tending", -3.2, 3.6),
    ("bakery_oven", -3.6, 4.0), ("harvest", -2.6, 3.6), ("market_evening", -2.2, 4.6),
    ("ending", -1.0, 4.6), ("finale", -3.2, 4.2), ("market_stall", -3.2, 4.0),
    ("grandma_box", -1.0, 5.0), ("mio_photo", -4.0, 4.4),
    ("tanabata_wish", -3.2, 4.2), ("tanabata_night", -4.2, 5.6),
]
segs = [("title.avi", 0.8, 3.5, None)]
for name, rel, d in PLAN:
    if name not in M:
        print("missing mark", name)
        continue
    segs.append(("play.avi", max(0.0, M[name] + rel), d, None))
idx = {name: i + 1 for i, (name, _, _) in enumerate(PLAN)}
bed = [("title.ogg", 0), ("day.ogg", 1), ("shop.ogg", idx["general_store"]), ("farm.ogg", idx["farm_arrival"]),
       ("night.ogg", idx["night_home"]), ("day.ogg", idx["meet_aoi"]), ("market.ogg", idx["market_evening"]),
       ("ending.ogg", idx["ending"]), ("market.ogg", idx["market_stall"]), ("memory.ogg", idx["grandma_box"]),
       ("tanabata.ogg", idx["tanabata_wish"])]
total = R.build(segs, bed, OUT)
print("wrote %s  %.1f s, %d clips" % (OUT, total, len(segs)))
