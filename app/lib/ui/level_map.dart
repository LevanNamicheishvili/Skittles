// A level drawn flat from the shared Dart rules: terrain, who made what, holograms of held changes, highlights,
// the solver's route, start, flag and the playtester. Used by the room screen and the welcome previews until
// phase C ports the 2.5D board.

import 'package:flutter/material.dart';

import '../game/model.dart';
import '../game/raster.dart';
import 'tokens.dart';

/// The demo's prepared level (server/src/levels/demo.ts): a cliff border, two boulders, start on the left and
/// the flag on the right.
World demoWorld([List<Entity> extra = const []]) => World(
      width: 24,
      height: 14,
      start: (x: 1, y: 7),
      flag: (x: 22, y: 7),
      entities: [
        const Entity(id: 'S1', type: EntityType.wall, owner: Owner.system(), x: 0, y: 0, w: 24, label: 'North cliffs'),
        const Entity(id: 'S2', type: EntityType.wall, owner: Owner.system(), x: 0, y: 13, w: 24, label: 'South cliffs'),
        const Entity(id: 'S3', type: EntityType.wall, owner: Owner.system(), x: 5, y: 3, w: 2, h: 2, label: 'Boulders'),
        const Entity(id: 'S4', type: EntityType.wall, owner: Owner.system(), x: 16, y: 9, w: 3, h: 2, label: 'Boulders'),
        ...extra,
      ],
      objectives: const [],
    );

class LevelMapPainter extends CustomPainter {
  const LevelMapPainter({
    required this.world,
    this.route,
    this.routeColor = const Color(0xD9FFFFFF),
    this.player,
    this.ownerColor,
    this.highlight = const {},
    this.ghosts = const [],
    this.ghostColor = const Color(0xFFF97316),
  });

  final World world;
  final List<Direction>? route;
  final Color routeColor;
  final Cell? player;

  /// The author colour for an object, or null for the level's own objects.
  final Color? Function(Entity entity)? ownerColor;

  /// Objects that just changed, washed in a colour.
  final Map<String, Color> highlight;

  /// A held change, drawn as a hologram.
  final List<Entity> ghosts;
  final Color ghostColor;

  static const _terrain = {
    Terrain.ground: Color(0xFF7DB85A),
    Terrain.wall: Color(0xFF5E6878),
    Terrain.lava: Color(0xFFF2602B),
    Terrain.bridge: Color(0xFF9A6B3F),
  };
  static const _doors = {GameColor.red: Color(0xFFDC2626), GameColor.blue: Color(0xFF2563EB), GameColor.gold: Color(0xFFEAB308)};

  @override
  void paint(Canvas canvas, Size size) {
    final grid = rasterize(world);
    final cell = size.width / world.width;
    Rect rect(Entity e) => Rect.fromLTWH(e.x * cell, e.y * cell, e.w * cell, e.h * cell);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.35)));

    final paint = Paint();
    for (var y = 0; y < world.height; y++) {
      for (var x = 0; x < world.width; x++) {
        final t = grid.terrainAt(x, y);
        paint.color = t == Terrain.door ? (_doors[grid.doorColor[grid.index(x, y)]] ?? _terrain[Terrain.wall]!) : _terrain[t]!;
        if (t == Terrain.ground && (x + y).isOdd) paint.color = Color.lerp(paint.color, Colors.black, 0.05)!;
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
    for (final e in world.entities) {
      if (e.type == EntityType.coin || e.type == EntityType.treasure || e.type == EntityType.key) {
        final colour = e.type == EntityType.key ? (_doors[e.color] ?? const Color(0xFFEAB308)) : const Color(0xFFF5C542);
        canvas.drawCircle(rect(e).center, cell * 0.22, Paint()..color = colour);
      }
    }

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final e in world.entities) {
      final colour = e.owner.kind == OwnerKind.mediator ? const Color(0xFFA78BFA) : ownerColor?.call(e);
      if (colour == null) continue;
      outline.color = colour;
      canvas.drawRect(rect(e).deflate(1), outline);
    }
    // A fresh object glows in its author's colour: a light tint, a bright edge and a soft halo, so the colour
    // reads on any terrain (a full wash over orange lava turns muddy).
    for (final MapEntry(key: id, value: colour) in highlight.entries) {
      for (final e in world.entities.where((e) => e.id == id)) {
        final r = rect(e);
        canvas.drawRect(r, Paint()..color = colour.withValues(alpha: 0.12));
        canvas.drawRect(
          r.inflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = colour.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawRect(
          r.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = colour,
        );
      }
    }
    for (final g in ghosts) {
      final r = rect(g);
      canvas.drawRect(r, Paint()..color = ghostColor.withValues(alpha: 0.35));
      final dashed = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ghostColor;
      for (final metric in (Path()..addRect(r.deflate(1))).computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 6) {
          canvas.drawPath(metric.extractPath(d, d + 3), dashed);
        }
      }
    }

    final path = route;
    if (path != null) {
      final dot = Paint()..color = routeColor;
      var (x, y) = (world.start.x, world.start.y);
      for (final d in path) {
        x += d.dx;
        y += d.dy;
        canvas.drawCircle(Offset((x + 0.5) * cell, (y + 0.5) * cell), cell * 0.08, dot);
      }
    }

    canvas.drawCircle(Offset((world.start.x + 0.5) * cell, (world.start.y + 0.5) * cell), cell * 0.28, Paint()..color = SkTokens.cream);
    final flag = Offset(world.flag.x * cell, world.flag.y * cell);
    canvas.drawRect(Rect.fromLTWH(flag.dx + cell * 0.3, flag.dy + cell * 0.15, cell * 0.08, cell * 0.7), Paint()..color = const Color(0xFF1F2328));
    canvas.drawPath(
      Path()
        ..moveTo(flag.dx + cell * 0.38, flag.dy + cell * 0.15)
        ..lineTo(flag.dx + cell * 0.8, flag.dy + cell * 0.3)
        ..lineTo(flag.dx + cell * 0.38, flag.dy + cell * 0.45)
        ..close(),
      Paint()..color = Colors.white,
    );
    final p = player;
    if (p != null) {
      canvas.drawCircle(
        Offset((p.x + 0.5) * cell, (p.y + 0.5) * cell),
        cell * 0.32,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = SkTokens.brand,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LevelMapPainter old) =>
      old.world != world || old.route != route || old.routeColor != routeColor || old.player != player || old.highlight != highlight || old.ghosts != ghosts;
}
