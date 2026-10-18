// The studio's right column in a shared project: who is here and what their agents are doing, then two chats. Team
// is everyone: what people write and what every agent did, with Undo on each change. My agent is your thread with
// your own agent, including what teammates asked it. Typing @ in the team chat picks an agent to ask; it acts on the
// request at once, and its owner sees it in their thread.

import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'play.dart';
import 'play_view.dart' show describeRun;
import 'project.dart';
import 'studio_controller.dart';

/// Opens someone's run to watch: whose ("Giorgi's", "your"), the scene version it was played on, and its inputs.
typedef WatchRun = void Function(String whose, int version, List<Segment> run);

enum _Tab { team, mine }

class StudioRightColumn extends StatefulWidget {
  const StudioRightColumn({super.key, required this.studio, this.onWatch});

  final StudioController studio;
  final WatchRun? onWatch;

  @override
  State<StudioRightColumn> createState() => _StudioRightColumnState();
}

class _StudioRightColumnState extends State<StudioRightColumn> {
  _Tab _tab = _Tab.mine;
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'composer');
  String? _error;

  /// The "@na" being typed, when the composer is in the team tab.
  String? _query;

  StudioController get studio => widget.studio;

  static const _examples = ['Build a forest level with four platforms', 'Make it night', 'Add two coins above the highest ledge', 'Add an enemy on the ground'];

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTyping);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTyping() {
    String? query;
    final sel = _text.selection;
    if (_tab == _Tab.team && sel.isValid && sel.isCollapsed) {
      final before = _text.text.substring(0, sel.baseOffset);
      final at = before.lastIndexOf('@');
      if (at >= 0 && (at == 0 || before[at - 1] == ' ') && !before.substring(at + 1).contains(' ')) query = before.substring(at + 1).toLowerCase();
    }
    if (query != _query) setState(() => _query = query);
  }

  void _pickTab(_Tab tab) {
    setState(() {
      _tab = tab;
      _query = null;
      _error = null;
    });
  }

  /// Puts "@Name's agent " into the team composer.
  void mention(Member m) {
    final text = _tab == _Tab.team ? _text.text : '';
    final sel = _text.selection;
    final cursor = sel.isValid ? sel.baseOffset : text.length;
    final before = text.substring(0, cursor);
    final at = _query != null ? before.lastIndexOf('@') : -1;
    final head = at >= 0 ? before.substring(0, at) : (before.isEmpty || before.endsWith(' ') ? before : '$before ');
    final insert = '@${m.agentName} ';
    setState(() {
      _tab = _Tab.team;
      _query = null;
      _text.value = TextEditingValue(text: '$head$insert${text.substring(cursor)}', selection: TextSelection.collapsed(offset: head.length + insert.length));
    });
    _focus.requestFocus();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _text.text).trim();
    if (text.isEmpty) return;
    if (preset == null) _text.clear();
    setState(() {
      _error = null;
      _query = null;
    });
    final error = _tab == _Tab.team ? await studio.sayToTeam(text) : await studio.askAgent(text);
    if (mounted && error != null) setState(() => _error = error);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final shared = studio.shared;
    if (shared == null) return _Offline(border: c.border);
    // Looking at a tab reads it.
    if ((_tab == _Tab.team && shared.unreadTeam > 0) || (_tab == _Tab.mine && shared.unreadMine > 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tab == _Tab.team ? shared.readTeam() : shared.readMine());
    }
    final suggestions = _query == null ? const <Member>[] : [for (final m in shared.people) if (m.name.toLowerCase().startsWith(_query!) || m.agentName.toLowerCase().startsWith(_query!)) m];
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _People(
            shared: shared,
            onAsk: (m) {
              if (m.id != shared.you) return mention(m);
              _pickTab(_Tab.mine);
              _focus.requestFocus();
            },
          ),
          Divider(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              Expanded(child: _TabButton(label: 'Team', unread: shared.unreadTeam, on: _tab == _Tab.team, onTap: () => _pickTab(_Tab.team))),
              const SizedBox(width: 6),
              Expanded(child: _TabButton(label: 'My agent', unread: shared.unreadMine, on: _tab == _Tab.mine, onTap: () => _pickTab(_Tab.mine))),
            ]),
          ),
          Expanded(child: _tab == _Tab.team ? _TeamList(studio: studio, shared: shared, onWatch: widget.onWatch) : _ThreadList(studio: studio, shared: shared, onExample: _send)),
          if (suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Container(
                decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(SkTokens.radiusBubble), border: Border.all(color: c.border)),
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in suggestions.take(5))
                      Pressable(
                        onPressed: () => mention(m),
                        builder: (context, s) => Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(color: s.hovered ? c.muted : null, borderRadius: BorderRadius.circular(SkTokens.radiusControl)),
                          child: Row(children: [
                            Icon(Icons.auto_awesome, size: 13, color: m.color),
                            const SizedBox(width: 8),
                            Expanded(child: Text(m.id == shared.you ? 'Your agent' : m.agentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: SkTokens.textSmall))),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(_error!, style: context.sans(size: SkTokens.textSecondary, color: c.destructive, height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: _ComposerField(
                  controller: _text,
                  focus: _focus,
                  placeholder: _tab == _Tab.team ? 'Message, or @ an agent' : 'Ask your agent…',
                  onSubmitted: () => suggestions.isNotEmpty ? mention(suggestions.first) : _send(),
                ),
              ),
              const SizedBox(width: 8),
              SkButton('Send', height: 34, onPressed: _send),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline({required this.border});
  final Color border;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: border))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 16),
            const SizedBox(width: 8),
            Text('Working offline', style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Agents and the team chat live in a shared project on a Skittles server. Start one (cd server && npm start), then choose Start creating on the welcome screen.',
            style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Who is in the project now (people who left are not listed). Each row says what that person's agent is doing; a
/// teammate's row asks their agent.
class _People extends StatelessWidget {
  const _People({required this.shared, required this.onAsk});

  final SharedProject shared;
  final ValueChanged<Member> onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final people = shared.people;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 196),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: _Caption('People', trailing: '${people.where((m) => m.online).length} online'),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final m in people)
                  Tooltip(
                    message: m.id == shared.you ? 'You' : 'Ask ${m.agentName}',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Pressable(
                      onPressed: () => onAsk(m),
                      builder: (context, s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(color: s.hovered ? c.muted : null, borderRadius: BorderRadius.circular(SkTokens.radiusControl)),
                        child: Row(
                          children: [
                            SkAvatar(letter: m.letter, color: m.color, online: true),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: m.name, style: context.sans(size: SkTokens.textSmall, weight: FontWeight.w500)),
                                      if (m.id == shared.you) TextSpan(text: '  you', style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)),
                                    ]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  _AgentLine(member: m, shared: shared),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentLine extends StatelessWidget {
  const _AgentLine({required this.member, required this.shared});

  final Member member;
  final SharedProject shared;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final a = member.agent;
    final style = context.sans(size: SkTokens.textSecondary, color: a.thinking ? c.foreground : c.mutedForeground);
    final forSomeoneElse = a.forId != null && a.forId != member.id;
    final text = !a.thinking
        ? 'Agent idle'
        : '${forSomeoneElse ? 'For ${a.forId == shared.you ? 'you' : shared.nameOf(a.forId)}: ' : ''}${a.task ?? 'working'}${a.queued > 0 ? ' · ${a.queued} waiting' : ''}';
    return Row(children: [
      Icon(Icons.auto_awesome, size: 11, color: a.thinking ? member.color : c.mutedForeground),
      const SizedBox(width: 6),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      if (a.thinking) ...[const SizedBox(width: 6), TypingDots(color: member.color)],
    ]);
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.trailing});
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

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.on, required this.onTap, this.unread = 0});

  final String label;
  final bool on;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Pressable(
      onPressed: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 30,
        decoration: BoxDecoration(
          color: on ? c.muted : (s.hovered ? c.muted.withValues(alpha: 0.5) : Colors.transparent),
          borderRadius: BorderRadius.circular(SkTokens.radiusControl),
          border: Border.all(color: on ? c.border : Colors.transparent),
          boxShadow: s.focused ? focusRing(c.background, c.foreground) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.sans(size: SkTokens.textSmall, weight: on ? FontWeight.w600 : FontWeight.w400, color: on ? c.foreground : c.mutedForeground))),
            if (unread > 0 && !on) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: SkTokens.brand, borderRadius: BorderRadius.circular(SkTokens.radiusPill)),
                child: Text('$unread', style: context.mono(size: 10, weight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The team chat: messages and every agent's reports, newest at the bottom, and who is working right now.
class _TeamList extends StatelessWidget {
  const _TeamList({required this.studio, required this.shared, this.onWatch});

  final StudioController studio;
  final SharedProject shared;
  final WatchRun? onWatch;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final messages = shared.team;
    final working = [for (final m in shared.people) if (m.agent.thinking) m];
    if (messages.isEmpty && working.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(
          'Everyone in the project sees this chat, and what every agent changes. Type @ to ask someone\'s agent; it acts right away, and its owner sees it.',
          style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5),
        ),
      );
    }
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      children: [
        for (final m in working.reversed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              TypingDots(color: m.color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${m.id == shared.you ? 'Your agent' : m.agentName} is working${m.agent.forId != null && m.agent.forId != m.id ? ' for ${m.agent.forId == shared.you ? 'you' : shared.nameOf(m.agent.forId)}' : ''}…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.sans(size: SkTokens.textSecondary, color: c.mutedForeground),
                ),
              ),
            ]),
          ),
        for (var i = messages.length - 1; i >= 0; i--)
          Padding(
            padding: EdgeInsets.only(top: i > 0 && messages[i].kind == 'chat' && messages[i - 1].kind == 'chat' && messages[i - 1].from == messages[i].from ? 2 : 12),
            child: messages[i].kind == 'playtest'
                ? PlaytestCard(message: messages[i], studio: studio, shared: shared, onWatch: onWatch)
                : messages[i].agent
                ? AgentReport(studio: studio, shared: shared, owner: messages[i].from, forId: messages[i].forId, text: messages[i].text, notes: messages[i].notes, outcome: messages[i].outcome, reason: messages[i].reason, change: messages[i].change, task: messages[i].task, undoneBy: messages[i].undoneBy)
                : _ChatLine(message: messages[i], shared: shared, header: i == 0 || messages[i - 1].kind != 'chat' || messages[i - 1].from != messages[i].from),
          ),
      ],
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.message, required this.shared, required this.header});

  final TeamMessage message;
  final SharedProject shared;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final member = shared.members[message.from];
    final color = member?.color ?? c.mutedForeground;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 22, child: header ? SkAvatar(letter: member?.letter ?? '?', color: color) : null),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (header) ...[
                Text(message.from == shared.you ? 'You' : shared.nameOf(message.from), style: context.sans(size: SkTokens.textSecondary, weight: FontWeight.w600, color: color)),
                const SizedBox(height: 2),
              ],
              Text.rich(_withMentions(context, message.text, shared), style: context.sans(size: SkTokens.textSmall, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The text with each "@Name's agent" in that member's colour.
TextSpan _withMentions(BuildContext context, String text, SharedProject shared) {
  final names = [for (final m in shared.members.values) RegExp.escape(m.agentName)];
  if (names.isEmpty) return TextSpan(text: text);
  final pattern = RegExp('@(${names.join('|')})', caseSensitive: false);
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in pattern.allMatches(text)) {
    spans.add(TextSpan(text: text.substring(last, match.start)));
    final who = shared.members.values.firstWhere((m) => m.agentName.toLowerCase() == match.group(1)!.toLowerCase());
    spans.add(TextSpan(text: match.group(0), style: TextStyle(color: who.color, fontWeight: FontWeight.w600)));
    last = match.end;
  }
  spans.add(TextSpan(text: text.substring(last)));
  return TextSpan(children: spans);
}

/// Your thread with your agent: your requests, teammates' requests, and its answers.
class _ThreadList extends StatelessWidget {
  const _ThreadList({required this.studio, required this.shared, required this.onExample});

  final StudioController studio;
  final SharedProject shared;
  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final thread = shared.myThread;
    final me = shared.me;
    if (thread.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        children: [
          Text('Your agent changes the scene with checked actions, never code. Teammates can ask it too; you see their requests here and can undo them.', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground, height: 1.5)),
          const SizedBox(height: 12),
          for (final e in _StudioRightColumnState._examples) Padding(padding: const EdgeInsets.only(bottom: 6), child: OptionRow(title: e, onTap: () => onExample(e))),
        ],
      );
    }
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      children: [
        if (me != null && me.agent.thinking)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ChatBubble(me.agent.forId != null && me.agent.forId != me.id ? 'Working for ${shared.nameOf(me.agent.forId)}…' : 'Thinking…', kind: BubbleKind.thinking),
          ),
        for (final m in thread.reversed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: switch (m.from) {
              'member' when m.by == shared.you => ChatBubble(m.text, kind: BubbleKind.you),
              'member' => _TeammateRequest(message: m, shared: shared),
              'agent' => AgentReport(studio: studio, shared: shared, owner: m.owner, forId: null, text: m.text, notes: m.notes, outcome: m.outcome, reason: m.reason, change: m.change, task: m.task, undoneBy: m.undoneBy, inThread: true),
              _ => ChatBubble(m.text, kind: BubbleKind.system),
            },
          ),
      ],
    );
  }
}

