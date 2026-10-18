// Draws a scene in the studio: the theme's sky and hills, platforms, coins, enemies with their patrol lanes, the
// finish and the player, then the reachability overlay (reachable tops green, the rest dashed red, the player's
// jump arc when selected) and the selection. World coordinates are pixels; the canvas pans and zooms them.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'scene.dart';
import 'validate.dart';

/// A moment of play: where the player and the enemies are, which coins are gone, and whether to draw the player
/// (it blinks while it is safe after a fall).
class PlayFrame {
  const PlayFrame({required this.player, required this.enemies, required this.collected, this.showPlayer = true});

  final Offset player;
  final Map<String, double> enemies;
  final Set<String> collected;
  final bool showPlayer;
}

/// A teammate on the canvas: where they point and what they have selected.
class RemoteMark {
  const RemoteMark({required this.name, required this.color, this.cursor, this.selectedId});

  final String name;
  final Color color;
  final Offset? cursor;
  final String? selectedId;

  @override
  bool operator ==(Object other) => other is RemoteMark && other.name == name && other.color == color && other.cursor == cursor && other.selectedId == selectedId;

  @override
  int get hashCode => Object.hash(name, color, cursor, selectedId);
}

class ScenePainter extends CustomPainter {
  ScenePainter({
    required this.scene,
    required this.report,
    required this.zoom,
    required this.pan,
    required this.backdrop,
    required this.mono,
    this.selectedId,
    this.hoverId,
    this.showGrid = true,
    this.showReach = true,
    this.remote = const [],
    this.play,
  });

  final Scene scene;
  final SceneReport report;
  final double zoom;
  final Offset pan;
  final Color backdrop;
  final String mono;
  final String? selectedId;
  final String? hoverId;
  final bool showGrid;
  final bool showReach;
  final List<RemoteMark> remote;

  /// Set while the scene is being played: draws the game instead of the editor's view.
  final PlayFrame? play;

  static const _skies = {
    'forest': [Color(0xFF8ED0F5), Color(0xFFDDF3FF), Color(0xFF9CCC8B), Color(0xFF79B868)],
    'desert': [Color(0xFFF6C27A), Color(0xFFFDE8C4), Color(0xFFE9B56C), Color(0xFFD99A4E)],
    'night': [Color(0xFF1E2A4A), Color(0xFF3B4A7A), Color(0xFF2C3E63), Color(0xFF22324F)],
  };

