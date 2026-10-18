// The studio projects on a server (GET /api/projects), for the welcome screen: a second window finds the project its
// team is in and joins it, without copying a code.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class OpenProject {
  const OpenProject({required this.id, required this.name, required this.people});

  factory OpenProject.fromJson(Map<String, dynamic> j) =>
      OpenProject(id: j['id'] as String, name: j['name'] as String? ?? 'Untitled', people: [for (final p in (j['people'] as List?) ?? const []) p as String]);

  final String id;
  final String name;

  /// Who is in it now.
  final List<String> people;
}

/// The projects someone is in right now on [server]; empty when the server cannot be reached.
Future<List<OpenProject>> listOpenProjects(String server, {Duration timeout = const Duration(seconds: 2)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final base = Uri.parse(server.contains('://') ? server : 'http://$server');
    final request = await client.getUrl(base.resolve('/api/projects')).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return const [];
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return [
      for (final p in jsonDecode(body) as List)
        if (((p as Map)['people'] as List?)?.isNotEmpty ?? false) OpenProject.fromJson(p.cast<String, dynamic>()),
    ];
  } catch (_) {
    return const [];
  } finally {
    client.close(force: true);
  }
}

/// The project code in what someone pasted: the code itself, or the whole invite ("Join my Skittles project: code
/// 4f2a9c on http://…").
String projectCode(String text) {
  final code = RegExp(r'code\s+([A-Za-z0-9_-]+)').firstMatch(text)?.group(1) ?? RegExp(r'\b[0-9a-f]{6}\b').firstMatch(text)?.group(0);
  return code ?? text.trim();
}
