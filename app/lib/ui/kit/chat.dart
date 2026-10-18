// Chat bubbles (CSS .msg and its kinds): yours on the right in the warm highlight, your agent's on a muted
// surface, system lines as centred small text, the mediator across the full width.

import 'package:flutter/material.dart';

import '../sk_theme.dart';
import '../tokens.dart';
import 'motion.dart';

enum BubbleKind { you, agent, system, thinking, mediator }

class ChatBubble extends StatelessWidget {
  const ChatBubble(this.text, {super.key, this.kind = BubbleKind.agent});

  final String text;
  final BubbleKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final Widget body = switch (kind) {
      BubbleKind.system => Text(text, textAlign: TextAlign.center, style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground, height: 1.5)),
      BubbleKind.thinking => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TypingDots(color: c.mutedForeground),
            const SizedBox(width: 20),
            Text(text, style: context.sans(color: c.mutedForeground, height: 1.5)),
          ],
        ),
      _ => Text(text, style: context.sans(color: kind == BubbleKind.you ? c.highlightForeground : c.foreground, height: 1.5)),
    };
    final Color? fill = switch (kind) {
      BubbleKind.you => c.highlight,
      BubbleKind.agent || BubbleKind.thinking => c.muted,
      BubbleKind.mediator => mix(c.mediator, 0.08, c.background),
      BubbleKind.system => null,
    };
    final alignment = switch (kind) {
      BubbleKind.you => Alignment.centerRight,
      BubbleKind.system => Alignment.center,
      _ => Alignment.centerLeft,
    };
    return Arrive(
      child: LayoutBuilder(
        builder: (context, box) {
          final bubble = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: fill == null ? null : BoxDecoration(color: fill, borderRadius: BorderRadius.circular(SkTokens.radiusBubble)),
            child: body,
          );
          if (kind == BubbleKind.mediator || kind == BubbleKind.system) return SizedBox(width: box.maxWidth, child: bubble);
          return Align(
            alignment: alignment,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.88), child: bubble),
          );
        },
      ),
    );
  }
}
