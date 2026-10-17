// The level board: draws the world and turns pointer and keyboard input into editor actions.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/model.dart';
import '../game/raster.dart';
import '../ui/theme.dart';
import '../ui/tile_art.dart';
import 'editor_controller.dart';

class LevelCanvas extends StatefulWidget {
  const LevelCanvas({super.key, required this.controller});

  final EditorController controller;

  @override
  State<LevelCanvas> createState() => _LevelCanvasState();
}

class _BoardGeometry {
  _BoardGeometry(Size size, World world) {
    const pad = 28.0;
    cell = math
        .min((size.width - pad * 2) / world.width, (size.height - pad * 2) / world.height)
        .floorToDouble()
        .clamp(10.0, 56.0);
    origin = Offset(
      ((size.width - cell * world.width) / 2).floorToDouble(),
      ((size.height - cell * world.height) / 2).floorToDouble(),
    );
  }

  late final double cell;
  late final Offset origin;

  Cell? cellAt(Offset local, World world) {
    final x = ((local.dx - origin.dx) / cell).floor();
    final y = ((local.dy - origin.dy) / cell).floor();
    return x >= 0 && y >= 0 && x < world.width && y < world.height ? (x: x, y: y) : null;
  }
}

class _LevelCanvasState extends State<LevelCanvas> {
  final _focus = FocusNode(debugLabel: 'level canvas');