  double get px => 1 / zoom; // one screen pixel, in world units

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backdrop);
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);

    final bounds = scene.bounds;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.shift(Offset(0, 10 * px)), Radius.circular(10 * px)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * px),
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bounds, Radius.circular(8 * px)));
    _sky(canvas, bounds);
    final play = this.play;
    if (showGrid && play == null) _grid(canvas, bounds);

    for (final o in scene.objects) {
      switch (o.type) {
        case SceneObjectType.platform:
          _platform(canvas, o);
        case SceneObjectType.coin:
          if (play == null || !play.collected.contains(o.id)) _coin(canvas, o);
        case SceneObjectType.enemy:
          play == null ? _enemy(canvas, o) : _enemy(canvas, o.copyWith(x: play.enemies[o.id] ?? o.x), lane: false);
        case SceneObjectType.finish:
          _finish(canvas, o);
        case SceneObjectType.player:
          if (play == null) {
            _player(canvas, o);
          } else if (play.showPlayer) {
            _player(canvas, o.copyWith(x: play.player.dx, y: play.player.dy));
          }
      }
    }
    if (showReach && play == null) _reach(canvas);
    canvas.restore();
    if (play != null) {
      canvas.restore();
      return;
    }

    for (final o in scene.objects) {
      if (o.id == hoverId && o.id != selectedId) {
        canvas.drawRect(
          o.rect.inflate(2 * px),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * px
            ..color = const Color(0xCCFFFFFF),
        );
      }
    }
    // What teammates have selected, in their colours.
    for (final r in remote) {
      final o = scene.byId(r.selectedId);
      if (o == null || o.id == selectedId) continue;
      canvas.drawRect(
        o.rect.inflate(3 * px),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = r.color,
      );
    }
    final selected = scene.byId(selectedId);
    if (selected != null) {
      canvas.drawRect(
        selected.rect.inflate(2 * px),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = SkTokens.brand,
      );
      final handle = Rect.fromCenter(center: selected.rect.bottomRight + Offset(2 * px, 2 * px), width: 9 * px, height: 9 * px);
      canvas.drawRect(handle, Paint()..color = Colors.white);
      canvas.drawRect(
        handle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * px
          ..color = SkTokens.brand,
      );
    }
    canvas.restore();

    // The selection's size, in screen space so it stays readable at any zoom.
    if (selected != null) {
      final r = Rect.fromLTWH(selected.x * zoom + pan.dx, selected.y * zoom + pan.dy, selected.w * zoom, selected.h * zoom);
      final text = TextPainter(
        text: TextSpan(
          text: '${selected.w.round()} × ${selected.h.round()}  ·  ${selected.x.round()}, ${selected.y.round()}',
          style: TextStyle(fontFamily: mono, fontFamilyFallback: SkTokens.fontMono, fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromLTWH(r.left - 2, r.top - text.height - 12, text.width + 12, text.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = SkTokens.brand);
      text.paint(canvas, box.topLeft + const Offset(6, 3));
      text.dispose();
    }
    for (final r in remote) {
      if (r.cursor != null) _cursor(canvas, r);
    }
  }

  // A teammate's pointer: an arrow and their name, in screen space.
  void _cursor(Canvas canvas, RemoteMark r) {
    final at = r.cursor! * zoom + pan;
    final arrow = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(at.dx, at.dy + 16)
      ..lineTo(at.dx + 4.5, at.dy + 12)
      ..lineTo(at.dx + 11, at.dy + 12)
      ..close();
    canvas.drawPath(arrow, Paint()..color = r.color);
    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white,
    );
    final text = TextPainter(
      text: TextSpan(text: r.name, style: TextStyle(fontFamily: mono, fontFamilyFallback: SkTokens.fontMono, fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromLTWH(at.dx + 10, at.dy + 16, text.width + 12, text.height + 6);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(4)), Paint()..color = r.color);
    text.paint(canvas, box.topLeft + const Offset(6, 3));
    text.dispose();
  }

  void _sky(Canvas canvas, Rect b) {
    final colours = _skies[scene.theme] ?? _skies['forest']!;
    canvas.drawRect(b, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [colours[0], colours[1]]).createShader(b));
    if (scene.theme == 'night') {
      final rand = math.Random(3);
      final star = Paint()..color = const Color(0xCCFFFFFF);
      for (var i = 0; i < 90; i++) {
        canvas.drawCircle(Offset(rand.nextDouble() * b.width, rand.nextDouble() * b.height * 0.6), rand.nextDouble() * 1.6 + 0.4, star);
      }
    }
    // Two rows of hills along the bottom.
    for (final (i, colour) in [(0, colours[2]), (1, colours[3])]) {
      final base = b.height * (0.62 + i * 0.1);
      final path = Path()..moveTo(0, b.height);
      for (var x = 0.0; x <= b.width; x += 20) {
        path.lineTo(x, base - math.sin(x / (230 - i * 60) + i * 2) * 38 - math.sin(x / 90 + i) * 10);
      }
      path
        ..lineTo(b.width, b.height)
        ..close();
      canvas.drawPath(path, Paint()..color = colour.withValues(alpha: 0.55 + i * 0.2));
    }
  }

  void _grid(Canvas canvas, Rect b) {
    final line = Paint()
      ..color = const Color(0x24FFFFFF)
      ..strokeWidth = px;
    for (var x = 32.0; x < b.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, b.height), line);
    }
    for (var y = 32.0; y < b.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(b.width, y), line);
    }
  }

  void _platform(Canvas canvas, SceneObject o) {
    final r = o.rect;
    final grass = math.min(8.0, o.h * 0.4);
    final body = RRect.fromRectAndRadius(r, Radius.circular(math.min(5.0, o.h / 3)));
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(
      r,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9A6A3C), Color(0xFF6E4524)]).createShader(r),
    );
    // Pebbles in the dirt.
    final rand = math.Random(o.id.hashCode);
    final pebble = Paint()..color = const Color(0x33000000);
    for (var i = 0; i < (o.w * o.h / 900).clamp(0, 60); i++) {
      canvas.drawCircle(Offset(r.left + rand.nextDouble() * o.w, r.top + grass + rand.nextDouble() * math.max(1, o.h - grass)), 1.2 + rand.nextDouble() * 1.8, pebble);
    }
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, o.w, grass), Paint()..color = const Color(0xFF5CB85C));
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, o.w, math.max(1.5, grass * 0.3)), Paint()..color = const Color(0xFF86D586));
    canvas.restore();
  }

  void _coin(Canvas canvas, SceneObject o) {
    final c = o.rect.center;
    final radius = math.min(o.w, o.h) / 2;
    canvas.drawCircle(c, radius, Paint()..color = const Color(0xFFFACC15));
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..color = const Color(0xFFA16207),
    );
    canvas.drawCircle(
      c,
      radius * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.12
        ..color = const Color(0xFFFDE68A),
    );
    canvas.drawCircle(c + Offset(-radius * 0.35, -radius * 0.35), radius * 0.16, Paint()..color = const Color(0xCCFFFFFF));
  }

  void _enemy(Canvas canvas, SceneObject o, {bool lane = true}) {
    if (lane) {
      final from = (o.param('patrol', 'from') ?? o.x).toDouble();
      final to = (o.param('patrol', 'to') ?? o.x).toDouble();
      // The patrol lane along its feet, dashed, with end ticks.
      final paint = Paint()
        ..color = const Color(0x99E11D48)
        ..strokeWidth = 2 * px;
      final y = o.y + o.h + 4;
      for (var x = from; x < to + o.w; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 6, to + o.w), y), paint);
      }
      canvas.drawLine(Offset(from, y - 5), Offset(from, y + 5), paint);
      canvas.drawLine(Offset(to + o.w, y - 5), Offset(to + o.w, y + 5), paint);
    }

    final r = o.rect;
    final body = RRect.fromRectAndCorners(r, topLeft: Radius.circular(o.w * 0.45), topRight: Radius.circular(o.w * 0.45), bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4));
    canvas.drawRRect(body, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF43F5E), Color(0xFF9F1239)]).createShader(r));
    for (final ex in [0.32, 0.68]) {
      final eye = Offset(r.left + o.w * ex, r.top + o.h * 0.4);
      canvas.drawCircle(eye, o.w * 0.12, Paint()..color = Colors.white);
      canvas.drawCircle(eye + Offset(o.w * 0.03, o.h * 0.02), o.w * 0.055, Paint()..color = const Color(0xFF111827));
    }
    // Angry brows.
    final brow = Paint()
      ..color = const Color(0xFF4C0519)
      ..strokeWidth = o.w * 0.06
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(r.left + o.w * 0.2, r.top + o.h * 0.2), Offset(r.left + o.w * 0.42, r.top + o.h * 0.28), brow);
    canvas.drawLine(Offset(r.left + o.w * 0.8, r.top + o.h * 0.2), Offset(r.left + o.w * 0.58, r.top + o.h * 0.28), brow);
  }

  void _finish(Canvas canvas, SceneObject o) {
    final r = o.rect;
    canvas.drawRect(r, Paint()..color = const Color(0x2E22C55E));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * px
      ..color = const Color(0xFF16A34A);
    for (final metric in (Path()..addRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), edge);
      }
    }
    final poleX = r.left + o.w * 0.25;
    canvas.drawRect(Rect.fromLTWH(poleX, r.top + 4, 4, o.h - 4), Paint()..color = const Color(0xFF374151));
    const cols = 5;
    const rows = 3;
    final fw = o.w * 0.62;
    final fh = math.min(o.h * 0.3, fw * 0.66);
    for (var i = 0; i < cols; i++) {
      for (var j = 0; j < rows; j++) {
        canvas.drawRect(
          Rect.fromLTWH(poleX + 4 + i * fw / cols, r.top + 6 + j * fh / rows, fw / cols + 0.5, fh / rows + 0.5),
          Paint()..color = (i + j).isEven ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
        );
      }
    }
  }

  void _player(Canvas canvas, SceneObject o) {
    final r = o.rect;
    final s = o.w;
    canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx, r.bottom), width: s * 0.9, height: s * 0.22), Paint()..color = const Color(0x40000000));
    final bodyTop = r.top + o.h * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(r.left + s * 0.1, bodyTop, r.right - s * 0.1, r.bottom - o.h * 0.08), Radius.circular(s * 0.22)),
      Paint()..color = const Color(0xFF0F766E),
    );
    // Feet.
    for (final fx in [0.18, 0.56]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left + s * fx, r.bottom - o.h * 0.12, s * 0.26, o.h * 0.12), Radius.circular(s * 0.06)), Paint()..color = const Color(0xFF1F2937));
    }
    final head = Offset(r.center.dx, r.top + o.h * 0.26);
    canvas.drawCircle(head, s * 0.38, Paint()..color = const Color(0xFFF5D0A9));
    canvas.drawArc(Rect.fromCircle(center: head - Offset(0, s * 0.06), radius: s * 0.38), math.pi, math.pi, true, Paint()..color = const Color(0xFF3F2A14));
    for (final ex in [0.08, 0.22]) {
      canvas.drawCircle(head + Offset(s * ex, s * 0.06), s * 0.05, Paint()..color = const Color(0xFF111827));
    }
  }

  void _reach(Canvas canvas) {
    // Where the player can stand: white dots just above each reachable top, like the solver's route on the site.
    // Tops nobody can reach get a dashed red line.
    for (final o in scene.objects.where((o) => o.type == SceneObjectType.platform)) {
      final reachable = report.reachable.contains(o.id);
      if (reachable) {
        final dot = Paint()..color = const Color(0xF2FFFFFF);
        final y = o.y - 6;
        for (var x = o.x + 6; x < o.x + o.w - 4; x += 12) {
          canvas.drawCircle(Offset(x, y), 2.2 * px.clamp(0.6, 2.0), dot);
        }
      } else if (report.reachable.isNotEmpty) {
        final dash = Paint()
          ..strokeWidth = 3 * px
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF87171);
        for (var x = o.x + 2; x < o.x + o.w - 2; x += 12) {
          canvas.drawLine(Offset(x, o.y - 5), Offset(math.min(x + 6, o.x + o.w - 2), o.y - 5), dash);
        }
      }
    }
    // Things the player cannot get to get a red ring.
    final unreachable = {for (final i in report.issues) if (i.code == 'coin_unreachable' || i.code == 'finish_unreachable') i.objectId};
    for (final o in scene.objects.where((o) => unreachable.contains(o.id))) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(o.rect.inflate(6), const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * px
          ..color = const Color(0xFFF87171),
      );
    }
    // The selected player's jump: how high and how far it gets on flat ground.
    final player = scene.byId(selectedId);
    if (player != null && player.type == SceneObjectType.player && report.jumpHeight > 0) {
      final jump = Jump(
        speed: (player.param('controller', 'speed') ?? 260).toDouble(),
        takeoff: (player.param('controller', 'jump') ?? 640).toDouble(),
        gravity: scene.gravity,
      );
      final feet = Offset(player.rect.center.dx, player.rect.bottom);
      final reach = jump.reach(0) / 0.9; // the arc itself, without the safety margin
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px
        ..color = const Color(0xE6FFFFFF);
      for (final side in [-1, 1]) {
        final path = Path()..moveTo(feet.dx, feet.dy);
        for (var k = 1; k <= 24; k++) {
          final f = k / 24;
          path.lineTo(feet.dx + side * reach * f, feet.dy - 4 * jump.height * f * (1 - f));
        }
        for (final metric in path.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 9) {
            canvas.drawPath(metric.extractPath(d, d + 5), arc);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(ScenePainter old) =>
      old.scene != scene ||
      old.report != report ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.selectedId != selectedId ||
      old.hoverId != hoverId ||
      old.showGrid != showGrid ||
      old.showReach != showReach ||
      old.backdrop != backdrop ||
      old.play != play ||
      !listEquals(old.remote, remote);
}
