// The welcome screen, laid out like Conductor's onboarding: the SKITTLES block wordmark on top, three features on
// the left (one lit, advancing on their own, click to pick), a live preview of the lit one on the right with a
// progress bar, and the way in. Skittles for Mac is a 2D game studio: tools and AI, together. Always dark.

import 'dart:async';

import 'package:flutter/material.dart';

import '../game/model.dart';
import '../game/solver.dart';
import '../net/models.dart';
import '../net/projects_api.dart';
import '../net/room_client.dart';
import '../ui/kit.dart';
import '../ui/kit/live_sky.dart';
import '../ui/kit/pixel_wordmark.dart';
import '../ui/level_map.dart';

/// Opens the studio. Answers with a message for the screen when it could not.
typedef OpenStudio = Future<String?> Function({required String server, required String name, String? project});

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.client,
    this.server = 'http://localhost:3001',
    this.name = '',
    this.autoRole,
    this.onNewProject,
    this.onOpenProject,
    this.onJoinProject,
    this.findProjects = listOpenProjects,
  });

  /// The projects someone is in right now on a server, listed so a second window can join its team in one click.
  final Future<List<OpenProject>> Function(String server) findProjects;

  final RoomClient client;

  /// A new shared project, one from a saved file, and a teammate's project by its code.
  final OpenStudio? onNewProject;
  final OpenStudio? onOpenProject;
  final OpenStudio? onJoinProject;
  final String server;
  final String name;

  /// Joins straight away with this role, like the web's ?role= links.
  final Role? autoRole;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

typedef _Feature = ({String title, String body});

const _features = <_Feature>[
  (title: 'Build any 2D game, with tools and AI', body: "Draw with the editor's tools, or tell your agent what you want. Both make the same checked changes."),
  (title: 'Create together, live', body: 'Everyone brings their own agent. See who is building what, as it happens.'),
  (title: 'Never break the game', body: 'A solver proves every change. When two changes collide, you pick from fixes it has already checked.'),
];

class _ConnectScreenState extends State<ConnectScreen> with SingleTickerProviderStateMixin {
  late final _server = TextEditingController(text: widget.server);
  late final _name = TextEditingController(text: widget.name);
  final _code = TextEditingController();

  /// Projects with people in them on the server, refreshed every few seconds.
  List<OpenProject> _here = const [];
  Timer? _poll;
  Role? _joining;

  /// What is being opened ('new', 'open' or 'join'), and why it could not be.
  String? _opening;
  String? _error;
  int _feature = 0;

