"""Cut the festival reel from the showcase movie (plus Tanabata from the autoplay movie).

    python3 art/tools/make_festival_reel.py <movie_dir>

<movie_dir> holds fest.avi + fest_log.txt (`--write-movie fest.avi --fixed-fps 30 -- --showcase --no-music`),
play.avi + play_log.txt (the autoplay run, for Tanabata) and title.avi. Each festival opens with a caption card.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reel_lib as R

os.chdir(sys.argv[1] if len(sys.argv) > 1 else ".")
F = R.marks("fest_log.txt")
P = R.marks("play_log.txt")
OUT = os.path.join(R.ROOT, "evidence", "festivals_showcase.mp4")
# (movie, marks, mark, seconds relative to the mark, duration, caption)
PLAN = [
    ("play.avi", P, "tanabata_wish", -3.0, 4.4, ("七夕", "7月7日 · 在庭院门口的竹子上挂短册")),
    ("play.avi", P, "tanabata_night", -4.4, 5.2, None),
    ("fest.avi", F, "contest_arrive", -1.4, 4.0, ("晴町蔬菜品评会", "7月14日 · 交一份作物，和邻居比分数")),
    ("fest.avi", F, "contest_board", -0.4, 3.8, None),
    ("fest.avi", F, "contest_result", -2.6, 3.4, None),
    ("fest.avi", F, "natsu_arrive", -1.6, 4.2, ("晴町夏祭", "7月20日 · 盆舞台、屋台，摊位料理 2 倍价")),
    ("fest.avi", F, "natsu_stalls", -3.0, 3.4, None),
    ("fest.avi", F, "natsu_stall_sell", -2.2, 3.2, None),
    ("fest.avi", F, "bon_odori_dance", -0.8, 6.6, ("盆舞", "20 点起，大家围着盆舞台跳")),
    ("fest.avi", F, "natsu_photo", -3.0, 4.6, ("金鱼摊前的约定", "第三章 · 十五年后的新合影")),
    ("fest.avi", F, "hanabi_arrive", -1.6, 4.0, ("晴川花火大会", "7月27日 · 在河边选一个人一起看烟花")),
    ("fest.avi", F, "hanabi_watch", -0.6, 7.2, None),
    ("fest.avi", F, "obon_float", -3.2, 4.6, ("盂兰盆 · 灯笼流", "8月15日 · 从木桥上放一盏纸灯笼")),
    ("fest.avi", F, "obon_lanterns", -3.6, 4.6, None),
    ("fest.avi", F, "tsukimi_arrive", -1.6, 4.2, ("月见", "9月17日 · 在供台上摆一盘月见团子")),
    ("fest.avi", F, "tsukimi_offer", -0.6, 3.4, None),
    ("fest.avi", F, "tsukimi_offering", -3.6, 5.2, None),
]
segs = [("title.avi", 0.8, 3.2, None)]
for f, m, name, rel, d, cap in PLAN:
    if name not in m:
        sys.exit("missing mark %s in %s" % (name, f))
    segs.append((f, max(0.0, m[name] + rel), d, cap))
first = {name: i + 1 for i, (_, _, name, _, _, _) in enumerate(PLAN)}
bed = [("title.ogg", 0), ("tanabata.ogg", first["tanabata_wish"]), ("contest.ogg", first["contest_arrive"]),
       ("natsumatsuri.ogg", first["natsu_arrive"]), ("bon_odori.ogg", first["bon_odori_dance"]), ("memory.ogg", first["natsu_photo"]),
       ("hanabi.ogg", first["hanabi_arrive"]), ("obon.ogg", first["obon_float"]), ("tsukimi.ogg", first["tsukimi_arrive"])]
total = R.build(segs, bed, OUT)
print("wrote %s  %.1f s, %d clips" % (OUT, total, len(segs)))
