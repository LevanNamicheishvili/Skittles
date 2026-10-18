// Opening and saving scene files (.skittles, JSON) through the system's file dialogs.

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'scene.dart';
import 'studio_controller.dart';

const sceneFiles = XTypeGroup(label: 'Skittles scene', extensions: ['skittles', 'json'], uniformTypeIdentifiers: ['public.json', 'public.data']);

/// Asks for a scene file and reads it. Null when the user cancels; a FormatException with a readable message when
/// the file is not a scene.
Future<({Scene scene, String path})?> pickScene() async {
  final file = await openFile(acceptedTypeGroups: const [sceneFiles]);
  if (file == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on FormatException {
    throw const FormatException('That file is not valid JSON.');
  }
  if (decoded is! Map) throw const FormatException('Not a Skittles scene file.');
  return (scene: Scene.fromJson(Map<String, dynamic>.from(decoded)), path: file.path);
}

/// Saves the studio's scene to its file, asking where the first time. Returns the path, or null if cancelled.
Future<String?> saveScene(StudioController studio) async {
  var path = studio.filePath;
  if (path == null) {
    final location = await getSaveLocation(suggestedName: '${studio.scene.name}.skittles', acceptedTypeGroups: const [sceneFiles]);
    if (location == null) return null;
    path = location.path;
  }
  await File(path).writeAsString(studio.encode());
  studio.saved(path);
  return path;
}
