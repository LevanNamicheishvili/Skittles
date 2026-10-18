// The studio's editing state: the scene, the selection, the tool, undo and redo. Every finished edit re-runs the
// validation, so the status line and the reachability overlay are always about the scene on screen.
//
// On its own the studio keeps its history locally. In a shared project (join) the server is the single writer:
// each edit goes to it as a patch and shows at once, the project's changes come back in order, and undo asks the
// server to revert your own last change, never a teammate's. The agents live in the project too.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'patch.dart';
import 'play.dart';
import 'project.dart';
import 'scene.dart';
import 'studio_link.dart';
import 'validate.dart';

enum StudioTool {
  select('Select', 'V'),
  pan('Hand', 'H'),
  player('Player', 'P'),
  platform('Platform', 'L'),
  coin('Coin', 'C'),
  enemy('Enemy', 'E'),
  finish('Finish', 'F');

  const StudioTool(this.label, this.key);
  final String label;
  final String key;

  SceneObjectType? get creates => switch (this) {
        player => SceneObjectType.player,
        platform => SceneObjectType.platform,
        coin => SceneObjectType.coin,
        enemy => SceneObjectType.enemy,
        finish => SceneObjectType.finish,
        _ => null,
      };
}

/// An edit sent to the project and not yet confirmed.
class _Pending {
  _Pending(this.seq, this.patch);
  final int seq;
  final ScenePatch patch;
}

class StudioController extends ChangeNotifier {
  StudioController(Scene scene, {this.filePath})
      : _scene = scene,
        _server = scene,
        _report = validateScene(scene);

  /// Joins a shared project over [link], or creates one when [project] is null (blank, or from [scene]).
  static Future<StudioController> join(StudioLink link, {required Uri server, required String name, String? project, Scene? scene, String? sceneName, String? filePath}) async {
    final answer = await link.request('join', {'name': name, 'project': ?project, 'scene': ?scene?.toJson(), 'sceneName': ?sceneName});
    if (answer['ok'] != true) {
      await link.close();
      throw answer['message'] as String? ?? 'The project refused the join.';
    }
    final studio = StudioController(Scene.fromJson((answer['scene'] as Map).cast<String, dynamic>()), filePath: filePath);
    studio._attach(link, server, name, answer);
    return studio;
  }

  Scene _scene;
  SceneReport _report;
  Scene get scene => _scene;
  SceneReport get report => _report;

  String? selectedId;
  StudioTool tool = StudioTool.select;
  bool showGrid = true;
  bool showReach = true;

  /// Where the scene was last opened from or saved to.
  String? filePath;

  /// Changed since the last save. A shared project is saved by the server, so it is never dirty.
  bool dirty = false;

  final _undo = <Scene>[];
  final _redo = <Scene>[];
  bool get canUndo => isShared ? _canUndoShared : _undo.isNotEmpty;
  bool get canRedo => isShared ? _canRedoShared : _redo.isNotEmpty;

  // A drag in progress: the scene before it, and the object as it was.
  Scene? _dragBase;
  SceneObject? _dragObject;

  SceneObject? get selected => _scene.byId(selectedId);

  static const gridStep = 8.0;
  static double snap(double v) => (v / gridStep).roundToDouble() * gridStep;

  // ---- Shared project --------------------------------------------------------------------------------------------

  StudioLink? _link;
  SharedProject? shared;
  String _name = '';
  bool get isShared => _link != null;

  /// False while the line to the project is down.
  bool connected = true;

  /// The scene as the project has it, version by version; what is on screen is this plus the edits still on their way.
  Scene _server;
  int _version = 0;
  final _pending = <_Pending>[];
  int _seq = 0;
  bool _canUndoShared = false;
  bool _canRedoShared = false;

  /// The last thing the project refused, for the screen to show once.
  String? notice;

  void _attach(StudioLink link, Uri server, String name, Map<String, dynamic> answer) {
    _link = link;
    _name = name;
    shared = SharedProject(id: answer['project'] as String, server: server, you: answer['you'] as String)..load(answer);
    shared!.addListener(notifyListeners);
    _loadSnapshot(answer);
    link
      ..onEvent = _onEvent
      ..onReconnect = _rejoin
      ..onConnection = (up) {
        connected = up;
        notifyListeners();
      };
  }

