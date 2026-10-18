// The published server address, read from a real local HTTP server. No testWidgets: the widget binding blocks
// real connections.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/net/server_config.dart';

void main() {
  late HttpServer site;
  late Uri base;

  setUpAll(() async {
    site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${site.port}');
    site.listen((request) {
      final body = switch (request.uri.path) {
        '/config.json' => '{"server": "https://abc.trycloudflare.com"}',
        '/broken.json' => 'not json',
        '/odd.json' => '{"server": "ftp://nope"}',
        _ => null,
      };
      if (body == null) request.response.statusCode = 404;
      request.response
        ..write(body ?? '')
        ..close();
    });
  });

  tearDownAll(() => site.close(force: true));

  test('reads the server the site publishes', () async {
    expect(await publishedServer(base.resolve('/config.json')), 'https://abc.trycloudflare.com');
  });

  test('anything else means no published server', () async {
    expect(await publishedServer(base.resolve('/missing.json')), isNull);
    expect(await publishedServer(base.resolve('/broken.json')), isNull);
    expect(await publishedServer(base.resolve('/odd.json')), isNull);
    final started = DateTime.now();
    expect(await publishedServer(Uri.parse('http://10.255.255.1/config.json'), timeout: const Duration(milliseconds: 300)), isNull);
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 2)));
  });
}
