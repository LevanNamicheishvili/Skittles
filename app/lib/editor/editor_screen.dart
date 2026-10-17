import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_controller.dart';
import 'level_canvas.dart';
import 'panels.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.controller});

  final EditorController? controller;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController c = widget.controller ?? EditorController();

  @override
  void initState() {
    super.initState();
    c.notice.addListener(_showNotice);
  }

  @override
  void dispose() {
    c.notice.removeListener(_showNotice);
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _showNotice() {
    final message = c.notice.value;
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, width: 420));
    c.notice.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): c.redo,
      },
      child: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(children: [
            TopBar(controller: c),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LeftPanel(controller: c),
                Expanded(child: LevelCanvas(controller: c)),
                RightPanel(controller: c),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
