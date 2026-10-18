// Runs the shared cases in spec/fixtures/scene_runs.json against the Dart game.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/play.dart';
import 'package:skittles/studio/scene.dart';

void main() {
  final cases = ((jsonDecode(File('../spec/fixtures/scene_runs.json').readAsStringSync()) as Map)['cases'] as List).cast<Map<String, dynamic>>();
  for (final c in cases) {
    test(c['name'], () {
      final game = Game(Scene.fromJson(c['scene'] as Map<String, dynamic>));
      final flat = [for (final s in c['run'] as List) for (var i = 0; i < (s[0] as num); i++) (s[1] as num).toInt()];
      var done = 0;
      for (final check in (c['checks'] as List).cast<Map<String, dynamic>>()) {
        final after = (check['after'] as num).toInt();
        while (done < after) {
          game.step(done < flat.length ? flat[done] : 0);
          done++;
        }
        final state = <String, Object?>{
          'frame': game.frame,
          'x': game.x,
          'y': game.y,
          'vx': game.vx,
          'vy': game.vy,
          'grounded': game.grounded,
          'score': game.score,
          'coins': game.coins,
          'deaths': game.deaths,
          'won': game.won,
          'enemies': {for (final e in game.enemies) e.id: enemyX(e, game.frame)},
        };
        for (final e in (check['expect'] as Map<String, dynamic>).entries) {
          final got = state[e.key];
          if (e.value is num) {
            expect(got as num, closeTo(e.value as num, 1e-6), reason: '${e.key} after $after');
          } else if (e.key == 'enemies') {
            for (final en in (e.value as Map).entries) {
              expect((got as Map)[en.key] as num, closeTo(en.value as num, 1e-6), reason: '${en.key} after $after');
            }
          } else {
            expect(got, e.value, reason: '${e.key} after $after');
          }
        }
      }
    });
  }

  test('a recorded run plays back the same inputs', () {
    final recorder = RunRecorder();
    for (final bits in [0, 0, 2, 2, 2, 6, 2]) {
      recorder.add(bits);
    }
    expect(recorder.run, [(2, 0), (3, 2), (1, 6), (1, 2)]);
    final player = RunPlayer(recorder.run);
    expect([for (var i = 0; i < 9; i++) player.next()], [0, 0, 2, 2, 2, 6, 2, 0, 0]);
    expect(player.done, isTrue);
  });
}
