// Buttons, toggles and the text field, as the site draws them (web/src/styles.css: button, .toggle, input).

import 'package:flutter/material.dart';

import '../sk_theme.dart';
import '../tokens.dart';
import 'pressable.dart';

enum SkButtonKind {
  /// Inverted: the foreground colour as the fill. The main action.
  primary,

  /// Outlined on a half-transparent background.
  secondary,

  /// Text only, 70% until hovered.
  ghost,
}

class SkButton extends StatelessWidget {
  const SkButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = SkButtonKind.primary,
    this.arrow = false,
    this.height = SkTokens.sizeControl,
    this.expand = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final SkButtonKind kind;

  /// A call to action: label on the left, an arrow on the right that nudges 4px on hover.
  final bool arrow;
  final double height;
  final bool expand;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Pressable(
      onPressed: onPressed,
      builder: (context, s) {
        final (Color bg, Color fg, Color edge) = switch (kind) {
          SkButtonKind.primary => (s.hovered ? c.foreground.withValues(alpha: 0.9) : c.foreground, c.background, Colors.transparent),
          SkButtonKind.secondary => (s.hovered ? c.secondary : c.background.withValues(alpha: 0.5), c.foreground, c.border),
          SkButtonKind.ghost => (Colors.transparent, s.hovered ? c.foreground : c.foreground.withValues(alpha: 0.7), Colors.transparent),
        };
        final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: SkTokens.textBody, weight: arrow ? FontWeight.w600 : FontWeight.w500, color: fg, height: 1));
        return Opacity(
          opacity: s.enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: kind == SkButtonKind.ghost && !arrow ? 0 : 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(SkTokens.radiusControl),
              border: Border.all(color: edge),
              boxShadow: s.focused ? focusRing(c.background, c.foreground) : null,
            ),
            child: Row(
              mainAxisSize: expand || arrow ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: arrow ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 8)],
                // The label gives way (with an ellipsis) when the button is squeezed, instead of overflowing.
                Flexible(child: text),
                if (arrow)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    transform: Matrix4.translationValues(s.hovered ? 4 : 0, 0, 0),
                    child: Text('→', style: context.sans(size: SkTokens.textBody, weight: FontWeight.w600, color: fg, height: 1)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A compact outlined switch that fills in when on (CSS `.toggle`).
class SkToggle extends StatelessWidget {
  const SkToggle(this.label, {super.key, required this.on, this.onChanged});

  final String label;
  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged!(!on),
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: SkTokens.sizeCompact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? c.foreground : (s.hovered ? c.muted : Colors.transparent),
          borderRadius: BorderRadius.circular(SkTokens.radiusControl),
          border: Border.all(color: on ? c.foreground : c.border),
          boxShadow: s.focused ? focusRing(c.background, c.foreground) : null,
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: context.sans(size: SkTokens.textSecondary, weight: FontWeight.w500, color: on ? c.background : c.foreground, height: 1)),
        ),
      ),
    );
  }
}

/// The site's input: 36px, hairline border that darkens on focus.
class SkTextField extends StatelessWidget {
  const SkTextField({super.key, this.controller, this.placeholder, this.onSubmitted, this.autofocus = false, this.height = SkTokens.sizeField});

  final TextEditingController? controller;
  final String? placeholder;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    OutlineInputBorder edge(Color color) => OutlineInputBorder(borderRadius: BorderRadius.circular(SkTokens.radiusControl), borderSide: BorderSide(color: color));
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        style: context.sans(size: SkTokens.textBody),
        cursorColor: c.foreground,
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: context.sans(size: SkTokens.textBody, color: c.mutedForeground),
          isDense: true,
          filled: true,
          fillColor: c.background,
          hoverColor: c.background,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: (height - 20) / 2),
          enabledBorder: edge(c.border),
          focusedBorder: edge(c.foreground.withValues(alpha: 0.3)),
          border: edge(c.border),
        ),
      ),
    );
  }
}
