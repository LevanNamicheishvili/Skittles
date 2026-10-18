# Writes spec/fixtures/scene_runs.json: input runs on small scenes and the state they must reach, step by step as
# spec/scene-play.md section 3 says. This file is a third, plain implementation of the steps; the notes give the rough
# numbers the physics predicts, so a mistake here shows. Run: python3 spec/fixtures/make_scene_runs.py spec/fixtures/scene_runs.json
import json, math, sys

DT = 1 / 120
LEFT, RIGHT, JUMP = 1, 2, 4


def overlaps(a, b):
    return a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]


def enemy_x(e, frame):
    p = e.get("behaviours", {}).get("patrol", {})
    lo, hi, speed = p.get("from", e["x"]), p.get("to", e["x"]), p.get("speed", 90)
    start = min(max(e["x"], lo), hi)
    length = hi - lo
    if length <= 0 or speed <= 0:
        return start
    m = ((start - lo) + speed * (frame / 120)) % (2 * length)
    return lo + m if m <= length else lo + 2 * length - m


class Game:
    def __init__(self, scene):
        self.scene = scene
        objs = scene["objects"]
        self.player = next(o for o in objs if o["type"] == "player")
        c = self.player.get("behaviours", {}).get("controller", {})
        self.speed, self.jump = c.get("speed", 260), c.get("jump", 640)
        self.g = scene["physics"]["gravity"]
        self.W, self.H = scene["size"]["w"], scene["size"]["h"]
        self.w, self.h = self.player["w"], self.player["h"]
        self.platforms = [o for o in objs if o["type"] == "platform"]
        self.coins = [o for o in objs if o["type"] == "coin"]
        self.enemies = [o for o in objs if o["type"] == "enemy"]
        self.finishes = [o for o in objs if o["type"] == "finish"]
        self.frame = self.score = self.deaths = self.safe = 0
        self.collected = []
        self.won = False
        self.prev_jump = False
        self.respawn()

    def respawn(self):
        self.x, self.y = self.player["x"], self.player["y"]
        self.vx = self.vy = 0
        self.grounded = False
        self.air = 11
        self.buffer = 0

    def die(self):
        self.deaths += 1
        self.respawn()
        self.safe = 120

    def step(self, bits):
        if self.won:
            return
        self.frame += 1
        self.vx = self.speed * ((1 if bits & RIGHT else 0) - (1 if bits & LEFT else 0))
        jump = bool(bits & JUMP)
        pressed = jump and not self.prev_jump
        self.prev_jump = jump
        if pressed:
            self.buffer = 12
        elif self.buffer > 0:
            self.buffer -= 1
        self.air = 0 if self.grounded else self.air + 1
        if self.buffer > 0 and self.air <= 10:
            self.vy = -self.jump
            self.buffer = 0
            self.air = 11
            self.grounded = False
        x, y, w, h = self.x, self.y, self.w, self.h
        nx = x + self.vx * DT
        for p in self.platforms:
            if not (p["y"] < y + h and y < p["y"] + p["h"]):
                continue
            if self.vx > 0 and x + w <= p["x"] < nx + w:
                nx = min(nx, p["x"] - w)
            if self.vx < 0 and nx < p["x"] + p["w"] <= x:
                nx = max(nx, p["x"] + p["w"])
        x = min(max(nx, 0), self.W - w)
        self.x = x
        ny = y + self.vy * DT + 0.5 * self.g * DT * DT
        self.vy = self.vy + self.g * DT
        self.grounded = False
        if ny > y:
            land = None
            for p in self.platforms:
                if p["x"] < x + w and x < p["x"] + p["w"] and y + h <= p["y"] < ny + h:
                    land = p["y"] - h if land is None else min(land, p["y"] - h)
            if land is not None:
                ny, self.vy, self.grounded = land, 0, True
        elif ny < y:
            bump = None
            for p in self.platforms:
                if p["x"] < x + w and x < p["x"] + p["w"] and ny < p["y"] + p["h"] <= y:
                    bump = p["y"] + p["h"] if bump is None else max(bump, p["y"] + p["h"])
            if bump is not None:
                ny, self.vy = bump, 0
        if ny < 0:
            ny, self.vy = 0, 0
        self.y = ny
        if self.y > self.H:
            return self.die()
        me = {"x": self.x, "y": self.y, "w": w, "h": h}
        for c in self.coins:
            if c["id"] not in self.collected and overlaps(me, c):
                self.collected.append(c["id"])
                self.score += c.get("behaviours", {}).get("collectible", {}).get("points", 10)
        if self.safe > 0:
            self.safe -= 1
        else:
            for e in self.enemies:
                if overlaps(me, {**e, "x": enemy_x(e, self.frame)}):
                    return self.die()
        if any(overlaps(me, f) for f in self.finishes):
            self.won = True

    def state(self):
        return {"frame": self.frame, "x": self.x, "y": self.y, "vx": self.vx, "vy": self.vy, "grounded": self.grounded,
                "score": self.score, "coins": list(self.collected), "deaths": self.deaths, "won": self.won,
                "enemies": {e["id"]: enemy_x(e, self.frame) for e in self.enemies}}


