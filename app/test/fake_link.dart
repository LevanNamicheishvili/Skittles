// A project link for widget tests: answers every request with {ok: true} (or what [answers] says), remembers what
// was sent, and lets the test play the project's events.

import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/studio_link.dart';

class FakeLink extends StudioLink {
  FakeLink([this.answers = const {}]);

  final Map<String, Map<String, dynamic>> answers;
  final requests = <(String, Map<String, dynamic>)>[];
  final sent = <(String, Map<String, dynamic>)>[];

  /// The join answer, set by [shared].
  Map<String, dynamic>? join;

  @override
  Future<Map<String, dynamic>> request(String event, [Map<String, dynamic> data = const {}]) async {
    if (event == 'join') return join!;
    requests.add((event, data));
    return answers[event] ?? {'ok': true};
  }

  @override
  void send(String event, Map<String, dynamic> data) => sent.add((event, data));

  @override
  Future<void> close() async {}

  void emit(String event, Object? data) => onEvent?.call(event, data);

  List<Map<String, dynamic>> sentAs(String event) => [for (final r in requests) if (r.$1 == event) r.$2];
}

Map<String, dynamic> member(String id, String name, String color, {bool online = true, Map<String, dynamic> agent = const {'status': 'idle', 'queued': 0}}) =>
    {'id': id, 'name': name, 'color': color, 'online': online, 'agent': agent};

/// A project with Nino (you), Giorgi and Ana: a team chat where Giorgi asked Nino's agent for coins, and Nino's
/// thread with that request and a held change. Giorgi's agent is working.
Map<String, dynamic> teamSnapshot(Scene scene) => {
      'ok': true,
      'project': 'k3x9ab',
      'you': 'm1',
      'version': 3,
      'scene': scene.toJson(),
      'history': {'canUndo': true, 'canRedo': false},
      'members': [
        member('m1', 'Nino', '#3b82f6'),
        member('m2', 'Giorgi', '#f97316', agent: {'status': 'thinking', 'task': 'make the right ground a lava pit', 'for': 'm2', 'queued': 0}),
        member('m3', 'Ana', '#10b981', online: false),
      ],
      'team': [
        {'id': 't1', 'kind': 'chat', 'from': 'm2', 'text': "Let's make the second half harder.", 'at': 1},
        {'id': 't2', 'kind': 'chat', 'from': 'm2', 'text': "@Nino's agent add two coins above Ledge C", 'agents': ['m1'], 'at': 2},
        {
          'id': 't3',
          'kind': 'agent',
          'from': 'm1',
          'for': 'm2',
          'text': 'Added two coins above Ledge C.',
          'task': 'k2',
          'notes': ['+ Coin 3 at (880, 480)', '+ Coin 4 at (960, 480)'],
          'outcome': 'applied',
          'change': 2,
          'at': 3,
        },
        {'id': 't4', 'kind': 'chat', 'from': 'm1', 'text': "Nice. I'll do the enemies.", 'at': 4},
      ],
      'threads': {
        'm1': [
          {'id': 'h1', 'owner': 'm1', 'from': 'member', 'by': 'm2', 'viaTeam': true, 'text': 'add two coins above Ledge C', 'task': 'k2', 'at': 2},
          {'id': 'h2', 'owner': 'm1', 'from': 'agent', 'text': 'Added two coins above Ledge C.', 'task': 'k2', 'notes': ['+ Coin 3 at (880, 480)', '+ Coin 4 at (960, 480)'], 'outcome': 'applied', 'change': 2, 'at': 3},
          {'id': 'h3', 'owner': 'm1', 'from': 'member', 'by': 'm1', 'text': 'put the finish up on Ledge C', 'task': 'k3', 'at': 5},
          {'id': 'h4', 'owner': 'm1', 'from': 'agent', 'text': 'Moved the finish onto Ledge C.', 'task': 'k3', 'notes': ['~ Moved Finish to (900, 420)'], 'outcome': 'held', 'reason': 'The finish cannot be reached.', 'at': 6},
        ],
      },
    };
