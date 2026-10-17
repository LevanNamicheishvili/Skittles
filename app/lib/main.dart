import 'package:flutter/material.dart';

import 'editor/editor_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ErtadApp());
}

class ErtadApp extends StatelessWidget {
  const ErtadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const EditorScreen(),
    );
  }
}
