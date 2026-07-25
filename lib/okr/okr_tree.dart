import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'log_value.dart';
import 'okr_screens.dart';
import 'period.dart';
import 'record_screen.dart';

/// The OKR tab: the whole tree in one scrolling outline.
///
/// Areas are headings rather than destinations — an area has no properties
/// worth a screen. Objectives are the only expand/collapse level, so the
/// chevron always means the same thing. Key results sit indented behind a
/// hairline guide.
///
/// Deliberately a flat [ListView] of heterogeneous children rather than nested
/// [ExpansionTile]s: ExpansionTile imposes its own ListTile padding and chevron
/// placement, which can't produce the indent scale below, and nesting two of
/// them stacks two scroll-affecting animations.
///
/// Indent scale, all off the `kGap*` ramp. Area headings and objectives share
/// the left edge — the heading is distinguished by typography, which is what
/// buys the third level its room:
///   area heading        kGapXs
///   objective title     kGapXs + 24dp chevron + kGapXs = 32
///   key result title    48, behind a hairline dropping from the chevron
class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key});
  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

/// Where the guide rule sits: the centre of the objective row's chevron, so the
/// line reads as descending from the thing you tapped.
const double _kGuideX = kGapXs + 12;

/// Left inset of key-result content — deep enough to read as a child level,
/// still leaving ~288dp of title on a 360dp phone.
const double _kKrIndent = kGapXl * 2;

class _GoalsTabState extends State<GoalsTab> {
  List<Map<String, dynamic>> _areas = [];
  bool _loading = true;
  bool _showArchived = false;
  String _newAreaEmoji = '🎯';

  /// Objectives the user has *closed*. Tracking the negative is what makes
  /// "everything expanded on load" and "a new objective is expanded" fall out
  /// for free — no reconciliation pass after an insert or a renew.
  final Set<String> _collapsed = {};

