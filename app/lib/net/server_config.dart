// Where the shared Skittles server is. The website publishes it in config.json ({"server": "https://…"}), so an app
// someone downloaded finds the server even after it moves; the site is updated, the app is not.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The website's config, read at startup.
final publishedConfig = Uri.parse('https://skittles-gamma.vercel.app/config.json');

/// The server address in the config at [config], or null when it cannot be read in time.
Future<String?> publishedServer(Uri config, {Duration timeout = const Duration(milliseconds: 1500)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(config).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    final server = (jsonDecode(body) as Map)['server'];
    return server is String && (server.startsWith('https://') || server.startsWith('http://')) ? server : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
