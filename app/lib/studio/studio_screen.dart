// The studio: build a 2D game with tools and agents, together. The layers and the inspector on the left; the scene
// canvas in the middle with the tools floating under it; on the right the people in the project, their agents, the
// team chat and your thread with your own agent. Every edit re-runs the validation, so the status line always says
// whether the finish can still be reached. A new project starts empty, with an invitation to describe the game.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/kit.dart';
import 'scene.dart';
import 'scene_files.dart';
import 'play.dart';
import 'play_view.dart';
import 'scene_painter.dart';
import 'starter.dart';
import 'studio_chat.dart';
import 'studio_controller.dart';
import 'studio_panels.dart';

const _toolIcons = {
  StudioTool.select: Icons.near_me_outlined,
  StudioTool.pan: Icons.pan_tool_outlined,
  StudioTool.player: Icons.directions_run_rounded,
  StudioTool.platform: Icons.horizontal_rule_rounded,
  StudioTool.coin: Icons.monetization_on_outlined,
  StudioTool.enemy: Icons.pest_control_outlined,
  StudioTool.finish: Icons.sports_score_outlined,
};

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.studio, required this.onHome});

  final StudioController studio;
  final VoidCallback onHome;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final _canvasKey = GlobalKey<_SceneCanvasState>();

  /// Set while playing or watching a run.
  PlaySession? _session;

  StudioController get studio => widget.studio;

  @override
  void initState() {
    super.initState();
    studio.addListener(_showNotice);
  }

  @override
  void didUpdateWidget(StudioScreen old) {
    super.didUpdateWidget(old);
    if (old.studio != studio) {
      old.studio.removeListener(_showNotice);
      studio.addListener(_showNotice);
    }
  }

  @override
  void dispose() {
    studio.removeListener(_showNotice);
    _session?.dispose();
    super.dispose();
  }

  void _setSession(PlaySession? session) {
    final old = _session;
    setState(() => _session = session);
    old?.dispose();
  }

  void _play() => _setSession(PlaySession.play(studio.scene, version: studio.version));

  /// Watches a run ([whose]: "Giorgi's"), on the scene as it was when it was played.
  Future<void> _watch(String whose, int version, List<Segment> run) async {
    try {
      final scene = await studio.sceneAt(version);
      if (mounted) _setSession(PlaySession.watch(scene, run, version: version, whose: whose));
    } catch (e) {
      _toast('$e', bad: true);
    }
  }

  Future<void> _playtestWithAi() async {
    final error = await studio.playtestWithAi();
    if (!mounted) return;
    _toast(error ?? 'The AI is playing. Its report arrives in the team chat.', bad: error != null);
  }

  // Something the project refused: say it once.
  void _showNotice() {
    final notice = studio.notice;
    if (notice == null) return;
    studio.notice = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _toast(notice, bad: true);
    });
  }

  void _toast(String text, {bool bad = false}) {
    final c = context.sk;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 440,
      backgroundColor: c.foreground,
      content: Text(text, style: context.sans(size: SkTokens.textSmall, color: bad ? c.destructive : c.background)),
    ));
  }

  /// Going home with unsaved changes asks first. A shared project is saved by the server.
  Future<void> _home() async {
    if (!studio.dirty) return widget.onHome();
    final c = context.sk;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SkTokens.radiusBubble), side: BorderSide(color: c.border)),
        title: Text('Leave without saving?', style: context.sans(size: 16, weight: FontWeight.w600)),
        content: Text('Your changes to ${studio.scene.name} are not saved.', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground)),
        actions: [
          SkButton('Cancel', kind: SkButtonKind.ghost, onPressed: () => Navigator.of(context).pop(false)),
          SkButton('Leave', kind: SkButtonKind.secondary, onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (leave == true) widget.onHome();
  }

  Future<void> _open() async {
    if (studio.isShared) return _toast('To work on a saved file together, open it from the welcome screen: it becomes a new shared project.');
    try {
      final picked = await pickScene();
      if (picked == null) return;
      studio.load(picked.scene, path: picked.path);
      _canvasKey.currentState?.fit();
      _toast('Opened ${picked.scene.name}.');
    } on FormatException catch (e) {
      _toast(e.message, bad: true);
    } catch (_) {
      _toast('Could not open that file.', bad: true);
    }
  }

  Future<void> _save() async {
    try {
      final path = await saveScene(studio);
      if (path != null) _toast('Saved a copy to ${path.split('/').last}.');
    } catch (e) {
      _toast('Could not save: $e', bad: true);
    }
  }

  Future<void> _invite() async {
    final shared = studio.shared;
    if (shared == null) return;
    await Clipboard.setData(ClipboardData(text: 'Join my Skittles project: code ${shared.id} on ${shared.server.origin}'));
    _toast('Copied the invite: code ${shared.id} on ${shared.server.origin}.');
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
      },
      child: ListenableBuilder(
        listenable: studio,
        builder: (context, _) => Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                studio: studio,
                onHome: _home,
                onSave: _save,
                onInvite: _invite,
                playing: _session != null,
                onPlay: _session != null ? () => _setSession(null) : _play,
                onAiPlaytest: _playtestWithAi,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 248, child: StudioLeftColumn(studio: studio)),
                    Expanded(
                      child: _session != null
                          ? PlayView(
                              key: ObjectKey(_session),
                              session: _session!,
                              onStop: () => _setSession(null),
                              sceneChanged: _session!.version != studio.version,
                              onShare: studio.isShared && _session!.watching == null ? (note) => studio.shareRun(_session!.version, _session!.recorder.run, note: note) : null,
                            )
                          : Stack(
                              children: [
                                Positioned.fill(child: _SceneCanvas(key: _canvasKey, studio: studio)),
                                if (studio.scene.objects.isEmpty) Center(child: _EmptyScene(studio: studio, onExample: () => WidgetsBinding.instance.addPostFrameCallback((_) => _canvasKey.currentState?.fit()))),
                                Positioned(left: 0, right: 0, bottom: 16, child: Center(child: _Toolbar(studio: studio, onFit: () => _canvasKey.currentState?.fit()))),
                              ],
                            ),
                    ),
                    SizedBox(width: 320, child: StudioRightColumn(studio: studio, onWatch: _watch)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.studio, required this.onHome, required this.onSave, required this.onInvite, required this.playing, required this.onPlay, required this.onAiPlaytest});

  final StudioController studio;
  final VoidCallback onHome;
  final VoidCallback onSave;
  final VoidCallback onInvite;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onAiPlaytest;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final report = studio.report;
    final shared = studio.shared;
    final online = [for (final m in shared?.people ?? const []) if (m.online) m];
    final empty = studio.scene.objects.isEmpty;
    final hasPlayer = studio.scene.objects.any((o) => o.type == SceneObjectType.player);
    final hasFinish = hasPlayer && studio.scene.objects.any((o) => o.type == SceneObjectType.finish);
    return Container(
      height: SkTokens.sizeTopbar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          Tooltip(message: 'Home', child: Pressable(onPressed: onHome, builder: (context, s) => const BrandMark(size: 24))),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(child: Text(studio.scene.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: 15, weight: FontWeight.w600, spacing: -0.3))),
                if (studio.dirty) ...[const SizedBox(width: 8), Text('edited', style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground))],
                const SizedBox(width: 14),
                Flexible(flex: 2, child: empty ? const StatusPill('Empty scene', neutral: true) : StatusPill(report.label, ok: report.ok)),
                if (studio.isShared && !studio.connected) ...[const SizedBox(width: 10), Text('Reconnecting…', style: context.mono(size: SkTokens.textCaption, color: c.warning))],
                const SizedBox(width: 14),
              ],
            ),
          ),
          if (shared != null) ...[
            for (final m in online.take(5))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(message: m.id == shared.you ? '${m.name} (you)' : m.name, child: SkAvatar(letter: m.letter, color: m.color, size: 24)),
              ),
            if (online.length > 5) Padding(padding: const EdgeInsets.only(left: 6), child: Text('+${online.length - 5}', style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground))),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Copy the invite',
              child: SkButton('Invite · ${shared.id}', kind: SkButtonKind.secondary, icon: Icons.person_add_alt_1_outlined, onPressed: onInvite),
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(message: 'Save a copy (⌘S)', child: SkButton('', kind: SkButtonKind.ghost, icon: Icons.save_outlined, onPressed: onSave)),
          const SizedBox(width: 8),
          if (shared != null) ...[
            Tooltip(
              message: hasFinish ? 'The AI plays it and reviews it for the team' : 'The AI needs a player and a finish',
              child: SkButton('AI playtest', kind: SkButtonKind.secondary, icon: Icons.smart_toy_outlined, onPressed: hasFinish ? onAiPlaytest : null),
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: playing ? 'Back to editing (Esc)' : (hasPlayer ? 'Play it' : 'Add a player to play'),
            child: SkButton(playing ? 'Stop' : 'Play', kind: playing ? SkButtonKind.secondary : SkButtonKind.primary, icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded, onPressed: playing || hasPlayer ? onPlay : null),
          ),
        ],
      ),
    );
  }
}

