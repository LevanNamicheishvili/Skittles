// Every kit component on one screen, in either theme, to compare with the site. Phase A of docs/flutter-plan:
// the app's home until the connect screen arrives in phase B.

import 'package:flutter/material.dart';

import '../ui/kit.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.dark, required this.onDarkChanged});

  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  // A new key replays the mark's draw-in.
  int _replay = 0;
  bool _sound = true;
  bool _route = false;
  String? _picked = 'bridge';

  static const _authors = [
    ('Nino', 'A', Color(0xFF3B82F6)),
    ('Giorgi', 'B', Color(0xFFF97316)),
    ('Ana', 'C', Color(0xFF10B981)),
    ('Dato', 'D', Color(0xFFE11D48)),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: SkTokens.sizeTopbar,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
            child: Row(
              children: [
                BrandMark(key: ValueKey(_replay), size: 24, draw: true),
                const SizedBox(width: 8),
                Text('Skittles', style: context.sans(size: 15, weight: FontWeight.w600, spacing: -0.375)),
                const SizedBox(width: 12),
                const VersionBadge('kit'),
                const Spacer(),
                SkButton('Replay mark', kind: SkButtonKind.ghost, onPressed: () => setState(() => _replay++)),
                const SizedBox(width: 16),
                SkToggle(widget.dark ? 'Dark' : 'Light', on: widget.dark, onChanged: widget.onDarkChanged),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Section('Brand', [_brand(context)]),
                      _Section('Colour', [_colours(context)]),
                      _Section('Type', [_type(context)]),
                      _Section('Controls', [_controls(context)]),
                      _Section('Status and people', [_status(context)]),
                      _Section('Chat and cards', [_chatAndCards(context)]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final size in const [16.0, 24.0, 40.0, 96.0]) BrandMark(key: ValueKey('$_replay-$size'), size: size, draw: true),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 28),
            const SizedBox(width: 10),
            Text('Skittles', style: context.sans(size: 24, weight: FontWeight.w600, spacing: -0.6)),
          ],
        ),
      ],
    );
  }

  Widget _colours(BuildContext context) {
    final c = context.sk;
    final swatches = <(String, Color)>[
      ('background', c.background),
      ('foreground', c.foreground),
      ('muted', c.muted),
      ('muted-foreground', c.mutedForeground),
      ('border', c.border),
      ('highlight', c.highlight),
      ('tip-secondary', c.tipSecondary),
      ('positive', c.positive),
      ('destructive', c.destructive),
      ('warning', c.warning),
      ('mediator', c.mediator),
      ('brand', SkTokens.brand),
      ('bronze', SkTokens.bronze),
      ('cream', SkTokens.cream),
      ('terminal-bg', SkTokens.terminalBg),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (name, color) in swatches)
          SizedBox(
            width: 128,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(SkTokens.radiusBubble), border: Border.all(color: c.border)),
                ),
                const SizedBox(height: 6),
                Text(name, style: context.sans(size: SkTokens.textSecondary, weight: FontWeight.w500)),
                Text(_hex(color), style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _type(BuildContext context) {
    final c = context.sk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Build together,', style: context.sans(size: SkTokens.textHero, weight: FontWeight.w600, spacing: -1.2, height: 48 / 44)),
        Text('one agent each.', style: context.sans(size: SkTokens.textHero, weight: FontWeight.w600, spacing: -1.2, height: 48 / 44, color: SkTokens.brand)),
        const SizedBox(height: 16),
        Text('Syncing bytes is solved. Syncing intent is not.', style: context.sans(size: 30, weight: FontWeight.w600, spacing: -0.9)),
        const SizedBox(height: 8),
        Text('When changes conflict', style: context.sans(size: SkTokens.textTitle, weight: FontWeight.w600, spacing: -0.4)),
        const SizedBox(height: 8),
        Text('A live room where your whole team builds one world, each person by talking to their own AI agent.',
            style: context.sans(size: SkTokens.textLede, color: c.mutedForeground, height: 1.6)),
        const SizedBox(height: 8),
        Text('Body 14 · the room checks every change before it goes live.', style: context.sans()),
        Text('Small 13 · panel titles and chips', style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w500)),
        Text('Secondary 12 · notes and captions', style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground)),
        const SizedBox(height: 4),
        Text('v3 · position (10, 8) · 0.2 ms', style: context.mono()),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SkButton('Send', onPressed: () {}),
        SkButton('Replay build', kind: SkButtonKind.secondary, onPressed: () {}),
        SkButton('Dismiss', kind: SkButtonKind.ghost, onPressed: () {}),
        const SkButton('Disabled'),
        SizedBox(width: 220, child: SkButton('Start creating', arrow: true, height: SkTokens.sizeCta, onPressed: () {})),
        SizedBox(width: 220, child: SkButton('Watch the demo', kind: SkButtonKind.secondary, arrow: true, height: SkTokens.sizeCta, onPressed: () {})),
        SkToggle('Sound on', on: _sound, onChanged: (v) => setState(() => _sound = v)),
        SkToggle('Show route', on: _route, onChanged: (v) => setState(() => _route = v)),
        const SizedBox(width: 320, child: SkTextField(placeholder: 'e.g. Add a lava river across the middle with one gap')),
      ],
    );
  }

  Widget _status(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusPill('Winnable · 21 steps', onTap: () {}),
        const StatusPill('Blocked · flag unreachable', ok: false),
        const VersionBadge('v3'),
        for (final key in const ['↑', '←', '↓', '→', 'WASD', 'R', 'F', 'V']) Keycap(key),
        CardLabel('Mediator', tone: context.sk.mediator),
        CardLabel('Playtest', tone: context.sk.warning),
        CardLabel('Suggested fix', tone: context.sk.positive),
        for (final (name, letter, color) in _authors) PresenceChip(name: name, letter: letter, color: color),
      ],
    );
  }

  Widget _chatAndCards(BuildContext context) {
    final c = context.sk;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SkPanel(
            title: 'Your agent',
            leading: SkAvatar(letter: 'A', color: _authors[0].$3),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChatBubble('Add a lava river down the middle. Leave one gap.', kind: BubbleKind.you),
                SizedBox(height: 8),
                ChatBubble('Thinking…', kind: BubbleKind.thinking),
                SizedBox(height: 8),
                ChatBubble('Done: a river at column 11 with one gap at row 4. Still winnable, 27 steps.'),
                SizedBox(height: 8),
                ChatBubble('Giorgi wants to build a stone bridge. It touches your object. Approve?', kind: BubbleKind.mediator),
                SizedBox(height: 8),
                ChatBubble('You approved the bridge · v3', kind: BubbleKind.system),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToneCard(
                tone: Tone.mediator,
                label: 'Mediator',
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: "Giorgi's", style: TextStyle(color: _authors[1].$3, fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' statue closes the only gap in '),
                    TextSpan(text: "Nino's", style: TextStyle(color: _authors[0].$3, fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' lava river.'),
                  ]), style: context.sans(height: 1.5)),
                  OptionRow(
                    title: 'Build a stone bridge',
                    detail: 'Bridge at (11, 9): the shortest route, 25 steps.',
                    picked: _picked == 'bridge',
                    onTap: () => setState(() => _picked = 'bridge'),
                  ),
                  OptionRow(
                    title: 'Move the statue next to the gap',
                    detail: "Proposed by Nino's agent",
                    agentColor: _authors[0].$3,
                    picked: _picked == 'agent',
                    onTap: () => setState(() => _picked = 'agent'),
                  ),
                  OptionRow(title: 'Cancel my change', detail: 'Keep the level as it is now.', cancel: true, onTap: () => setState(() => _picked = null)),
                ],
              ),
              const SizedBox(height: 12),
              ToneCard(
                tone: Tone.playtest,
                label: 'Playtest',
                children: [Text('Luka fell into lava at (11, 8), 2 times.', style: context.sans(height: 1.5))],
              ),
              const SizedBox(height: 12),
              ToneCard(
                tone: Tone.suggestion,
                label: 'Suggested fix',
                children: [
                  Text('Shorten the river by one row, so the crossing is fair.', style: context.sans(height: 1.5)),
                  Row(
                    children: [
                      SkButton('Apply', onPressed: () {}),
                      const SizedBox(width: 8),
                      SkButton('Dismiss', kind: SkButtonKind.ghost, onPressed: () {}),
                      const Spacer(),
                      Text('checked · stays winnable', style: context.mono(size: SkTokens.textCaption, color: c.positive)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// #rrggbb, or #rrggbbaa when the colour is see-through (the dark border is white at 10%).
String _hex(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = argb >>> 24;
  return alpha == 0xFF ? '#$rgb' : '#$rgb${alpha.toRadixString(16).padLeft(2, '0')}';
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: context.mono(size: SkTokens.textCaption, color: SkTokens.brand, spacing: 0.66)),
          const SizedBox(height: 4),
          Divider(color: c.border),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
