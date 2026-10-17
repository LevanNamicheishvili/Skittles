// Editor state: the level document, tools, selection, undo history and Play mode.
// Single-player for now; phase 3 routes committed changes through the room server.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../game/model.dart';
import '../game/play.dart';
import '../game/raster.dart';
import '../game/solver.dart';
import '../game/validate.dart';
import 'sample_level.dart';

enum EditorTool {
  select('Select', 'V'),
  wall('Wall', 'W'),
  lava('Lava', 'L'),
  bridge('Bridge', 'B'),
  castle('Castle', 'C'),
  door('Door', 'D'),
  key('Key', 'K'),
  treasure('Treasure', 'T'),
  coin('Coin', 'O'),
  start('Start', 'S'),
  flag('Flag', 'F'),
  erase('Erase', 'E');

  const EditorTool(this.label, this.shortcut);
  final String label;
  final String shortcut;

  EntityType? get entityType => switch (this) {
        wall => EntityType.wall,
        lava => EntityType.lava,
        bridge => EntityType.bridge,
        castle => EntityType.castle,
        door => EntityType.door,
        key => EntityType.key,
        treasure => EntityType.treasure,
        coin => EntityType.coin,
        _ => null,
      };

  bool get drawsRect => entityType?.isRect ?? false;
  bool get usesColor => this == door || this == key || this == castle;
}

enum EditorMode { edit, play }

/// Pseudo ids so start and flag can be selected and dragged like objects.
const startId = '__start';
const flagId = '__flag';

const _localOwner = Owner(OwnerKind.player, 'me');
const _maxHistory = 200;

class EditorController extends ChangeNotifier {
  EditorController({World? world, this.levelName = 'Castle Story'}) : _world = world ?? sampleLevel() {
    _resolve();
  }

  String levelName;
  World _world;
  World get world => _world;

  final List<World> _undo = [];
  final List<World> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  late Grid _grid;
  late ValidationResult _validation;
  SolveResult? _solve;
  Grid get grid => _grid;
  ValidationResult get validation => _validation;

  /// Null while a drag is in progress or the level has errors.
  SolveResult? get solveResult => _solve;

  EditorTool tool = EditorTool.select;
  GameColor toolColor = GameColor.gold;
  String? selectedId;
  Cell? hover;
  bool showPath = true;

  /// Short notices for the user (e.g. a rejected edit). The view shows and clears them.
  final ValueNotifier<String?> notice = ValueNotifier(null);

  Cell? _dragStart;
  Cell? _dragCurrent;
  World? _dragBase;

  EditorMode mode = EditorMode.edit;
  PlayEngine? _engine;
  PlayState? playState;
  int playMoves = 0;
  PlayEngine? get playEngine => _engine;

  Entity? get selected => selectedId == null ? null : _world.byId(selectedId!);

  /// The rectangle being drawn with a rect tool, in cells.
  ({int x, int y, int w, int h})? get rectPreview {
    if (!tool.drawsRect || _dragStart == null || _dragCurrent == null) return null;
    return _normalized(_dragStart!, _dragCurrent!);
  }

  // ---------------------------------------------------------------- history

  bool _commit(World next, {World? base}) {
    final result = validateWorld(next);
    if (result.errors.isNotEmpty) {
      notice.value = result.errors.first.message;
      _resolve();
      notifyListeners();
      return false;
    }
    _undo.add(base ?? _world);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    _world = next;
    _resolve();
    notifyListeners();
    return true;
  }

  void undo() {
    if (_undo.isEmpty || mode == EditorMode.play) return;
    _redo.add(_world);
    _world = _undo.removeLast();
    _afterHistoryJump();
  }

  void redo() {
    if (_redo.isEmpty || mode == EditorMode.play) return;
    _undo.add(_world);
    _world = _redo.removeLast();
    _afterHistoryJump();
  }

  void _afterHistoryJump() {
    if (selectedId != null && selectedId != startId && selectedId != flagId && _world.byId(selectedId!) == null) {
      selectedId = null;
    }
    _resolve();
    notifyListeners();
  }

  void _resolve() {
    _grid = rasterize(_world);
    _validation = validateWorld(_world);
    _solve = _validation.errors.isEmpty ? solve(_world, _grid) : null;
  }

  void loadLevel(World world, String name) {
    if (_commit(world)) {
      levelName = name;
      selectedId = null;
      notifyListeners();
    }
  }

