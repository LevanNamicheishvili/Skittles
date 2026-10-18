// The live sky behind the connect screen, ported from the site (web/src/Landing.tsx LiveSky): clouds of digits
// and symbols drift and flicker in the Skittles colours, bronze at the edges and red-orange where they are thick,
// over twinkling stars. Glyphs come from a sprite sheet drawn once and are blitted in one drawAtlas call per frame,
// about 20 times a second. Static under reduced motion.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../tokens.dart';
import '../sk_theme.dart';
import 'motion.dart';

const _glyphs = '0123456789?%#*+=<>/\$&';
const _cw = 8.0;
const _ch = 12.0;
const _alphas = [0.12, 0.2, 0.3, 0.42, 0.56, 0.72];

double _hash(double x, double y) {
  final s = math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return s - s.floorToDouble();
}

double _noise(double x, double y) {
  final xi = x.floorToDouble();
  final yi = y.floorToDouble();
  final u = (x - xi) * (x - xi) * (3 - 2 * (x - xi));
  final v = (y - yi) * (y - yi) * (3 - 2 * (y - yi));
  final a = _hash(xi, yi);
  final b = _hash(xi + 1, yi);
  final c = _hash(xi, yi + 1);
  final d = _hash(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

class LiveSky extends StatefulWidget {
  const LiveSky({super.key, this.clear});

  /// Where the text sits, in this widget's coordinates: the clouds dim behind it.
  final Rect Function(Size size)? clear;

  @override
  State<LiveSky> createState() => _LiveSkyState();
}

class _LiveSkyState extends State<LiveSky> with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _drawn = Duration.zero;
  ui.Image? _atlas;
  double _atlasRatio = 0;
  String _atlasFont = '';

  void _tick(Duration elapsed) {
    if (elapsed - _drawn < const Duration(milliseconds: 50)) return; // the clouds drift slowly; 20 fps is plenty
    _drawn = elapsed;
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
    // 1.5× is sharp enough for a dim backdrop and draws about half the pixels of 2×.
    final ratio = math.min(1.5, MediaQuery.devicePixelRatioOf(context));
    final font = context.skFonts.mono;
    if (ratio != _atlasRatio || font != _atlasFont) {
      _atlasRatio = ratio;
      _atlasFont = font;
      _buildAtlas(ratio, font);
    }
  }

  Future<void> _buildAtlas(double ratio, String font) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    for (var row = 0; row < 24; row++) {
      final k = row ~/ 6 / 3;
      final colour = Color.lerp(SkTokens.bronze, SkTokens.brand, k)!.withValues(alpha: _alphas[row % 6]);
      for (var i = 0; i < _glyphs.length; i++) {
        final painter = TextPainter(
          text: TextSpan(text: _glyphs[i], style: TextStyle(fontFamily: font, fontFamilyFallback: SkTokens.fontMono, fontSize: 10, color: colour)),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(i * _cw, row * _ch));
        painter.dispose();
      }
    }
    final image = await recorder.endRecording().toImage((_glyphs.length * _cw * ratio).ceil(), (24 * _ch * ratio).ceil());
    if (!mounted || ratio != _atlasRatio || font != _atlasFont) {
      image.dispose();
      return;
    }
    setState(() {
      _atlas?.dispose();
      _atlas = image;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.55, 0.92],
        ).createShader(bounds),
        child: CustomPaint(painter: _SkyPainter(time: _time, atlas: _atlas, ratio: _atlasRatio, clear: widget.clear), size: Size.infinite),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.time, required this.atlas, required this.ratio, required this.clear}) : super(repaint: time);

  final ValueNotifier<double> time;
  final ui.Image? atlas;
  final double ratio;
  final Rect Function(Size size)? clear;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width;
    final h = size.height;
    final box = clear?.call(size);
    final atlas = this.atlas;

    if (atlas != null) {
      final transforms = <RSTransform>[];
      final rects = <Rect>[];
      for (var y = 0.0; y < h * 0.92; y += _ch) {
        for (var x = 0.0; x < w; x += _cw) {
          // Clouds gather toward the sides, and dim (but stay) behind the text.
          final edge = 0.3 + 0.7 * math.min(1, (x - w / 2).abs() / (w * 0.34));
          final n = (_noise(x / 180 + t * 0.05, y / 100 + t * 0.018) * 0.7 + _noise(x / 46 - t * 0.09, y / 30) * 0.3) * edge;
          if (n < 0.46) continue;
          var dim = 1.0;
          if (box != null) {
            final away = [box.left - x, x - box.right, box.top - y, y - box.bottom, 0.0].reduce(math.max);
            dim = 0.25 + 0.75 * math.min(1, away / 80);
          }
          final strength = math.min(1.0, (n - 0.46) / 0.3);
          final row = math.min(3, (strength * 4).floor()) * 6 + math.min(5, (strength * 6 * dim).floor());
          // Each cell swaps its glyph now and then, at its own pace.
          final cx = x / _cw;
          final cy = y / _ch;
          final flip = (t * (0.6 + _hash(cx, cy) * 2.4) + _hash(cy, cx) * 10).floorToDouble();
          final glyph = (_hash(cx + flip * 17.3, cy) * _glyphs.length).floor() % _glyphs.length;
          transforms.add(RSTransform(1 / ratio, 0, x, y));
          rects.add(Rect.fromLTWH(glyph * _cw * ratio, row * _ch * ratio, _cw * ratio, _ch * ratio));
        }
      }
      canvas.drawAtlas(atlas, transforms, rects, null, null, null, Paint()..filterQuality = FilterQuality.low);
    }

    // Stars twinkle; a few sparkles stay out of the text column.
    final rand = math.Random(7);
    final star = Paint();
    final count = (w * h / 6500).round();
    for (var i = 0; i < count; i++) {
      final size = rand.nextDouble() < 0.1 ? 2.0 : 1.0;
      final alpha = 0.2 + rand.nextDouble() * 0.6;
      final phase = rand.nextDouble() * 6.28;
      star.color = const Color(0xFFFFF4EC).withValues(alpha: alpha * (0.65 + 0.35 * math.sin(t * 1.5 + phase)));
      canvas.drawRect(Rect.fromLTWH(rand.nextDouble() * w, rand.nextDouble() * h, size, size), star);
    }
    final sparkle = Paint()..color = const Color(0xD9FFF4EC);
    for (var i = 0; i < 9; i++) {
      final side = rand.nextDouble() < 0.5 ? -1 : 1;
      final x = (w / 2 + side * (w * 0.22 + rand.nextDouble() * w * 0.28)).roundToDouble();
      final y = (rand.nextDouble() * h * 0.75).roundToDouble();
      canvas.drawRect(Rect.fromLTWH(x - 3, y, 7, 1), sparkle);
      canvas.drawRect(Rect.fromLTWH(x, y - 3, 1, 7), sparkle);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.atlas != atlas || old.ratio != ratio;
}
