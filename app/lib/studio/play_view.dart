// Playing in the studio: your own run with the keyboard, or watching someone's recorded run (a teammate's or the
// AI's). The game advances in exact steps of 1/120 s (play.dart), however fast the screen draws, so a shared run
// replays on the server and on teammates' screens exactly as it was played.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../ui/kit.dart';
import 'play.dart';
import 'scene.dart';
import 'scene_painter.dart';
import 'validate.dart';

class PlaySession extends ChangeNotifier {
  /// You play [scene], the project's [version] of it, with the keyboard.
  PlaySession.play(this.scene, {required this.version})
      : watching = null,
        _run = null,
        game = Game(scene);

  /// Watching a recorded [run] ([whose]: "Giorgi's", "the AI's", "your") on [scene] at [version].
  PlaySession.watch(this.scene, List<Segment> run, {required this.version, required String whose})
      : watching = whose,
        _run = run,
        game = Game(scene) {
    _player = RunPlayer(run);
  }

  final Scene scene;
  final int version;

  /// The painter wants one; nothing in play uses it.
  late final SceneReport report = validateScene(scene);

  /// Whose run is being watched ("Giorgi's"); null when you play.
  final String? watching;
  final List<Segment>? _run;
  RunPlayer? _player;
  Game game;
  RunRecorder recorder = RunRecorder();

  /// Shared with the team already (once per run).
  bool shared = false;
  Duration? _last;
  double _behind = 0;

  bool get over => game.won || (_player?.done ?? false);

  /// Runs the steps the time since the last frame calls for, at most a quarter of a second's worth.
  void advance(Duration now, int Function() keys) {
    final last = _last;
    final elapsed = last == null ? 0.0 : (now - last).inMicroseconds / 1e6;
    _last = now;
    if (over) return;
    _behind = math.min(_behind + elapsed, 0.25);
    var stepped = false;
    while (_behind >= dt && !over) {
      _behind -= dt;
      final bits = _player?.next() ?? keys();
      if (_player == null) recorder.add(bits);
      game.step(bits);
      stepped = true;
    }
    if (stepped) notifyListeners();
  }

  void restart() {
    game = Game(scene);
    recorder = RunRecorder();
    if (_run != null) _player = RunPlayer(_run);
    shared = false;
    _behind = 0;
    notifyListeners();
  }

  PlayFrame get frame => PlayFrame(
        player: Offset(game.x, game.y),
        enemies: {for (final e in game.enemies) e.id: enemyX(e, game.frame)},
        collected: game.coins.toSet(),
        // Blink while safe after a fall.
        showPlayer: game.safe == 0 || (game.safe ~/ 8).isEven,
      );
}

/// The game on screen, its numbers, the keys, and the result when the run is over.
class PlayView extends StatefulWidget {
  const PlayView({super.key, required this.session, required this.onStop, this.onShare, this.sceneChanged = false});

  final PlaySession session;
  final VoidCallback onStop;

  /// Shares your finished run; null when there is no project to share with. Answers with a message on failure.
  final Future<String?> Function(String note)? onShare;

  /// The scene has changed since this run started.
  final bool sceneChanged;

  @override
  State<PlayView> createState() => _PlayViewState();
}

