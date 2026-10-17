import 'package:flutter/material.dart';

import 'editor/editor_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const SkittlesApp());
}

class SkittlesApp extends StatelessWidget {
  const SkittlesApp({super.key});

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
