// Side panels and the top bar around the level canvas.

import 'package:flutter/material.dart';

import '../game/model.dart';
import '../ui/theme.dart';
import '../ui/tile_art.dart';
import 'editor_controller.dart';
import 'level_canvas.dart' show PlayHud, typeName;

// ------------------------------------------------------------------ shared bits

class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: Palette.of(context).system,
                  ),
            ),
            const Spacer(),
            ?trailing,
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class NumberStepper extends StatelessWidget {
  const NumberStepper({super.key, required this.label, required this.value, required this.min, required this.max, required this.onChanged});

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (label.isNotEmpty) SizedBox(width: 18, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      Container(
        height: 28,
        decoration: BoxDecoration(border: Border.all(color: p.panelBorder), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _tinyButton(p, Icons.remove, value > min ? () => onChanged(value - 1) : null),
          SizedBox(width: 30, child: Text('$value', textAlign: TextAlign.center)),
          _tinyButton(p, Icons.add, value < max ? () => onChanged(value + 1) : null),
        ]),
      ),
    ]);
  }

  Widget _tinyButton(Palette p, IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 14, color: onTap == null ? p.system.withValues(alpha: 0.4) : p.ink),
        ),
      );
}

class ColorChips extends StatelessWidget {
  const ColorChips({super.key, required this.value, required this.onChanged, this.allowOpen = false});

  final GameColor? value;
  final ValueChanged<GameColor?> onChanged;
  final bool allowOpen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget chip(GameColor? color, String tip) {
      final selected = value == color;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => onChanged(color),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: color == null ? Colors.transparent : p.doorColors[color],
              shape: BoxShape.circle,
              border: Border.all(color: selected ? p.accent : p.panelBorder, width: selected ? 2.5 : 1),
            ),
            child: color == null ? Icon(Icons.door_front_door_outlined, size: 14, color: p.system) : null,
          ),
        ),
      );
    }

    return Row(children: [
      for (final c in GameColor.values) chip(c, '${c.name[0].toUpperCase()}${c.name.substring(1)}'),
      if (allowOpen) chip(null, 'Open doorway'),
    ]);
  }
}

String unreachableText(World world, String code) {
  if (code == 'flag') return 'The flag cannot be reached';
  if (code == 'collect_count:coin') return 'Not enough coins can be reached';
  final e = world.byId(code.substring('collect:'.length));
  return '${e?.label ?? typeName(e?.type ?? EntityType.treasure)} cannot be reached';
}

