// Validation and reachability for scenes (spec/scene.md sections 4 and 5): the platformer form of Skittles' promise
// that no change makes the game unwinnable. Deterministic and quick enough to run on every edit.

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'scene.dart';

enum Severity { error, warning }

class SceneIssue {
  const SceneIssue(this.code, this.severity, this.message, {this.objectId});

  final String code;
  final Severity severity;
  final String message;
  final String? objectId;
}

class SceneReport {
  const SceneReport({required this.issues, required this.finishReachable, required this.reachable, this.start, required this.jumpHeight});

  final List<SceneIssue> issues;
  final bool finishReachable;

  /// Ids of platforms whose top the player can stand on.
  final Set<String> reachable;

  /// The platform the player starts on.
  final String? start;

  /// The highest jump, H, in pixels (0 without a player).
  final double jumpHeight;

  List<SceneIssue> get errors => [for (final i in issues) if (i.severity == Severity.error) i];
  List<SceneIssue> get warnings => [for (final i in issues) if (i.severity == Severity.warning) i];
  bool get ok => errors.isEmpty;

  /// The status line: "Playable · finish reachable" or the first error.
  String get label => ok ? 'Playable · finish reachable' : 'Blocked · ${errors.first.message.toLowerCase().replaceAll(RegExp(r'\.$'), '')}';
}

/// The jump model: take-off speed v, run speed s, gravity g.
class Jump {
  const Jump({required this.speed, required this.takeoff, required this.gravity});

  final double speed;
  final double takeoff;
  final double gravity;

  double get height => takeoff * takeoff / (2 * gravity);

  /// How far the player gets horizontally while landing dh higher (negative: lower), with the 90% margin.
  double reach(double dh) {
    final under = takeoff * takeoff - 2 * gravity * dh;
    if (under < 0) return -1;
    return 0.9 * speed * (takeoff + math.sqrt(under)) / gravity;
  }
}

SceneReport validateScene(Scene scene) {
  final issues = <SceneIssue>[];
  void error(String code, String message, [String? id]) => issues.add(SceneIssue(code, Severity.error, message, objectId: id));
  void warn(String code, String message, [String? id]) => issues.add(SceneIssue(code, Severity.warning, message, objectId: id));

  final players = [for (final o in scene.objects) if (o.type == SceneObjectType.player) o];
  final finishes = [for (final o in scene.objects) if (o.type == SceneObjectType.finish) o];
  final platforms = [for (final o in scene.objects) if (o.type == SceneObjectType.platform) o];

  if (players.isEmpty) error('no_player', 'There is no player.');
  if (players.length > 1) error('many_players', 'There is more than one player.', players[1].id);
  if (finishes.isEmpty) error('no_finish', 'There is no finish.');

  final seen = <String>{};
  for (final o in scene.objects) {
    if (!seen.add(o.id)) error('duplicate_id', 'Two objects share the id ${o.id}.', o.id);
    if (o.w < 8 || o.h < 8) error('bad_size', '${o.name} is smaller than 8 px.', o.id);
    if (o.x < 0 || o.y < 0 || o.x + o.w > scene.width || o.y + o.h > scene.height) error('out_of_bounds', '${o.name} is outside the scene.', o.id);
    if (o.type == SceneObjectType.enemy) {
      final from = (o.param('patrol', 'from') ?? o.x).toDouble();
      final to = (o.param('patrol', 'to') ?? o.x).toDouble();
      if (from > to || from < 0 || to + o.w > scene.width) error('bad_patrol', "${o.name}'s patrol runs backwards or leaves the scene.", o.id);
    }
  }

  // Warnings about the player's surroundings.
  if (players.length == 1) {
    final p = players.single;
    for (final f in platforms) {
      if (p.rect.overlaps(f.rect)) warn('player_in_platform', 'The player is stuck inside ${f.name}.', p.id);
    }
    for (final e in scene.objects.where((o) => o.type == SceneObjectType.enemy)) {
      final from = (e.param('patrol', 'from') ?? e.x).toDouble();
      final to = (e.param('patrol', 'to') ?? e.x).toDouble();
      final lane = Rect.fromLTRB(math.min(from, to), e.y, math.max(from, to) + e.w, e.y + e.h);
      if (lane.overlaps(p.rect)) warn('enemy_on_start', "${e.name}'s patrol passes through the player's start.", e.id);
    }
  }

  // Reachability runs only with exactly one player and at least one finish.
  if (players.length != 1 || finishes.isEmpty) {
    return SceneReport(issues: issues, finishReachable: false, reachable: const {}, jumpHeight: 0);
  }
  final player = players.single;
  final jump = Jump(
    speed: (player.param('controller', 'speed') ?? 260).toDouble(),
    takeoff: (player.param('controller', 'jump') ?? 640).toDouble(),
    gravity: scene.gravity,
  );

  // The start: the nearest platform top at or below the player's feet that overlaps it horizontally.
  final feet = player.y + player.h;
  SceneObject? start;
  for (final f in platforms) {
    final under = f.x < player.x + player.w && player.x < f.x + f.w && f.y >= feet;
    if (under && (start == null || f.y < start.y)) start = f;
  }
  if (start == null) {
    error('player_falls', 'Nothing is below the player: it falls out of the world.', player.id);
    return SceneReport(issues: issues, finishReachable: false, reachable: const {}, jumpHeight: jump.height);
  }

  // Breadth-first search over platform tops.
  final reachable = <String>{start.id};
  final queue = Queue<SceneObject>()..add(start);
  while (queue.isNotEmpty) {
    final a = queue.removeFirst();
    for (final b in platforms) {
      if (reachable.contains(b.id)) continue;
      final dh = a.y - b.y; // how much higher b's top is
      if (dh > jump.height) continue;
      final gap = math.max(0.0, math.max(b.x - (a.x + a.w), a.x - (b.x + b.w)));
      if (gap <= jump.reach(dh)) {
        reachable.add(b.id);
        queue.add(b);
      }
    }
  }

  // What the player can touch from a reachable top.
  final half = jump.reach(0) / 2;
  bool touchable(SceneObject target) {
    for (final f in platforms.where((f) => reachable.contains(f.id))) {
      final zone = Rect.fromLTRB(f.x - half, f.y - jump.height - player.h, f.x + f.w + half, f.y);
      if (zone.overlaps(target.rect) || zone.contains(target.rect.center)) return true;
    }
    return false;
  }

  final finishReachable = finishes.any(touchable);
  if (!finishReachable) error('finish_unreachable', 'The finish cannot be reached.', finishes.first.id);
  for (final coin in scene.objects.where((o) => o.type == SceneObjectType.coin)) {
    if (!touchable(coin)) warn('coin_unreachable', '${coin.name} cannot be reached.', coin.id);
  }
  return SceneReport(issues: issues, finishReachable: finishReachable, reachable: reachable, start: start.id, jumpHeight: jump.height);
}
