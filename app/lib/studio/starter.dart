// The forest example: the platformer from spec/fixtures/scenes.json ("the starter forest is playable"). A new
// project starts empty; the empty canvas offers this as a place to start.

import 'scene.dart';

Scene starterScene() => const Scene(
      name: 'Forest platformer',
      width: 1600,
      height: 900,
      objects: [
        SceneObject(id: 'ground-1', name: 'Ground', type: SceneObjectType.platform, x: 0, y: 820, w: 640, h: 80),
        SceneObject(id: 'ground-2', name: 'Ground', type: SceneObjectType.platform, x: 760, y: 820, w: 840, h: 80),
        SceneObject(id: 'ledge-a', name: 'Ledge A', type: SceneObjectType.platform, x: 300, y: 720, w: 200, h: 24),
        SceneObject(id: 'ledge-b', name: 'Ledge B', type: SceneObjectType.platform, x: 560, y: 620, w: 180, h: 24),
        SceneObject(id: 'ledge-c', name: 'Ledge C', type: SceneObjectType.platform, x: 840, y: 540, w: 200, h: 24),
        SceneObject(id: 'coin-1', name: 'Coin', type: SceneObjectType.coin, x: 380, y: 660, w: 24, h: 24, behaviours: {
          'collectible': {'points': 10},
        }),
        SceneObject(id: 'coin-2', name: 'Coin', type: SceneObjectType.coin, x: 900, y: 480, w: 24, h: 24, behaviours: {
          'collectible': {'points': 10},
        }),
        SceneObject(id: 'enemy-1', name: 'Enemy', type: SceneObjectType.enemy, x: 1000, y: 784, w: 40, h: 36, behaviours: {
          'patrol': {'from': 900, 'to': 1300, 'speed': 90},
        }),
        SceneObject(id: 'finish', name: 'Finish', type: SceneObjectType.finish, x: 1480, y: 700, w: 60, h: 120),
        SceneObject(id: 'player', name: 'Player', type: SceneObjectType.player, x: 80, y: 772, w: 32, h: 48, behaviours: {
          'controller': {'speed': 260, 'jump': 640},
        }),
      ],
    );
