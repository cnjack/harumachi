"""Economy and time balance check for 晴町日常 (reads the game's own data files).

    python3 art/tools/balance_sim.py [days] [--quiet]

Simulates a steady, not min-maxing player: plants the best unlocked crop per plot, waters every day,
sells at the farm stand (holding produce for Saturday markets when close), cooks with spare produce,
buys expansions and upgrades once affordable, and fulfils about half of the daily board requests.
Prints per-crop and per-recipe margins, the coin / level curve, milestone days and the real-time budget
of a typical day. The targets checked at the end are the design goals in docs/game-design/BALANCE.md.
"""
import json, math, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
D = os.path.join(ROOT, "game", "data")
crops = json.load(open(os.path.join(D, "crops.json")))
items = json.load(open(os.path.join(D, "items.json")))
recipes = json.load(open(os.path.join(D, "recipes.json")))
fests = json.load(open(os.path.join(D, "festivals.json")))
# kept in sync with GameState (scripts/autoload/game_state.gd)
LEVELS = [0, 30, 90, 190, 340, 550, 830, 1190, 1640, 2200]
XP_TILL, XP_SOW, XP_WATER = 2, 1, 1
MARKET_RATE, STAND_RATE = 1.3, 1.0
EXPAND = [200, 600]
EXPAND_LV = [2, 4]
# late upgrades: (milestone, price, level, effect)
UPGRADES = [("yard_ext", 600, 3, "yard"), ("bag40", 1200, 5, "bag"), ("gh_ext", 900, 6, "gh"), ("gold_can", 1800, 7, "can")]
GLUT_N, GLUT_RATE = 12, 0.7        # a buyer pays full price for the first 12 of an item per day
MIN_PER_SEC = 1.5
FIRST_WEEKDAY, SATURDAY = 3, 5
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 30
QUIET = "--quiet" in sys.argv


def dish_margin(base, station):
    """Processing adds most to cheap produce and less to already valuable crops."""
    m = 1.25 + 0.35 * math.exp(-base / 150.0)
    return m + (0.07 if station == "oven" else 0.0)


def write_dish_prices():
    for rid, r in recipes.items():
        out_id, n = next(iter(r["output"].items()))
        if r["station"] == "mill":
            continue
        base = sum(raw_value(k) * v for k, v in r["inputs"].items())
        m = 1.15 if rid == "watermelon_slice" else dish_margin(base, r["station"])
        items[out_id]["sell"] = int(round(base * m / n / 5.0)) * 5
    json.dump(items, open(os.path.join(D, "items.json"), "w"), ensure_ascii=False, indent="\t")
    print("dish prices written")


def sale(iid, n, rate):
    full = min(n, GLUT_N)
    return int(round(items[iid].get("sell", 0) * rate)) * full + int(round(items[iid].get("sell", 0) * rate * GLUT_RATE)) * (n - full)


def level_of(xp):
    return sum(1 for t in LEVELS if xp >= t)


def weekday(d):
    return (d - 1 + FIRST_WEEKDAY) % 7


def price(i):
    return items[i].get("price", 0)


def raw_value(i):
    if i in crops:
        return crops[i]["sell"]
    return price(i)


def crop_profit_per_day(cid, horizon=12):
    c = crops[cid]
    t, harvests = c["days"], 0
    while t <= horizon:
        harvests += 1
        if c["regrow"] <= 0:
            t += c["days"]
        else:
            t += c["regrow"]
    if c["regrow"] <= 0:
        # replanting costs seeds each cycle
        cycles = horizon // c["days"]
        return (cycles * (c["yield"] * c["sell"] - c["seed_price"])) / max(1, cycles * c["days"])
    return (harvests * c["yield"] * c["sell"] - c["seed_price"]) / horizon


def report_margins():
    print("== crops (base price, 12-day horizon) ==")
    print(f"{'crop':11s} lv days rg  y sell seed  profit/plot/day  xp/day")
    for cid, c in sorted(crops.items(), key=lambda kv: kv[1]["level"]):
        per = crop_profit_per_day(cid)
        xpd = (c["xp"] / (c["regrow"] or c["days"])) + XP_WATER
        print(f"{cid:11s} {c['level']:2d} {c['days']:4d} {c['regrow']:2d} {c['yield']:2d} {c['sell']:4d} {c['seed_price']:4d}  {per:15.1f}  {xpd:6.1f}")
    print("== recipes ==")
    for rid, r in recipes.items():
        base = sum(raw_value(k) * v for k, v in r["inputs"].items())
        out_id, n = next(iter(r["output"].items()))
        val = items[out_id].get("sell", 0) * n if out_id != "flour" else price("flour") * n
        per_h = (val - base) / (r["minutes"] / 60.0)
        print(f"{rid:17s} {r['station']:7s} in {base:4d} -> {val:4d}  +{val - base:4d}  ({val / max(1, base):.2f}x)  {r['minutes']:3d} min  +{per_h:5.0f}/h  unlock {r['unlock']}")