  void newLevel() => loadLevel(emptyLevel(), 'Untitled level');

  void loadSampleLevel() => loadLevel(sampleLevel(), 'Castle Story');

  // ------------------------------------------------------------- selection

  void setTool(EditorTool t) {
    if (mode == EditorMode.play) return;
    tool = t;
    notifyListeners();
  }

  void setToolColor(GameColor c) {
    toolColor = c;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void toggleShowPath() {
    showPath = !showPath;
    notifyListeners();
  }

  /// Topmost thing under a cell: start and flag, then single-cell entities, then rectangles.
  String? hitTest(Cell c) {
    if (c == _world.start) return startId;
    if (c == _world.flag) return flagId;
    for (final e in _world.entities.reversed) {
      if (!e.type.isRect && e.contains(c.x, c.y)) return e.id;
    }
    for (final e in _world.entities.reversed) {
      if (e.type.isRect && e.contains(c.x, c.y)) return e.id;
    }
    return null;
  }

  // ------------------------------------------------------------ pointer input

  void pointerDown(Cell c) {
    if (mode == EditorMode.play) return;
    switch (tool) {
      case EditorTool.select:
        selectedId = hitTest(c);
        if (selectedId != null) {
          _dragStart = c;
          _dragBase = _world;
        }
        notifyListeners();
      case EditorTool.wall || EditorTool.lava || EditorTool.bridge || EditorTool.castle:
        _dragStart = c;
        _dragCurrent = c;
        notifyListeners();
      case EditorTool.door || EditorTool.key || EditorTool.treasure || EditorTool.coin:
        _placeCellEntity(tool.entityType!, c);
      case EditorTool.start:
        if (_commit(_world.copyWith(start: c))) selectedId = startId;
      case EditorTool.flag:
        if (_commit(_world.copyWith(flag: c))) selectedId = flagId;
      case EditorTool.erase:
        final hit = hitTest(c);
        if (hit != null && hit != startId && hit != flagId) deleteEntity(hit);
    }
  }

  void pointerMove(Cell c) {
    if (hover == c && _dragStart == null) return;
    hover = c;
    if (_dragStart != null) {
      _dragCurrent = c;
      if (tool == EditorTool.select && _dragBase != null && selectedId != null) {
        _world = _moved(_dragBase!, selectedId!, c.x - _dragStart!.x, c.y - _dragStart!.y);
        _grid = rasterize(_world);
        _solve = null;
      }
    }
    notifyListeners();
  }

  void pointerExit() {
    hover = null;
    notifyListeners();
  }

  void pointerUp() {
    if (tool == EditorTool.select && _dragBase != null) {
      final moved = _world;
      _world = _dragBase!;
      if (_dragCurrent != null && _dragCurrent != _dragStart) _commit(moved, base: _dragBase);
    } else if (tool.drawsRect && _dragStart != null && _dragCurrent != null) {
      _createRect(tool.entityType!, _normalized(_dragStart!, _dragCurrent!), clicked: _dragStart == _dragCurrent);
    }
    _dragStart = null;
    _dragCurrent = null;
    _dragBase = null;
    _resolve();
    notifyListeners();
  }

  // ------------------------------------------------------------------- edits

  String _nextId() {
    var n = 0;
    for (final e in _world.entities) {
      if (e.id.startsWith('me:')) n = math.max(n, int.tryParse(e.id.substring(3)) ?? 0);
    }
    return 'me:${n + 1}';
  }

  static ({int x, int y, int w, int h}) _normalized(Cell a, Cell b) {
    final x0 = a.x < b.x ? a.x : b.x;
    final y0 = a.y < b.y ? a.y : b.y;
    return (x: x0, y: y0, w: (a.x - b.x).abs() + 1, h: (a.y - b.y).abs() + 1);
  }

  void _createRect(EntityType type, ({int x, int y, int w, int h}) r, {required bool clicked}) {
    var rect = r;
    if (type == EntityType.castle) {
      if (clicked) {
        // A single click drops a default 5 x 4 castle, kept inside the grid.
        final w = 5.clamp(3, _world.width);
        final h = 4.clamp(3, _world.height);
        rect = (x: r.x.clamp(0, _world.width - w), y: r.y.clamp(0, _world.height - h), w: w, h: h);
      } else if (r.w < 3 || r.h < 3) {
        notice.value = 'A castle needs at least 3 × 3 cells.';
        return;
      }
    }
    final id = _nextId();
    final entity = Entity(
      id: id,
      type: type,
      owner: _localOwner,
      x: rect.x,
      y: rect.y,
      w: rect.w,
      h: rect.h,
      door: type == EntityType.castle ? CastleDoor(side: DoorSide.left, offset: (rect.h - 3) ~/ 2, color: toolColor) : null,
    );
    if (_commit(_world.copyWith(entities: [..._world.entities, entity]))) selectedId = id;
  }

  void _placeCellEntity(EntityType type, Cell c) {
    for (final e in _world.entities) {
      if (e.type == type && e.x == c.x && e.y == c.y) {
        select(e.id);
        return;
      }
    }
    final id = _nextId();
    final entity = Entity(id: id, type: type, owner: _localOwner, x: c.x, y: c.y, color: type.hasColor ? toolColor : null);
    final objectives = type == EntityType.treasure ? [..._world.objectives, CollectObjective(id)] : _world.objectives;
    if (_commit(_world.copyWith(entities: [..._world.entities, entity], objectives: objectives))) selectedId = id;
  }

  World _moved(World base, String id, int dx, int dy) {
    Cell shift(Cell c) => (x: (c.x + dx).clamp(0, base.width - 1), y: (c.y + dy).clamp(0, base.height - 1));
    if (id == startId) return base.copyWith(start: shift(base.start));
    if (id == flagId) return base.copyWith(flag: shift(base.flag));
    return base.copyWith(entities: [
      for (final e in base.entities)
        if (e.id == id)
          e.copyWith(x: (e.x + dx).clamp(0, base.width - e.w), y: (e.y + dy).clamp(0, base.height - e.h))
        else
          e,
    ]);
  }

  void nudgeSelected(int dx, int dy) {
    if (selectedId == null || mode == EditorMode.play) return;
    final moved = _moved(_world, selectedId!, dx, dy);
    if (jsonEncode(moved.toJson()) != jsonEncode(_world.toJson())) _commit(moved);
  }

  void updateEntity(String id, Entity Function(Entity e) change) {
    _commit(_world.copyWith(entities: [for (final e in _world.entities) e.id == id ? change(e) : e]));
  }

  void deleteEntity(String id) {
    final next = _world.copyWith(
      entities: [for (final e in _world.entities) if (e.id != id) e],
      objectives: [for (final o in _world.objectives) if (!(o is CollectObjective && o.target == id)) o],
    );
    if (_commit(next) && selectedId == id) selectedId = null;
  }

  void deleteSelected() {
    final id = selectedId;
    if (id != null && id != startId && id != flagId) deleteEntity(id);
  }

  bool isRequired(String id) => _world.objectives.any((o) => o is CollectObjective && o.target == id);

  void setRequired(String id, bool required) {
    final others = [for (final o in _world.objectives) if (!(o is CollectObjective && o.target == id)) o];
    _commit(_world.copyWith(objectives: required ? [...others, CollectObjective(id)] : others));
  }

  int get coinGoal =>
      _world.objectives.whereType<CollectCountObjective>().fold(0, (m, o) => o.count > m ? o.count : m);

  void setCoinGoal(int count) {
    final others = [for (final o in _world.objectives) if (o is! CollectCountObjective) o];
    _commit(_world.copyWith(objectives: count > 0 ? [...others, CollectCountObjective(count)] : others));
  }

  // -------------------------------------------------------------------- play

  void startPlay() {
    if (_validation.errors.isNotEmpty) return;
    mode = EditorMode.play;
    _engine = PlayEngine(_world);
    playState = _engine!.initialState();
    playMoves = 0;
    notifyListeners();
  }

  void restartPlay() {
    if (_engine == null) return;
    playState = _engine!.initialState();
    playMoves = 0;
    notifyListeners();
  }

  void stopPlay() {
    mode = EditorMode.edit;
    _engine = null;
    playState = null;
    notifyListeners();
  }

  void togglePlay() => mode == EditorMode.play ? stopPlay() : startPlay();

  void playMove(Direction d) {
    final engine = _engine;
    final s = playState;
    if (engine == null || s == null || s.won) return;
    final next = engine.step(s, d);
    if (identical(next, s)) return;
    playMoves++;
    playState = next;
    notifyListeners();
  }
}