  // Each feature shows for 6 s, then the next one lights up.
  late final AnimationController _progress = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _feature = (_feature + 1) % _features.length);
        _progress.forward(from: 0);
      }
    });

  @override
  void initState() {
    super.initState();
    final role = widget.autoRole;
    if (role != null) WidgetsBinding.instance.addPostFrameCallback((_) => _join(role));
    if (widget.onJoinProject != null) {
      _findProjects();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _findProjects());
    }
  }

  Future<void> _findProjects() async {
    final found = await widget.findProjects(_server.text.trim());
    if (!mounted) return;
    final same = found.length == _here.length && [for (var i = 0; i < found.length; i++) found[i].id == _here[i].id && found[i].people.join() == _here[i].people.join()].every((x) => x);
    if (!same) setState(() => _here = found);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _progress.value = 1;
      _progress.stop();
    } else if (!_progress.isAnimating) {
      _progress.forward(from: _progress.value == 1 ? 0 : _progress.value);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _progress.dispose();
    _server.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  void _pick(int index) {
    setState(() => _feature = index);
    if (!reducedMotion(context)) _progress.forward(from: 0);
  }

  /// [project]: a project picked from the list; otherwise the code typed or pasted (the whole invite works too).
  Future<void> _studio(String kind, OpenStudio? open, {String? project}) async {
    final name = _name.text.trim();
    final code = project ?? projectCode(_code.text);
    String? error;
    if (open == null) return;
    if (name.isEmpty) {
      error = 'Type your name first: your team sees it, and your agent is named after you.';
    } else if (kind == 'join' && code.isEmpty) {
      error = "Type the project code your teammate sent you.";
    }
    if (error != null) return setState(() => _error = error);
    setState(() {
      _opening = kind;
      _error = null;
    });
    final failed = await open(server: _server.text.trim(), name: name, project: kind == 'join' ? code : null);
    if (mounted) {
      setState(() {
        _opening = null;
        _error = failed;
      });
    }
  }

  Future<void> _join(Role role) async {
    final name = role == Role.stage && _name.text.trim().isEmpty ? 'Stage' : _name.text.trim();
    if (name.isEmpty) {
      widget.client.store.setConnection(widget.client.store.connection, error: 'Type your name first.');
      return;
    }
    setState(() => _joining = role);
    try {
      await widget.client.connectAndJoin(_server.text.trim(), name, role);
    } catch (_) {
      // The store holds the message; the screen shows it.
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(data: skTheme(Brightness.dark, fonts: context.skFonts), child: Builder(builder: _page));
  }

  Widget _page(BuildContext context) {
    final c = context.sk;
    // Short windows (down to the 720px minimum) get a smaller wordmark and tighter spacing, so the way in stays
    // on screen.
    final compact = MediaQuery.sizeOf(context).height < 840;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.55, child: LiveSky(clear: (size) => Rect.fromLTRB(40, 200, size.width - 40, size.height)))),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(48, compact ? 24 : 36, 48, compact ? 20 : 36),
                  // The wordmark, tagline and the two columns sit together, centred as one block.
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PixelWordmark(height: compact ? 72 : 96),
                      SizedBox(height: compact ? 12 : 18),
                      Text(
                        'The multiplayer 2D game studio: build any 2D game with tools and AI, together.',
                        textAlign: TextAlign.center,
                        style: context.sans(size: SkTokens.textLede, color: c.mutedForeground),
                      ),
                      SizedBox(height: compact ? 20 : 40),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 470),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 45, child: _left(context)),
                              const SizedBox(width: 48),
                              Expanded(flex: 55, child: _right(context)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _left(BuildContext context) {
    final c = context.sk;
    final store = widget.client.store;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _features.length; i++) _FeatureRow(feature: _features[i], lit: i == _feature, compact: MediaQuery.sizeOf(context).height < 840, onTap: () => _pick(i)),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 4, child: SkTextField(controller: _name, placeholder: 'Your name', height: 32, onSubmitted: (_) => _studio('new', widget.onNewProject))),
                      const SizedBox(width: 8),
                      Expanded(flex: 5, child: SkTextField(controller: _server, placeholder: 'http://localhost:3001', height: 32)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: SkButton(_opening == 'new' ? 'Creating…' : 'Start creating', arrow: true, height: SkTokens.sizeCta, onPressed: _opening == null ? () => _studio('new', widget.onNewProject) : null)),
                      const SizedBox(width: 10),
                      Expanded(child: SkButton(_opening == 'open' ? 'Opening…' : 'Open project…', kind: SkButtonKind.secondary, height: SkTokens.sizeCta, onPressed: _opening == null ? () => _studio('open', widget.onOpenProject) : null)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("JOIN YOUR TEAM'S PROJECT", style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground, spacing: 0.66)),
                  const SizedBox(height: 8),
                  // At most two, so the smallest window still shows the code field and the demo room below.
                  for (final p in _here.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _OpenProjectRow(project: p, busy: _opening != null, onJoin: () => _studio('join', widget.onJoinProject, project: p.id)),
                    ),
                  Row(
                    children: [
                      Expanded(child: SkTextField(controller: _code, placeholder: _here.isEmpty ? 'Project code from Invite' : 'Or paste a project code', height: 32, onSubmitted: (_) => _studio('join', widget.onJoinProject))),
                      const SizedBox(width: 8),
                      SkButton(_opening == 'join' ? 'Joining…' : 'Join', kind: SkButtonKind.secondary, onPressed: _opening == null ? () => _studio('join', widget.onJoinProject) : null),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Grid demo room:', style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground)),
                      SkButton(_joining == Role.author ? 'Connecting…' : 'Join', kind: SkButtonKind.ghost, height: 24, onPressed: _joining == null ? () => _join(Role.author) : null),
                      SkButton(_joining == Role.player ? 'Connecting…' : 'Playtest', kind: SkButtonKind.ghost, height: 24, onPressed: _joining == null ? () => _join(Role.player) : null),
                      SkButton(_joining == Role.stage ? 'Connecting…' : 'Stage screen', kind: SkButtonKind.ghost, height: 24, onPressed: _joining == null ? () => _join(Role.stage) : null),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Arrive(child: Text(_error!, style: context.sans(size: SkTokens.textSmall, color: c.destructive, height: 1.4))),
                  ],
                  if (store.error != null) ...[
                    const SizedBox(height: 10),
                    Arrive(child: Text(store.error!, style: context.sans(size: SkTokens.textSmall, color: c.destructive, height: 1.4))),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _right(BuildContext context) {
    final c = context.sk;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: AspectRatio(
            aspectRatio: 16 / 11,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(SkTokens.radiusPanel),
                border: Border.all(color: c.border),
                boxShadow: const [BoxShadow(color: Color(0xB3000000), offset: Offset(0, 30), blurRadius: 80, spreadRadius: -20)],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: AnimatedBuilder(
                  key: ValueKey(_feature),
                  animation: _progress,
                  builder: (context, _) => _Preview(feature: _feature, t: _progress.value),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // The progress bar under the preview, as in the reference.
        AnimatedBuilder(
          animation: _progress,
          builder: (context, _) => Container(
            height: 3,
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ((_feature + _progress.value) / _features.length).clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(color: c.foreground.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ),
      ],
    );
  }
}

/// A project someone is in right now: its name, who is there, and Join.
class _OpenProjectRow extends StatelessWidget {
  const _OpenProjectRow({required this.project, required this.busy, required this.onJoin});

  final OpenProject project;
  final bool busy;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final people = project.people.length <= 2 ? project.people.join(' and ') : '${project.people.take(2).join(', ')} and ${project.people.length - 2} more';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(SkTokens.radiusControl), border: Border.all(color: c.border)),
      child: Row(
        children: [
          LiveDot(color: c.positive),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: project.name, style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w600)),
                TextSpan(text: '  ·  $people here now', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SkButton('Join', height: 28, onPressed: busy ? null : onJoin),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature, required this.lit, required this.onTap, this.compact = false});

  final _Feature feature;
  final bool lit;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Pressable(
      onPressed: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 12 : 18),
        decoration: BoxDecoration(
          color: lit ? Color.alphaBlend(Colors.white.withValues(alpha: 0.09), c.background) : (s.hovered ? c.muted : Colors.transparent),
          borderRadius: BorderRadius.circular(SkTokens.radiusPanel),
          boxShadow: s.focused ? focusRing(c.background, c.foreground) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(feature.title, style: context.sans(size: 17, weight: FontWeight.w500, color: lit ? c.foreground : c.foreground.withValues(alpha: 0.85), height: 1.35)),
            // On short windows only the lit feature says more, so the way in below stays on screen.
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topLeft,
              child: compact && !lit
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(feature.body, style: context.sans(size: SkTokens.textLede, color: c.mutedForeground, height: 1.5)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// The previews: a small Skittles window acting out each feature, driven by the feature's progress t (0..1).

const _nino = Color(0xFF3B82F6);
const _giorgi = Color(0xFFF97316);
const _ana = Color(0xFF10B981);
const _dato = Color(0xFFE11D48);

Owner _by(String id) => Owner(OwnerKind.player, id);
const _people = {'nino': _nino, 'giorgi': _giorgi, 'ana': _ana, 'dato': _dato};
Color? _ownerColor(Entity e) => _people[e.owner.playerId];

final _river = [
  Entity(id: 'R1', type: EntityType.lava, owner: _by('nino'), x: 11, y: 1, w: 2, h: 3),
  Entity(id: 'R2', type: EntityType.lava, owner: _by('nino'), x: 11, y: 5, w: 2, h: 8),
];
final _statue = Entity(id: 'G1', type: EntityType.wall, owner: _by('giorgi'), x: 11, y: 4, w: 2, h: 1);
const _bridge = Entity(id: 'M1', type: EntityType.bridge, owner: Owner(OwnerKind.mediator), x: 11, y: 7, w: 2, h: 1);

typedef _Scene = ({World world, List<Entity> ghosts, Map<String, Color> highlight, bool blocked, List<(String, Color)> chips});

class _Preview extends StatelessWidget {
  const _Preview({required this.feature, required this.t});

  final int feature;
  final double t;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final scene = switch (feature) {
      0 => _tools(),
      1 => _together(),
      _ => _conflict(),
    };
    final solved = solve(scene.world);
    // While a change is held, the ghost runs the old route and the route shows red.
    final route = scene.blocked ? solve(demoWorld(_river)).path : solved.path;
    final status = scene.blocked ? 'Blocked · flag unreachable' : 'Winnable · ${solved.steps} steps';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(
            children: [
              for (final dot in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)]) ...[
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 6),
              const BrandMark(size: 16),
              const SizedBox(width: 10),
              StatusPill(status, ok: !scene.blocked),
              const Spacer(),
              for (final (name, color) in scene.chips) ...[const SizedBox(width: 6), SkAvatar(letter: name[0], color: color, size: 20, online: true)],
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (feature == 0) _ToolPalette(active: t < 0.45 ? 1 : (t < 0.7 ? 0 : 2)),
              Expanded(
                child: Container(
                  color: c.muted,
                  padding: const EdgeInsets.all(14),
                  child: Stack(
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: 24 / 14,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final cell = box.maxWidth / 24;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: LevelMapPainter(
                                        world: scene.world,
                                        route: route,
                                        routeColor: scene.blocked ? const Color(0xFFF87171) : const Color(0xD9FFFFFF),
                                        ownerColor: _ownerColor,
                                        ghosts: scene.ghosts,
                                        ghostColor: _giorgi,
                                        highlight: scene.highlight,
                                      ),
                                    ),
                                  ),
                                  for (final cursor in _cursors()) _CursorMark(cursor: cursor, cell: cell),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      ..._overlays(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _phase(double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

  // Feature 1: a wall drawn with the tool, then a river from the agent.
  _Scene _tools() {
    final wallLength = 1 + (_phase(0.05, 0.4) * 6).round();
    return (
      world: demoWorld([
        Entity(id: 'W1', type: EntityType.wall, owner: _by('nino'), x: 3, y: 10, w: wallLength, h: 1),
        if (t >= 0.72) ..._river,
      ]),
      ghosts: const [],
      highlight: {
        if (t < 0.45) 'W1': _nino,
        if (t >= 0.72 && t < 0.9) for (final r in _river) r.id: _nino,
      },
      blocked: false,
      chips: const [('Nino', _nino)],
    );
  }

  // Feature 2: four people building at once.
  _Scene _together() {
    const coins = [19, 20, 21];
    return (
      world: demoWorld([
        ..._river,
        if (t >= 0.3) for (final x in coins) Entity(id: 'C$x', type: EntityType.coin, owner: _by('ana'), x: x, y: 3),
        if (t >= 0.55) Entity(id: 'D1', type: EntityType.wall, owner: _by('dato'), x: 15, y: 2, w: 3, h: 2),
        if (t >= 0.75) Entity(id: 'G2', type: EntityType.wall, owner: _by('giorgi'), x: 3, y: 10, w: 4, h: 1),
      ]),
      ghosts: const [],
      highlight: {
        if (t >= 0.3 && t < 0.5) for (final x in coins) 'C$x': _ana,
        if (t >= 0.55 && t < 0.75) 'D1': _dato,
        if (t >= 0.75) 'G2': _giorgi,
      },
      blocked: false,
      chips: const [('Nino', _nino), ('Giorgi', _giorgi), ('Ana', _ana), ('Dato', _dato)],
    );
  }

  // Feature 3: the statue lands in the gap, the room holds it, a checked bridge fixes it.
  _Scene _conflict() {
    final held = t >= 0.22 && t < 0.66;
    final fixed = t >= 0.66;
    return (
      world: demoWorld([..._river, if (fixed) ...[_statue, _bridge]]),
      ghosts: held ? [_statue] : const [],
      highlight: fixed && t < 0.85 ? {'M1': const Color(0xFFA78BFA), 'G1': _giorgi} : const {},
      blocked: held,
      chips: const [('Nino', _nino), ('Giorgi', _giorgi)],
    );
  }

  List<_Cursor> _cursors() {
    Offset lerp(Offset a, Offset b, double k) => Offset.lerp(a, b, Curves.easeInOut.transform(k))!;
    switch (feature) {
      case 0:
        return [_Cursor('Nino', _nino, t < 0.45 ? Offset(3.0 + _phase(0.05, 0.4) * 6, 10.4) : lerp(const Offset(9, 10.4), const Offset(11.6, 6), _phase(0.5, 0.7)))];
      case 1:
        return [
          _Cursor('Nino', _nino, lerp(const Offset(11.6, 6), const Offset(12, 11), _phase(0, 1))),
          _Cursor('Ana', _ana, lerp(const Offset(14, 6), const Offset(20.5, 3.4), _phase(0.05, 0.3))),
          _Cursor('Dato', _dato, lerp(const Offset(20, 10), const Offset(16.4, 3), _phase(0.3, 0.55))),
          _Cursor('Giorgi', _giorgi, lerp(const Offset(8, 4), const Offset(5, 10.4), _phase(0.55, 0.75))),
        ];
      default:
        return [
          _Cursor('Giorgi', _giorgi, lerp(const Offset(6, 9), const Offset(12, 4.4), _phase(0, 0.22))),
          if (t >= 0.4) _Cursor('Nino', _nino, lerp(const Offset(16, 11), const Offset(12, 7.4), _phase(0.4, 0.62))),
        ];
    }
  }

  List<Widget> _overlays(BuildContext context) {
    switch (feature) {
      case 0:
        return [
          if (t >= 0.45)
            Positioned(
              right: 0,
              bottom: 0,
              width: 270,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const ChatBubble('Add a lava river down the middle, leave one gap.', kind: BubbleKind.you),
                  const SizedBox(height: 6),
                  if (t >= 0.52 && t < 0.72) const ChatBubble('Thinking…', kind: BubbleKind.thinking),
                  if (t >= 0.72) const ChatBubble('Done. Still winnable, 27 steps.'),
                ],
              ),
            ),
        ];
      case 2:
        return [
          if (t >= 0.36)
            Positioned(
              right: 0,
              bottom: 0,
              width: 280,
              child: ToneCard(
                tone: Tone.mediator,
                label: 'Mediator',
                children: [
                  OptionRow(title: 'Build a stone bridge', detail: 'checked: the shortest route', picked: t >= 0.56),
                  if (t >= 0.66) Text('✓ Nino approved · v3 is live', style: context.mono(size: SkTokens.textCaption, color: context.sk.positive)),
                ],
              ),
            ),
        ];
      default:
        return const [];
    }
  }
}

class _Cursor {
  const _Cursor(this.name, this.color, this.at);
  final String name;
  final Color color;
  final Offset at;
}

class _CursorMark extends StatelessWidget {
  const _CursorMark({required this.cursor, required this.cell});

  final _Cursor cursor;
  final double cell;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: cursor.at.dx * cell,
      top: cursor.at.dy * cell,
      child: IgnorePointer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: const Size(12, 16), painter: _Arrow(cursor.color)),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: cursor.color, borderRadius: BorderRadius.circular(4)),
                child: Text("${cursor.name}'s agent", style: context.sans(size: 10, weight: FontWeight.w600, color: Colors.white, height: 1.2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Arrow extends CustomPainter {
  const _Arrow(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width * 0.32, size.height * 0.72)
      ..lineTo(size.width * 0.62, size.height)
      ..lineTo(size.width * 0.8, size.height * 0.9)
      ..lineTo(size.width * 0.5, size.height * 0.62)
      ..lineTo(size.width, size.height * 0.62)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_Arrow old) => old.color != color;
}

/// The editor's tools, down the left of the first preview.
class _ToolPalette extends StatelessWidget {
  const _ToolPalette({required this.active});

  final int active;

  static const _tools = [
    Icons.near_me_outlined,
    Icons.crop_square_rounded,
    Icons.local_fire_department_outlined,
    Icons.view_week_outlined,
    Icons.fort_outlined,
    Icons.key_outlined,
    Icons.circle_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: Column(
        children: [
          for (var i = 0; i < _tools.length; i++)
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(color: i == active ? c.foreground : Colors.transparent, borderRadius: BorderRadius.circular(SkTokens.radiusControl)),
              child: Icon(_tools[i], size: 18, color: i == active ? c.background : c.mutedForeground),
            ),
        ],
      ),
    );
  }
}