// ---------------------------------------------------------------------- top bar

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = controller;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: p.panel, border: Border(bottom: BorderSide(color: p.panelBorder))),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: LinearGradient(colors: [p.players[0], p.players[2]]),
          ),
          alignment: Alignment.center,
          child: const Text('E', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Text(appName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Text('/', style: TextStyle(color: p.system)),
        const SizedBox(width: 10),
        Text(c.levelName, style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        SegmentedButton<EditorMode>(
          segments: const [
            ButtonSegment(value: EditorMode.edit, label: Text('Edit'), icon: Icon(Icons.edit_outlined, size: 16)),
            ButtonSegment(value: EditorMode.play, label: Text('Play'), icon: Icon(Icons.play_arrow_rounded, size: 18)),
          ],
          selected: {c.mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => s.first == EditorMode.play ? c.startPlay() : c.stopPlay(),
        ),
        const SizedBox(width: 12),
        _StatusPill(controller: c),
        const Spacer(),
        IconButton(
          tooltip: c.showPath ? 'Hide solver path' : 'Show solver path',
          isSelected: c.showPath,
          icon: const Icon(Icons.route_outlined),
          onPressed: c.toggleShowPath,
        ),
        IconButton(tooltip: 'Undo (⌘Z)', icon: const Icon(Icons.undo), onPressed: c.canUndo ? c.undo : null),
        IconButton(tooltip: 'Redo (⇧⌘Z)', icon: const Icon(Icons.redo), onPressed: c.canRedo ? c.redo : null),
        PopupMenuButton<String>(
          tooltip: 'Level',
          icon: const Icon(Icons.more_horiz),
          onSelected: (v) => v == 'new' ? c.newLevel() : c.loadSampleLevel(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: Text('New empty level')),
            PopupMenuItem(value: 'sample', child: Text('Load “Castle Story” sample')),
          ],
        ),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = controller;
    final result = c.solveResult;
    final (Color color, IconData icon, String text) = switch (result) {
      _ when c.validation.errors.isNotEmpty => (p.lava, Icons.error_outline, 'Fix: ${c.validation.errors.first.message}'),
      null => (p.system, Icons.hourglass_empty, 'Checking…'),
      final r when r.solvable => (p.path, Icons.check_circle_outline, 'Winnable · ${r.steps} moves'),
      final r => (p.lava, Icons.block, unreachableText(c.world, r.unreachable.first)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(text, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ left panel

class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = controller;
    final editing = c.mode == EditorMode.edit;
    return Container(
      width: 252,
      decoration: BoxDecoration(color: p.panel, border: Border(right: BorderSide(color: p.panelBorder))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PanelSection(
          title: 'Tools',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in EditorTool.values) _ToolButton(tool: t, controller: c, enabled: editing)],
          ),
        ),
        if (c.tool.usesColor && editing)
          PanelSection(
            title: 'Color',
            child: ColorChips(value: c.toolColor, onChanged: (v) => c.setToolColor(v ?? GameColor.gold)),
          ),
        const Divider(),
        Expanded(
          child: PanelSection(
            title: 'Objects',
            trailing: Text('${c.world.entities.length}', style: Theme.of(context).textTheme.labelSmall),
            child: Expanded(child: _ObjectList(controller: c)),
          ),
        ),
        const Divider(),
        PanelSection(title: 'Goals', child: _Goals(controller: c)),
      ]),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.controller, required this.enabled});

  final EditorTool tool;
  final EditorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final selected = controller.tool == tool;
    final Widget glyph = switch (tool) {
      EditorTool.select => const Icon(Icons.near_me_outlined, size: 18),
      EditorTool.erase => const Icon(Icons.backspace_outlined, size: 17),
      EditorTool.start => Icon(Icons.person, size: 18, color: p.accent),
      EditorTool.flag => Icon(Icons.flag, size: 18, color: p.path),
      _ => TileIcon(tool.entityType!, color: controller.toolColor, size: 20),
    };
    return Tooltip(
      message: '${tool.label}  (${tool.shortcut})',
      child: InkWell(
        onTap: enabled ? () => controller.setTool(tool) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 70,
          height: 58,
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? p.accent : p.panelBorder),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              glyph,
              const SizedBox(height: 4),
              Text(tool.label, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ObjectList extends StatelessWidget {
  const _ObjectList({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = controller;
    final entities = c.world.entities.reversed.toList();
    if (entities.isEmpty) {
      return Text('Nothing here yet. Pick a tool and draw on the board.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.system));
    }
    return ListView.builder(
      itemCount: entities.length,
      itemExtent: 34,
      itemBuilder: (context, i) {
        final e = entities[i];
        final selected = c.selectedId == e.id;
        return InkWell(
          onTap: () => c.select(e.id),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? p.accent.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              TileIcon(e.type, color: e.color ?? e.door?.color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.label ?? typeName(e.type), overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: ownerColor(p, e.owner), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(ownerName(e.owner), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: p.system)),
            ]),
          ),
        );
      },
    );
  }
}

class _Goals extends StatelessWidget {
  const _Goals({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = Palette.of(context);
    final coins = c.world.entities.where((e) => e.type == EntityType.coin).length;
    final targets = [for (final o in c.world.objectives) if (o is CollectObjective) c.world.byId(o.target)].nonNulls;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in targets)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            TileIcon(e.type, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Collect ${e.label ?? typeName(e.type)}', style: Theme.of(context).textTheme.bodySmall)),
            InkWell(onTap: () => c.setRequired(e.id, false), child: Icon(Icons.close, size: 14, color: p.system)),
          ]),
        ),
      Row(children: [
        const TileIcon(EntityType.coin, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text('Coins needed', style: Theme.of(context).textTheme.bodySmall)),
        NumberStepper(label: '', value: c.coinGoal, min: 0, max: coins, onChanged: c.setCoinGoal),
      ]),
      const SizedBox(height: 4),
      Text('Then reach the flag.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.system)),
    ]);
  }
}

