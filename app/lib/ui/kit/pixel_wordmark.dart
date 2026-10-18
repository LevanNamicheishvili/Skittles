// SKITTLES in blocks, like Conductor's onboarding wordmark: five rows per letter, runs of cells merged into rounded
// bars. The blocks arrive in a sweep from the left; afterwards a soft wave of the brand colour passes through them
// now and then, like a route lighting the cells it crosses. Static under reduced motion.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../tokens.dart';
import 'motion.dart';

// Two-cell strokes, so the letters read as chunky bars like the reference rather than dots.
const _letters = <String, List<String>>{
  'S': ['.#####', '##....', '.####.', '....##', '#####.'],
  'K': ['##..##', '##.##.', '####..', '##.##.', '##..##'],
  'I': ['######', '..##..', '..##..', '..##..', '######'],
  'T': ['######', '..##..', '..##..', '..##..', '..##..'],
  'L': ['##....', '##....', '##....', '##....', '######'],
  'E': ['######', '##....', '#####.', '##....', '######'],
};

/// One bar: a run of cells in one row of the whole word.
typedef _Bar = ({int row, int from, int to});

List<_Bar> _bars(String word) {
  final bars = <_Bar>[];
  var column = 0;
  for (final ch in word.split('')) {
    final rows = _letters[ch]!;
    for (var row = 0; row < rows.length; row++) {
      final line = rows[row];
      var start = -1;
      for (var i = 0; i <= line.length; i++) {
        final on = i < line.length && line[i] == '#';
        if (on && start < 0) start = i;
        if (!on && start >= 0) {
          bars.add((row: row, from: column + start, to: column + i));
          start = -1;
        }
      }
    }
    column += rows.first.length + 1;
  }
  return bars;
}

class PixelWordmark extends StatefulWidget {
  const PixelWordmark({super.key, this.word = 'SKITTLES', this.height = 112, this.color = SkTokens.cream});

  final String word;
  final double height;
  final Color color;

  @override
  State<PixelWordmark> createState() => _PixelWordmarkState();
}

class _PixelWordmarkState extends State<PixelWordmark> with SingleTickerProviderStateMixin {
  late final List<_Bar> _barsOfWord = _bars(widget.word);
  late final int _columns = widget.word.split('').fold(0, (n, ch) => n + _letters[ch]!.first.length + 1) - 1;
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);

  void _tick(Duration elapsed) => _time.value = elapsed.inMicroseconds / 1e6;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      if (_ticker.isActive) _ticker.stop();
      _time.value = 100; // past the sweep, between waves
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rows with gaps like the reference; cells narrower than a row is tall, so a two-cell stroke is chunky.
    final rowHeight = widget.height / (5 + 4 * 0.32);
    final cellWidth = rowHeight * 0.86;
    final width = _columns * cellWidth;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, widget.height),
        painter: _WordmarkPainter(bars: _barsOfWord, columns: _columns, time: _time, color: widget.color, rowHeight: rowHeight, cellWidth: cellWidth),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter({required this.bars, required this.columns, required this.time, required this.color, required this.rowHeight, required this.cellWidth}) : super(repaint: time);

  final List<_Bar> bars;
  final int columns;
  final ValueNotifier<double> time;
  final Color color;
  final double rowHeight;
  final double cellWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final gapY = rowHeight * 0.32;
    final gapX = cellWidth * 0.28;
    final paint = Paint();
    for (final bar in bars) {
      // Arrival: a sweep from the left, 28ms per column, each bar settling for 350ms.
      final arrive = ((t * 1000 - bar.from * 28) / 350).clamp(0.0, 1.0);
      if (arrive <= 0) continue;
      final eased = Curves.easeOutBack.transform(arrive);
      // Afterwards, every 7 s a diagonal wave of the brand colour runs through the word.
      final wavePos = ((t - 2.2) % 7.0) / 1.6 * (columns + 10) - 5;
      final distance = (bar.from + bar.row * 0.8 - wavePos).abs();
      final glow = t < 2.2 ? 0.0 : math.max(0.0, 1 - distance / 4);
      paint.color = Color.lerp(color, SkTokens.brand, glow * 0.9)!.withValues(alpha: arrive);
      final left = bar.from * cellWidth + gapX / 2;
      final right = bar.to * cellWidth - gapX / 2;
      final top = bar.row * (rowHeight + gapY);
      final rise = (1 - eased) * rowHeight * 0.6;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(left, top + rise, right, top + rowHeight + rise), Radius.circular(rowHeight * 0.18)), paint);
    }
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.color != color || old.rowHeight != rowHeight;
}