  EditorController get c => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  // Letter keys' logical ids are their lowercase code points.
  static final _toolKeys = {
    for (final t in EditorTool.values) LogicalKeyboardKey(t.shortcut.toLowerCase().codeUnitAt(0)): t,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    if (meta) return KeyEventResult.ignored; // Cmd shortcuts are handled by the screen.

    if (c.mode == EditorMode.play) {
      final dir = switch (key) {
        LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => Direction.up,
        LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => Direction.down,
        LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => Direction.left,
        LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD => Direction.right,
        _ => null,
      };
      if (dir != null) {
        c.playMove(dir);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        c.restartPlay();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
        c.stopPlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is KeyRepeatEvent && !_isArrow(key)) return KeyEventResult.ignored;
    switch (key) {
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        c.deleteSelected();
      case LogicalKeyboardKey.escape:
        c.select(null);
      case LogicalKeyboardKey.arrowUp:
        c.nudgeSelected(0, -1);
      case LogicalKeyboardKey.arrowDown:
        c.nudgeSelected(0, 1);
      case LogicalKeyboardKey.arrowLeft:
        c.nudgeSelected(-1, 0);
      case LogicalKeyboardKey.arrowRight:
        c.nudgeSelected(1, 0);
      case LogicalKeyboardKey.keyP:
        c.startPlay();
      default:
        final tool = _toolKeys[key];
        if (tool == null) return KeyEventResult.ignored;
        c.setTool(tool);
    }
    return KeyEventResult.handled;
  }

  static bool _isArrow(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight;

  MouseCursor get _cursor => switch (c.tool) {
        _ when c.mode == EditorMode.play => SystemMouseCursors.basic,
        EditorTool.select => SystemMouseCursors.basic,
        EditorTool.erase => SystemMouseCursors.disappearing,
        _ => SystemMouseCursors.precise,
      };

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
        final geo = _BoardGeometry(constraints.biggest, c.world);
        Cell? cellOf(Offset p) => geo.cellAt(p, c.world);
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _cursor,
            onHover: (e) {
              final cell = cellOf(e.localPosition);
              if (cell != null) c.pointerMove(cell);
            },
            onExit: (_) => c.pointerExit(),
            child: Listener(
              onPointerDown: (e) {
                _focus.requestFocus();
                final cell = cellOf(e.localPosition);
                if (cell != null) c.pointerDown(cell);
              },
              onPointerMove: (e) {
                final cell = cellOf(e.localPosition);
                if (cell != null) c.pointerMove(cell);
              },
              onPointerUp: (_) => c.pointerUp(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _LevelPainter(c, palette, geo)),
                  ),
                  if (c.playState?.won ?? false) Positioned.fill(child: _WinOverlay(controller: c)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _LevelPainter extends CustomPainter {
  _LevelPainter(this.c, this.p, this.geo);

  final EditorController c;
  final Palette p;
  final _BoardGeometry geo;

  Rect cellRect(int x, int y) => Rect.fromLTWH(geo.origin.dx + x * geo.cell, geo.origin.dy + y * geo.cell, geo.cell, geo.cell);

  Rect boundsOf(Entity e) => Rect.fromLTWH(
        geo.origin.dx + e.x * geo.cell,
        geo.origin.dy + e.y * geo.cell,
        e.w * geo.cell,
        e.h * geo.cell,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final world = c.world;
    final grid = c.grid;
    final s = geo.cell;
    final board = Rect.fromLTWH(geo.origin.dx, geo.origin.dy, world.width * s, world.height * s);

    canvas.drawRRect(
      RRect.fromRectAndRadius(board.inflate(6), const Radius.circular(10)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(board, const Radius.circular(6)));
    canvas.drawRect(board, Paint()..color = p.ground);

    // Cells under a bridge still show lava around the planks.
    final lavaCells = <int>{
      for (final e in world.entities)
        if (e.type == EntityType.lava)
          for (var y = e.y; y < e.y + e.h; y++)
            for (var x = e.x; x < e.x + e.w; x++) grid.index(x, y),
    };

    final line = Paint()
      ..color = p.gridLine
      ..strokeWidth = 1;
    for (var y = 0; y < world.height; y++) {
      for (var x = 0; x < world.width; x++) {
        final r = cellRect(x, y);
        switch (grid.terrainAt(x, y)) {
          case Terrain.ground:
            canvas.drawRect(r.deflate(0.5), Paint()..color = p.ground);
            canvas.drawRect(r, line..style = PaintingStyle.stroke);
          case Terrain.lava:
            paintLava(canvas, r, p, x: x, y: y);
          case Terrain.bridge:
            if (lavaCells.contains(grid.index(x, y))) paintLava(canvas, r, p, x: x, y: y);
            paintBridge(canvas, r, p);
          case Terrain.wall:
            paintWall(canvas, r, p, y: y);
          case Terrain.door:
            paintDoor(canvas, r, p, grid.doorColor[grid.index(x, y)]!);
        }
      }
    }

    // Castle battlements along the top edge, so castles read as one building.
    for (final e in world.entities.where((e) => e.type == EntityType.castle)) {
      final b = boundsOf(e);
      canvas.drawRect(b.deflate(0.5), Paint()
        ..color = p.wallMortar
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      final merlon = Paint()..color = p.wallMortar;
      for (var i = 0; i < e.w; i++) {
        final r = cellRect(e.x + i, e.y);
        canvas.drawRect(Rect.fromLTWH(r.left + s * 0.2, r.top, s * 0.3, s * 0.12), merlon);
      }
    }

    final taken = c.playState?.taken ?? const <String>{};
    for (final e in world.entities) {
      if (!e.type.isItem || taken.contains(e.id)) continue;
      final r = cellRect(e.x, e.y);
      switch (e.type) {
        case EntityType.key:
          paintKey(canvas, r, p, e.color!);
        case EntityType.treasure:
          paintTreasure(canvas, r);
        default:
          paintCoin(canvas, r);
      }
    }

    paintFlag(canvas, cellRect(world.flag.x, world.flag.y), p);
    final play = c.playState;
    final startRect = cellRect(world.start.x, world.start.y);
    if (play == null) {
      paintPlayer(canvas, startRect, p, solid: true);
    } else {
      canvas.drawCircle(startRect.center, s * 0.42, Paint()..color = p.accent.withValues(alpha: 0.16));
    }

    if (play == null) {
      _paintSolverOverlay(canvas);
      _paintEditingOverlay(canvas);
    } else {
      paintPlayer(canvas, cellRect(play.x, play.y), p, solid: true);
    }
    canvas.restore();
  }

  void _paintSolverOverlay(Canvas canvas) {
    final result = c.solveResult;
    if (result == null) return;
    final s = geo.cell;
    if (result.path case final path? when c.showPath) {
      var x = c.world.start.x;
      var y = c.world.start.y;
      final dot = Paint()..color = p.path.withValues(alpha: 0.85);
      for (final d in path) {
        final from = cellRect(x, y).center;
        x += d.dx;
        y += d.dy;
        final to = cellRect(x, y).center;
        for (var t = 0.25; t < 1.0; t += 0.25) {
          canvas.drawCircle(Offset.lerp(from, to, t)!, math.max(1.5, s * 0.06), dot);
        }
      }
    }
    // Ring everything the team cannot reach.
    final ring = Paint()
      ..color = p.lava
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, s * 0.08);
    for (final u in result.unreachable) {
      Cell? at;
      if (u == 'flag') at = c.world.flag;
      if (u.startsWith('collect:')) {
        final e = c.world.byId(u.substring(8));
        if (e != null) at = (x: e.x, y: e.y);
      }
      if (at != null) canvas.drawCircle(cellRect(at.x, at.y).center, s * 0.44, ring);
    }
  }

  void _paintEditingOverlay(Canvas canvas) {
    final s = geo.cell;
    final hover = c.hover;
    if (hover != null && c.tool != EditorTool.select) {
      canvas.drawRect(cellRect(hover.x, hover.y), Paint()..color = p.accent.withValues(alpha: 0.14));
    }
    if (c.rectPreview case final r?) {
      final rect = Rect.fromLTWH(geo.origin.dx + r.x * s, geo.origin.dy + r.y * s, r.w * s, r.h * s);
      canvas.drawRect(rect, Paint()..color = p.accent.withValues(alpha: 0.18));
      canvas.drawRect(rect, Paint()
        ..color = p.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }

    final id = c.selectedId;
    if (id == null) return;
    final Rect bounds;
    final String label;
    if (id == startId) {
      bounds = cellRect(c.world.start.x, c.world.start.y);
      label = 'Start';
    } else if (id == flagId) {
      bounds = cellRect(c.world.flag.x, c.world.flag.y);
      label = 'Flag';
    } else {
      final e = c.world.byId(id);
      if (e == null) return;
      bounds = boundsOf(e);
      label = '${e.label ?? typeName(e.type)} · ${ownerName(e.owner)}';
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.inflate(2), const Radius.circular(4)),
      Paint()
        ..color = p.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final tp = TextPainter(
      text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final chip = Rect.fromLTWH(bounds.left - 2, bounds.top - tp.height - 10, tp.width + 12, tp.height + 6);
    final placed = chip.top < geo.origin.dy ? chip.shift(Offset(0, bounds.height + tp.height + 16)) : chip;
    canvas.drawRRect(RRect.fromRectAndRadius(placed, const Radius.circular(4)), Paint()..color = p.accent);
    tp.paint(canvas, placed.topLeft + const Offset(6, 3));
  }

  @override
  bool shouldRepaint(_LevelPainter old) => true;
}

String typeName(EntityType t) => switch (t) {
      EntityType.wall => 'Wall',
      EntityType.lava => 'Lava',
      EntityType.bridge => 'Bridge',
      EntityType.castle => 'Castle',
      EntityType.door => 'Door',
      EntityType.key => 'Key',
      EntityType.treasure => 'Treasure',
      EntityType.coin => 'Coin',
    };

/// Goals, keys and moves while playing; shown in the right panel in place of the inspector.
class PlayHud extends StatelessWidget {
  const PlayHud({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.playState!;
    final engine = controller.playEngine!;
    final p = Palette.of(context);
    final world = controller.world;
    final goals = <(String, bool)>[
      for (final o in world.objectives)
        switch (o) {
          CollectObjective(:final target) => (
              'Collect ${world.byId(target)?.label ?? typeName(world.byId(target)?.type ?? EntityType.treasure)}',
              s.collected.contains(target)
            ),
          CollectCountObjective(:final count) => (
              'Collect $count coins (${world.entities.where((e) => e.type == EntityType.coin && s.collected.contains(e.id)).length}/$count)',
              world.entities.where((e) => e.type == EntityType.coin && s.collected.contains(e.id)).length >= count
            ),
        },
      ('Reach the flag', s.won),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PLAYING',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700, color: p.system),
          ),
          const SizedBox(height: 10),
          for (final (label, done) in goals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? p.path : p.system),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ),
          const Divider(height: 18),
          Row(children: [
            for (final k in s.keys) ...[Icon(Icons.key, size: 16, color: p.doorColors[k]), const SizedBox(width: 4)],
            if (s.keys.isEmpty) Text('No keys', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.system)),
            const Spacer(),
            Text('Moves ${controller.playMoves}', style: Theme.of(context).textTheme.bodySmall),
            if (s.deaths > 0) ...[
              const SizedBox(width: 8),
              Text('Falls ${s.deaths}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.lava)),
            ],
          ]),
          const SizedBox(height: 8),
          Text(
            engine.objectivesDone(s.collected) ? 'All goals done — head to the flag.' : 'Arrows or WASD to move · R restart · Esc edit',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.system),
          ),
        ],
      ),
    );
  }
}

class _WinOverlay extends StatelessWidget {
  const _WinOverlay({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final best = controller.solveResult?.steps;
    final moves = controller.playMoves;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events_rounded, size: 44, color: Palette.of(context).players[1]),
              const SizedBox(height: 8),
              Text('You won!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(best == null ? '$moves moves' : '$moves moves · best possible $best'),
              const SizedBox(height: 16),
              Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(onPressed: controller.restartPlay, child: const Text('Play again')),
                const SizedBox(width: 8),
                FilledButton(onPressed: controller.stopPlay, child: const Text('Back to editor')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
