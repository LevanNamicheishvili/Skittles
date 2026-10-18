// Playing a scene (spec/scene-play.md): the exact fixed-step game, the same as server/src/studio/play.ts. Both pass
// spec/fixtures/scene_runs.json, so a run recorded here replays the same on the server, and the AI's run replays the
// same here.

import 'dart:math' as math;

import 'scene.dart';

const dt = 1 / 120;
const keyLeft = 1;
const keyRight = 2;
const keyJump = 4;

/// A run: hold `bits` for `frames` steps, segment after segment.
typedef Segment = (int frames, int bits);

List<Segment> segmentsFromJson(Object? raw) => [for (final s in (raw as List? ?? const [])) (((s as List)[0] as num).toInt(), (s[1] as num).toInt())];
List<List<int>> segmentsToJson(List<Segment> run) => [for (final (frames, bits) in run) [frames, bits]];

class RunResult {
  const RunResult({required this.won, required this.frame, required this.score, required this.coins, required this.coinsTotal, required this.deaths});

  factory RunResult.fromJson(Map<String, dynamic> j) => RunResult(
        won: j['won'] == true,
        frame: (j['frame'] as num).toInt(),
        score: (j['score'] as num).toInt(),
        coins: [for (final c in j['coins'] as List? ?? const []) c as String],
        coinsTotal: (j['coinsTotal'] as num?)?.toInt() ?? 0,
        deaths: (j['deaths'] as num).toInt(),
      );

  final bool won;
  final int frame;
  final int score;
  final List<String> coins;
  final int coinsTotal;
  final int deaths;

  double get time => frame / 120;
}

bool _overlaps(double ax, double ay, double aw, double ah, SceneObject b) => ax < b.x + b.w && b.x < ax + aw && ay < b.y + b.h && b.y < ay + ah;

/// Where an enemy is after [frame] steps (spec/scene-play.md section 4).
double enemyX(SceneObject e, int frame) {
  final lo = (e.param('patrol', 'from') ?? e.x).toDouble();
  final hi = (e.param('patrol', 'to') ?? e.x).toDouble();
  final speed = (e.param('patrol', 'speed') ?? 90).toDouble();
  final start = math.min(math.max(e.x, lo), hi);
  final length = hi - lo;
  if (length <= 0 || speed <= 0) return start;
  final m = ((start - lo) + speed * (frame / 120)) % (2 * length);
  return m <= length ? lo + m : lo + 2 * length - m;
}

class Game {
  Game(this.scene) : player = scene.objects.firstWhere((o) => o.type == SceneObjectType.player) {
    speed = (player.param('controller', 'speed') ?? 260).toDouble();
    jump = (player.param('controller', 'jump') ?? 640).toDouble();
    platforms = [for (final o in scene.objects) if (o.type == SceneObjectType.platform) o];
    coinObjects = [for (final o in scene.objects) if (o.type == SceneObjectType.coin) o];
    enemies = [for (final o in scene.objects) if (o.type == SceneObjectType.enemy) o];
    finishes = [for (final o in scene.objects) if (o.type == SceneObjectType.finish) o];
    _respawn();
  }

  final Scene scene;
  final SceneObject player;
  late final double speed;
  late final double jump;
  late final List<SceneObject> platforms;
  late final List<SceneObject> coinObjects;
  late final List<SceneObject> enemies;
  late final List<SceneObject> finishes;

  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  bool grounded = false;
  int air = 11;
  int buffer = 0;
  bool prevJump = false;
  int safe = 0;
  int frame = 0;
  int score = 0;
  final List<String> coins = [];
  int deaths = 0;
  bool won = false;

  void _respawn() {
    x = player.x;
    y = player.y;
    vx = 0;
    vy = 0;
    grounded = false;
    air = 11;
    buffer = 0;
  }

  void _die() {
    deaths += 1;
    _respawn();
    safe = 120;
  }

  /// One step of spec/scene-play.md section 3.
  void step(int bits) {
    if (won) return;
    frame += 1;
    vx = speed * ((bits & keyRight != 0 ? 1 : 0) - (bits & keyLeft != 0 ? 1 : 0));
    final jumping = bits & keyJump != 0;
    final pressed = jumping && !prevJump;
    prevJump = jumping;
    if (pressed) {
      buffer = 12;
    } else if (buffer > 0) {
      buffer -= 1;
    }
    air = grounded ? 0 : air + 1;
    if (buffer > 0 && air <= 10) {
      vy = -jump;
      buffer = 0;
      air = 11;
      grounded = false;
    }
    final ox = x;
    final oy = y;
    final w = player.w;
    final h = player.h;
    var nx = ox + vx * dt;
    for (final p in platforms) {
      if (!(p.y < oy + h && oy < p.y + p.h)) continue;
      if (vx > 0 && ox + w <= p.x && p.x < nx + w) nx = math.min(nx, p.x - w);
      if (vx < 0 && nx < p.x + p.w && p.x + p.w <= ox) nx = math.max(nx, p.x + p.w);
    }
    x = math.min(math.max(nx, 0.0), scene.width - w);
    var ny = oy + vy * dt + 0.5 * scene.gravity * dt * dt;
    vy = vy + scene.gravity * dt;
    grounded = false;
    if (ny > oy) {
      double? land;
      for (final p in platforms) {
        if (p.x < x + w && x < p.x + p.w && oy + h <= p.y && p.y < ny + h) land = land == null ? p.y - h : math.min(land, p.y - h);
      }
      if (land != null) {
        ny = land;
        vy = 0;
        grounded = true;
      }
    } else if (ny < oy) {
      double? bump;
      for (final p in platforms) {
        if (p.x < x + w && x < p.x + p.w && ny < p.y + p.h && p.y + p.h <= oy) bump = bump == null ? p.y + p.h : math.max(bump, p.y + p.h);
      }
      if (bump != null) {
        ny = bump;
        vy = 0;
      }
    }
    if (ny < 0) {
      ny = 0;
      vy = 0;
    }
    y = ny;
    if (y > scene.height) return _die();
    for (final c in coinObjects) {
      if (!coins.contains(c.id) && _overlaps(x, y, w, h, c)) {
        coins.add(c.id);
        score += (c.param('collectible', 'points') ?? 10).toInt();
      }
    }
    if (safe > 0) {
      safe -= 1;
    } else {
      for (final e in enemies) {
        if (_overlaps(x, y, w, h, e.copyWith(x: enemyX(e, frame)))) return _die();
      }
    }
    if (finishes.any((f) => _overlaps(x, y, w, h, f))) won = true;
  }

  RunResult result() => RunResult(won: won, frame: frame, score: score, coins: List.of(coins), coinsTotal: coinObjects.length, deaths: deaths);
}

/// Records the inputs of a run as segments.
class RunRecorder {
  final List<Segment> run = [];

  void add(int bits) {
    if (run.isNotEmpty && run.last.$2 == bits) {
      run[run.length - 1] = (run.last.$1 + 1, bits);
    } else {
      run.add((1, bits));
    }
  }
}

/// Feeds a recorded run back one step at a time; 0 once it is over.
class RunPlayer {
  RunPlayer(this.run);

  final List<Segment> run;
  int _segment = 0;
  int _used = 0;

  bool get done => _segment >= run.length;

  int next() {
    while (_segment < run.length && _used >= run[_segment].$1) {
      _segment++;
      _used = 0;
    }
    if (_segment >= run.length) return 0;
    _used++;
    return run[_segment].$2;
  }
}
