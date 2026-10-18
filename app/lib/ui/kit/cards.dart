// Panels, tone cards and option rows (CSS .chat/.history panels, .card, .option). One shape everywhere: a
// 1px border and a 12px radius on the background.

import 'package:flutter/material.dart';

import '../sk_theme.dart';
import '../tokens.dart';
import 'badges.dart';
import 'motion.dart';
import 'pressable.dart';

/// A bordered surface with an optional 40px header, like the agent chat and the history.
class SkPanel extends StatelessWidget {
  const SkPanel({super.key, this.title, this.leading, this.trailing, required this.child, this.padding = const EdgeInsets.all(12), this.expand = false});

  final String? title;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  /// Fill the height the panel is given, with the child taking what the header leaves.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final body = Padding(padding: padding, child: child);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(SkTokens.radiusPanel), border: Border.all(color: c.border)),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Expanded(child: Text(title!, style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w500))),
                  ?trailing,
                ],
              ),
            ),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

enum Tone { mediator, playtest, suggestion }

/// A card in its tone: violet for the mediator, amber for a playtest report, green for a suggested fix.
class ToneCard extends StatelessWidget {
  const ToneCard({super.key, required this.tone, required this.label, required this.children});

  final Tone tone;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final color = switch (tone) {
      Tone.mediator => c.mediator,
      Tone.playtest => c.warning,
      Tone.suggestion => c.positive,
    };
    return Arrive(
      kind: ArriveKind.card,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(SkTokens.radiusPanel), border: Border.all(color: c.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: CardLabel(label, tone: color)),
            for (final child in children) ...[const SizedBox(height: 8), child],
          ],
        ),
      ),
    );
  }
}

/// One fix to pick. An agent's proposal gets a 3px edge in its author's colour; cancelling is dashed.
class OptionRow extends StatelessWidget {
  const OptionRow({super.key, required this.title, this.detail, this.onTap, this.agentColor, this.cancel = false, this.picked = false});

  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final Color? agentColor;
  final bool cancel;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final radius = BorderRadius.circular(SkTokens.radiusBubble);
    return Pressable(
      onPressed: onTap,
      builder: (context, s) {
        final edge = picked ? c.positive : c.border;
        final content = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.fromLTRB(agentColor == null ? 12 : 14, 10, 12, 10),
          decoration: BoxDecoration(
            color: picked ? mix(c.positive, 0.12, c.background) : (s.hovered ? c.muted : c.background),
            borderRadius: radius,
            border: cancel ? null : Border.all(color: edge),
            boxShadow: s.focused ? focusRing(c.background, c.foreground) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: context.sans(color: cancel ? c.mutedForeground : c.foreground, height: 1.4)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(detail!, style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground, height: 1.4)),
              ],
            ],
          ),
        );
        return Stack(
          fit: StackFit.passthrough,
          children: [
            if (cancel) Positioned.fill(child: CustomPaint(painter: _DashedBorder(color: c.border, radius: SkTokens.radiusBubble))),
            content,
            // A border of uneven widths cannot be rounded in Flutter, so the agent's edge is a bar clipped to the corners.
            if (agentColor != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(SkTokens.radiusBubble)),
                  child: Container(width: 3, color: agentColor),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius)));
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