  void _loadSnapshot(Map<String, dynamic> answer) {
    _server = Scene.fromJson((answer['scene'] as Map).cast<String, dynamic>());
    _version = (answer['version'] as num).toInt();
    _pending.clear();
    final history = (answer['history'] as Map?)?.cast<String, dynamic>();
    _canUndoShared = history?['canUndo'] == true;
    _canRedoShared = history?['canRedo'] == true;
    _refresh();
  }

  /// After a drop, or a gap in the changes: fetch the project again. Edits still on their way are dropped; the
  /// project's copy is the truth.
  Future<void> _rejoin() async {
    final link = _link;
    final project = shared;
    if (link == null || project == null) return;
    final answer = await link.request('join', {'project': project.id, 'name': _name, 'member': project.you});
    if (answer['ok'] != true) {
      notice = answer['message'] as String? ?? 'Could not rejoin the project.';
      notifyListeners();
      return;
    }
    project.load(answer);
    _loadSnapshot(answer);
  }

  void _onEvent(String event, Object? data) {
    switch (event) {
      case 'change':
        _onChange((data as Map).cast<String, dynamic>());
      case 'history':
        final h = (data as Map).cast<String, dynamic>();
        _canUndoShared = h['canUndo'] == true;
        _canRedoShared = h['canRedo'] == true;
        notifyListeners();
      default:
        shared?.handle(event, data);
    }
  }

  void _onChange(Map<String, dynamic> change) {
    final v = (change['v'] as num).toInt();
    if (v <= _version) return; // already have it (a replay after reconnecting)
    if (v != _version + 1) {
      unawaited(_rejoin()); // missed one
      return;
    }
    _version = v;
    _server = applyPatch(_server, ScenePatch.fromJson((change['patch'] as Map).cast<String, dynamic>()));
    if (change['by'] == shared?.you && change['seq'] is num) {
      final seq = (change['seq'] as num).toInt();
      _pending.removeWhere((p) => p.seq == seq);
    }
    _refresh();
  }

  Scene _folded() {
    var s = _server;
    for (final p in _pending) {
      s = applyPatch(s, p.patch);
    }
    return s;
  }

  /// The project's scene with your edits on their way on top, and a drag in progress on top of that.
  void _refresh() {
    var s = _folded();
    final dragging = _dragObject == null ? null : _scene.byId(_dragObject!.id);
    if (dragging != null && s.byId(dragging.id) != null) s = s.replace(dragging);
    _scene = s;
    _report = validateScene(s);
    if (s.byId(selectedId) == null && _dragObject == null) selectedId = null;
    notifyListeners();
  }

  /// Sends what changed between the project's scene (with edits on their way) and [next]; shows [next] at once.
  void _share(Scene next) {
    final link = _link!;
    final base = _folded();
    final patch = diffScenes(base, next);
    _scene = next;
    _report = validateScene(next);
    notifyListeners();
    if (patch.isEmpty) return;
    final created = [for (final e in patch.objects.entries) if (e.value != null && base.byId(e.key) == null) e.key];
    final seq = ++_seq;
    _pending.add(_Pending(seq, patch));
    unawaited(link.request('edit', {...patch.toJson(), 'created': created, 'seq': seq}).then((ack) {
      _pending.removeWhere((p) => p.seq == seq);
      final renamed = (ack['renamed'] as Map?)?.cast<String, String>() ?? const {};
      if (renamed[selectedId] != null) selectedId = renamed[selectedId];
      if (ack['ok'] != true) notice = ack['message'] as String? ?? 'The project refused that edit.';
      _refresh();
    }));
  }

  Future<String?> _ask(String event, Map<String, dynamic> data) async {
    final link = _link;
    if (link == null) return 'Agents work in a shared project. Start the Skittles server and create one.';
    final answer = await link.request(event, data);
    return answer['ok'] == true ? null : (answer['message'] as String? ?? 'That did not work.');
  }

  /// A request to an agent: your own, or a teammate's ([owner]).
  Future<String?> askAgent(String text, {String? owner}) => _ask('ask', {'text': text, 'agent': ?owner});

  /// A message to the team. Agents written as "@Name's agent" get it as a request.
  Future<String?> sayToTeam(String text) {
    final project = shared;
    final lower = text.toLowerCase();
    final agents = [
      if (project != null)
        for (final m in project.members.values)
          if (lower.contains("@${m.name.toLowerCase()}'s agent")) m.id,
    ];
    return _ask('say', {'text': text, 'agents': agents});
  }

