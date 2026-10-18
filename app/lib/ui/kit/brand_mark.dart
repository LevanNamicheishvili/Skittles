// The Skittles mark, drawn from the same 32×32 geometry as the site's SVG (web/src/Landing.tsx BrandMark): an S
// drawn as a route through a 3×3 level, from the runner's start (round) to the goal cell (square).

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'motion.dart';

class BrandMark extends StatefulWidget {
  const BrandMark({super.key, this.size = 20, this.draw = false});

  final double size;

  /// Trace the route in once, then pop the start and goal markers, like the ghost runner proving the path.
  final bool draw;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with SingleTickerProviderStateMixin {
  // Route: 250ms delay + 900ms draw. Start pops at 0-350ms, the goal at 1100-1450ms.
  static const _total = Duration(milliseconds: 1450);
  late final AnimationController _c = AnimationController(vsync: this, duration: _total, value: widget.draw ? 0 : 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.draw && !_c.isAnimating && _c.value == 0) {
      if (reducedMotion(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _phase(int fromMs, Duration length, Curve curve) {
    final t = (_c.value * _total.inMilliseconds - fromMs) / length.inMilliseconds;
    return curve.transform(t.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _MarkPainter(
          route: _phase(SkTokens.routeDrawDelay.inMilliseconds, SkTokens.routeDraw, SkTokens.routeDrawCurve),
          start: _phase(0, SkTokens.popIn, SkTokens.popInCurve),
          goal: _phase(1100, SkTokens.popIn, SkTokens.popInCurve),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.route, required this.start, required this.goal});

  final double route;
  final double start;
  final double goal;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 32, 32), const Radius.circular(8)), Paint()..color = SkTokens.brand);

    final cell = Paint()..color = const Color(0x24FFFFFF);
    for (final y in const [5.0, 13.0, 21.0]) {
      for (final x in const [5.0, 13.0, 21.0]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 6, 6), const Radius.circular(1.6)), cell);
      }
    }

    final path = Path()
      ..moveTo(24, 8)
      ..lineTo(8, 8)
      ..lineTo(8, 16)
      ..lineTo(24, 16)
      ..lineTo(24, 24)
      ..lineTo(8, 24);
    final stroke = Paint()
      ..color = SkTokens.cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (route >= 1) {
      canvas.drawPath(path, stroke);
    } else if (route > 0) {
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * route), stroke);
      }
    }

    final fill = Paint()..color = SkTokens.bronze;
    final rim = Paint()
      ..color = SkTokens.cream
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    void popped(double t, Offset centre, void Function() draw) {
      if (t <= 0) return;
      final scale = SkTokens.popInScale + (1 - SkTokens.popInScale) * t;
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(scale);
      canvas.translate(-centre.dx, -centre.dy);
      draw();
      canvas.restore();
    }

    popped(goal, const Offset(8, 24), () {
      final goalCell = RRect.fromRectAndRadius(const Rect.fromLTWH(5.6, 21.6, 4.8, 4.8), const Radius.circular(1.2));
      canvas.drawRRect(goalCell, fill);
      canvas.drawRRect(goalCell, rim);
    });
    popped(start, const Offset(24, 8), () {
      canvas.drawCircle(const Offset(24, 8), 3, fill);
      canvas.drawCircle(const Offset(24, 8), 3, rim);
    });
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.route != route || old.start != start || old.goal != goal;
}
