// What the room sends, as typed Dart. Mirrors server/src/room/room.ts, mediator.ts and playtest.ts; the
// recorded session in spec/fixtures/protocol/session.json is parsed by test/protocol_test.dart. Ops stay as
// JSON maps until the board needs them (phase C).

import 'dart:ui' show Color;

import '../game/model.dart';

typedef Json = Map<String, dynamic>;
typedef OpJson = Map<String, dynamic>;

/// "awaiting_approval" → awaitingApproval, matched against an enum's names.
T _enum<T extends Enum>(List<T> values, Object? raw) {
  final name = (raw as String).replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
  return values.firstWhere((v) => v.name == name, orElse: () => throw FormatException('unknown ${T.toString()} "$raw"'));
}

List<T> _list<T>(Object? raw, T Function(Json) parse) => [for (final e in (raw as List? ?? const [])) parse(e as Json)];
List<String> _strings(Object? raw) => [for (final e in (raw as List? ?? const [])) e as String];
List<OpJson> _ops(Object? raw) => [for (final e in (raw as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
Cell _cell(Object? raw) => (x: (raw as Json)['x'] as int, y: raw['y'] as int);
DateTime _time(Object? ms) => DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());

Color _hex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse(h.length == 6 ? 'ff$h' : h, radix: 16));
}

enum Role { author, player, stage }

class Member {
  const Member({required this.id, required this.name, required this.role, required this.letter, required this.color});

  factory Member.fromJson(Json j) => Member(
        id: j['id'] as String,
        name: j['name'] as String,
        role: _enum(Role.values, j['role']),
        letter: j['letter'] as String,
        color: _hex(j['color'] as String),
      );

  final String id;
  final String name;
  final Role role;
  final String letter;
  final Color color;
}

class SolveSummary {
  const SolveSummary({required this.solvable, this.steps, this.path, required this.unreachable});

  factory SolveSummary.fromJson(Json j) => SolveSummary(
        solvable: j['solvable'] as bool,
        steps: j['steps'] as int?,
        path: j['path'] == null ? null : [for (final d in j['path'] as List) _enum(Direction.values, d)],
        unreachable: _strings(j['unreachable']),
      );

  final bool solvable;
  final int? steps;
  final List<Direction>? path;
  final List<String> unreachable;

  /// The status line the site shows: "Winnable · 21 steps" or "Blocked · flag unreachable".
  String get label => solvable ? 'Winnable · $steps steps' : 'Blocked · ${unreachable.join(', ')} unreachable';
}

/// The `state` event: the live level, its version and the solver's verdict.
class RoomState {
  const RoomState({required this.world, required this.rev, required this.solve, required this.deferred, required this.solveMs});

  factory RoomState.fromJson(Json j) => RoomState(
        world: World.fromJson(j['world'] as Json),
        rev: j['rev'] as int,
        solve: SolveSummary.fromJson(j['solve'] as Json),
        deferred: j['deferred'] as int,
        solveMs: (j['solveMs'] as num).toDouble(),
      );

  final World world;
  final int rev;
  final SolveSummary solve;

  /// Changes waiting for the playtester to step away.
  final int deferred;
  final double solveMs;
}

class LogFix {
  const LogFix({required this.summary, required this.ops, required this.approvedBy});

  factory LogFix.fromJson(Json j) => LogFix(summary: j['summary'] as String, ops: _ops(j['ops']), approvedBy: _strings(j['approvedBy']));

  final String summary;
  final List<OpJson> ops;
  final List<String> approvedBy;
}

class LogEntry {
  const LogEntry({required this.rev, required this.at, required this.by, required this.summary, required this.ops, this.fix, this.revertTo});

  factory LogEntry.fromJson(Json j) => LogEntry(
        rev: j['rev'] as int,
        at: _time(j['at']),
        by: j['by'] as String,
        summary: j['summary'] as String,
        ops: _ops(j['ops']),
        fix: j['fix'] == null ? null : LogFix.fromJson(j['fix'] as Json),
        revertTo: j['revertTo'] as int?,
      );

  final int rev;
  final DateTime at;
  final String by;
  final String summary;
  final List<OpJson> ops;
  final LogFix? fix;
  final int? revertTo;
}

enum ChatFrom { you, agent, system, mediator, playtest }

class ChatMessage {
  const ChatMessage({required this.id, required this.authorId, required this.from, required this.text, required this.at, this.proposalId, this.reportId, this.suggestionId});

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: j['id'] as String,
        authorId: j['authorId'] as String,
        from: _enum(ChatFrom.values, j['from']),
        text: j['text'] as String,
        at: _time(j['at']),
        proposalId: j['proposalId'] as String?,
        reportId: j['reportId'] as String?,
        suggestionId: j['suggestionId'] as String?,
      );

  final String id;

  /// Whose chat this belongs to.
  final String authorId;
  final ChatFrom from;
  final String text;
  final DateTime at;
  final String? proposalId;
  final String? reportId;
  final String? suggestionId;
}

