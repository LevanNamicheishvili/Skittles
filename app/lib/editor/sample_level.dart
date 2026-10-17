import '../game/model.dart';

/// The demo story from the concept: Nino adds a lava river, Gio a locked castle with treasure,
/// and the mediator a bridge and a key so the level stays winnable.
World sampleLevel() {
  const nino = Owner(OwnerKind.player, 'A');
  const gio = Owner(OwnerKind.player, 'B');
  const mediator = Owner(OwnerKind.mediator);
  return const World(
    width: 24,
    height: 14,
    start: (x: 1, y: 7),
    flag: (x: 22, y: 12),
    entities: [
      Entity(id: 'A:1', type: EntityType.lava, owner: nino, label: 'Lava river', x: 10, y: 0, w: 2, h: 14),
      Entity(id: 'A:2', type: EntityType.wall, owner: nino, label: 'Rocks', x: 4, y: 10, w: 4, h: 1),
      Entity(
        id: 'B:1',
        type: EntityType.castle,
        owner: gio,
        label: 'Castle',
        x: 15,
        y: 2,
        w: 7,
        h: 8,
        door: CastleDoor(side: DoorSide.left, offset: 3, color: GameColor.gold),
      ),
      Entity(id: 'B:2', type: EntityType.treasure, owner: gio, label: 'Treasure', x: 19, y: 6),
      Entity(id: 'B:3', type: EntityType.coin, owner: gio, x: 7, y: 5),
      Entity(id: 'B:4', type: EntityType.coin, owner: gio, x: 13, y: 3),
      Entity(id: 'B:5', type: EntityType.coin, owner: gio, x: 20, y: 12),
      Entity(id: 'M:1', type: EntityType.bridge, owner: mediator, label: 'Bridge', x: 10, y: 10, w: 2, h: 1),
      Entity(id: 'M:2', type: EntityType.key, owner: mediator, label: 'Castle key', x: 4, y: 2, color: GameColor.gold),
    ],
    objectives: [CollectObjective('B:2'), CollectCountObjective(2)],
  );
}

World emptyLevel() => const World(
      width: 24,
      height: 14,
      start: (x: 1, y: 7),
      flag: (x: 22, y: 7),
      entities: [],
      objectives: [],
    );
