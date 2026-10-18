// The site's motion, with its timings from tokens.dart: things arrive (rise, sharpen, settle) and never loop
// for decoration. Every animation here stops when the platform asks for reduced motion.

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../tokens.dart';

bool reducedMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

enum ArriveKind {
  /// Fade and a 4px rise: chat bubbles, history rows (CSS `msg-in`).
  msg,

  /// Fade, an 8px rise and a 4px blur that sharpens: cards (CSS `card-in`).
  card,

  /// Fade and scale from 95%: dialogs (CSS `dialog-in`).
  dialog,

  /// Scale from 60% with a little overshoot: avatars joining, markers (CSS `pop-in`).
  pop,
}

/// Plays its arrival once, when it first appears.
class Arrive extends StatefulWidget {
  const Arrive({super.key, required this.child, this.kind = ArriveKind.msg, this.delay = Duration.zero});

  final Widget child;
  final ArriveKind kind;
  final Duration delay;

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> with SingleTickerProviderStateMixin {
  late final Duration _length = switch (widget.kind) {
    ArriveKind.msg => SkTokens.msgIn,
    ArriveKind.card => SkTokens.cardIn,
    ArriveKind.dialog => SkTokens.dialogIn,
    ArriveKind.pop => SkTokens.popIn,
  };
  late final Curve _curve = switch (widget.kind) {
    ArriveKind.msg => SkTokens.msgInCurve,
    ArriveKind.card => SkTokens.cardInCurve,
    ArriveKind.dialog => SkTokens.dialogInCurve,
    ArriveKind.pop => SkTokens.popInCurve,
  };
  // The delay is part of the animation, so no timer outlives the widget.
  late final AnimationController _c = AnimationController(vsync: this, duration: _length + widget.delay);
  late final Curve _timed = Interval(widget.delay.inMicroseconds / (_length + widget.delay).inMicroseconds, 1, curve: _curve);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _timed.transform(_c.value);
        final opacity = t.clamp(0.0, 1.0);
        var out = child!;
        switch (widget.kind) {
          case ArriveKind.msg:
            out = Transform.translate(offset: Offset(0, SkTokens.msgInRise * (1 - t)), child: out);
          case ArriveKind.card:
            // The filter stays in the tree and is only switched off: removing a parent would rebuild everything
            // inside the card, resetting its state (focus, scroll, nested animations) when the blur ends.
            final blur = SkTokens.cardInBlur * (1 - t);
            out = ImageFiltered(enabled: blur > 0.01, imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: out);
            out = Transform.translate(offset: Offset(0, SkTokens.cardInRise * (1 - t)), child: out);
          case ArriveKind.dialog:
            out = Transform.scale(scale: SkTokens.dialogInScale + (1 - SkTokens.dialogInScale) * t, child: out);
          case ArriveKind.pop:
            out = Transform.scale(scale: SkTokens.popInScale + (1 - SkTokens.popInScale) * t, child: out);
        }
        return Opacity(opacity: opacity, child: out);
      },
    );
  }
}

/// A status dot whose halo breathes, like the site's live, blocked and waiting dots (CSS `live`).
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: SkTokens.live);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // 0 → 1 → 0 over the cycle, eased: the halo grows from 3px to 5px and fades out at the middle.
        final phase = Curves.easeInOut.transform(1 - (1 - 2 * _c.value).abs());
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.2 * (1 - phase)), spreadRadius: 3 + 2 * phase)],
          ),
        );
      },
    );
  }
}

/// Three dots that pulse in turn: an agent thinking.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color});

  final Color color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: Opacity(
                opacity: 0.35 + 0.65 * (0.5 + 0.5 * math.sin((_c.value - i * 0.18) * 2 * math.pi)).clamp(0.0, 1.0),
                child: Container(width: 4, height: 4, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
              ),
            ),
        ],
      ),
    );
  }
}
