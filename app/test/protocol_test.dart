// The app's models against a session recorded from the real room code (spec/fixtures/protocol/session.json,
// written by server/scripts/record-protocol.ts): every event parses, and replaying them builds the right state.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/net/models.dart';
import 'package:skittles/net/room_client.dart';
import 'package:skittles/net/room_store.dart';

void main() {
  final session = jsonDecode(File('../spec/fixtures/protocol/session.json').readAsStringSync()) as Map<String, dynamic>;
  final events = (session['events'] as List).cast<Map<String, dynamic>>();
  final ids = (session['members'] as Map).cast<String, String>();

  test('the join snapshot parses', () {
    final s = Snapshot.fromJson(session['snapshot'] as Map<String, dynamic>);
    expect(s.you.name, 'Nino');
    expect(s.you.role, Role.author);
    expect(s.members.map((m) => m.name), containsAll(['Nino', 'Giorgi', 'Luka', 'Stage']));
    expect(s.state.rev, 4);
    expect(s.state.solve.solvable, isTrue);
    expect(s.state.solve.label, startsWith('Winnable · '));
    expect(s.log, hasLength(4));
    expect(s.log.last.revertTo, 1);
    expect(s.chats[ids['nino']], isNotEmpty);
    expect(s.play.deaths, 2);
  });

  test('every recorded event parses through the store', () {
    final store = RoomStore();
    for (final e in events) {
      final kept = store.handle(e['type'] as String, e['payload']);
      expect(kept, e['type'] != 'reset', reason: 'event ${e['type']}');
    }
  });

  test('replaying the session builds the state the room ended with', () {
    final store = RoomStore();
    for (final e in events) {
      store.handle(e['type'] as String, e['payload']);
    }
    expect(store.members, hasLength(4));
    expect(store.log.map((l) => l.rev), [1, 2, 3, 4]);
    // v2 is Giorgi's statue together with the mediator's bridge, approved by Nino.
    expect(store.log[1].fix?.approvedBy, [ids['nino']]);
    final proposal = store.proposals.values.single;
    expect(proposal.status, ProposalStatus.done);
    expect(proposal.options.map((o) => o.kind), [FixKind.bridge, FixKind.agent, FixKind.cancel]);
    expect(proposal.options[1].from, ids['nino']);
    expect(proposal.approvals, {ids['nino']: true});
    final report = store.reports.values.single;
    expect(report.kind, ReportKind.signal);
    expect(report.fallsHere, 2);
    expect(report.routedTo, [ids['nino']]);
    expect(store.suggestions.values.single.status, SuggestionStatus.open);
    expect(store.play!.deaths, 2);
    expect(store.chats[ids['giorgi']]!.any((m) => m.from == ChatFrom.mediator), isTrue);
    expect(store.chats[ids['nino']]!.any((m) => m.from == ChatFrom.playtest), isTrue);
  });

  test('an agent answer ends its thinking', () {
    final store = RoomStore()..startThinking(ids['nino']!);
    final answer = events.firstWhere((e) => e['type'] == 'chat' && (e['payload'] as Map)['from'] == 'agent' && (e['payload'] as Map)['authorId'] == ids['nino']);
    store.handle('chat', answer['payload']);
    expect(store.thinking, isEmpty);
  });

  test('every submit result maps to its type', () {
    final results = (session['results'] as Map).cast<String, Map<String, dynamic>>();
    expect(SubmitResult.fromJson(results['committed']!), isA<Committed>().having((r) => r.rev, 'rev', 1));
    expect(SubmitResult.fromJson(results['conflict']!), isA<Conflict>().having((r) => r.proposal.diagnosis.unreachable, 'unreachable', ['flag']));
    expect(SubmitResult.fromJson(results['awaiting_approval']!), isA<AwaitingApproval>());
    expect(SubmitResult.fromJson(results['rejected']!), isA<Rejected>().having((r) => r.code, 'code', 'unknown_id'));
    expect(SubmitResult.fromJson(results['deferred']!), isA<Deferred>());
    expect(SubmitResult.fromJson(results['revert']!), isA<Committed>().having((r) => r.rev, 'rev', 4));
  });

  test('broadcasts lose the recovery offset Socket.IO appends', () {
    final member = {'id': 'author-1', 'name': 'Nino', 'role': 'author', 'letter': 'A', 'color': '#3b82f6'};
    expect(RoomClient.payloadOf([
      [member],
      'offset-1',
    ]), [member]);
    expect(RoomClient.payloadOf([{'rev': 1}, 'offset-2']), {'rev': 1});
    // Without recovery the payload comes through untouched, even a list of two members.
    expect(RoomClient.payloadOf([member, member]), [member, member]);
    expect(RoomClient.payloadOf({'rev': 1}), {'rev': 1});
  });

  test('an unknown status is an error, not a silent default', () {
    expect(() => SubmitResult.fromJson({'status': 'teleported'}), throwsFormatException);
  });
}
