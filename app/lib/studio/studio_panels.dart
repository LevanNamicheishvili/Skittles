// The studio's left column: the layers (every object, topmost first, with who made it) over the inspector for the
// selection or the scene, and the checks. One label column for every row, so the fields line up.

import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'scene.dart';
import 'studio_controller.dart';
import 'validate.dart';

const typeIcons = {
  SceneObjectType.player: Icons.directions_run_rounded,
  SceneObjectType.platform: Icons.horizontal_rule_rounded,
  SceneObjectType.coin: Icons.monetization_on_outlined,
  SceneObjectType.enemy: Icons.pest_control_outlined,
  SceneObjectType.finish: Icons.sports_score_outlined,
};

/// Small caps over a section, with an optional count on the right.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return SizedBox(
      height: 36,
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground, spacing: 0.66))),
        if (trailing != null) Text(trailing!, style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)),
      ]),
    );
  }
}

class StudioLeftColumn extends StatelessWidget {
  const StudioLeftColumn({super.key, required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final selected = studio.selected;
    final shared = studio.shared;
    return Container(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: SectionLabel('Layers', trailing: '${studio.scene.objects.length}')),
          Expanded(
            flex: 4,
            child: studio.scene.objects.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text('Nothing here yet.', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground)),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    children: [
                      for (final o in studio.scene.objects.reversed)
                        _HierarchyRow(
                          object: o,
                          selected: o.id == studio.selectedId,
                          flagged: studio.report.issues.any((i) => i.objectId == o.id),
                          author: shared != null && o.by != null ? shared.colorOf(o.by) : null,
                          onTap: () => studio.select(o.id),
                        ),
                    ],
                  ),
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            flex: 6,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              children: [
                if (selected == null) _SceneInspector(studio: studio) else _ObjectInspector(key: ValueKey(selected.id), studio: studio, object: selected),
                const SizedBox(height: 18),
                _Checks(studio: studio),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HierarchyRow extends StatelessWidget {
  const _HierarchyRow({required this.object, required this.selected, required this.flagged, required this.onTap, this.author});

  final SceneObject object;
  final bool selected;
  final bool flagged;
  final VoidCallback onTap;

  /// The colour of whoever made it, in a shared project.
  final Color? author;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Pressable(
      onPressed: onTap,
      builder: (context, s) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? mix(SkTokens.brand, 0.16, c.background) : (s.hovered ? c.muted : null),
          borderRadius: BorderRadius.circular(SkTokens.radiusControl),
        ),
        child: Row(
          children: [
            Icon(typeIcons[object.type], size: 15, color: selected ? SkTokens.brand : c.mutedForeground),
            const SizedBox(width: 8),
            Expanded(child: Text(object.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: SkTokens.textSmall))),
            if (flagged) ...[const SizedBox(width: 6), Container(width: 6, height: 6, decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle))],
            if (author != null) ...[const SizedBox(width: 6), Container(width: 8, height: 8, decoration: BoxDecoration(color: author, shape: BoxShape.circle))],
          ],
        ),
      ),
    );
  }
}

/// One label column for every inspector row, so the fields line up.
const _labelWidth = 72.0;

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SectionLabel(text);
}

class _SceneInspector extends StatelessWidget {
  const _SceneInspector({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final scene = studio.scene;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Scene'),
        _TextProperty(label: 'Name', value: scene.name, onCommit: studio.rename),
        const SizedBox(height: 8),
        _Fact('Size', '${scene.width.round()} × ${scene.height.round()} px'),
        _Fact('Gravity', '${scene.gravity.round()} px/s²'),
        _Fact('Template', scene.template),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: _labelWidth, child: Text('Theme', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground))),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in const ['forest', 'desert', 'night']) SkToggle('${t[0].toUpperCase()}${t.substring(1)}', on: scene.theme == t, onChanged: (_) => studio.setTheme(t))],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Select an object to edit it, or pick a tool and click the scene to place one.', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5)),
      ],
    );
  }
}

class _ObjectInspector extends StatelessWidget {
  const _ObjectInspector({super.key, required this.studio, required this.object});

