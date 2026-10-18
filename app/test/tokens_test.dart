// The generated tokens.dart must say what design/tokens.json says (run `node design/build.ts` after editing it).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skittles/ui/tokens.dart';

Color hex(String value) {
  var h = value.replaceFirst('#', '');
  if (h.length == 6) h = '${h}ff';
  return Color(int.parse(h.substring(6) + h.substring(0, 6), radix: 16));
}

Map<String, Color> named(SkColors c) => {
      'background': c.background,
      'foreground': c.foreground,
      'muted': c.muted,
      'muted-foreground': c.mutedForeground,
      'border': c.border,
      'secondary': c.secondary,
      'highlight': c.highlight,
      'highlight-foreground': c.highlightForeground,
      'tip-secondary': c.tipSecondary,
      'tip-secondary-border': c.tipSecondaryBorder,
      'tip-muted': c.tipMuted,
      'positive': c.positive,
      'destructive': c.destructive,
      'warning': c.warning,
      'mediator': c.mediator,
    };

void main() {
  final tokens = jsonDecode(File('../design/tokens.json').readAsStringSync()) as Map<String, dynamic>;
  final color = tokens['color'] as Map<String, dynamic>;

  for (final (theme, set) in [('light', SkColors.light), ('dark', SkColors.dark)]) {
    test('$theme colours match the JSON', () {
      final expected = (color[theme] as Map<String, dynamic>).map((k, v) => MapEntry(k, hex(v as String)));
      expect(named(set), expected);
    });
  }

  test('brand colours, radii and motion match the JSON', () {
    final shared = color['shared'] as Map<String, dynamic>;
    expect(SkTokens.brand, hex(shared['brand'] as String));
    expect(SkTokens.bronze, hex(shared['bronze'] as String));
    expect(SkTokens.terminalBg, hex(shared['terminal-bg'] as String));
    final radius = tokens['radius'] as Map<String, dynamic>;
    expect([SkTokens.radiusBadge, SkTokens.radiusControl, SkTokens.radiusBubble, SkTokens.radiusPanel], [radius['badge'], radius['control'], radius['bubble'], radius['panel']]);
    final motion = tokens['motion'] as Map<String, dynamic>;
    expect(SkTokens.msgIn.inMilliseconds, (motion['msg-in'] as Map)['ms']);
    expect(SkTokens.cardIn.inMilliseconds, (motion['card-in'] as Map)['ms']);
  });
}