  Future<String?> approve(String task) => _ask('approve', {'task': task});
  Future<String?> discard(String task) => _ask('discard', {'task': task});

  /// Reverts one change in the project, whoever made it (the Undo on an agent's report).
  Future<String?> revert(int change) => _ask('revert', {'change': change});

  /// The project's version of the scene on screen (0 on its own).
  int get version => _version;

  /// Asks the AI to play the scene and review it; the result arrives in the team chat.
  Future<String?> playtestWithAi() => _ask('playtest:ai', const {});

  /// Shares a run you played on [version] with the team.
  Future<String?> shareRun(int version, List<Segment> run, {String? note}) =>
      _ask('playtest:share', {'version': version, 'run': segmentsToJson(run), if (note != null && note.trim().isNotEmpty) 'note': note.trim()});

  /// The scene as it was at [version], to watch a run on; throws a message when it is gone.
  Future<Scene> sceneAt(int version) async {
    if (version == _version) return _server;
    final link = _link;
    if (link == null) throw 'Runs can be watched in a shared project.';
    final answer = await link.request('scene:at', {'version': version});
    if (answer['ok'] != true) throw answer['message'] as String? ?? 'That version is gone.';
    return Scene.fromJson((answer['scene'] as Map).cast<String, dynamic>());
  }

  Offset? _cursor;
  DateTime _cursorSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// Shows teammates where you point, at most 20 times a second. Null when the pointer leaves the scene.
  void pointAt(Offset? world) {
    final link = _link;
    if (link == null) return;
    _cursor = world;
    final now = DateTime.now();
    if (world != null && now.difference(_cursorSent) < const Duration(milliseconds: 50)) return;
    _cursorSent = now;
    _sendPresence();
  }

  void _sendPresence() => _link?.send('presence', {
        'cursor': _cursor == null ? null : {'x': _cursor!.dx, 'y': _cursor!.dy},
        'selected': selectedId,
      });

  @override
  void dispose() {
    shared?.removeListener(notifyListeners);
    shared?.dispose();
    unawaited(_link?.close());
    super.dispose();
  }

  // ---- Editing ---------------------------------------------------------------------------------------------------

  void _apply(Scene next, {bool record = true}) {
    if (isShared) return _share(next);
    if (record) {
      _undo.add(_scene);
      if (_undo.length > 200) _undo.removeAt(0);
      _redo.clear();
    }
    _scene = next;
    _report = validateScene(next);
    dirty = true;
    notifyListeners();
  }

  void setTool(StudioTool value) {
    tool = value;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    if (isShared) _sendPresence();
    notifyListeners();
  }

  void toggleGrid() {
    showGrid = !showGrid;
    notifyListeners();
  }

  void toggleReach() {
    showReach = !showReach;
    notifyListeners();
  }

  /// Places a new object centred on [at] (snapped, inside the scene) and selects it. There is one player per
  /// scene, so the player tool moves the existing player instead of adding a second.
  SceneObject place(SceneObjectType type, Offset at) {
    final size = defaultSizes[type]!;
    final x = snap(at.dx - size.width / 2).clamp(0.0, _scene.width - size.width);
    final y = snap(at.dy - size.height / 2).clamp(0.0, _scene.height - size.height);
    if (type == SceneObjectType.player) {
      final existing = [for (final o in _scene.objects) if (o.type == SceneObjectType.player) o].firstOrNull;
      if (existing != null) {
        final moved = existing.copyWith(x: x, y: y);
        selectedId = moved.id;
        tool = StudioTool.select;
        _apply(_scene.replace(moved));
        return moved;
      }
    }
    var n = 1;
    final ids = {for (final o in _scene.objects) o.id};
    while (ids.contains('${type.name}-$n')) {
      n++;
    }
    final count = _scene.objects.where((o) => o.type == type).length + 1;
    final label = '${type.name[0].toUpperCase()}${type.name.substring(1)}';
    var behaviours = defaultBehaviours(type, x: x);
    if (type == SceneObjectType.enemy) {
      final to = math.min(x + 200, _scene.width - size.width);
      behaviours = {
        'patrol': {'from': x, 'to': to, 'speed': 90},
      };
    }
    final object = SceneObject(id: '${type.name}-$n', name: count == 1 ? label : '$label $count', type: type, x: x, y: y, w: size.width, h: size.height, behaviours: behaviours);
    selectedId = object.id;
    tool = StudioTool.select;
    _apply(_scene.copyWith(objects: [..._scene.objects, object]));
    return object;
  }

