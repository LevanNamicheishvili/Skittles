// The site's rotating headline line (web/src/Landing.tsx Scramble): every 3 s the next phrase scrambles in left to
// right, one settled character every 24 ms with a few random letters just ahead of it. Driven by a ticker, so no
// timer outlives the widget. Pinned to the first phrase under reduced motion.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'motion.dart';

class Scramble extends StatefulWidget {
  const Scramble({super.key, required this.phrases, required this.style});

  final List<String> phrases;
  final TextStyle style;

  @override
  State<Scramble> createState() => _ScrambleState();
}

class _ScrambleState extends State<Scramble> with SingleTickerProviderStateMixin {
  static const _hold = 3000; // ms per phrase
  static const _letters = 'abcdefghijklmnopqrstuvwxyz';
  late final Ticker _ticker = createTicker(_tick);
  late String _text = widget.phrases.first;

  void _tick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    final cycle = ms ~/ _hold;
    if (cycle == 0) return;
    final from = widget.phrases[(cycle - 1) % widget.phrases.length];
    final to = widget.phrases[cycle % widget.phrases.length];
    final length = from.length > to.length ? from.length : to.length;
    final settled = (ms % _hold) ~/ 24;
    String next;
    if (settled >= length) {
      next = to;
    } else {
      final out = StringBuffer();
      for (var i = 0; i < length; i++) {
        final target = i < to.length ? to[i] : '';
        if (i < settled) {
          out.write(target);
        } else if (i < settled + 4 && target.isNotEmpty && target != ' ' && target != '.') {
          out.write(_letters[(ms ~/ 40 + i * 7) % _letters.length]);
        } else {
          out.write(i < from.length ? from[i] : '');
        }
      }
      next = out.toString();
    }
    if (next != _text) setState(() => _text = next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive && widget.phrases.length > 1) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_text, style: widget.style, maxLines: 1, softWrap: false);
}
