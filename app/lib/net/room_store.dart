// The room as this client knows it. Every server event lands in [handle], the way web/src/net.ts folds events
// into its store; screens listen to it. Pure state: the socket lives in RoomClient.

import 'package:flutter/foundation.dart';

import 'models.dart';

enum Connection { idle, connecting, connected, offline }

class RoomStore extends ChangeNotifier {
  Connection connection = Connection.idle;

  /// Why the last connection attempt failed, in words for the connect screen.
  String? error;

  Member? you;
  List<Member> members = const [];
  RoomState? state;
  List<LogEntry> log = const [];
  Map<String, List<ChatMessage>> chats = const {};
  Map<String, Proposal> proposals = const {};
  Map<String, PlaytestReport> reports = const {};
  Map<String, Suggestion> suggestions = const {};
  PlayState? play;

  /// Authors whose agent is working on a request.
  Set<String> thinking = const {};

  /// When the latest log entry arrived, for the change highlight.
  DateTime? lastLogAt;

  bool get joined => you != null && state != null;

  void setConnection(Connection value, {String? error}) {
    connection = value;
    this.error = error;
    notifyListeners();
  }

  void applySnapshot(Snapshot s) {
    you = s.you;
    members = s.members;
    state = s.state;
    log = s.log;
    chats = s.chats;
    proposals = {for (final p in s.proposals) p.id: p};
    reports = {for (final r in s.reports) r.id: r};
    suggestions = {for (final g in s.suggestions) g.id: g};
    play = s.play;
    thinking = const {};
    notifyListeners();
  }

  /// Folds one server event into the state. Returns false for events this store does not keep (`reset` is
  /// handled by the client, which joins again).
  bool handle(String event, Object? payload) {
    final j = payload is Map ? Map<String, dynamic>.from(payload) : null;
    switch (event) {
      case 'state':
        state = RoomState.fromJson(j!);
      case 'log':
        log = [...log, LogEntry.fromJson(j!)];
        lastLogAt = DateTime.now();
      case 'members':
        members = [for (final m in payload as List) Member.fromJson(Map<String, dynamic>.from(m as Map))];
      case 'play':
        play = PlayState.fromJson(j!);
      case 'proposal':
        final p = Proposal.fromJson(j!);
        proposals = {...proposals, p.id: p};
      case 'report':
        final r = PlaytestReport.fromJson(j!);
        reports = {...reports, r.id: r};
      case 'suggestion':
        final g = Suggestion.fromJson(j!);
        suggestions = {...suggestions, g.id: g};
      case 'chat':
        final m = ChatMessage.fromJson(j!);
        chats = {...chats, m.authorId: [...?chats[m.authorId], m]};
        // Any answer in an author's chat means their agent has finished thinking.
        if (m.from != ChatFrom.you) thinking = {...thinking}..remove(m.authorId);
      default:
        return false;
    }
    notifyListeners();
    return true;
  }

  /// Marks an author's agent as working, until its answer arrives in their chat.
  void startThinking(String authorId) {
    thinking = {...thinking, authorId};
    notifyListeners();
  }

  void clear() {
    you = null;
    members = const [];
    state = null;
    log = const [];
    chats = const {};
    proposals = const {};
    reports = const {};
    suggestions = const {};
    play = null;
    thinking = const {};
    lastLogAt = null;
    connection = Connection.idle;
    error = null;
    notifyListeners();
  }

  Member? member(String? id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }
}