class Sim:
    def __init__(self):
        self.coins = 100
        self.xp = 0
        self.plots = {}
        self.bag = {}
        self.known = {rid for rid, r in recipes.items() if r["unlock"].get("default")}
        self.expansions = 0
        self.bag_cap = 20
        self.can = 5
        self.log = []
        self.milestones = {}
        self.greenhouse = False

    def lvl(self):
        return level_of(self.xp)

    def open(self, ids):
        for i in ids:
            self.plots.setdefault(i, {"crop": None, "days": 0})

    def best_crop(self, pid):
        gh = pid.startswith("gh")
        cands = [c for c, d in crops.items() if d["level"] <= self.lvl() and d["greenhouse"] == gh and d["seed_price"] <= self.coins - 20]
        if not cands:
            return None
        return max(cands, key=lambda c: crop_profit_per_day(c) + 0.15 * crops[c]["xp"])

    def run_day(self, d):
        wd = weekday(d)
        income, spend, xp0 = 0, 0, self.xp
        actions = {"water": 0, "harvest": 0, "sow": 0, "refill": 0, "cook": 0, "sell": 0}
        # unlocks by story progress
        if d == 1:
            self.open(["farm0", "farm1", "farm2", "farm3", "yard0", "yard1", "yard2", "yard3", "court"])
            income += 20 + 30 + 40          # Q03, Q06, first mini-game stars
            self.xp += 4 * XP_TILL
        if d == 2:
            income += 35                    # remaining mini-game stars
        if d == 4 and not self.greenhouse:
            self.greenhouse = True
            self.open(["gh0", "gh1"])
            income += 20
        if d == 10:
            income += 50                    # Q09
        # grow (watered yesterday; rain handled as watered)
        for p in self.plots.values():
            if p["crop"]:
                p["days"] += 1
        # harvest
        produce = {}
        for pid, p in self.plots.items():
            c = p["crop"]
            if c and p["days"] >= crops[c]["days"]:
                produce[c] = produce.get(c, 0) + crops[c]["yield"]
                self.xp += crops[c]["xp"]
                actions["harvest"] += 1
                if crops[c]["regrow"] > 0:
                    p["days"] = crops[c]["days"] - crops[c]["regrow"]
                else:
                    p["crop"], p["days"] = None, 0
        for c, n in produce.items():
            self.bag[c] = self.bag.get(c, 0) + n
        # cook: best-margin known recipes, up to ~3 game hours of kitchen time
        budget = 180
        while budget > 0:
            best, gain = None, 0
            for rid in self.known:
                r = recipes[rid]
                if r["station"] == "mill" or r["minutes"] > budget:
                    continue
                if any(self.bag.get(k, 0) < v for k, v in r["inputs"].items() if k in crops):
                    continue
                buy = sum(price(k) * v for k, v in r["inputs"].items() if k not in crops)
                if buy > self.coins - 30:
                    continue
                out_id, n = next(iter(r["output"].items()))
                val = items[out_id]["sell"] * n
                base = sum(raw_value(k) * v for k, v in r["inputs"].items())
                if val - base > gain:
                    best, gain = rid, val - base
            if not best:
                break
            r = recipes[best]
            for k, v in r["inputs"].items():
                if k in crops:
                    self.bag[k] -= v
                else:
                    self.coins -= price(k) * v
                    spend += price(k) * v
            out_id, n = next(iter(r["output"].items()))
            self.bag[out_id] = self.bag.get(out_id, 0) + n
            budget -= r["minutes"]
            actions["cook"] += 1
        # sell: at the market on Saturdays; otherwise hold if Saturday is within 2 days
        days_to_sat = (SATURDAY - wd) % 7
        if wd == SATURDAY or days_to_sat > 2:
            rate = MARKET_RATE if wd == SATURDAY else STAND_RATE
            for k, n in list(self.bag.items()):
                if n > 0:
                    income += sale(k, n, rate)
                    self.bag[k] = 0
                    actions["sell"] += 1
        # board request about every other day
        if d >= 2 and d % 2 == 0:
            income += 60
        # festivals
        for fid, f in fests.items():
            if f["day"] == d and fid == "contest":
                lvl = self.lvl()
                score = max(crops[c]["sell"] * (1 + 0.08 * lvl) for c in crops if crops[c]["level"] <= lvl)
                rivals = sorted([r[2] for r in f["rivals"]], reverse=True)
                place = sum(1 for r in rivals if r >= score)
                income += f["prizes"][min(place, 3)]
        self.coins += income
        # replant and water
        for pid, p in self.plots.items():
            if not p["crop"]:
                c = self.best_crop(pid)
                if c:
                    p["crop"], p["days"] = c, 0
                    self.coins -= crops[c]["seed_price"]
                    spend += crops[c]["seed_price"]
                    self.xp += XP_SOW
                    actions["sow"] += 1
            if p["crop"]:
                self.xp += XP_WATER
                actions["water"] += 1
        actions["refill"] = math.ceil(actions["water"] / self.can)
        # purchases
        for key, cost, lv_req, eff in UPGRADES:
            if key not in self.milestones and self.lvl() >= lv_req and self.coins >= cost + 300:
                self.coins -= cost
                spend += cost
                self.milestones[key] = d
                if eff == "yard":
                    self.open(["yard4", "yard5"])
                elif eff == "gh":
                    self.open(["gh2", "gh3"])
                elif eff == "can":
                    self.can = 20
        if self.expansions < 2 and self.lvl() >= EXPAND_LV[self.expansions] and self.coins >= EXPAND[self.expansions] + 80:
            self.coins -= EXPAND[self.expansions]
            spend += EXPAND[self.expansions]
            base = 4 + 4 * self.expansions
            self.open([f"farm{i}" for i in range(base, base + 4)])
            self.xp += 4 * XP_TILL
            self.expansions += 1
            self.milestones.setdefault(f"expand{self.expansions}", d)
        if self.can < 10 and self.lvl() >= 3 and self.coins >= 500 + 150:
            self.coins -= 500
            spend += 500
            self.can = 10
            self.milestones.setdefault("copper_can", d)
        if self.bag_cap < 30 and self.coins >= 400 + 150:
            self.coins -= 400
            spend += 400
            self.bag_cap = 30
            self.milestones.setdefault("bag30", d)
        for rid, r in recipes.items():
            c = r["unlock"]
            if rid in self.known:
                continue
            ok = ("level" in c and self.lvl() >= c["level"] and "heart" not in c) or ("card" in c and self.coins >= c["card"] + 250)
            if "heart" in c and "level" not in c and "card" not in c:
                ok = d >= 8
            if ok:
                if "card" in c:
                    self.coins -= c["card"]
                    spend += c["card"]
                self.known.add(rid)
        lv = self.lvl()
        for L in range(2, lv + 1):
            self.milestones.setdefault(f"lv{L}", d)
        # real-time budget (seconds): travel, farm actions, shop/cook UI, chatting
        t = 60 + 3.2 * actions["water"] + 4.5 * actions["harvest"] + 5 * actions["sow"] + 6 * actions["refill"] + 12 * actions["cook"] + 6 * actions["sell"] + 5 * 18
        self.log.append((d, "日一二三四五六"[(wd + 1) % 7], self.coins, income, spend, self.xp, lv, len(self.plots), t))


