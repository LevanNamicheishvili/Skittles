// A shared project as the studio sees it (server/src/studio/project.ts): the members and their agents, the team
// chat, each member's thread with their agent, and where everyone is pointing. The scene itself lives in the
// StudioController; this holds the people around it.

import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';

import 'play.dart';

enum Outcome { applied, held, approved, discarded, undone, failed }

Outcome? _outcome(Object? v) => Outcome.values.where((o) => o.name == v).firstOrNull;
List<String> _strings(Object? v) => [for (final s in (v as List?) ?? const []) s as String];

Color _hex(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

class AgentStatus {
  const AgentStatus({this.thinking = false, this.task, this.forId, this.queued = 0});

  factory AgentStatus.fromJson(Map<String, dynamic> j) =>
      AgentStatus(thinking: j['status'] == 'thinking', task: j['task'] as String?, forId: j['for'] as String?, queued: (j['queued'] as num?)?.toInt() ?? 0);

  final bool thinking;
  final String? task;

  /// Who the request it is working on came from.
  final String? forId;
  final int queued;
}

class Member {
  const Member({required this.id, required this.name, required this.color, this.online = true, this.agent = const AgentStatus()});

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'] as String,
        name: j['name'] as String,
        color: _hex(j['color'] as String),
        online: j['online'] as bool? ?? false,
        agent: AgentStatus.fromJson(((j['agent'] as Map?) ?? const {}).cast<String, dynamic>()),
      );

  final String id;
  final String name;
  final Color color;
  final bool online;
  final AgentStatus agent;

  String get letter => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
  String get agentName => "$name's agent";
}

/// One problem or idea from the AI playtester: the objects behind it and the people who made them.
class PlaytestNote {
  const PlaytestNote({required this.text, required this.problem, this.objects = const [], this.owners = const []});

  factory PlaytestNote.fromJson(Map<String, dynamic> j) =>
      PlaytestNote(text: j['text'] as String? ?? '', problem: j['kind'] != 'idea', objects: _strings(j['objects']), owners: _strings(j['owners']));

  final String text;
  final bool problem;
  final List<String> objects;
  final List<String> owners;
}

/// A playtest: a person's shared run, or the AI's.
class Playtest {
  const Playtest({required this.status, required this.version, this.result, this.run = const [], this.note, this.finished, this.coinsMissed = const [], this.summary, this.issues = const []});

  factory Playtest.fromJson(Map<String, dynamic> j) => Playtest(
        status: j['status'] as String? ?? 'done',
        version: (j['version'] as num?)?.toInt() ?? 0,
        result: j['result'] == null ? null : RunResult.fromJson((j['result'] as Map).cast<String, dynamic>()),
        run: segmentsFromJson(j['run']),
        note: j['note'] as String?,
        finished: j['finished'] as bool?,
        coinsMissed: _strings(j['coinsMissed']),
        summary: j['summary'] as String?,
        issues: [for (final i in (j['issues'] as List?) ?? const []) PlaytestNote.fromJson((i as Map).cast<String, dynamic>())],
      );

  /// "playing", "done" or "failed".
  final String status;
  final int version;
  final RunResult? result;
  final List<Segment> run;
  final String? note;
  final bool? finished;
  final List<String> coinsMissed;
  final String? summary;
  final List<PlaytestNote> issues;
}

/// A line in the team chat: what someone wrote, an agent reporting what it did, or a playtest.
class TeamMessage {
  const TeamMessage({required this.id, required this.kind, required this.from, required this.text, this.agents = const [], this.forId, this.task, this.notes = const [], this.outcome, this.reason, this.change, this.undoneBy, this.playtest});

  factory TeamMessage.fromJson(Map<String, dynamic> j) => TeamMessage(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'chat',
        playtest: j['playtest'] == null ? null : Playtest.fromJson((j['playtest'] as Map).cast<String, dynamic>()),
        from: j['from'] as String,
        text: j['text'] as String? ?? '',
        agents: _strings(j['agents']),
        forId: j['for'] as String?,
        task: j['task'] as String?,
        notes: _strings(j['notes']),
        outcome: _outcome(j['outcome']),
        reason: j['reason'] as String?,
        change: (j['change'] as num?)?.toInt(),
        undoneBy: j['undoneBy'] as String?,
      );

  final String id;

  /// "chat", "agent" (an agent's report) or "playtest".
  final String kind;
  bool get agent => kind == 'agent';
  final Playtest? playtest;

  /// The member who wrote it; for a report, the agent's owner; "ai" for the AI's playtest.
  final String from;
  final String text;

  /// A chat message: the owners of the agents it asks.
  final List<String> agents;

  /// A report: who asked.
  final String? forId;
  final String? task;
  final List<String> notes;
  final Outcome? outcome;
  final String? reason;
  final int? change;
  final String? undoneBy;
}