// ----------------------------------------------------------------- right panel

class RightPanel extends StatelessWidget {
  const RightPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: 300,
      decoration: BoxDecoration(color: p.panel, border: Border(left: BorderSide(color: p.panelBorder))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: SingleChildScrollView(
            child: controller.mode == EditorMode.play ? PlayHud(controller: controller) : Inspector(controller: controller),
          ),
        ),
        const Divider(),
        const AiTeamPanel(),
      ]),
    );
  }
}

class Inspector extends StatelessWidget {
  const Inspector({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final id = c.selectedId;

    if (id == null) {
      final result = c.solveResult;
      return PanelSection(
        title: 'Level',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.levelName, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${c.world.width} × ${c.world.height} cells · ${c.world.entities.length} objects',
              style: text.bodySmall?.copyWith(color: p.system)),
          const SizedBox(height: 14),
          if (result != null && !result.solvable) ...[
            Text('Why it is blocked', style: text.labelLarge),
            const SizedBox(height: 6),
            for (final u in result.unreachable)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.block, size: 14, color: p.lava),
                  const SizedBox(width: 6),
                  Expanded(child: Text(unreachableText(c.world, u), style: text.bodySmall)),
                ]),
              ),
            const SizedBox(height: 10),
          ],
          for (final w in c.validation.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: p.players[1]),
                const SizedBox(width: 6),
                Expanded(child: Text(w.message, style: text.bodySmall)),
              ]),
            ),
          const SizedBox(height: 8),
          Text('Select an object on the board to edit it. Drag to move, Delete to remove, '
              'arrow keys to nudge, P to play.', style: text.bodySmall?.copyWith(color: p.system)),
        ]),
      );
    }

    if (id == startId || id == flagId) {
      final cell = id == startId ? c.world.start : c.world.flag;
      return PanelSection(
        title: id == startId ? 'Start' : 'Flag',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Position ${cell.x}, ${cell.y}', style: text.bodyMedium),
          const SizedBox(height: 6),
          Text(id == startId ? 'Where every player begins.' : 'Reach it after all goals to win.',
              style: text.bodySmall?.copyWith(color: p.system)),
        ]),
      );
    }

    final e = c.world.byId(id);
    if (e == null) return const SizedBox.shrink();
    void update(Entity Function(Entity) f) => c.updateEntity(e.id, f);
    return PanelSection(
      title: typeName(e.type),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: ownerColor(p, e.owner), shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(ownerName(e.owner), style: text.labelSmall),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _LabelField(key: ValueKey(e.id), initial: e.label ?? '', onSubmit: (v) => update((x) => x.copyWith(label: () => v.isEmpty ? null : v))),
        const SizedBox(height: 12),
        Row(children: [
          NumberStepper(label: 'X', value: e.x, min: 0, max: c.world.width - e.w, onChanged: (v) => update((x) => x.copyWith(x: v))),
          const SizedBox(width: 10),
          NumberStepper(label: 'Y', value: e.y, min: 0, max: c.world.height - e.h, onChanged: (v) => update((x) => x.copyWith(y: v))),
        ]),
        if (e.type.isRect) ...[
          const SizedBox(height: 8),
          Row(children: [
            NumberStepper(
              label: 'W',
              value: e.w,
              min: e.type == EntityType.castle ? 3 : 1,
              max: c.world.width - e.x,
              onChanged: (v) => update((x) => x.copyWith(w: v)),
            ),
            const SizedBox(width: 10),
            NumberStepper(
              label: 'H',
              value: e.h,
              min: e.type == EntityType.castle ? 3 : 1,
              max: c.world.height - e.y,
              onChanged: (v) => update((x) => x.copyWith(h: v)),
            ),
          ]),
        ],
        if (e.type.hasColor) ...[
          const SizedBox(height: 12),
          Text('Color', style: text.labelMedium),
          const SizedBox(height: 6),
          ColorChips(value: e.color, onChanged: (v) => update((x) => x.copyWith(color: v))),
        ],
        if (e.type == EntityType.castle) ..._castleDoorFields(context, e, update),
        if (e.type == EntityType.treasure || e.type == EntityType.coin) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Required to win'),
            value: c.isRequired(e.id),
            onChanged: (v) => c.setRequired(e.id, v),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: p.lava),
            onPressed: () => c.deleteEntity(e.id),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
          ),
        ),
      ]),
    );
  }

  List<Widget> _castleDoorFields(BuildContext context, Entity e, void Function(Entity Function(Entity)) update) {
    final door = e.door!;
    final span = door.side == DoorSide.left || door.side == DoorSide.right ? e.h : e.w;
    return [
      const SizedBox(height: 12),
      Text('Door', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 6),
      SegmentedButton<DoorSide>(
        segments: const [
          ButtonSegment(value: DoorSide.left, icon: Icon(Icons.border_left, size: 18), tooltip: 'Left wall'),
          ButtonSegment(value: DoorSide.top, icon: Icon(Icons.border_top, size: 18), tooltip: 'Top wall'),
          ButtonSegment(value: DoorSide.right, icon: Icon(Icons.border_right, size: 18), tooltip: 'Right wall'),
          ButtonSegment(value: DoorSide.bottom, icon: Icon(Icons.border_bottom, size: 18), tooltip: 'Bottom wall'),
        ],
        selected: {door.side},
        showSelectedIcon: false,
        onSelectionChanged: (s) {
          final side = s.first;
          final newSpan = side == DoorSide.left || side == DoorSide.right ? e.h : e.w;
          update((x) => x.copyWith(door: door.copyWith(side: side, offset: (newSpan - 3) ~/ 2)));
        },
      ),
      const SizedBox(height: 8),
      NumberStepper(
        label: '',
        value: door.offset,
        min: 0,
        max: span - 3,
        onChanged: (v) => update((x) => x.copyWith(door: door.copyWith(offset: v))),
      ),
      const SizedBox(height: 8),
      ColorChips(
        value: door.color,
        allowOpen: true,
        onChanged: (v) => update((x) => x.copyWith(door: door.copyWith(color: () => v))),
      ),
    ];
  }
}

class _LabelField extends StatefulWidget {
  const _LabelField({super.key, required this.initial, required this.onSubmit});

  final String initial;
  final ValueChanged<String> onSubmit;

  @override
  State<_LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<_LabelField> {
  late final _text = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != widget.initial) widget.onSubmit(_text.text.trim());
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Name', counterText: ''),
        onSubmitted: (v) => widget.onSubmit(v.trim()),
      );
}

class AiTeamPanel extends StatelessWidget {
  const AiTeamPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    return PanelSection(
      title: 'AI team',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: p.mediator.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
        child: Text('Phase 4', style: text.labelSmall?.copyWith(color: p.mediator)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Each teammate will describe changes in plain English. Their AI turns them into edits, '
          'every change is checked for a winning path, and the mediator proposes fixes when ideas collide.',
          style: text.bodySmall?.copyWith(color: p.system),
        ),
        const SizedBox(height: 12),
        const TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'Tell your AI what to build…',
            suffixIcon: Icon(Icons.mic_none, size: 18),
          ),
        ),
      ]),
    );
  }
}