def main():
    if "--write" in sys.argv:
        write_dish_prices()
    report_margins()
    s = Sim()
    for d in range(1, DAYS + 1):
        s.run_day(d)
    print("== simulation ==")
    print(" day wd  coins  +in  -out    xp lv plots  busy(s/720)")
    for row in s.log:
        if not QUIET or row[0] % 3 == 0:
            print(f"{row[0]:4d} 周{row[1]} {row[2]:6d} {row[3]:4d} {row[4]:5d} {row[5]:5d} {row[6]:2d} {row[7]:5d}  {row[8]:4.0f} ({row[8] / (18 * 60 / MIN_PER_SEC) * 100:.0f}%)")
    print("== milestones ==", ", ".join(f"{k}: day {v}" for k, v in sorted(s.milestones.items(), key=lambda kv: kv[1])))
    goals = [("expand1", 4, 9), ("expand2", 8, 16), ("bag30", 5, 14), ("lv4", 5, 11), ("lv7", 14, 26)]
    ok = True
    for k, lo, hi in goals:
        v = s.milestones.get(k)
        good = v is not None and lo <= v <= hi
        ok &= good
        print(f"  goal {k:8s} day {lo}-{hi}: {'OK ' if good else 'OFF'} ({v})")
    busy = max(r[8] for r in s.log) / (18 * 60 / MIN_PER_SEC)
    print(f"  busiest day uses {busy * 100:.0f}% of the waking day (goal <= 80%): {'OK' if busy <= 0.8 else 'OFF'}")
    ok &= busy <= 0.8
    print("BALANCE", "OK" if ok else "NEEDS TUNING")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