  bool _isExpanded(String id) => !_collapsed.contains(id);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final areas =
        await DBHelper().getAreasWithRollup(includeArchived: _showArchived);
    if (!mounted) return;
    // Drop collapse state for objectives that no longer exist, so a delete or
    // a renew can't leak it onto some future id.
    final live = {
      for (final a in areas)
        for (final o in (a['objectives'] as List)) o['id'] as String,
    };
    setState(() {
      _areas = areas;
      _loading = false;
      _collapsed.retainWhere(live.contains);
    });
  }

  Iterable<String> get _allObjectiveIds => [
        for (final a in _areas)
          for (final o in (a['objectives'] as List)) o['id'] as String,
      ];

  @override
  Widget build(BuildContext context) {
    final p = Period.current();
    final pct = (p.fractionElapsed * 100).round();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('${p.label} · $pct% elapsed'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'expand':
                  setState(_collapsed.clear);
                case 'collapse':
                  setState(() => _collapsed.addAll(_allObjectiveIds));
                case 'archived':
                  setState(() => _showArchived = !_showArchived);
                  _load();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'expand', child: Text('Expand all')),
              const PopupMenuItem(
                  value: 'collapse', child: Text('Collapse all')),
              PopupMenuItem(
                value: 'archived',
                child: Text(_showArchived
                    ? 'Hide archived objectives'
                    : 'Show archived objectives'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecord,
        icon: const Icon(Icons.add),
        label: const Text('Record'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: kListPadding,
                children: [
                  if (_areas.isEmpty) _emptyState(),
                  for (final a in _areas) ..._areaSection(a),
                  const SizedBox(height: kGapMd),
                  InlineAddField(
                    label: 'Add area',
                    hint: 'Training, Books, Body…',
                    leading: _areaEmojiButton(),
                    onSubmit: (name) async {
                      await DBHelper().insertArea(name, icon: _newAreaEmoji);
                      _newAreaEmoji = '🎯';
                      await _load();
                    },
                  ),
                  // Room to scroll the last row clear of the FAB.
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Future<void> _openRecord() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RecordScreen()));
    _load();
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kGapLg),
      child: Text(
        'Start with an area — a part of your life you want to track '
        '(Training, Reading, Body). Objectives and key results go under it.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  // ---------- Areas ----------

  List<Widget> _areaSection(Map<String, dynamic> a) {
    final objectives = (a['objectives'] as List).cast<Map<String, dynamic>>();
    return [
      _areaHeading(a),
      // No per-area add field: an "Add objective" row under every area is noise
      // once the whole tree is on one screen. Adding lives on long-press, and
      // the empty state is what teaches it.
      if (objectives.isEmpty)
        _hint('No objectives yet — long-press the area to add one.',
            indent: kGapXl),
      for (final o in objectives) ..._objectiveSection(o),
    ];
  }

  Widget _hint(String text, {double indent = 0}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: indent, top: kGapXs, bottom: kGapSm, right: kGapXs),
      child: Text(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  /// A quiet uppercase label, not a row you can enter. Long-press is the menu.
  Widget _areaHeading(Map<String, dynamic> a) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onLongPress: () => _areaMenu(a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kGapXs, kGapLg, kGapXs, kGapSm),
        child: Row(
          children: [
            Text(a['icon'] ?? '🎯', style: const TextStyle(fontSize: 18)),
            const SizedBox(width: kGapSm),
            Expanded(
              child: Text(
                (a['name'] as String).toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _areaMenu(Map<String, dynamic> a) {
    showActionSheet(context, title: a['name'], actions: [
      SheetAction(
          icon: Icons.add,
          label: 'Add objective',
          onTap: () => _addObjective(a)),
      SheetAction(
          icon: Icons.emoji_emotions_outlined,
          label: 'Change emoji',
          onTap: () => _changeAreaEmoji(a)),
      SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => _renameArea(a)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteArea(a)),
    ]);
  }

  /// The 48x48 emoji well next to the "Add area" field.
  Widget _areaEmojiButton() {
    return InkWell(
      onTap: () async {
        final emoji = await pickEmoji(context);
        if (emoji != null) setState(() => _newAreaEmoji = emoji);
      },
      child: Container(
        width: kTapTarget,
        height: kTapTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(kGapXs),
        ),
        child: Text(_newAreaEmoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }

  Future<void> _addObjective(Map<String, dynamic> a) async {
    final title =
        await promptText(context, title: 'New objective', initial: '');
    if (title == null || title.isEmpty) return;
    final p = Period.current();
    await DBHelper().insertObjective(
      areaId: a['id'] as String,
      title: title,
      start: p.start,
      end: p.end,
    );
    _load();
  }

  Future<void> _changeAreaEmoji(Map<String, dynamic> a) async {
    final emoji = await pickEmoji(context);
    if (emoji == null) return;
    await DBHelper().updateArea(a['id'], icon: emoji);
    _load();
  }

  Future<void> _renameArea(Map<String, dynamic> a) async {
    final name =
        await promptText(context, title: 'Rename area', initial: a['name']);
    if (name != null && name.isNotEmpty) {
      await DBHelper().updateArea(a['id'], name: name);
      _load();
    }
  }

  Future<void> _confirmDeleteArea(Map<String, dynamic> a) async {
    final ok = await confirmDelete(context,
        title: 'Delete area',
        message: 'Delete "${a['name']}" and everything under it? '
            'Its objectives, key results and their measurements go too.');
    if (!ok) return;
    await DBHelper().deleteArea(a['id']);
    _load();
  }

  // ---------- Objectives ----------

  List<Widget> _objectiveSection(Map<String, dynamic> o) {
    final krs = (o['key_results'] as List).cast<Map<String, dynamic>>();
    // Presentation only: the objective still exists and still gets graded, and
    // a second key result unfolds it back into a parent with children.
    if (krs.length == 1) return [_mergedRow(o, krs.single)];
    final open = _isExpanded(o['id'] as String);
    return [
      _objectiveRow(o, open),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: open
            ? _krBlock(o)
            : const SizedBox(width: double.infinity, height: 0),
      ),
    ];
  }

  Widget _objectiveRow(Map<String, dynamic> o, bool open) {
    final theme = Theme.of(context);
    final score = o['score'] as double?;
    final archived = o['status'] == 'archived';
    return InkWell(
      onTap: () => setState(() {
        final id = o['id'] as String;
        open ? _collapsed.add(id) : _collapsed.remove(id);
      }),
      onLongPress: () => _objectiveMenu(o),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kTapTarget),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kGapXs, kGapSm, kGapXs, kGapSm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                child: AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: open ? 0 : -0.25,
                  child: Icon(Icons.expand_more,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: kGapXs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(o['title'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: archived
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        )),
                    if (archived) _archivedLabel(),
                    if (score != null) ...[
                      const SizedBox(height: kGapXs),
                      ScoreBar(score),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// An objective with exactly one key result, as one row: the KR's title, its
  /// value and its bar. No chevron — there is nothing left to expand.
  Widget _mergedRow(Map<String, dynamic> o, Map<String, dynamic> k) {
    final theme = Theme.of(context);
    final score = k['score'] as double?;
    final archived = o['status'] == 'archived';
    return InkWell(
      onTap: () => _openKr(k),
      onLongPress: () => _mergedMenu(o, k),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kTapTarget),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kGapXs, kGapSm, kGapXs, kGapSm),
          child: Row(
            children: [
              // Empty chevron slot, so titles line up with expandable ones.
              const SizedBox(width: 24 + kGapXs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(k['title'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: archived
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        )),
                    if (archived) _archivedLabel(),
                    if (k['target'] != null) ...[
                      const SizedBox(height: kGapXs),
                      ScoreBar(score ?? 0, down: krWantsDown(k)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: kGapSm),
              _valueCell(k),
            ],
          ),
        ),
      ),
    );
  }

  Widget _archivedLabel() => Text('archived',
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));

  /// Both entities' actions in one sheet, since the row stands for both.
  void _mergedMenu(Map<String, dynamic> o, Map<String, dynamic> k) {
    showActionSheet(context, title: k['title'], actions: [
      SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit key result',
          onTap: () => _editKr(k)),
      SheetAction(
          icon: Icons.add, label: 'Add key result', onTap: () => _addKr(o)),
      SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename objective',
          onTap: () => _renameObjective(o)),
      SheetAction(
          icon: Icons.flag_outlined,
          label: 'Close quarter · grade + renew',
          onTap: () => _closeQuarter(o)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteObjective(o)),
    ]);
  }

  void _objectiveMenu(Map<String, dynamic> o) {
    showActionSheet(context, title: o['title'], actions: [
      SheetAction(
          icon: Icons.add, label: 'Add key result', onTap: () => _addKr(o)),
      SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => _renameObjective(o)),
      SheetAction(
          icon: Icons.flag_outlined,
          label: 'Close quarter · grade + renew',
          onTap: () => _closeQuarter(o)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteObjective(o)),
    ]);
  }

  Future<void> _renameObjective(Map<String, dynamic> o) async {
    final t = await promptText(context,
        title: 'Rename objective', initial: o['title']);
    if (t != null && t.isNotEmpty) {
      await DBHelper().updateObjective(o['id'], title: t);
      _load();
    }
  }

  Future<void> _confirmDeleteObjective(Map<String, dynamic> o) async {
    final ok = await confirmDelete(context,
        title: 'Delete objective',
        message: 'Delete "${o['title']}" and its key results?');
    if (!ok) return;
    await DBHelper().deleteObjective(o['id']);
    _load();
  }

  Future<void> _closeQuarter(Map<String, dynamic> o) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuarterCloseScreen(
          objective: o,
          krs: (o['key_results'] as List).cast<Map<String, dynamic>>(),
        ),
      ),
    );
    _load();
  }

  // ---------- Key results ----------

  /// The indented child block: a hairline guide plus the objective's key
  /// results. No add button here either — long-press the objective.
  Widget _krBlock(Map<String, dynamic> o) {
    final theme = Theme.of(context);
    final krs = (o['key_results'] as List).cast<Map<String, dynamic>>();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: _kGuideX, bottom: kGapSm),
      // The 1px rule itself eats a pixel of the inset.
      padding: const EdgeInsets.only(left: _kKrIndent - _kGuideX - 1),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (krs.isEmpty)
            _hint('No key results yet — long-press the objective to add one.'),
          for (final k in krs) _krRow(k),
        ],
      ),
    );
  }

  /// Two lines — title, then the bar — with the value in the right-hand column
  /// beside both, so the title has its line to itself.
  Widget _krRow(Map<String, dynamic> k) {
    final theme = Theme.of(context);
    final score = k['score'] as double?;
    return InkWell(
      onTap: () => _openKr(k),
      onLongPress: () => _krMenu(k),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kTapTarget),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, kGapSm, kGapXs, kGapSm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(k['title'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (k['target'] != null) ...[
                      const SizedBox(height: kGapXs),
                      ScoreBar(score ?? 0, down: krWantsDown(k)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: kGapSm),
              _valueCell(k),
            ],
          ),
        ),
      ),
    );
  }

  /// `3x10 / 3x12 reps`, or just the current value when the KR is track-only.
  /// Both sides read as the notation that was typed. Scales down rather than
  /// wrapping.
  Widget _valueCell(Map<String, dynamic> k) {
    final theme = Theme.of(context);
    final unit = k['unit'] ?? '';
    final text = k['target'] != null
        ? '${currentLabel(k)} / ${targetLabel(k)} $unit'
        : '${currentLabel(k)} $unit';
    final delta = krDelta(k);
    return ConstrainedBox(
      // Fits "30 / 500 reps · 3x10"; longer text scales down.
      constraints: const BoxConstraints(maxWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(text.trim(),
                maxLines: 1,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (delta != null) DeltaText(delta, down: krWantsDown(k)),
        ],
      ),
    );
  }

  Future<void> _openKr(Map<String, dynamic> k) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => KrDetailScreen(kr: k)));
    _load();
  }

  Future<void> _addKr(Map<String, dynamic> o) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => KrEditScreen(objectiveId: o['id'] as String)),
    );
    if (created == true) _load();
  }

  void _krMenu(Map<String, dynamic> k) {
    showActionSheet(context, title: k['title'], actions: [
      SheetAction(
          icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editKr(k)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteKr(k)),
    ]);
  }

  Future<void> _editKr(Map<String, dynamic> k) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => KrEditScreen(kr: k)));
    if (changed == true) _load();
  }

  Future<void> _confirmDeleteKr(Map<String, dynamic> k) async {
    if (!await confirmDelete(context,
        title: kDeleteKrTitle, message: deleteKrMessage(k['title']))) {
      return;
    }
    await DBHelper().deleteKeyResult(k['id']);
    _load();
  }
}