/// The tools, floating under the canvas: select and hand, the five objects, then undo, redo and the view.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.studio, required this.onFit});

  final StudioController studio;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget button(IconData icon, String tip, VoidCallback? onTap, {bool on = false}) => Tooltip(
          message: tip,
          child: Pressable(
            onPressed: onTap,
            builder: (context, s) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: on ? c.foreground : (s.hovered ? c.muted : Colors.transparent),
                borderRadius: BorderRadius.circular(SkTokens.radiusControl),
                boxShadow: s.focused ? focusRing(c.background, c.foreground) : null,
              ),
              child: Icon(icon, size: 17, color: onTap == null ? c.mutedForeground.withValues(alpha: 0.4) : (on ? c.background : c.foreground)),
            ),
          ),
        );
    Widget gap() => Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 6), color: c.border);
    Widget tool(StudioTool t) => button(_toolIcons[t]!, '${t.label} (${t.key})', () => studio.setTool(t), on: studio.tool == t);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(SkTokens.radiusPanel),
        border: Border.all(color: c.border),
        boxShadow: dark ? SkTokens.shadowLgDark : SkTokens.shadowLgLight,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tool(StudioTool.select),
          tool(StudioTool.pan),
          gap(),
          for (final t in StudioTool.values.where((t) => t.creates != null)) tool(t),
          gap(),
          button(Icons.undo_rounded, 'Undo (⌘Z)', studio.canUndo ? studio.undo : null),
          button(Icons.redo_rounded, 'Redo (⇧⌘Z)', studio.canRedo ? studio.redo : null),
          gap(),
          button(Icons.grid_4x4_rounded, 'Grid (G)', studio.toggleGrid, on: studio.showGrid),
          button(Icons.alt_route_rounded, 'Show what the player can reach (R)', studio.toggleReach, on: studio.showReach),
          button(Icons.fit_screen_outlined, 'Fit the scene (0)', onFit),
        ],
      ),
    );
  }
}