  /// Starts moving or resizing the selected object; the whole drag becomes one undo step.
  void beginDrag() {
    _dragBase = _scene;
    _dragObject = selected;
  }

  /// Moves the selected object by [delta] from where the drag began, snapped and kept inside the scene. An enemy's
  /// patrol moves with it.
  void dragTo(Offset delta) {
    final base = _dragObject;
    if (base == null) return;
    final x = snap(base.x + delta.dx).clamp(0.0, _scene.width - base.w);
    final y = snap(base.y + delta.dy).clamp(0.0, _scene.height - base.h);
    var moved = base.copyWith(x: x, y: y);
    if (base.type == SceneObjectType.enemy) {
      final shift = x - base.x;
      moved = moved
          .withParam('patrol', 'from', (base.param('patrol', 'from') ?? base.x) + shift)
          .withParam('patrol', 'to', (base.param('patrol', 'to') ?? base.x) + shift);
    }
    if (_scene.byId(base.id) == null) return; // removed by a teammate meanwhile
    _scene = _scene.replace(moved);
    notifyListeners();
  }

  /// Resizes the selected object from its bottom-right corner by [delta] from where the drag began.
  void resizeTo(Offset delta) {
    final base = _dragObject;
    if (base == null || _scene.byId(base.id) == null) return;
    final w = snap(base.w + delta.dx).clamp(8.0, _scene.width - base.x);
    final h = snap(base.h + delta.dy).clamp(8.0, _scene.height - base.y);
    _scene = _scene.replace(base.copyWith(w: w, h: h));
    notifyListeners();
  }

  void endDrag() {
    final base = _dragBase;
    _dragBase = null;
    _dragObject = null;
    if (base == null || identical(base, _scene)) return;
    if (isShared) return _share(_scene);
    _undo.add(base);
    _redo.clear();
    _report = validateScene(_scene);
    dirty = true;
    notifyListeners();
  }

  /// Applies an edit from the inspector, keeping the object inside the scene (and an enemy's patrol too).
  void update(SceneObject object) => _apply(_scene.replace(_scene.fit(object)));

  void rename(String name) {
    if (name.trim().isEmpty || name == _scene.name) return;
    _apply(_scene.copyWith(name: name.trim()));
  }

  void setTheme(String theme) {
    if (theme != _scene.theme) _apply(_scene.copyWith(theme: theme));
  }

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    selectedId = null;
    _apply(_scene.copyWith(objects: [for (final o in _scene.objects) if (o.id != id) o]));
  }

  /// Fills the scene with [example]'s objects: the "start from an example" on an empty scene. The look someone
  /// already picked stays; the name too, unless it is still the default.
  void startFrom(Scene example) => _apply(_scene.copyWith(name: _scene.name == 'Untitled' ? example.name : null, objects: [for (final o in example.objects) _scene.fit(o)]));

  void undo() {
    if (isShared) {
      unawaited(_ask('undo', const {}));
      return;
    }
    if (_undo.isEmpty) return;
    _redo.add(_scene);
    _scene = _undo.removeLast();
    _afterHistory();
  }

  void redo() {
    if (isShared) {
      unawaited(_ask('redo', const {}));
      return;
    }
    if (_redo.isEmpty) return;
    _undo.add(_scene);
    _scene = _redo.removeLast();
    _afterHistory();
  }

  void _afterHistory() {
    if (_scene.byId(selectedId) == null) selectedId = null;
    _report = validateScene(_scene);
    dirty = true;
    notifyListeners();
  }

  /// Replaces the scene (a file was opened); the history starts again. Not in a shared project.
  void load(Scene scene, {String? path}) {
    assert(!isShared, 'a shared project is opened by joining it');
    _scene = scene;
    _report = validateScene(scene);
    _undo.clear();
    _redo.clear();
    selectedId = null;
    filePath = path;
    dirty = false;
    notifyListeners();
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(_scene.toJson());

  void saved(String path) {
    filePath = path;
    dirty = false;
    notifyListeners();
  }
}
