// Runs the shared fixtures in spec/fixtures against the Dart rules.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:team_ai_game/game/model.dart';
import 'package:team_ai_game/game/play.dart';
import 'package:team_ai_game/game/raster.dart';
import 'package:team_ai_game/game/solver.dart';
import 'package:team_ai_game/game/validate.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('../spec/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final solverCases = (_load('solver.json')['cases'] as List).cast<Map<String, dynamic>>();
  final playCases = (_load('play.json')['cases'] as List).cast<Map<String, dynamic>>();
  World worldOf(Map<String, dynamic> c) => World.fromJson(c['world'] as Map<String, dynamic>);

  group('solver fixtures', () {
    for (final c in solverCases) {
      test(c['name'], () {
        final world = worldOf(c);
        final expected = c['expect'] as Map<String, dynamic>;
        expect(validateWorld(world).errors.map((e) => e.code), isEmpty);
        expect(toAscii(world), c['ascii']);

        final result = solve(world);
        expect(result.solvable, expected['solvable']);
        expect(result.steps, expected['steps']);
        expect(result.unreachable, expected['unreachable']);

        // The solver's path must win under the Play rules in exactly that many inputs.
        if (result.path case final path?) {
          final engine = PlayEngine(world);
          final beforeLast = engine.run(path.take(path.length - 1));
          final last = engine.step(beforeLast, path.last);
          expect(beforeLast.won, isFalse);
          expect(last.won, isTrue);
          expect(last.deaths, 0);
        }
      });
    }
  });

  test('round-trips every fixture world through JSON', () {
    for (final c in solverCases) {
      expect(worldOf(c).toJson(), c['world'], reason: c['name'] as String);
    }
  });

  group('play fixtures', () {
    for (final c in playCases) {
      test(c['name'], () {
        final world = c['world'] != null
            ? worldOf(c)
            : worldOf(solverCases.firstWhere((s) => s['name'] == c['worldRef']));
        final inputs = [for (final d in c['inputs'] as List) Direction.values.byName(d as String)];
        final s = PlayEngine(world).run(inputs);
        final expected = c['expect'] as Map<String, dynamic>;
        expect(s.x, expected['x']);
        expect(s.y, expected['y']);
        expect([for (final k in s.keys) k.name]..sort(), expected['keys']);
        expect(s.collected.toList()..sort(), expected['collected']);
        expect(s.deaths, expected['deaths']);
        expect(s.won, expected['won']);
      });
    }
  });
}
