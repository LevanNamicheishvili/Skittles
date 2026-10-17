// Design tokens from docs/design.md, plus the light and dark Material themes built on them.

import 'package:flutter/material.dart';

import '../game/model.dart';

const appName = 'Skittles';

class Palette {
  const Palette._({
    required this.players,
    required this.mediator,
    required this.system,
    required this.lava,
    required this.lavaGlow,
    required this.path,
    required this.ground,
    required this.gridLine,
    required this.wall,
    required this.wallMortar,
    required this.bridge,
    required this.bridgeShade,
    required this.ink,
    required this.accent,
    required this.panel,
    required this.panelBorder,
    required this.canvasBackdrop,
    required this.doorColors,
  });

  final List<Color> players;
  final Color mediator;
  final Color system;
  final Color lava;
  final Color lavaGlow;
  final Color path;
  final Color ground;
  final Color gridLine;
  final Color wall;
  final Color wallMortar;
  final Color bridge;
  final Color bridgeShade;
  final Color ink;
  final Color accent;
  final Color panel;
  final Color panelBorder;
  final Color canvasBackdrop;
  final Map<GameColor, Color> doorColors;

  static const light = Palette._(
    players: [Color(0xFF2F6FDB), Color(0xFFC2560F), Color(0xFF0E8A7A), Color(0xFF7A4CD9), Color(0xFFC2338A), Color(0xFF6E7F12)],
    mediator: Color(0xFF0E8A7A),
    system: Color(0xFF8A8F98),
    lava: Color(0xFFD93A2B),
    lavaGlow: Color(0xFFF59E3B),
    path: Color(0xFF1E8E3E),
    ground: Color(0xFFF4F2EC),
    gridLine: Color(0xFFE3E0D7),
    wall: Color(0xFF8E939B),
    wallMortar: Color(0xFF6F747C),
    bridge: Color(0xFFB07A44),
    bridgeShade: Color(0xFF7F5530),
    ink: Color(0xFF1F2328),
    accent: Color(0xFF2F6FDB),
    panel: Color(0xFFF7F7F8),
    panelBorder: Color(0xFFE2E3E6),
    canvasBackdrop: Color(0xFFECEDEF),
    doorColors: {GameColor.red: Color(0xFFD93A2B), GameColor.blue: Color(0xFF2F6FDB), GameColor.gold: Color(0xFFB7791F)},
  );

  static const dark = Palette._(
    players: [Color(0xFF6EA2FF), Color(0xFFFF9A52), Color(0xFF3FC9B4), Color(0xFFB39BFF), Color(0xFFFF7AC6), Color(0xFFB9CC4A)],
    mediator: Color(0xFF3FC9B4),
    system: Color(0xFF9AA0A8),
    lava: Color(0xFFFF6B5B),
    lavaGlow: Color(0xFFFFB45E),
    path: Color(0xFF4CC26A),
    ground: Color(0xFF2A2D33),
    gridLine: Color(0xFF363A41),
    wall: Color(0xFF6A7079),
    wallMortar: Color(0xFF52575F),
    bridge: Color(0xFFB98552),
    bridgeShade: Color(0xFF86603A),
    ink: Color(0xFFF2F3F5),
    accent: Color(0xFF6EA2FF),
    panel: Color(0xFF1E1F22),
    panelBorder: Color(0xFF2E3034),
    canvasBackdrop: Color(0xFF17181A),
    doorColors: {GameColor.red: Color(0xFFFF6B5B), GameColor.blue: Color(0xFF6EA2FF), GameColor.gold: Color(0xFFE3B341)},
  );

  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// People and agents in the local session. Phase 3 replaces this with the room roster.
class Participant {
  const Participant(this.name, this.colorIndex);
  final String name;
  final int colorIndex;
}

const participants = {
  'me': Participant('You', 3),
  'A': Participant('Nino', 0),
  'B': Participant('Gio', 1),
};

String ownerName(Owner o) => switch (o.kind) {
      OwnerKind.player => participants[o.playerId]?.name ?? 'Player',
      OwnerKind.assistant => '${participants[o.playerId]?.name ?? 'Player'}’s AI',
      OwnerKind.mediator => 'Mediator',
      OwnerKind.system => 'System',
    };

Color ownerColor(Palette p, Owner o) => switch (o.kind) {
      OwnerKind.player || OwnerKind.assistant => p.players[(participants[o.playerId]?.colorIndex ?? 5) % p.players.length],
      OwnerKind.mediator => p.mediator,
      OwnerKind.system => p.system,
    };

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: brightness).copyWith(
    primary: p.accent,
    surface: p.panel,
    outlineVariant: p.panelBorder,
  );
  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: p.canvasBackdrop,
    dividerTheme: DividerThemeData(color: p.panelBorder, thickness: 1, space: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: brightness == Brightness.dark ? const Color(0xFF2A2B2F) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.panelBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: p.panelBorder)),
    ),
  );
}
