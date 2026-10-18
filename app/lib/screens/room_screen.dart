// The room, phase B: the site's top bar (status, version, members) and the live state, all updated by the room's
// events. The level shows as a flat preview from the shared Dart rules until phase C ports the 2.5D board.

import 'package:flutter/material.dart';

import '../net/models.dart';
import '../net/room_client.dart';
import '../net/room_store.dart';
import '../ui/kit.dart';
import '../ui/level_map.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.client, required this.onLeave});

  final RoomClient client;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: client.store,
      builder: (context, _) {
        final store = client.store;
        final state = store.state;
        if (state == null || store.you == null) return const Scaffold();
        return Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(store: store, state: state, onLeave: onLeave),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _Stage(store: store, state: state)),
                      const SizedBox(width: 16),
                      SizedBox(width: 380, child: _Side(store: store, state: state)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.store, required this.state, required this.onLeave});

  final RoomStore store;
  final RoomState state;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final online = store.connection == Connection.connected;
    return Container(
      height: SkTokens.sizeTopbar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          const BrandMark(size: 24),
          const SizedBox(width: 8),
          Text('Skittles', style: context.sans(size: 15, weight: FontWeight.w600, spacing: -0.375)),
          const SizedBox(width: 16),
          Flexible(child: StatusPill(state.solve.label, ok: state.solve.solvable)),
          const SizedBox(width: 12),
          VersionBadge('v${state.rev}'),
          if (state.deferred > 0) ...[
            const SizedBox(width: 12),
            LiveDot(color: c.warning),
            const SizedBox(width: 8),
            Text('${state.deferred} change waiting for the player to step away', style: context.sans(size: SkTokens.textSmall, color: c.warning)),
          ],
          const Spacer(),
          ...() {
            final people = store.members.where((m) => m.role != Role.stage).toList();
            return [
              for (final m in people.take(4)) ...[PresenceChip(name: m.name, letter: m.letter, color: m.color), const SizedBox(width: 8)],
              if (people.length > 4) ...[
                Tooltip(
                  message: people.skip(4).map((m) => m.name).join(', '),
                  child: Container(
                    height: SkTokens.sizeCompact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(SkTokens.radiusPill), border: Border.all(color: c.border)),
                    child: Text('+${people.length - 4}', style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w500, color: c.mutedForeground)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ];
          }(),
          const SizedBox(width: 4),
          Tooltip(message: online ? 'Connected' : 'Reconnecting…', child: LiveDot(color: online ? c.positive : c.destructive)),
          const SizedBox(width: 12),
          SkButton('Leave', kind: SkButtonKind.ghost, onPressed: onLeave),
        ],
      ),
    );
  }
}

/// The level as a flat map: terrain from the shared rules, objects outlined in their author's colour, the solver's
/// route, the start, the flag and the playtester.
class _Stage extends StatelessWidget {
  const _Stage({required this.store, required this.state});

  final RoomStore store;
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(SkTokens.radiusPanel), border: Border.all(color: c.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LEVEL PREVIEW · THE 2.5D BOARD ARRIVES IN PHASE C', style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground, spacing: 0.55)),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: state.world.width / state.world.height,
                child: CustomPaint(
                  painter: LevelMapPainter(
                    world: state.world,
                    route: state.solve.path,
                    player: store.play == null ? null : (x: store.play!.x, y: store.play!.y),
                    ownerColor: (e) => store.member(e.owner.playerId)?.color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.store, required this.state});

  final RoomStore store;
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final you = store.you!;
    final play = store.play;
    final roleName = switch (you.role) {
      Role.author => 'creator',
      Role.player => 'playtester',
      Role.stage => 'stage screen',
    };
    final facts = <(String, String)>[
      ('Level', '${state.world.width} × ${state.world.height} · ${state.world.entities.length} objects'),
      ('Validator', '${state.solveMs.toStringAsFixed(2)} ms'),
      if (play != null) ('Playtester', '(${play.x}, ${play.y}) · ${play.deaths} falls${play.won ? ' · finished' : ''}'),
      (
        'Server',
        switch (store.connection) {
          Connection.connected => 'connected',
          Connection.connecting => 'connecting…',
          Connection.offline => 'reconnecting…',
          Connection.idle => 'not connected',
        },
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkPanel(
          title: 'You',
          leading: SkAvatar(letter: you.letter, color: you.color),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${you.name}, $roleName', style: context.sans(weight: FontWeight.w500)),
              const SizedBox(height: 10),
              for (final (label, value) in facts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 84, child: Text(label, style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground))),
                      Expanded(child: Text(value, style: context.mono(size: SkTokens.textSecondary))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SkPanel(
            title: 'History',
            trailing: Text('${store.log.length} versions', style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)),
            padding: EdgeInsets.zero,
            expand: true,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _HistoryRow(rev: 0, summary: 'Prepared level', current: state.rev == 0),
                for (final entry in store.log)
                  _HistoryRow(rev: entry.rev, summary: entry.summary, fix: entry.fix?.summary, author: store.member(entry.by), current: entry.rev == state.rev),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.rev, required this.summary, this.fix, this.author, required this.current});

  final int rev;
  final String summary;
  final String? fix;
  final Member? author;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Arrive(
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: current ? c.muted : null, borderRadius: BorderRadius.circular(SkTokens.radiusControl)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 32, child: Text('v$rev', style: context.mono(size: SkTokens.textSecondary, color: c.mutedForeground))),
            if (author != null) ...[SkAvatar(letter: author!.letter, color: author!.color, size: 18), const SizedBox(width: 8)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary, style: context.sans(size: SkTokens.textSmall, height: 1.4)),
                  if (fix != null) Text('+ $fix', style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
