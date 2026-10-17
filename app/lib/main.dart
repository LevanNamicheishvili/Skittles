import 'package:flutter/material.dart';

void main() {
  runApp(const TeamAiGameApp());
}

/// Phase 0 shell. The editor itself starts in phase 2 (see docs and spec/).
class TeamAiGameApp extends StatelessWidget {
  const TeamAiGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Team AI Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F6FDB)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF2F6FDB), brightness: Brightness.dark),
      home: const PlaceholderScreen(),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ერთად მოიფიქრე, მაშინვე ითამაშე', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text('ეტაპი 0: საფუძველი მზადდება', style: text.bodyLarge),
          ],
        ),
      ),
    );
  }
}