class Blocker {
  const Blocker({required this.id, required this.type, this.ownerId});

  factory Blocker.fromJson(Json j) => Blocker(id: j['id'] as String, type: _enum(EntityType.values, j['type']), ownerId: j['ownerId'] as String?);

  final String id;
  final EntityType type;
  final String? ownerId;
}

class Diagnosis {
  const Diagnosis({required this.unreachable, required this.blockers, required this.closedBy});

  factory Diagnosis.fromJson(Json j) => Diagnosis(
        unreachable: _strings(j['unreachable']),
        blockers: _list(j['blockers'], Blocker.fromJson),
        closedBy: _list(j['closedBy'], Blocker.fromJson),
      );

  final List<String> unreachable;

  /// What stands in the way of every route.
  final List<Blocker> blockers;

  /// What the change put on the route that used to work.
  final List<Blocker> closedBy;
}

enum FixKind { bridge, move, key, cancel, agent }

class FixOption {
  const FixOption({required this.id, required this.kind, this.from, required this.title, required this.detail, required this.ops, required this.touches});

  factory FixOption.fromJson(Json j) => FixOption(
        id: j['id'] as String,
        kind: _enum(FixKind.values, j['kind']),
        from: j['from'] as String?,
        title: j['title'] as String,
        detail: j['detail'] as String,
        ops: _ops(j['ops']),
        touches: _strings(j['touches']),
      );

  final String id;
  final FixKind kind;

  /// For an agent's compromise: the author whose agent proposed it.
  final String? from;
  final String title;
  final String detail;
  final List<OpJson> ops;

  /// Authors whose objects this fix covers or changes; each must approve.
  final List<String> touches;
}

enum ProposalStatus { open, awaitingApproval, done }

/// A held conflict and its fixes.
class Proposal {
  const Proposal({
    required this.id,
    required this.requesterId,
    required this.summary,
    required this.ops,
    required this.diagnosis,
    required this.text,
    required this.options,
    required this.status,
    required this.negotiating,
    this.chosen,
    required this.approvals,
  });

  factory Proposal.fromJson(Json j) => Proposal(
        id: j['id'] as String,
        requesterId: j['requesterId'] as String,
        summary: j['summary'] as String,
        ops: _ops(j['ops']),
        diagnosis: Diagnosis.fromJson(j['diagnosis'] as Json),
        text: j['text'] as String,
        options: _list(j['options'], FixOption.fromJson),
        status: _enum(ProposalStatus.values, j['status']),
        negotiating: _strings(j['negotiating']),
        chosen: j['chosen'] as String?,
        approvals: {for (final e in (j['approvals'] as Json).entries) e.key: e.value as bool?},
      );

  final String id;
  final String requesterId;
  final String summary;
  final List<OpJson> ops;
  final Diagnosis diagnosis;
  final String text;
  final List<FixOption> options;
  final ProposalStatus status;

  /// Authors whose agents are working on a compromise right now.
  final List<String> negotiating;
  final String? chosen;

  /// Owner id → answer, null while waiting.
  final Map<String, bool?> approvals;
}

class Fall {
  const Fall({required this.x, required this.y, required this.rev, required this.at});

  factory Fall.fromJson(Json j) => Fall(x: j['x'] as int, y: j['y'] as int, rev: j['rev'] as int, at: _time(j['at']));

  final int x;
  final int y;
  final int rev;
  final DateTime at;
}

/// The `play` event: the playtester as everyone sees them.
class PlayState {
  const PlayState({required this.x, required this.y, required this.keys, required this.collected, required this.deaths, required this.won, required this.trail, required this.falls});

  factory PlayState.fromJson(Json j) => PlayState(
        x: j['x'] as int,
        y: j['y'] as int,
        keys: [for (final k in j['keys'] as List) _enum(GameColor.values, k)],
        collected: _strings(j['collected']),
        deaths: j['deaths'] as int,
        won: j['won'] as bool,
        trail: [for (final c in j['trail'] as List) _cell(c)],
        falls: _list(j['falls'], Fall.fromJson),
      );

  final int x;
  final int y;
  final List<GameColor> keys;
  final List<String> collected;
  final int deaths;
  final bool won;
  final List<Cell> trail;
  final List<Fall> falls;
}

class Suspect {
  const Suspect({required this.id, required this.type, this.ownerId, this.mediator = false, this.label, required this.distance});

  factory Suspect.fromJson(Json j) => Suspect(
        id: j['id'] as String,
        type: _enum(EntityType.values, j['type']),
        ownerId: j['ownerId'] as String?,
        mediator: j['mediator'] as bool? ?? false,
        label: j['label'] as String?,
        distance: (j['distance'] as num).toDouble(),
      );

