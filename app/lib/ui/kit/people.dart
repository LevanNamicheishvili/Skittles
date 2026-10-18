// Who is in the room: author avatars and presence chips (CSS .chip, .chip i).

import 'package:flutter/material.dart';

import '../sk_theme.dart';
import '../tokens.dart';

/// An author's letter on their colour. With [online], a green dot sits at the bottom right.
class SkAvatar extends StatelessWidget {
  const SkAvatar({super.key, required this.letter, required this.color, this.size = SkTokens.sizeAvatar, this.online = false});

  final String letter;
  final Color color;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(letter, style: context.sans(size: size * 0.5, weight: FontWeight.w600, color: Colors.white, height: 1)),
          ),
          if (online)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c.positive, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.background, spreadRadius: 2)]),
              ),
            ),
        ],
      ),
    );
  }
}

/// A member of the room: avatar and name in a pill.
class PresenceChip extends StatelessWidget {
  const PresenceChip({super.key, required this.name, required this.letter, required this.color});

  final String name;
  final String letter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      height: SkTokens.sizeCompact,
      padding: const EdgeInsets.only(left: 3, right: 10),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(SkTokens.radiusPill),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkAvatar(letter: letter, color: color, online: true),
          const SizedBox(width: 8),
          Text(name, style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w500, color: c.mutedForeground, height: 1)),
        ],
      ),
    );
  }
}
