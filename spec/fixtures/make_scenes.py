# Writes spec/fixtures/scenes.json. Expectations are worked out by hand in spec terms (see the notes), not computed.
import copy, json, sys

def obj(id, type, x, y, w, h, name=None, **behaviours):
    o = {"id": id, "name": name or type.capitalize(), "type": type, "x": x, "y": y, "w": w, "h": h}
    if behaviours: o["behaviours"] = behaviours
    return o

player = lambda x=80, y=772, id="player": obj(id, "player", x, y, 32, 48, controller={"speed": 260, "jump": 640})

def scene(name, objects):
    return {"format": "skittles-scene", "version": 1, "name": name, "template": "platformer", "size": {"w": 1600, "h": 900},
            "theme": "forest", "physics": {"gravity": 1800}, "objects": objects, "ui": {"score": True}}

starter_objects = [
    obj("ground-1", "platform", 0, 820, 640, 80, "Ground"),
    obj("ground-2", "platform", 760, 820, 840, 80, "Ground"),
    obj("ledge-a", "platform", 300, 720, 200, 24, "Ledge A"),
    obj("ledge-b", "platform", 560, 620, 180, 24, "Ledge B"),
    obj("ledge-c", "platform", 840, 540, 200, 24, "Ledge C"),
    obj("coin-1", "coin", 380, 660, 24, 24, collectible={"points": 10}),
    obj("coin-2", "coin", 900, 480, 24, 24, collectible={"points": 10}),
    obj("enemy-1", "enemy", 1000, 784, 40, 36, patrol={"from": 900, "to": 1300, "speed": 90}),
    obj("finish", "finish", 1480, 700, 60, 120),
    player(),
]
starter = scene("Forest platformer", starter_objects)

def variant(name, edit):
    objects = copy.deepcopy(starter_objects)
    edit(objects)
    return scene(name, objects)

def without(id):
    return lambda objects: objects.remove(next(o for o in objects if o["id"] == id))

def move(id, **props):
    def edit(objects):
        o = next(o for o in objects if o["id"] == id)
        o.update(props)
    return edit

def add(*extra):
    return lambda objects: objects.extend(extra)

def both(*edits):
    def edit(objects):
        for e in edits: e(objects)
    return edit

cases = [
    {"name": "the starter forest is playable", "scene": starter, "expect": {"errors": [], "warnings": [], "finishReachable": True},
     "notes": "H = 113.8; ground-1 to ground-2 is a 120 gap at reach(0) = 166.4; ground-1 to A rises 100 with no gap; A to B rises 100, gap 60, reach 112.2; B to C rises 80, gap 100, reach 128.5."},
    {"name": "a finish on a ledge nobody can reach", "scene": variant("High ledge", both(add(obj("ledge-d", "platform", 1300, 600, 160, 24, "Ledge D")), move("finish", x=1360, y=480))),
     "expect": {"errors": ["finish_unreachable"], "warnings": [], "finishReachable": False},
     "notes": "Ledge D rises 220 from the ground (more than H); from C it is 60 lower but 260 away, reach(-60) = 186.0."},
    {"name": "a gap too wide to jump", "scene": scene("Wide gap", [obj("ground-1", "platform", 0, 820, 600, 80, "Ground"), obj("ground-2", "platform", 800, 820, 800, 80, "Ground"), obj("finish", "finish", 1480, 700, 60, 120), player()]),
     "expect": {"errors": ["finish_unreachable"], "warnings": [], "finishReachable": False}, "notes": "Gap 200 at reach(0) = 166.4."},
    {"name": "dropping to a lower ledge reaches farther than a flat jump", "scene": scene("Drop", [obj("high", "platform", 0, 700, 400, 200, "High ground"), obj("low", "platform", 590, 820, 1010, 80, "Low ground"), obj("finish", "finish", 1480, 700, 60, 120), player(80, 652)]),
     "expect": {"errors": [], "warnings": [], "finishReachable": True}, "notes": "Gap 190, the low ground is 120 lower: reach(-120) = 202.4, while reach(0) = 166.4 would not do."},
    {"name": "no player", "scene": variant("No player", without("player")), "expect": {"errors": ["no_player"], "warnings": [], "finishReachable": False}, "notes": "Reachability does not run."},
    {"name": "two players", "scene": variant("Two players", add(player(200, 772, "player-2"))), "expect": {"errors": ["many_players"], "warnings": [], "finishReachable": False}, "notes": "Reachability does not run."},
    {"name": "a player over the gap falls out of the world", "scene": variant("Falling", both(without("ledge-b"), move("player", x=680, y=400))), "expect": {"errors": ["player_falls"], "warnings": [], "finishReachable": False},
     "notes": "Without ledge B (which spans 560..740), x 680..712 lies over the gap between the grounds at 640 and 760; nothing below. The check stops, no finish_unreachable."},
    {"name": "a coin in the sky", "scene": variant("Sky coin", add(obj("coin-3", "coin", 1200, 300, 24, 24, collectible={"points": 10}))), "expect": {"errors": [], "warnings": ["coin_unreachable"], "finishReachable": True},
     "notes": "From the ground the player touches up to y 658.2; ledge C's touch zone ends at x 1123.2."},
    {"name": "a platform off the edge", "scene": variant("Off the edge", add(obj("ledge-e", "platform", 1500, 860, 200, 24, "Ledge E"))), "expect": {"errors": ["out_of_bounds"], "warnings": [], "finishReachable": True}, "notes": "1500 + 200 > 1600. Other errors do not stop reachability."},
    {"name": "an enemy patrolling backwards", "scene": variant("Bad patrol", move("enemy-1", behaviours={"patrol": {"from": 1300, "to": 900, "speed": 90}})), "expect": {"errors": ["bad_patrol"], "warnings": [], "finishReachable": True}, "notes": "from > to."},
    {"name": "an enemy patrolling through the start", "scene": variant("Enemy at start", add(obj("enemy-2", "enemy", 100, 784, 40, 36, patrol={"from": 0, "to": 300, "speed": 90}))), "expect": {"errors": [], "warnings": ["enemy_on_start"], "finishReachable": True},
     "notes": "The patrol covers x 0..340, the player starts at 80..112."},
    {"name": "a player stuck in a ledge", "scene": variant("Stuck", move("player", x=310, y=690)), "expect": {"errors": [], "warnings": ["player_in_platform"], "finishReachable": True},
     "notes": "The player (y 690..738) overlaps ledge A (y 720..744). Its feet are at 738, so it starts on the ground below, at 820."},
]
json.dump({"$comment": "Shared cases for spec/scene.md. Expectations were worked out by hand; see each case's notes.", "cases": cases}, open(sys.argv[1], "w"), indent=2)
print(len(cases), "cases")
