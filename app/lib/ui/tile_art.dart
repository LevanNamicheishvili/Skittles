// Vector art for tiles and items, shared by the level canvas and the tool palette.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/model.dart';
import 'theme.dart';

const _gold = Color(0xFFE3B341);
const _goldDark = Color(0xFFB7791F);
const _chest = Color(0xFF8B5A2B);
const _chestLid = Color(0xFFA86B34);

/// Deterministic pseudo-random value in [0, 1) per cell, so decorations do not flicker.
double cellNoise(int x, int y, int salt) {
  final h = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791);
  return (h & 0xffff) / 0x10000;
}

void paintLava(Canvas canvas, Rect r, Palette p, {int x = 0, int y = 0}) {
  canvas.drawRect(
    r,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.lava, Color.lerp(p.lava, p.lavaGlow, 0.55)!],
      ).createShader(r),
  );
  final glow = Paint()..color = p.lavaGlow.withValues(alpha: 0.55);
  for (var i = 0; i < 2; i++) {
    final cx = r.left + r.width * (0.2 + 0.6 * cellNoise(x, y, i));
    final cy = r.top + r.height * (0.2 + 0.6 * cellNoise(x, y, i + 7));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: r.width * 0.32, height: r.height * 0.18), glow);
  }
}

void paintWall(Canvas canvas, Rect r, Palette p, {int y = 0}) {
  canvas.drawRect(r, Paint()..color = p.wall);
  final mortar = Paint()
    ..color = p.wallMortar
    ..strokeWidth = math.max(1, r.width * 0.04);
  final mid = r.top + r.height / 2;
  canvas.drawLine(Offset(r.left, mid), Offset(r.right, mid), mortar);
  // Brick joints alternate per row so the courses look staggered.
  final upper = y.isEven ? 0.5 : 0.25;
  final lower = (upper + 0.5) % 1.0;
  canvas.drawLine(Offset(r.left + r.width * upper, r.top), Offset(r.left + r.width * upper, mid), mortar);
  canvas.drawLine(Offset(r.left + r.width * lower, mid), Offset(r.left + r.width * lower, r.bottom), mortar);
  canvas.drawLine(Offset(r.left, r.top), Offset(r.right, r.top), Paint()..color = Colors.white.withValues(alpha: 0.12));
}

void paintBridge(Canvas canvas, Rect r, Palette p) {
  final deck = Rect.fromLTRB(r.left, r.top + r.height * 0.1, r.right, r.bottom - r.height * 0.1);
  canvas.drawRect(deck, Paint()..color = p.bridge);
  final seam = Paint()
    ..color = p.bridgeShade
    ..strokeWidth = math.max(1, r.width * 0.04);
  for (final f in [1 / 3, 2 / 3]) {
    canvas.drawLine(Offset(r.left + r.width * f, deck.top), Offset(r.left + r.width * f, deck.bottom), seam);
  }
  final rail = Paint()..color = p.bridgeShade;
  canvas.drawRect(Rect.fromLTWH(r.left, deck.top, r.width, r.height * 0.08), rail);
  canvas.drawRect(Rect.fromLTWH(r.left, deck.bottom - r.height * 0.08, r.width, r.height * 0.08), rail);
}

void paintDoor(Canvas canvas, Rect r, Palette p, GameColor color) {
  canvas.drawRect(r, Paint()..color = p.wall);
  final panel = RRect.fromRectAndCorners(
    r.deflate(r.width * 0.16),
    topLeft: Radius.circular(r.width * 0.3),
    topRight: Radius.circular(r.width * 0.3),
  );
  canvas.drawRRect(panel, Paint()..color = p.doorColors[color]!);
  final hole = Paint()..color = Colors.black.withValues(alpha: 0.55);
  canvas.drawCircle(Offset(r.center.dx, r.top + r.height * 0.52), r.width * 0.07, hole);
  canvas.drawRect(
    Rect.fromCenter(center: Offset(r.center.dx, r.top + r.height * 0.62), width: r.width * 0.06, height: r.height * 0.14),
    hole,
  );
}

void paintKey(Canvas canvas, Rect r, Palette p, GameColor color) {
  final c = p.doorColors[color]!;
  final s = r.width;
  final stroke = Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.09
    ..strokeCap = StrokeCap.round;
  final bow = Offset(r.left + s * 0.32, r.center.dy);
  canvas.drawCircle(bow, s * 0.14, stroke);
  canvas.drawLine(Offset(bow.dx + s * 0.14, bow.dy), Offset(r.left + s * 0.84, bow.dy), stroke);
  canvas.drawLine(Offset(r.left + s * 0.72, bow.dy), Offset(r.left + s * 0.72, bow.dy + s * 0.14), stroke);
  canvas.drawLine(Offset(r.left + s * 0.82, bow.dy), Offset(r.left + s * 0.82, bow.dy + s * 0.1), stroke);
}

