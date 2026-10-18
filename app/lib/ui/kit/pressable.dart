// Hover, press, focus and keyboard activation for the kit's custom controls, so each control only draws itself.

import 'package:flutter/material.dart';

@immutable
class PressState {
  const PressState({required this.hovered, required this.pressed, required this.focused, required this.enabled});

  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool enabled;
}

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onPressed, required this.builder, this.autofocus = false});

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, PressState state) builder;
  final bool autofocus;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return FocusableActionDetector(
      enabled: enabled,
      autofocus: widget.autofocus,
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          enabled: enabled,
          child: widget.builder(context, PressState(hovered: _hovered && enabled, pressed: _pressed, focused: _focused, enabled: enabled)),
        ),
      ),
    );
  }
}

/// The site's focus ring: 2px in the foreground at 35%, 2px away from the control. Shadows paint in order, so
/// the ring goes first and the background gap is drawn over its inner half.
List<BoxShadow> focusRing(Color background, Color foreground) => [
      BoxShadow(color: Color.alphaBlend(foreground.withValues(alpha: 0.35), background), spreadRadius: 4),
      BoxShadow(color: background, spreadRadius: 2),
    ];