  final String id;
  final EntityType type;
  final String? ownerId;
  final bool mediator;
  final String? label;
  final double distance;
}

enum ReportKind { player, signal }

class PlaytestReport {
  const PlaytestReport({
    required this.id,
    required this.by,
    required this.kind,
    required this.text,
    required this.at,
    required this.rev,
    required this.spot,
    required this.position,
    required this.keys,
    required this.fallsHere,
    required this.falls,
    required this.trail,
    required this.suspects,
    required this.routedTo,
  });

  factory PlaytestReport.fromJson(Json j) => PlaytestReport(
        id: j['id'] as String,
        by: j['by'] as String,
        kind: _enum(ReportKind.values, j['kind']),
        text: j['text'] as String,
        at: _time(j['at']),
        rev: j['rev'] as int,
        spot: _cell(j['spot']),
        position: _cell(j['position']),
        keys: [for (final k in j['keys'] as List) _enum(GameColor.values, k)],
        fallsHere: j['fallsHere'] as int,
        falls: j['falls'] as int,
        trail: [for (final c in j['trail'] as List) _cell(c)],
        suspects: _list(j['suspects'], Suspect.fromJson),
        routedTo: _strings(j['routedTo']),
      );

  final String id;
  final String by;

  /// A playtester's own report, or dev mode's signal after repeated falls.
  final ReportKind kind;
  final String text;
  final DateTime at;
  final int rev;
  final Cell spot;
  final Cell position;
  final List<GameColor> keys;
  final int fallsHere;
  final int falls;
  final List<Cell> trail;
  final List<Suspect> suspects;
  final List<String> routedTo;
}

enum SuggestionStatus { drafting, open, applied, dismissed, failed }

class Suggestion {
  const Suggestion({required this.id, required this.authorId, required this.reportId, required this.status, this.message, this.summary, this.ops, this.note});

  factory Suggestion.fromJson(Json j) => Suggestion(
        id: j['id'] as String,
        authorId: j['authorId'] as String,
        reportId: j['reportId'] as String,
        status: _enum(SuggestionStatus.values, j['status']),
        message: j['message'] as String?,
        summary: j['summary'] as String?,
        ops: j['ops'] == null ? null : _ops(j['ops']),
        note: j['note'] as String?,
      );

  final String id;
  final String authorId;
  final String reportId;
  final SuggestionStatus status;
  final String? message;
  final String? summary;
  final List<OpJson>? ops;
  final String? note;
}

/// The answer to `join`: everything a client needs to draw the room.
class Snapshot {
  const Snapshot({
    required this.you,
    required this.members,
    required this.state,
    required this.log,
    required this.chats,
    required this.proposals,
    required this.reports,
    required this.suggestions,
    required this.play,
  });

  factory Snapshot.fromJson(Json j) => Snapshot(
        you: Member.fromJson(j['you'] as Json),
        members: _list(j['members'], Member.fromJson),
        state: RoomState.fromJson(j['state'] as Json),
        log: _list(j['log'], LogEntry.fromJson),
        chats: {for (final e in (j['chats'] as Json).entries) e.key: _list(e.value, ChatMessage.fromJson)},
        proposals: _list(j['proposals'], Proposal.fromJson),
        reports: _list(j['reports'], PlaytestReport.fromJson),
        suggestions: _list(j['suggestions'], Suggestion.fromJson),
        play: PlayState.fromJson(j['play'] as Json),
      );

  final Member you;
  final List<Member> members;
  final RoomState state;
  final List<LogEntry> log;
  final Map<String, List<ChatMessage>> chats;
  final List<Proposal> proposals;
  final List<PlaytestReport> reports;
  final List<Suggestion> suggestions;
  final PlayState play;
}

/// What the room answers to a change, a fix choice, an approval or a restore.
sealed class SubmitResult {
  const SubmitResult();

  factory SubmitResult.fromJson(Json j) => switch (j['status']) {
        'committed' => Committed(j['rev'] as int),
        'deferred' => const Deferred(),
        'conflict' => Conflict(Proposal.fromJson(j['proposal'] as Json)),
        'awaiting_approval' => AwaitingApproval(Proposal.fromJson(j['proposal'] as Json)),
        'rejected' => Rejected(j['code'] as String, j['message'] as String? ?? ''),
        final other => throw FormatException('unknown submit status "$other"'),
      };
}

class Committed extends SubmitResult {
  const Committed(this.rev);
  final int rev;
}

class Deferred extends SubmitResult {
  const Deferred();
}

class Conflict extends SubmitResult {
  const Conflict(this.proposal);
  final Proposal proposal;
}

class AwaitingApproval extends SubmitResult {
  const AwaitingApproval(this.proposal);
  final Proposal proposal;
}

class Rejected extends SubmitResult {
  const Rejected(this.code, this.message);
  final String code;
  final String message;
}