/// A line in one member's thread with their agent.
class ThreadMessage {
  const ThreadMessage({required this.id, required this.owner, required this.from, required this.text, this.by, this.viaTeam = false, this.task, this.notes = const [], this.outcome, this.reason, this.change, this.undoneBy});

  factory ThreadMessage.fromJson(Map<String, dynamic> j) => ThreadMessage(
        id: j['id'] as String,
        owner: j['owner'] as String,
        from: j['from'] as String,
        text: j['text'] as String? ?? '',
        by: j['by'] as String?,
        viaTeam: j['viaTeam'] as bool? ?? false,
        task: j['task'] as String?,
        notes: _strings(j['notes']),
        outcome: _outcome(j['outcome']),
        reason: j['reason'] as String?,
        change: (j['change'] as num?)?.toInt(),
        undoneBy: j['undoneBy'] as String?,
      );

  final String id;
  final String owner;

  /// "member", "agent" or "system".
  final String from;
  final String text;

  /// A member's message: who wrote it, the owner or a teammate.
  final String? by;
  final bool viaTeam;
  final String? task;
  final List<String> notes;
  final Outcome? outcome;
  final String? reason;
  final int? change;
  final String? undoneBy;
}

/// Where a teammate is pointing (scene pixels) and what they have selected.
class Presence {
  const Presence({this.cursor, this.selected});

  final Offset? cursor;
  final String? selected;
}

/// Everyone in the project and what they say, kept up to date from the project's events.
class SharedProject extends ChangeNotifier {
  SharedProject({required this.id, required this.server, required this.you});

  final String id;
  final Uri server;
  final String you;

  final Map<String, Member> members = {};
  final List<TeamMessage> team = [];
  final Map<String, List<ThreadMessage>> threads = {};
  final Map<String, Presence> presence = {};

  /// Messages that arrived since each tab was last looked at.
  int unreadTeam = 0;
  int unreadMine = 0;

  Member? get me => members[you];
  List<ThreadMessage> get myThread => threads[you] ?? const [];

  /// The members, you first.
  List<Member> get people => [?members[you], for (final m in members.values) if (m.id != you) m];

  String nameOf(String? id) {
    if (id == null) return 'someone';
    if (id.startsWith('agent:')) return "${nameOf(id.substring(6))}'s agent";
    return members[id]?.name ?? 'someone';
  }

  Color colorOf(String? id) => members[id?.replaceFirst('agent:', '')]?.color ?? const Color(0xFF64748B);

  void load(Map<String, dynamic> snapshot) {
    members
      ..clear()
      ..addEntries([for (final m in (snapshot['members'] as List? ?? const [])) Member.fromJson((m as Map).cast<String, dynamic>())].map((m) => MapEntry(m.id, m)));
    team
      ..clear()
      ..addAll([for (final m in (snapshot['team'] as List? ?? const [])) TeamMessage.fromJson((m as Map).cast<String, dynamic>())]);
    threads.clear();
    for (final e in ((snapshot['threads'] as Map?) ?? const {}).entries) {
      threads[e.key as String] = [for (final m in e.value as List) ThreadMessage.fromJson((m as Map).cast<String, dynamic>())];
    }
    notifyListeners();
  }

  /// Applies one of the project's events (not the scene's own changes, which the studio handles).
  void handle(String type, Object? data) {
    switch (type) {
      case 'members':
        members
          ..clear()
          ..addEntries([for (final m in data as List) Member.fromJson((m as Map).cast<String, dynamic>())].map((m) => MapEntry(m.id, m)));
        for (final m in members.values) {
          if (!m.online) presence.remove(m.id);
        }
      case 'team':
        final m = TeamMessage.fromJson((data as Map).cast<String, dynamic>());
        final i = team.indexWhere((x) => x.id == m.id);
        if (i >= 0) {
          team[i] = m;
        } else {
          team.add(m);
          if (m.from != you || m.kind != 'chat') unreadTeam++;
        }
      case 'thread':
        final m = ThreadMessage.fromJson((data as Map).cast<String, dynamic>());
        final list = threads.putIfAbsent(m.owner, () => []);
        final i = list.indexWhere((x) => x.id == m.id);
        if (i >= 0) {
          list[i] = m;
        } else {
          list.add(m);
          if (m.owner == you && !(m.from == 'member' && m.by == you)) unreadMine++;
        }
      case 'presence':
        final j = (data as Map).cast<String, dynamic>();
        final member = j['member'] as String;
        if (member == you) return;
        final c = j['cursor'] as Map?;
        presence[member] = Presence(cursor: c == null ? null : Offset((c['x'] as num).toDouble(), (c['y'] as num).toDouble()), selected: j['selected'] as String?);
      default:
        return;
    }
    notifyListeners();
  }

  void readTeam() {
    if (unreadTeam == 0) return;
    unreadTeam = 0;
    notifyListeners();
  }

  void readMine() {
    if (unreadMine == 0) return;
    unreadMine = 0;
    notifyListeners();
  }
}
