# Writes spec/fixtures/actions.json: action batches on the starter scene and what they must do. The expectations come
# from spec/scene.md section 3a and were checked by hand. Run: python3 spec/fixtures/make_actions.py spec/fixtures/actions.json
import json, sys

starter = json.load(open("spec/fixtures/scenes.json"))["cases"][0]["scene"]

def case(name, actions, expect, notes):
    return {"name": name, "actions": actions, "expect": expect, "notes": notes}

cases = [
    case("a new platform is named, numbered and kept inside",
         [{"type": "CREATE_OBJECT", "objectType": "platform", "x": 1500, "y": 500, "w": 300},
          {"type": "CREATE_OBJECT", "objectType": "coin", "x": 600, "y": 560, "points": 25}],
         {"count": 12, "created": ["platform-1", "coin-3"], "objects": [
             {"id": "platform-1", "name": "Platform 6", "x": 1300, "y": 500, "w": 300, "h": 24},
             {"id": "coin-3", "name": "Coin 3", "x": 600, "y": 560, "w": 24, "h": 24, "behaviours": {"collectible": {"points": 25}}}],
          "notes": ["+ Platform 6 at (1300, 500)", "+ Coin 3 at (600, 560)"]},
         "The starter has five platforms (ids ground-* and ledge-*) and the coins coin-1 and coin-2, so the new ids are platform-1 and coin-3. 1500 + 300 > 1600, so x becomes 1300."),
    case("creating a player moves the one there is",
         [{"type": "CREATE_OBJECT", "objectType": "player", "x": 400, "y": 672, "jump": 700}],
         {"count": 10, "created": [], "objects": [{"id": "player", "name": "Player", "x": 400, "y": 672, "w": 32, "h": 48, "behaviours": {"controller": {"speed": 260, "jump": 700}}}],
          "notes": ["~ Moved Player to (400, 672)"]},
         "One player per scene."),
    case("moving an enemy moves its patrol; a missing id is skipped",
         [{"type": "UPDATE_OBJECT", "id": "enemy-1", "x": 1100}, {"type": "UPDATE_OBJECT", "id": "nope", "x": 1}],
         {"count": 10, "created": [], "objects": [{"id": "enemy-1", "name": "Enemy", "x": 1100, "y": 784, "w": 40, "h": 36, "behaviours": {"patrol": {"from": 1000, "to": 1400, "speed": 90}}}],
          "notes": ["~ Changed Enemy", "· Skipped: there is no nope"]},
         "The enemy moves 100 to the right; its patrol 900..1300 becomes 1000..1400."),
    case("delete, a behaviour, the scene and the score",
         [{"type": "DELETE_OBJECT", "id": "coin-2"}, {"type": "ADD_COMPONENT", "id": "enemy-1", "component": "patrol", "speed": 150},
          {"type": "UPDATE_SCENE", "theme": "night", "sceneName": "Night run"}, {"type": "UPDATE_UI", "score": False}],
         {"count": 9, "created": [], "objects": [{"id": "enemy-1", "name": "Enemy", "x": 1000, "y": 784, "w": 40, "h": 36, "behaviours": {"patrol": {"from": 900, "to": 1300, "speed": 150}}}],
          "missing": ["coin-2"], "theme": "night", "name": "Night run", "score": False,
          "notes": ["− Removed Coin", "~ Set Enemy's patrol", "~ Scene renamed to Night run · night theme", "~ Score hidden"]},
         "Four kinds of action in one batch."),
    case("a given id is kept when it is free",
         [{"type": "CREATE_OBJECT", "objectType": "coin", "x": 100, "y": 100, "id": "sky-coin"},
          {"type": "CREATE_OBJECT", "objectType": "coin", "x": 140, "y": 100, "id": "coin-1"}],
         {"count": 12, "created": ["sky-coin", "coin-3"], "objects": [
             {"id": "sky-coin", "name": "Coin 3", "x": 100, "y": 100},
             {"id": "coin-3", "name": "Coin 4", "x": 140, "y": 100}],
          "notes": ["+ Coin 3 at (100, 100)", "+ Coin 4 at (140, 100)"]},
         "coin-1 is taken, so the second coin gets the lowest free coin-n. Names count the coins there are."),
    case("a name already in use gets a number",
         [{"type": "CREATE_OBJECT", "objectType": "coin", "x": 600, "y": 570, "name": "Coin"},
          {"type": "CREATE_OBJECT", "objectType": "coin", "x": 670, "y": 570, "name": "Coin"},
          {"type": "CREATE_OBJECT", "objectType": "platform", "x": 100, "y": 400, "name": "Ledge A"},
          {"type": "CREATE_OBJECT", "objectType": "platform", "x": 400, "y": 400, "name": "Sky ledge"}],
         {"count": 14, "created": ["coin-3", "coin-4", "platform-1", "platform-2"], "objects": [
             {"id": "coin-3", "name": "Coin 2"}, {"id": "coin-4", "name": "Coin 3"},
             {"id": "platform-1", "name": "Ledge A 2"}, {"id": "platform-2", "name": "Sky ledge"}],
          "notes": ["+ Coin 2 at (600, 570)", "+ Coin 3 at (670, 570)", "+ Ledge A 2 at (100, 400)", "+ Sky ledge at (400, 400)"]},
         "The starter's two coins are both named Coin, so Coin 2 is the lowest free number; then Coin 3. A new name stays as it is."),
    case("an unknown action changes nothing",
         [{"type": "CREATE_SCRIPT", "code": "while (true) {}"}],
         {"count": 10, "created": [], "objects": [], "notes": []},
         "Scripts are not part of the studio: behaviours are data."),
]
json.dump({"$comment": "Shared cases for spec/scene.md section 3a: action batches applied to the starter scene (scenes.json, first case).", "scene": starter, "cases": cases},
          open(sys.argv[1], "w"), indent=2, ensure_ascii=False)
print(len(cases), "cases")