/// A new project: describe the game to your agent, start from the example, or place things by hand.
class _EmptyScene extends StatefulWidget {
  const _EmptyScene({required this.studio, required this.onExample});

  final StudioController studio;
  final VoidCallback onExample;

  @override
  State<_EmptyScene> createState() => _EmptySceneState();
}

class _EmptySceneState extends State<_EmptyScene> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _error = null);
    final error = await widget.studio.askAgent(text);
    if (!mounted) return;
    if (error == null) _text.clear();
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final studio = widget.studio;
    final me = studio.shared?.me;
    final working = me?.agent.thinking ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Arrive(
      child: Container(
        width: 460,
        margin: const EdgeInsets.all(24),
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
              const Icon(Icons.auto_awesome, size: 16, color: SkTokens.brand),
              const SizedBox(width: 8),
              Text('Describe your game', style: context.sans(size: 16, weight: FontWeight.w600, spacing: -0.2)),
            ]),
            const SizedBox(height: 6),
            Text(
              studio.isShared ? 'Your agent builds it with checked actions, and everyone in the project sees it happen.' : 'Agents need a shared project on a Skittles server. You can still build by hand.',
              style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5),
            ),
            const SizedBox(height: 14),
            if (working)
              Row(children: [
                TypingDots(color: me!.color),
                const SizedBox(width: 12),
                Expanded(child: Text('Your agent is building it…', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground))),
              ])
            else if (studio.isShared)
              Row(children: [
                Expanded(child: SkTextField(controller: _text, placeholder: 'A desert level with three ledges and a few coins', height: 34, onSubmitted: (_) => _build())),
                const SizedBox(width: 8),
                SkButton('Build', height: 34, onPressed: _build),
              ]),
            if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: context.sans(size: SkTokens.textSecondary, color: c.destructive, height: 1.4))],
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SkButton('Start from the forest example', kind: SkButtonKind.ghost, height: 26, onPressed: () {
                  studio.startFrom(starterScene());
                  widget.onExample();
                }),
                Text('or pick a tool below and click the scene', style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The scene canvas: click to place with a creation tool or to select, drag to move, drag the corner handle to
/// resize, scroll to pan, pinch or ⌘-scroll to zoom. Keys work while the canvas has focus (click it).
class _SceneCanvas extends StatefulWidget {
  const _SceneCanvas({super.key, required this.studio});

  final StudioController studio;

  @override
  State<_SceneCanvas> createState() => _SceneCanvasState();
}

enum _DragMode { none, move, resize, pan }

class _SceneCanvasState extends State<_SceneCanvas> {
  final _focus = FocusNode(debugLabel: 'scene canvas');
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _size = Size.zero;
  bool _fitted = false;
  String? _hover;
  _DragMode _mode = _DragMode.none;
  Offset _dragStartWorld = Offset.zero;
  Offset _dragStartPan = Offset.zero;
  bool _spaceDown = false;
  double _pinchScale = 1;

  /// Whether the person has panned or zoomed. Until then the scene keeps fitting the canvas as it resizes.
  bool _userMoved = false;

  StudioController get studio => widget.studio;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void fit() {
    if (_size.isEmpty) return;
    final scene = studio.scene;
    _userMoved = false;
    setState(() {
      _zoom = ((_size.width - 64) / scene.width).clamp(0.1, 4.0);
      _zoom = _zoom < (_size.height - 64) / scene.height ? _zoom : ((_size.height - 64) / scene.height).clamp(0.1, 4.0);
      _pan = Offset((_size.width - scene.width * _zoom) / 2, (_size.height - scene.height * _zoom) / 2);
    });
  }

  Offset _toWorld(Offset screen) => (screen - _pan) / _zoom;

  /// Teammates who are here, where they point and what they have selected.
  List<RemoteMark> _remote() {
    final shared = studio.shared;
    if (shared == null) return const [];
    return [
      for (final e in shared.presence.entries)
        if (shared.members[e.key]?.online ?? false) RemoteMark(name: shared.members[e.key]!.name, color: shared.members[e.key]!.color, cursor: e.value.cursor, selectedId: e.value.selected),
    ];
  }

  SceneObject? _hit(Offset world) {
    for (final o in studio.scene.objects.reversed) {
      if (o.rect.inflate(3 / _zoom).contains(world)) return o;
    }
    return null;
  }

  bool _onHandle(Offset world) {
    final s = studio.selected;
    return s != null && (world - s.rect.bottomRight).distance < 9 / _zoom;
  }

  void _zoomAt(Offset screen, double factor) {
    final before = _toWorld(screen);
    _userMoved = true;
    setState(() {
      _zoom = (_zoom * factor).clamp(0.1, 4.0);
      _pan = screen - before * _zoom;
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.space) {
      _spaceDown = e is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final meta = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = e.logicalKey;
    if (meta && k == LogicalKeyboardKey.keyZ) {
      shift ? studio.redo() : studio.undo();
      return KeyEventResult.handled;
    }
    if (meta) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      studio.deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      studio
        ..select(null)
        ..setTool(StudioTool.select);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyG) {
      studio.toggleGrid();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyR) {
      studio.toggleReach();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.digit0) {
      fit();
      return KeyEventResult.handled;
    }
    // Arrow keys nudge the selection by one grid step.
    final s = studio.selected;
    final nudge = {
      LogicalKeyboardKey.arrowLeft: const Offset(-StudioController.gridStep, 0),
      LogicalKeyboardKey.arrowRight: const Offset(StudioController.gridStep, 0),
      LogicalKeyboardKey.arrowUp: const Offset(0, -StudioController.gridStep),
      LogicalKeyboardKey.arrowDown: const Offset(0, StudioController.gridStep),
    }[k];
    if (nudge != null && s != null) {
      studio
        ..beginDrag()
        ..dragTo(nudge)
        ..endDrag();
      return KeyEventResult.handled;
    }
    for (final t in StudioTool.values) {
      if (k.keyLabel.toUpperCase() == t.key) {
        studio.setTool(t);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return LayoutBuilder(
      builder: (context, box) {
        if (box.biggest != _size) {
          final grew = box.biggest - _size as Offset;
          _size = box.biggest;
          if (!_fitted || !_userMoved) {
            // Not moved by hand yet: fit the scene to the new size.
            _fitted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => fit());
          } else {
            // Moved by hand: keep the same part of the scene in the middle.
            _pan += grew / 2;
          }
        }
        final creating = studio.tool.creates != null;
        final panning = studio.tool == StudioTool.pan || _spaceDown || _mode == _DragMode.pan;
        final cursor = panning
            ? SystemMouseCursors.grab
            : creating
                ? SystemMouseCursors.precise
                : _mode == _DragMode.resize
                    ? SystemMouseCursors.resizeDownRight
                    : _hover != null
                        ? SystemMouseCursors.move
                        : SystemMouseCursors.basic;
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _key,
          child: Listener(
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                final meta = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
                if (meta) {
                  _zoomAt(signal.localPosition, signal.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
                } else {
                  _userMoved = true;
                  setState(() => _pan -= signal.scrollDelta);
                }
              }
            },
            // The trackpad: two fingers pan, a pinch zooms around the fingers. e.scale is the total since the gesture
            // began, so the zoom follows the change since the last update.
            onPointerPanZoomStart: (_) => _pinchScale = 1,
            onPointerPanZoomUpdate: (e) {
              final factor = e.scale / _pinchScale;
              _pinchScale = e.scale;
              _userMoved = true;
              setState(() => _pan += e.panDelta);
              if (factor != 1) _zoomAt(e.localPosition, factor);
            },
            child: MouseRegion(
              cursor: cursor,
              onHover: (e) {
                final world = _toWorld(e.localPosition);
                final over = _hit(world)?.id;
                if (over != _hover) setState(() => _hover = over);
                studio.pointAt(studio.scene.bounds.contains(world) ? world : null);
              },
              onExit: (_) {
                setState(() => _hover = null);
                studio.pointAt(null);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Report a drag from where the button went down, not from where it passed the drag threshold, so a
                // small object grabbed near its edge is still hit and follows the pointer exactly.
                dragStartBehavior: DragStartBehavior.down,
                // Two-finger trackpad gestures pan and zoom (the Listener above); they never drag objects.
                supportedDevices: const {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
                onTapDown: (_) => _focus.requestFocus(),
                onTapUp: (e) {
                  final world = _toWorld(e.localPosition);
                  final type = studio.tool.creates;
                  if (type != null) {
                    if (studio.scene.bounds.contains(world)) studio.place(type, world);
                  } else if (studio.tool == StudioTool.select) {
                    studio.select(_hit(world)?.id);
                  }
                },
                onPanStart: (e) {
                  _focus.requestFocus();
                  final world = _toWorld(e.localPosition);
                  _dragStartWorld = world;
                  _dragStartPan = _pan;
                  if (panning) {
                    _mode = _DragMode.pan;
                  } else if (studio.tool == StudioTool.select && _onHandle(world)) {
                    _mode = _DragMode.resize;
                    studio.beginDrag();
                  } else if (studio.tool == StudioTool.select) {
                    final hit = _hit(world);
                    if (hit != null) {
                      studio.select(hit.id);
                      _mode = _DragMode.move;
                      studio.beginDrag();
                    } else {
                      _mode = _DragMode.pan; // dragging empty space pans
                    }
                  }
                  setState(() {});
                },
                onPanUpdate: (e) {
                  switch (_mode) {
                    case _DragMode.pan:
                      _userMoved = true;
                      setState(() => _pan = _dragStartPan + (e.localPosition - (_dragStartWorld * _zoom + _dragStartPan)));
                    case _DragMode.move:
                      studio.dragTo(_toWorld(e.localPosition) - _dragStartWorld);
                    case _DragMode.resize:
                      studio.resizeTo(_toWorld(e.localPosition) - _dragStartWorld);
                    case _DragMode.none:
                      break;
                  }
                },
                onPanEnd: (_) {
                  if (_mode == _DragMode.move || _mode == _DragMode.resize) studio.endDrag();
                  setState(() => _mode = _DragMode.none);
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: ScenePainter(
                    scene: studio.scene,
                    report: studio.report,
                    zoom: _zoom,
                    pan: _pan,
                    backdrop: c.muted,
                    mono: context.skFonts.mono,
                    selectedId: studio.selectedId,
                    hoverId: _hover,
                    showGrid: studio.showGrid,
                    showReach: studio.showReach && studio.scene.objects.isNotEmpty,
                    remote: _remote(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
