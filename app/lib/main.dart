import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'net/models.dart';
import 'net/room_client.dart';
import 'net/room_store.dart';
import 'net/server_config.dart';
import 'screens/connect_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/room_screen.dart';
import 'studio/scene.dart';
import 'studio/scene_files.dart';
import 'studio/studio_controller.dart';
import 'studio/studio_link.dart';
import 'studio/studio_screen.dart';
import 'ui/sk_theme.dart';
import 'ui/theme.dart' show appName;

// Launch settings, as --dart-define or, for a second copy of the app, as environment variables
// (open -n Skittles.app --env SKITTLES_NAME=Giorgi --env SKITTLES_PROJECT=abc123 --env SKITTLES_SCREEN=studio):
//   SKITTLES_SERVER   the Skittles server; by default the one the website publishes (server_config.dart), and
//                     http://localhost:3001 when that cannot be read
//   SKITTLES_NAME     your name; SKITTLES_ROLE joins the grid demo room straight away as author, player or stage
//   SKITTLES_SCREEN   studio opens the studio at once (a new project, or SKITTLES_PROJECT); gallery the components
String _setting(String define, String key, [String fallback = '']) => define.isNotEmpty ? define : (Platform.environment[key] ?? fallback);

final _name = _setting(const String.fromEnvironment('SKITTLES_NAME'), 'SKITTLES_NAME');
final _role = _setting(const String.fromEnvironment('SKITTLES_ROLE'), 'SKITTLES_ROLE');
final _screen = _setting(const String.fromEnvironment('SKITTLES_SCREEN'), 'SKITTLES_SCREEN');
final _project = _setting(const String.fromEnvironment('SKITTLES_PROJECT'), 'SKITTLES_PROJECT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final explicit = _setting(const String.fromEnvironment('SKITTLES_SERVER'), 'SKITTLES_SERVER');
  final server = explicit.isNotEmpty ? explicit : (await publishedServer(publishedConfig) ?? 'http://localhost:3001');
  runApp(SkittlesApp(server: server));
}

/// Dark by default, like the site. The welcome screen until you open a project or join the demo room.
class SkittlesApp extends StatefulWidget {
  const SkittlesApp({super.key, this.fonts = const SkFonts(), this.client, this.openLink = SocketStudioLink.open, this.server = 'http://localhost:3001'});

  final SkFonts fonts;

  /// The server the welcome screen offers and the studio opens on.
  final String server;

  /// Tests pass their own client and their own line to a project.
  final RoomClient? client;
  final Future<StudioLink> Function(Uri server) openLink;

  @override
  State<SkittlesApp> createState() => _SkittlesAppState();
}

class _SkittlesAppState extends State<SkittlesApp> {
  late final RoomClient _client = widget.client ?? RoomClient(RoomStore());
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _dark = true;
  StudioController? _studio;

  @override
  void initState() {
    super.initState();
    if (_screen == 'studio') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startStudio(server: widget.server, name: _name.isEmpty ? 'Guest' : _name, project: _project.isEmpty ? null : _project));
    }
  }

  @override
  void dispose() {
    _client.disconnect();
    _studio?.dispose();
    super.dispose();
  }

  void _openStudio(StudioController? studio) {
    final old = _studio;
    setState(() => _studio = studio);
    old?.dispose();
  }

  void _toast(String text) => _messenger.currentState?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, width: 460, content: Text(text)));

  /// Opens a shared project on [server]: a teammate's ([project]), or a new one, empty or from [scene]. A new one
  /// opens offline when the server cannot be reached; joining needs it.
  Future<String?> _startStudio({required String server, required String name, String? project, Scene? scene, String? path}) async {
    final uri = Uri.parse(server.contains('://') ? server : 'http://$server');
    try {
      final link = await widget.openLink(uri);
      final studio = await StudioController.join(link, server: uri, name: name, project: project, scene: scene, sceneName: scene == null ? 'Untitled' : null, filePath: path);
      _openStudio(studio);
      return null;
    } catch (e) {
      if (project != null) return '$e';
      _openStudio(StudioController(scene ?? Scene.blank(), filePath: path));
      _toast('Working offline, without agents: $e');
      return null;
    }
  }

  Future<String?> _openFile({required String server, required String name, String? project}) async {
    try {
      final picked = await pickScene();
      if (picked == null) return null;
      return await _startStudio(server: server, name: name, scene: picked.scene, path: picked.path);
    } on FormatException catch (e) {
      return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: skTheme(Brightness.light, fonts: widget.fonts),
      darkTheme: skTheme(Brightness.dark, fonts: widget.fonts),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      scaffoldMessengerKey: _messenger,
      home: _screen == 'gallery'
          ? GalleryScreen(dark: _dark, onDarkChanged: (v) => setState(() => _dark = v))
          : ListenableBuilder(
              listenable: _client.store,
              builder: (context, _) => _client.store.joined
                  ? RoomScreen(
                      client: _client,
                      onLeave: () async {
                        await _client.disconnect();
                        _client.store.clear();
                      },
                    )
                  : _studio != null
                      ? StudioScreen(studio: _studio!, onHome: () => _openStudio(null))
                      : ConnectScreen(
                          client: _client,
                          server: widget.server,
                          name: _name,
                          autoRole: Role.values.where((r) => r.name == _role).firstOrNull,
                          onNewProject: ({required server, required name, project}) => _startStudio(server: server, name: name),
                          onOpenProject: _openFile,
                          onJoinProject: ({required server, required name, project}) => _startStudio(server: server, name: name, project: project),
                        ),
            ),
    );
  }
}
