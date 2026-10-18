// Runs the shared cases in spec/fixtures/actions.json against the Dart action applier.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/studio/actions.dart';
import 'package:skittles/studio/scene.dart';

void main() {
  final file = jsonDecode(File('../spec/fixtures/actions.json').readAsStringSync()) as Map<String, dynamic>;
  final scene = Scene.fromJson(file['scene'] as Map<String, dynamic>);
  for (final c in (file['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'], () {
      final actions = [for (final a in c['actions'] as List) SceneAction.fromJson(Map<String, dynamic>.from(a as Map))];
      final r = applyActions(scene, actions);
      final e = c['expect'] as Map<String, dynamic>;
      expect(r.scene.objects, hasLength(e['count']));
      expect(r.created, e['created']);
      expect(r.notes, e['notes']);
      for (final o in (e['objects'] as List).cast<Map<String, dynamic>>()) {
        final got = r.scene.byId(o['id'] as String)!.toJson();
        for (final key in o.keys) {
          expect(got[key], o[key], reason: '${o['id']}.$key');
        }
      }
      for (final id in (e['missing'] as List? ?? const [])) {
        expect(r.scene.byId(id as String), isNull);
      }
      if (e.containsKey('theme')) expect(r.scene.theme, e['theme']);
      if (e.containsKey('name')) expect(r.scene.name, e['name']);
      if (e.containsKey('score')) expect(r.scene.score, e['score']);
    });
  }
}
