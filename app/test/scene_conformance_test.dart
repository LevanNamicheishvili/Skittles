// Runs the shared cases in spec/fixtures/scenes.json against the Dart scene model and validation.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/scene.dart';
import 'package:skittles/studio/validate.dart';

void main() {
  final cases = ((jsonDecode(File('../spec/fixtures/scenes.json').readAsStringSync()) as Map)['cases'] as List).cast<Map<String, dynamic>>();

  group('scene fixtures', () {
    for (final c in cases) {
      test(c['name'], () {
        final scene = Scene.fromJson(c['scene'] as Map<String, dynamic>);
        final report = validateScene(scene);
        final expected = c['expect'] as Map<String, dynamic>;
        expect(report.errors.map((i) => i.code).toSet(), (expected['errors'] as List).toSet(), reason: 'errors');
        expect(report.warnings.map((i) => i.code).toSet(), (expected['warnings'] as List).toSet(), reason: 'warnings');
        expect(report.finishReachable, expected['finishReachable'], reason: 'finish');
      });
    }
  });

  test('a scene survives a round trip through JSON', () {
    final original = cases.first['scene'] as Map<String, dynamic>;
    final again = Scene.fromJson(Scene.fromJson(original).toJson()).toJson();
    expect(jsonEncode(again), jsonEncode(Scene.fromJson(original).toJson()));
    expect(again['objects'], hasLength((original['objects'] as List).length));
  });

  test('the jump model matches the spec', () {
    const jump = Jump(speed: 260, takeoff: 640, gravity: 1800);
    expect(jump.height, closeTo(113.8, 0.1));
    expect(jump.reach(0), closeTo(166.4, 0.1));
    expect(jump.reach(100), closeTo(112.2, 0.1));
    expect(jump.reach(-120), closeTo(202.4, 0.1));
    expect(jump.reach(200), lessThan(0)); // higher than the player can jump
  });

  test('files that are not scenes are refused', () {
    expect(() => Scene.fromJson({'format': 'something-else'}), throwsFormatException);
    expect(() => Scene.fromJson({'format': 'skittles-scene', 'version': 9}), throwsFormatException);
  });
}