  final StudioController studio;
  final SceneObject object;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    void set(SceneObject o) => studio.update(o);
    Widget param(String label, String behaviour, String key, {String unit = ''}) => _NumberProperty(
          label: label,
          unit: unit,
          value: (object.param(behaviour, key) ?? 0).toDouble(),
          onCommit: (v) => set(object.withParam(behaviour, key, v)),
        );
    final behaviourFields = switch (object.type) {
      SceneObjectType.player => [param('Run speed', 'controller', 'speed', unit: 'px/s'), param('Jump', 'controller', 'jump', unit: 'px/s')],
      SceneObjectType.coin => [param('Points', 'collectible', 'points')],
      SceneObjectType.enemy => [param('Patrol from', 'patrol', 'from', unit: 'x'), param('Patrol to', 'patrol', 'to', unit: 'x'), param('Speed', 'patrol', 'speed', unit: 'px/s')],
      _ => <Widget>[],
    };
    final jump = object.type == SceneObjectType.player
        ? Jump(speed: (object.param('controller', 'speed') ?? 260).toDouble(), takeoff: (object.param('controller', 'jump') ?? 640).toDouble(), gravity: studio.scene.gravity)
        : null;
    final behaviourName = switch (object.type) {
      SceneObjectType.player => 'Controller',
      SceneObjectType.platform => 'Solid',
      SceneObjectType.coin => 'Collectible',
      SceneObjectType.enemy => 'Patrol',
      SceneObjectType.finish => 'Goal',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(typeIcons[object.type], size: 16, color: SkTokens.brand),
            const SizedBox(width: 8),
            Expanded(child: Text(object.type.name.toUpperCase(), style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground, spacing: 0.66))),
            Text(object.id, style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)),
          ],
        ),
        if (studio.shared != null && object.by != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: studio.shared!.colorOf(object.by), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text('Made by ${studio.shared!.nameOf(object.by)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground))),
          ]),
        ],
        const SizedBox(height: 10),
        _TextProperty(label: 'Name', value: object.name, onCommit: (v) => set(object.copyWith(name: v))),
        const SizedBox(height: 18),
        const _Label('Transform'),
        Row(children: [
          Expanded(child: _NumberProperty(label: 'X', value: object.x, onCommit: (v) => set(object.copyWith(x: v)))),
          const SizedBox(width: 8),
          Expanded(child: _NumberProperty(label: 'Y', value: object.y, onCommit: (v) => set(object.copyWith(y: v)))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _NumberProperty(label: 'W', value: object.w, onCommit: (v) => set(object.copyWith(w: v < 8 ? 8 : v)))),
          const SizedBox(width: 8),
          Expanded(child: _NumberProperty(label: 'H', value: object.h, onCommit: (v) => set(object.copyWith(h: v < 8 ? 8 : v)))),
        ]),
        const SizedBox(height: 18),
        _Label('Behaviour · $behaviourName'),
        if (behaviourFields.isEmpty)
          Text(
            object.type == SceneObjectType.platform ? 'Stands still. The player stands on its top.' : 'Touching it wins the game.',
            style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5),
          ),
        for (final f in behaviourFields) ...[f, const SizedBox(height: 8)],
        if (jump != null)
          Text('Jumps ${jump.height.round()} px high and ${jump.reach(0).round()} px far on flat ground.', style: context.mono(size: SkTokens.textCaption, color: c.positive)),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerLeft, child: SkButton('Delete', kind: SkButtonKind.secondary, icon: Icons.delete_outline_rounded, onPressed: studio.deleteSelected)),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: _labelWidth, child: Text(label, style: context.sans(size: SkTokens.textSmall, color: context.sk.mutedForeground))),
          Expanded(child: Text(value, style: context.mono(size: SkTokens.textSecondary))),
        ]),
      );
}

/// A text field that commits when you press Enter or leave it.
class _TextProperty extends StatefulWidget {
  const _TextProperty({required this.label, required this.value, required this.onCommit});

  final String label;
  final String value;
  final ValueChanged<String> onCommit;

  @override
  State<_TextProperty> createState() => _TextPropertyState();
}

class _TextPropertyState extends State<_TextProperty> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onCommit(_text.text);
    });
  }

  @override
  void didUpdateWidget(_TextProperty old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: _labelWidth, child: Text(widget.label, style: context.sans(size: SkTokens.textSmall, color: context.sk.mutedForeground))),
      Expanded(child: Focus(focusNode: _focus, child: SkTextField(controller: _text, height: 30, onSubmitted: widget.onCommit))),
    ]);
  }
}

/// A number field that commits when you press Enter or leave it; anything that is not a number is ignored.
class _NumberProperty extends StatefulWidget {
  const _NumberProperty({required this.label, required this.value, required this.onCommit, this.unit = ''});

  final String label;
  final double value;
  final String unit;
  final ValueChanged<double> onCommit;

  @override
  State<_NumberProperty> createState() => _NumberPropertyState();
}

class _NumberPropertyState extends State<_NumberProperty> {
  late final _text = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  static String _format(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  void _commit() {
    final v = double.tryParse(_text.text.trim());
    if (v == null) {
      _text.text = _format(widget.value);
    } else if (v != widget.value) {
      widget.onCommit(v);
    }
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_NumberProperty old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != _format(widget.value)) _text.text = _format(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Row(children: [
      SizedBox(width: widget.label.length > 1 ? _labelWidth : 16, child: Text(widget.label, style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground))),
      Expanded(child: Focus(focusNode: _focus, child: SkTextField(controller: _text, height: 30, onSubmitted: (_) => _commit()))),
      if (widget.unit.isNotEmpty) SizedBox(width: 40, child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(widget.unit, style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)))),
    ]);
  }
}

class _Checks extends StatelessWidget {
  const _Checks({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final report = studio.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Checks'),
        if (studio.scene.objects.isEmpty)
          Text('An empty scene. Add a player, a platform under it and a finish, or ask your agent to build a level.', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5))
        else if (report.issues.isEmpty)
          Row(children: [
            LiveDot(color: c.positive),
            const SizedBox(width: 10),
            Expanded(child: Text('Playable. The finish and every coin can be reached.', style: context.sans(size: SkTokens.textSmall, height: 1.4))),
          ]),
        for (final issue in studio.scene.objects.isEmpty ? const <SceneIssue>[] : report.issues)
          Pressable(
            onPressed: issue.objectId == null ? null : () => studio.select(issue.objectId),
            builder: (context, s) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(color: s.hovered ? c.muted : null, borderRadius: BorderRadius.circular(SkTokens.radiusControl)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: issue.severity == Severity.error ? c.destructive : c.warning, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(issue.message, style: context.sans(size: SkTokens.textSmall, height: 1.4))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
