// Small status pieces: the status pill, the version badge, keycaps and card labels (CSS .status, .version,
// kbd, .card-head).

import 'package:flutter/material.dart';

import '../sk_theme.dart';
import '../tokens.dart';
import 'motion.dart';
import 'pressable.dart';

/// "Winnable · 21 steps" or "Blocked · flag unreachable": a breathing dot beside plain text.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.ok = true, this.neutral = false, this.onTap});

  final String label;
  final bool ok;

  /// Neither good nor bad news: a grey dot and plain text (an empty scene).
  final bool neutral;

  /// On the site a click replays the ghost runner.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final tone = neutral ? c.mutedForeground : (ok ? c.positive : c.destructive);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Pressable(
      onPressed: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: SkTokens.sizeCompact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: s.hovered ? c.muted : c.background,
          borderRadius: BorderRadius.circular(SkTokens.radiusControl),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveDot(color: tone),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w500, color: ok || neutral ? c.foreground : c.destructive, height: 1)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// "v3": Conductor's changelog badge, mono and tinted.
class VersionBadge extends StatelessWidget {
  const VersionBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: c.tipSecondary,
        borderRadius: BorderRadius.circular(SkTokens.radiusBadge),
        border: Border.all(color: c.tipSecondaryBorder),
      ),
      child: Text(text, style: context.mono(size: SkTokens.textSecondary, color: c.tipMuted, spacing: 0.6).copyWith(height: 1.3)),
    );
  }
}

/// A key the user can press, drawn as a keycap.
class Keycap extends StatelessWidget {
  const Keycap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      constraints: const BoxConstraints(minWidth: SkTokens.sizeKeycap),
      height: SkTokens.sizeKeycap,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(SkTokens.radiusKeycap),
        border: Border.all(color: c.border),
      ),
      child: Center(widthFactor: 1, child: Text(label, style: context.mono(size: SkTokens.textCaption))),
    );
  }
}

/// A card's kind, in its tone: MEDIATOR, PLAYTEST, SUGGESTED FIX.
class CardLabel extends StatelessWidget {
  const CardLabel(this.text, {super.key, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: mix(tone, 0.10, c.background),
        borderRadius: BorderRadius.circular(SkTokens.radiusBadge),
        border: Border.all(color: mix(tone, 0.28, c.background)),
      ),
      child: Text(text.toUpperCase(), style: context.mono(size: SkTokens.textCaption, color: tone, spacing: 0.55).copyWith(height: 1)),
    );
  }
}