def obj(id, type, x, y, w, h, **behaviours):
    o = {"id": id, "name": id, "type": type, "x": x, "y": y, "w": w, "h": h}
    if behaviours:
        o["behaviours"] = behaviours
    return o


def player(x=100, y=772, speed=260, jump=640):
    return obj("player", "player", x, y, 32, 48, controller={"speed": speed, "jump": jump})


def scene(objects):
    return {"format": "skittles-scene", "version": 1, "name": "case", "template": "platformer", "size": {"w": 1600, "h": 900},
            "theme": "forest", "physics": {"gravity": 1800}, "objects": objects, "ui": {"score": True}}


ground = lambda x=0, w=1600: obj("ground", "platform", x, 820, w, 80)


def case(name, sc, run, checks, notes):
    """checks: list of (after_frames, keys to report)"""
    game = Game(sc)
    flat = [bits for frames, bits in run for _ in range(frames)]
    out = []
    done = 0
    for after, keys in checks:
        while done < after:
            game.step(flat[done] if done < len(flat) else 0)
            done += 1
        s = game.state()
        out.append({"after": after, "expect": {k: s[k] for k in keys}})
    return {"name": name, "scene": sc, "run": run, "checks": out, "notes": notes}


POS = ["frame", "x", "y", "vx", "vy", "grounded"]
cases = [
    case("standing still: the player lands and stays", scene([ground(), player()]), [[120, 0]],
         [(1, POS), (120, POS)], "Feet start on the ground's top (772 + 48 = 820), so every step lands again: y stays 772, vy 0."),
    case("running right for a second covers the run speed", scene([ground(), player()]), [[120, RIGHT]],
         [(120, POS)], "260 px/s for 1 s: x goes from 100 to about 360."),
    case("a jump in place peaks at the jump height and lands", scene([ground(), player()]), [[2, 0], [1, JUMP], [120, 0]],
         [(2 + 43, POS), (2 + 86, POS), (130, POS)],
         "Take-off on step 3. The peak is v/g = 0.356 s = about 43 steps later, 640²/3600 = 113.8 px up: y near 658.2. Back down about 86 steps after take-off."),
    case("running into a wall stops at its side", scene([ground(), obj("wall", "platform", 300, 600, 40, 220), player()]), [[120, RIGHT]],
         [(120, POS)], "The wall's left side is at 300, so the player's x stops at 300 − 32 = 268."),
    case("a running jump lands on a ledge 80 px up", scene([ground(), obj("ledge", "platform", 200, 740, 200, 24), player()]),
         [[2, 0], [1, RIGHT | JUMP], [80, RIGHT]],
         [(2 + 1 + 70, POS)],
         "Landing 80 px higher takes (640 + √(640² − 2·1800·80)) / 1800 = 0.549 s = 66 steps; x is about 100 + 143 = 243, over the ledge (200..400), so it stands at y = 740 − 48 = 692. Then it runs on to the right."),
    case("walking off the world: fall, die, start again", scene([obj("ground", "platform", 0, 820, 200, 80), player()]), [[200, RIGHT]],
         [(60, POS + ["deaths"]), (110, POS + ["deaths"])],
         "It leaves the ground when x passes 200 (about 47 steps), then falls 80 px below the scene's bottom (y > 900) in about 0.38 s = 46 steps: dead near step 93, back at x = 100."),
    case("a coin counts once", scene([ground(), obj("coin", "coin", 200, 780, 24, 24, collectible={"points": 25}), player()]),
         [[80, RIGHT], [80, LEFT]],
         [(80, ["score", "coins"]), (160, ["score", "coins", "x"])], "Running through the coin and back: 25 points, not 50."),
    case("an enemy sends the player back to the start, then a second of safety",
         scene([ground(), obj("enemy", "enemy", 300, 784, 40, 36, patrol={"from": 60, "to": 300, "speed": 120}), player(x=120)]),
         [[100, 0], [40, RIGHT], [200, 0]],
         [(60, ["deaths", "x", "enemies"]), (200, ["deaths", "x", "y", "enemies"]), (340, ["deaths", "x", "enemies"])],
         "The enemy starts at 300, the right end of its patrol, so it turns at once and walks left at 120 px/s. At step 60 it is at 240. The player stands until step 100, then runs right into it: they meet when the enemy's x is under the player's right side, and the player is back at 120 with one death. For the next 120 steps the enemy passes through the standing player harmlessly; it turns at 60 at t = 2 s and comes back, and once the safe second is over it catches the player again."),
    case("touching the finish wins and stops the clock", scene([ground(), obj("finish", "finish", 300, 700, 60, 120), player()]), [[300, RIGHT]],
         [(120, ["won", "frame"]), (300, ["won", "frame", "x"])],
         "The finish starts at 300: the player touches it when x passes 268, after about 77 steps. The frame stays there."),
    case("a jump just after walking off an edge still works", scene([obj("ground", "platform", 0, 820, 200, 80), player()]),
         [[51, RIGHT], [1, RIGHT | JUMP], [10, RIGHT]],
         [(52, ["vy", "grounded"]), (62, ["vy", "y"])],
         "It leaves the ground near step 47; a press at step 52 is within the 10 steps of grace, so vy becomes −640 + 15."),
    case("a jump long after walking off an edge does nothing", scene([obj("ground", "platform", 0, 820, 200, 80), player()]),
         [[65, RIGHT], [1, RIGHT | JUMP], [5, RIGHT]],
         [(66, ["vy", "grounded"])], "Pressed about 19 steps after leaving the ground: too late, it keeps falling (vy > 0)."),
    case("a press just before landing jumps on landing", scene([ground(), player(y=700)]),
         [[25, 0], [1, JUMP], [20, 0]],
         [(26, ["grounded", "vy"]), (40, ["vy", "grounded"])],
         "Dropped from 72 px above the ground it lands after about 34 steps. The press at step 26 is held for 12 steps, so it takes off right after landing: by step 40 vy is negative."),
    case("the head bumps a low ceiling", scene([ground(), obj("roof", "platform", 0, 700, 400, 24), player()]),
         [[2, 0], [1, JUMP], [30, 0]],
         [(33, ["y", "vy"])], "The roof's bottom is at 724; the head (y) stops there and vy goes to 0, then the player falls back."),
]

json.dump({"$comment": "Shared cases for spec/scene-play.md: each run is replayed step by step; after each check's number of steps the state must match (numbers within 1e-6). A run shorter than a check is padded with no input.",
           "cases": cases}, open(sys.argv[1], "w"), indent=1, ensure_ascii=False)
print(len(cases), "cases")
for c in cases:
    print("-", c["name"], [ck["expect"] for ck in c["checks"]])
