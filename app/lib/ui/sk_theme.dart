// The site's design as a Flutter theme: colours and sizes from tokens.dart (generated from design/tokens.json),
// system type like the web's system-ui, no ripples, hairline borders. The legacy editor keeps theme.dart.

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Font families. A null [sans] is the platform's system font (San Francisco on macOS), as `system-ui` is on the
/// web. Tests pass families they have loaded from font files, so snapshots show real text.
@immutable
class SkFonts extends ThemeExtension<SkFonts> {
  const SkFonts({this.sans, this.mono = 'SF Mono'});

  final String? sans;
  final String mono;

  @override
  SkFonts copyWith({String? sans, String? mono}) => SkFonts(sans: sans ?? this.sans, mono: mono ?? this.mono);

  @override
  SkFonts lerp(SkFonts? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData skTheme(Brightness brightness, {SkFonts fonts = const SkFonts()}) {
  final c = brightness == Brightness.dark ? SkColors.dark : SkColors.light;
  final base = ThemeData(brightness: brightness, fontFamily: fonts.sans);
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.foreground,
      onPrimary: c.background,
      secondary: SkTokens.brand,
      onSecondary: Colors.white,
      error: c.destructive,
      onError: Colors.white,
      surface: c.background,
      onSurface: c.foreground,
      outline: c.border,
      outlineVariant: c.border,
    ),
    textTheme: base.textTheme
        .apply(bodyColor: c.foreground, displayColor: c.foreground, fontFamily: fonts.sans)
        .copyWith(bodyMedium: TextStyle(fontSize: SkTokens.textBody, height: 1.5, color: c.foreground, fontFamily: fonts.sans)),
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.muted,
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.foreground, selectionColor: SkTokens.brand.withValues(alpha: 0.3)),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(c.foreground.withValues(alpha: 0.2))),
    extensions: [c, fonts],
  );
}

extension SkContext on BuildContext {
  SkColors get sk => Theme.of(this).extension<SkColors>() ?? SkColors.dark;
  SkFonts get skFonts => Theme.of(this).extension<SkFonts>() ?? const SkFonts();

  /// Machine text: versions, positions, labels, the console.
  TextStyle mono({double size = SkTokens.textSecondary, FontWeight weight = FontWeight.w500, Color? color, double? spacing}) => TextStyle(
        fontFamily: skFonts.mono,
        fontFamilyFallback: SkTokens.fontMono,
        fontSize: size,
        fontWeight: weight,
        color: color ?? sk.foreground,
        letterSpacing: spacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Everything else, in the system sans.
  TextStyle sans({double size = SkTokens.textBody, FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) => TextStyle(
        fontFamily: skFonts.sans,
        fontSize: size,
        fontWeight: weight,
        color: color ?? sk.foreground,
        height: height,
        letterSpacing: spacing,
      );
}

/// CSS `color-mix(in oklab, a p%, b)`, close enough in sRGB for tints this light.
Color mix(Color a, double share, Color b) => Color.lerp(b, a, share)!;