/// A teammate asking your agent, from the team chat.
class _TeammateRequest extends StatelessWidget {
  const _TeammateRequest({required this.message, required this.shared});

  final ThreadMessage message;
  final SharedProject shared;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final color = shared.colorOf(message.by);
    return Arrive(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          color: mix(color, 0.08, c.background),
          borderRadius: BorderRadius.circular(SkTokens.radiusBubble),
          border: Border.all(color: mix(color, 0.35, c.background)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${shared.nameOf(message.by)} → your agent', style: context.mono(size: SkTokens.textCaption, weight: FontWeight.w600, color: color)),
            const SizedBox(height: 4),
            Text(message.text, style: context.sans(size: SkTokens.textSmall, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

/// What an agent did with a request: its answer, the changes, the outcome and what you can do about it.
class AgentReport extends StatelessWidget {
  const AgentReport({
    super.key,
    required this.studio,
    required this.shared,
    required this.owner,
    required this.forId,
    required this.text,
    required this.notes,
    required this.outcome,
    required this.reason,
    required this.change,
    required this.task,
    required this.undoneBy,
    this.inThread = false,
  });

  final StudioController studio;
  final SharedProject shared;
  final String owner;
  final String? forId;
  final String text;
  final List<String> notes;
  final Outcome? outcome;
  final String? reason;
  final int? change;
  final String? task;
  final String? undoneBy;

  /// In its owner's thread: no header, the thread says whose agent it is.
  final bool inThread;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final color = shared.colorOf(owner);
    final mine = owner == shared.you;
    final forOther = forId != null && forId != owner;
    final (String? status, Color tone) = switch (outcome) {
      Outcome.applied => ('✓ Applied · still playable', c.positive),
      Outcome.approved => ('Applied anyway', c.warning),
      Outcome.discarded => ('Discarded', c.mutedForeground),
      Outcome.held => ('Held: ${reason ?? 'it would break the game'}', c.warning),
      Outcome.undone => ('Undone by ${undoneBy == shared.you ? 'you' : shared.nameOf(undoneBy)}', c.mutedForeground),
      Outcome.failed => ('Failed', c.destructive),
      null => (null, c.mutedForeground),
    };
    final mayDecide = outcome == Outcome.held && task != null && (shared.you == owner || shared.you == forId || inThread);
    final mayUndo = (outcome == Outcome.applied || outcome == Outcome.approved) && change != null;
    return Arrive(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(SkTokens.radiusBubble),
          border: Border(left: BorderSide(color: color, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!inThread) ...[
              Row(children: [
                Icon(Icons.auto_awesome, size: 12, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${mine ? 'Your agent' : "${shared.nameOf(owner)}'s agent"}${forOther ? ' · for ${forId == shared.you ? 'you' : shared.nameOf(forId)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mono(size: SkTokens.textCaption, weight: FontWeight.w600, color: color),
                  ),
                ),
              ]),
              const SizedBox(height: 5),
            ],
            Text(text, style: context.sans(size: SkTokens.textSmall, height: 1.45)),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final n in notes.take(6)) Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground).copyWith(height: 1.6)),
              if (notes.length > 6) Text('… and ${notes.length - 6} more', style: context.mono(size: SkTokens.textCaption, color: c.mutedForeground)),
            ],
            if (status != null || mayUndo || mayDecide) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (status != null) Text(status, style: context.mono(size: SkTokens.textCaption, color: tone)),
                  if (mayUndo) SkButton('Undo', kind: SkButtonKind.ghost, height: 24, icon: Icons.undo_rounded, onPressed: () => studio.revert(change!)),
                  if (mayDecide) ...[
                    SkButton('Apply anyway', kind: SkButtonKind.secondary, height: 26, onPressed: () => studio.approve(task!)),
                    SkButton('Discard', kind: SkButtonKind.ghost, height: 26, onPressed: () => studio.discard(task!)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The composer's field: the site's input, with a focus node so the @ picker and Enter work.
class _ComposerField extends StatelessWidget {
  const _ComposerField({required this.controller, required this.focus, required this.placeholder, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focus;
  final String placeholder;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    OutlineInputBorder edge(Color color) => OutlineInputBorder(borderRadius: BorderRadius.circular(SkTokens.radiusControl), borderSide: BorderSide(color: color));
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focus,
        onSubmitted: (_) => onSubmitted(),
        style: context.sans(size: SkTokens.textSmall),
        cursorColor: c.foreground,
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: context.sans(size: SkTokens.textSmall, color: c.mutedForeground),
          isDense: true,
          filled: true,
          fillColor: c.background,
          hoverColor: c.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          enabledBorder: edge(c.border),
          focusedBorder: edge(c.foreground.withValues(alpha: 0.3)),
          border: edge(c.border),
        ),
      ),
    );
  }
}

/// A playtest in the team chat: a person's shared run, or the AI's run and review. The AI's problems name the
/// objects behind them and the people who made them, with a button to ask that person's agent for a fix.
class PlaytestCard extends StatelessWidget {
  const PlaytestCard({super.key, required this.message, required this.studio, required this.shared, this.onWatch});

  final TeamMessage message;
  final StudioController studio;
  final SharedProject shared;
  final WatchRun? onWatch;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    final p = message.playtest!;
    final ai = message.from == 'ai';
    final who = ai ? 'The AI' : (message.from == shared.you ? 'You' : shared.nameOf(message.from));
    final color = ai ? SkTokens.brand : shared.colorOf(message.from);
    final asker = message.forId == null ? '' : ' · asked by ${message.forId == shared.you ? 'you' : shared.nameOf(message.forId)}';
    String nameOf(String id) => studio.scene.byId(id)?.name ?? id;
    final r = p.result;
    return Arrive(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(SkTokens.radiusBubble), border: Border(left: BorderSide(color: color, width: 2))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(ai ? Icons.smart_toy_outlined : Icons.sports_esports_outlined, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ai ? 'AI playtest$asker · v${p.version}' : '$who played · v${p.version}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mono(size: SkTokens.textCaption, weight: FontWeight.w600, color: color),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            if (p.status == 'playing')
              Row(children: [
                TypingDots(color: color),
                const SizedBox(width: 12),
                Expanded(child: Text('The AI is playing the level…', style: context.sans(size: SkTokens.textSmall, color: c.mutedForeground))),
              ])
            else if (p.status == 'failed')
              Text(message.text, style: context.sans(size: SkTokens.textSmall, color: c.destructive, height: 1.45))
            else ...[
              if (r != null)
                Text(
                  ai
                      ? [
                          p.finished == true ? 'Finished in ${r.time.toStringAsFixed(1)} s without falling' : 'Could not reach the finish',
                          if (r.coinsTotal > 0) p.coinsMissed.isEmpty ? 'every coin reachable' : 'cannot reach ${p.coinsMissed.map(nameOf).join(', ')}',
                        ].join(' · ')
                      : describeRun(r),
                  style: context.mono(size: SkTokens.textCaption, color: (ai ? p.finished == true : r.won) ? c.positive : c.warning).copyWith(height: 1.5),
                ),
              if ((p.note ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text('“${p.note}”', style: context.sans(size: SkTokens.textSmall, height: 1.45))],
              if ((p.summary ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(p.summary!, style: context.sans(size: SkTokens.textSmall, height: 1.45))],
              for (final issue in p.issues) _Issue(issue: issue, studio: studio, shared: shared),
              if (p.run.isNotEmpty && onWatch != null) ...[
                const SizedBox(height: 8),
                SkButton('Watch run', kind: SkButtonKind.ghost, height: 24, icon: Icons.play_circle_outline_rounded, onPressed: () => onWatch!(ai ? "the AI's" : (message.from == shared.you ? 'your' : "$who's"), p.version, p.run)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Issue extends StatelessWidget {
  const _Issue({required this.issue, required this.studio, required this.shared});

  final PlaytestNote issue;
  final StudioController studio;
  final SharedProject shared;

  @override
  Widget build(BuildContext context) {
    final c = context.sk;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 7, height: 7, decoration: BoxDecoration(color: issue.problem ? c.destructive : c.warning, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.text, style: context.sans(size: SkTokens.textSmall, height: 1.45)),
                for (final owner in issue.owners)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SkButton(
                      owner == shared.you ? 'Ask my agent to fix it' : "Ask ${shared.nameOf(owner)}'s agent",
                      kind: SkButtonKind.ghost,
                      height: 24,
                      icon: Icons.auto_awesome,
                      onPressed: () => studio.askAgent('From the AI playtest: ${issue.text}', owner: owner == shared.you ? null : owner),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