class _PlayViewState extends State<PlayView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => widget.session.advance(elapsed, _keys));
  final _focus = FocusNode(debugLabel: 'play');
  final _note = TextEditingController();
  String? _shareError;
  bool _sharing = false;

  static final _left = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA};
  static final _right = {LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD};
  static final _jump = {LogicalKeyboardKey.space, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW};

  @override
  void initState() {
    super.initState();
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _note.dispose();
    super.dispose();
  }

  // The keys held right now, only while the game has the keyboard (typing in the chat moves nothing).
  int _keys() {
    if (!_focus.hasFocus) return 0;
    final held = HardwareKeyboard.instance.logicalKeysPressed;
    return (held.any(_left.contains) ? keyLeft : 0) | (held.any(_right.contains) ? keyRight : 0) | (held.any(_jump.contains) ? keyJump : 0);
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return _left.contains(e.logicalKey) || _right.contains(e.logicalKey) || _jump.contains(e.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.keyR) {
      widget.session.restart();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onStop();
      return KeyEventResult.handled;
    }
    return _left.contains(e.logicalKey) || _right.contains(e.logicalKey) || _jump.contains(e.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  Future<void> _share() async {
    final share = widget.onShare;
    if (share == null) return;
    setState(() {
      _sharing = true;
      _shareError = null;
    });
    final error = await share(_note.text);
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _shareError = error;
      if (error == null) widget.session.shared = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final session = widget.session;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focus.requestFocus,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              final scene = session.scene;
              final zoom = math.min((box.maxWidth - 48) / scene.width, (box.maxHeight - 120) / scene.height).clamp(0.1, 4.0);
              final pan = Offset((box.maxWidth - scene.width * zoom) / 2, (box.maxHeight - scene.height * zoom) / 2 - 12);
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ScenePainter(
                        scene: scene,
                        report: session.report,
                        zoom: zoom,
                        pan: pan,
                        backdrop: c.muted,
                        mono: context.skFonts.mono,
                        showGrid: false,
                        showReach: false,
                        play: session.frame,
                      ),
                    ),
                  ),
                  Positioned(left: 16, top: 16, child: _Hud(session: session, showScore: scene.score)),
                  if (widget.sceneChanged && session.watching == null)
                    Positioned(
                      right: 16,
                      top: 16,
                      child: _Tag(text: 'The scene changed · R plays the new version', color: c.warning),
                    ),
                  if (session.watching != null) Positioned(right: 16, top: 16, child: _Tag(text: 'Watching ${session.watching} run · v${session.version}', color: SkTokens.brand)),
                  Positioned(left: 0, right: 0, bottom: 16, child: Center(child: _Keys(watching: session.watching != null))),
                  if (session.over) Center(child: _result(context, session)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _result(BuildContext context, PlaySession session) {
    final c = context.sk;
    final r = session.game.result();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final who = session.watching;
    final title = who == null ? 'Finished!' : (r.won ? 'Finished' : 'End of the run');
    return Arrive(
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(SkTokens.radiusPanel),
          border: Border.all(color: c.border),
          boxShadow: dark ? SkTokens.shadowLgDark : SkTokens.shadowLgLight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(r.won ? Icons.flag_rounded : Icons.timer_off_outlined, size: 18, color: r.won ? c.positive : c.warning),
              const SizedBox(width: 8),
              Text(title, style: context.sans(size: 17, weight: FontWeight.w600, spacing: -0.2)),
            ]),
            const SizedBox(height: 10),
            Text(describeRun(r), style: context.mono(size: SkTokens.textSecondary, color: c.mutedForeground)),
            if (who == null && widget.onShare != null && r.won) ...[
              const SizedBox(height: 16),
              SkTextField(controller: _note, placeholder: 'Anything to tell the team? (optional)', height: 34),
              if (_shareError != null) ...[const SizedBox(height: 6), Text(_shareError!, style: context.sans(size: SkTokens.textSecondary, color: c.destructive))],
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (who == null && widget.onShare != null && r.won)
                  SkButton(session.shared ? 'Shared with the team' : (_sharing ? 'Sharing…' : 'Share with the team'), icon: session.shared ? Icons.check_rounded : Icons.ios_share_rounded, onPressed: session.shared || _sharing ? null : _share),
                SkButton(who == null ? 'Play again' : 'Watch again', kind: SkButtonKind.secondary, icon: Icons.replay_rounded, onPressed: () {
                  session.restart();
                  _focus.requestFocus();
                }),
                SkButton('Back to editing', kind: SkButtonKind.ghost, onPressed: widget.onStop),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Finished in 12.4 s · 30 points · coins 2/3 · 1 fall".
String describeRun(RunResult r) => [
      r.won ? 'Finished in ${r.time.toStringAsFixed(1)} s' : 'Did not finish (${r.time.toStringAsFixed(1)} s)',
      '${r.score} points',
      if (r.coinsTotal > 0) 'coins ${r.coins.length}/${r.coinsTotal}',
      r.deaths == 0 ? 'no falls' : (r.deaths == 1 ? '1 fall' : '${r.deaths} falls'),
    ].join(' · ');

class _Hud extends StatelessWidget {
  const _Hud({required this.session, required this.showScore});

  final PlaySession session;
  final bool showScore;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final g = session.game;
    final coins = g.coinObjects.length;
    Widget item(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c.mutedForeground),
          const SizedBox(width: 6),
          Text(text, style: context.mono(size: SkTokens.textSmall, weight: FontWeight.w600)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.background.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(SkTokens.radiusBubble), border: Border.all(color: c.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(Icons.timer_outlined, '${(g.frame / 120).toStringAsFixed(1)} s'),
          if (showScore) ...[const SizedBox(width: 16), item(Icons.star_outline_rounded, '${g.score}')],
          if (coins > 0) ...[const SizedBox(width: 16), item(Icons.monetization_on_outlined, '${g.coins.length}/$coins')],
          const SizedBox(width: 16),
          item(Icons.heart_broken_outlined, '${g.deaths}'),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(SkTokens.radiusControl)),
        child: Text(text, style: context.mono(size: SkTokens.textCaption, weight: FontWeight.w600, color: Colors.white)),
      );
}

class _Keys extends StatelessWidget {
  const _Keys({required this.watching});
  final bool watching;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    Widget hint(List<String> keys, String what) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (final k in keys) ...[Keycap(k), const SizedBox(width: 4)],
          const SizedBox(width: 2),
          Text(what, style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.background.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(SkTokens.radiusPanel), border: Border.all(color: c.border)),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          if (!watching) ...[hint(['←', '→'], 'move'), hint(['Space'], 'jump')],
          hint(['R'], watching ? 'watch again' : 'restart'),
          hint(['Esc'], 'back to editing'),
        ],
      ),
    );
  }
}