void paintTreasure(Canvas canvas, Rect r) {
  final s = r.width;
  final body = Rect.fromLTRB(r.left + s * 0.16, r.top + s * 0.44, r.right - s * 0.16, r.bottom - s * 0.18);
  final lid = RRect.fromRectAndCorners(
    Rect.fromLTRB(body.left, r.top + s * 0.24, body.right, body.top),
    topLeft: Radius.circular(s * 0.14),
    topRight: Radius.circular(s * 0.14),
  );
  canvas.drawRect(body, Paint()..color = _chest);
  canvas.drawRRect(lid, Paint()..color = _chestLid);
  canvas.drawRect(Rect.fromLTWH(r.center.dx - s * 0.05, lid.top, s * 0.1, body.bottom - lid.top), Paint()..color = _gold);
  canvas.drawRect(Rect.fromCenter(center: Offset(r.center.dx, body.top), width: s * 0.16, height: s * 0.12), Paint()..color = _goldDark);
}

void paintCoin(Canvas canvas, Rect r) {
  final s = r.width;
  canvas.drawCircle(r.center, s * 0.24, Paint()..color = _gold);
  canvas.drawCircle(
    r.center,
    s * 0.16,
    Paint()
      ..color = _goldDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05,
  );
  canvas.drawCircle(r.center.translate(-s * 0.08, -s * 0.08), s * 0.04, Paint()..color = Colors.white.withValues(alpha: 0.7));
}

void paintFlag(Canvas canvas, Rect r, Palette p) {
  final s = r.width;
  final pole = Paint()
    ..color = p.ink
    ..strokeWidth = s * 0.07
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(r.left + s * 0.32, r.top + s * 0.16), Offset(r.left + s * 0.32, r.bottom - s * 0.14), pole);
  final cloth = Path()
    ..moveTo(r.left + s * 0.35, r.top + s * 0.18)
    ..lineTo(r.left + s * 0.82, r.top + s * 0.32)
    ..lineTo(r.left + s * 0.35, r.top + s * 0.48)
    ..close();
  canvas.drawPath(cloth, Paint()..color = p.path);
}

/// The player figure: a start pad in the editor, the moving hero in Play mode.
void paintPlayer(Canvas canvas, Rect r, Palette p, {required bool solid}) {
  final s = r.width;
  if (!solid) {
    canvas.drawCircle(r.center, s * 0.42, Paint()..color = p.accent.withValues(alpha: 0.16));
  } else {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(r.center.dx, r.bottom - s * 0.1), width: s * 0.6, height: s * 0.14),
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );
  }
  final body = Paint()..color = p.accent;
  final outline = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.05;
  final head = Offset(r.center.dx, r.top + s * 0.33);
  final torso = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset(r.center.dx, r.top + s * 0.66), width: s * 0.44, height: s * 0.3),
    Radius.circular(s * 0.15),
  );
  if (solid) {
    canvas.drawRRect(torso, outline);
    canvas.drawCircle(head, s * 0.14, outline);
  }
  canvas.drawRRect(torso, body);
  canvas.drawCircle(head, s * 0.14, body);
}

/// A small preview tile, used by the tool palette and the objects list.
class TileIcon extends StatelessWidget {
  const TileIcon(this.type, {super.key, this.color, this.size = 22});

  final EntityType type;
  final GameColor? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
      child: CustomPaint(size: Size.square(size), painter: _TilePainter(type, color, p)),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.type, this.color, this.palette);

  final EntityType type;
  final GameColor? color;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = palette;
    switch (type) {
      case EntityType.lava:
        paintLava(canvas, r, p);
      case EntityType.wall:
        paintWall(canvas, r, p);
      case EntityType.bridge:
        paintLava(canvas, r, p);
        paintBridge(canvas, r, p);
      case EntityType.castle:
        canvas.drawRect(r, Paint()..color = p.ground);
        final ring = Paint()
          ..color = p.wall
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.22;
        canvas.drawRect(r.deflate(size.width * 0.11), ring);
        final merlon = Paint()..color = p.wallMortar;
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(Rect.fromLTWH(size.width * (0.08 + i * 0.33), 0, size.width * 0.18, size.height * 0.14), merlon);
        }
      case EntityType.door:
        paintDoor(canvas, r, p, color ?? GameColor.gold);
      case EntityType.key:
        canvas.drawRect(r, Paint()..color = p.ground);
        paintKey(canvas, r, p, color ?? GameColor.gold);
      case EntityType.treasure:
        canvas.drawRect(r, Paint()..color = p.ground);
        paintTreasure(canvas, r);
      case EntityType.coin:
        canvas.drawRect(r, Paint()..color = p.ground);
        paintCoin(canvas, r);
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.type != type || old.color != color || old.palette != palette;
}
