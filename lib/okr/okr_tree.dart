import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'kr_row.dart';
import 'log_value.dart';
import 'okr_screens.dart';
import 'period.dart';
import 'record_screen.dart';

/// The OKR tab: the whole tree in one scrolling outline.
///
/// Areas are headings rather than destinations — an area has no properties
/// worth a screen. Objectives are the only expand/collapse level, so the
/// chevron always means the same thing.
///
/// Deliberately a flat [ListView] of heterogeneous children rather than nested
/// [ExpansionTile]s: ExpansionTile imposes its own ListTile padding and chevron
/// placement, and nesting two of them stacks two scroll-affecting animations.
///
/// Every row starts at the same left edge, `kGapXs`; only an objective's chevron
/// pushes its own title in to 32. Key results are not indented — the indent cost
/// 48dp of a title 136dp wide, and the accordion already says which objective
/// they belong to. Weight tells the levels apart: an objective is `titleSmall`
/// w700, a key result `bodyMedium` w600 with its number alongside.
class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key});
  @override
  State<GoalsTab> createState() => GoalsTabState();
}

/// What a key result's number may claim, sharing its row with a title. Narrower
/// than [KrValueCell]'s default, which the detail screen keeps.
const double _kKrValueWidth = 110;

class GoalsTabState extends State<GoalsTab> {
  List<Map<String, dynamic>> _areas = [];
  bool _loading = true;
  bool _showArchived = false;
  String _newAreaEmoji = '🎯';

  /// Objectives the user has *closed* — a mirror of `objectives.collapsed`,
  /// seeded by [_load] and written back on every toggle so the tree reopens
  /// the way it was left. The column defaults to 0, which is what keeps a new
  /// or renewed objective expanded.
  final Set<String> _collapsed = {};

  bool _isExpanded(String id) => !_collapsed.contains(id);

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Public so the nav shell can reload the tab on entry.
  Future<void> reload() async {
    final areas =
        await DBHelper().getAreasWithRollup(includeArchived: _showArchived);
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _loading = false;
      _collapsed
        ..clear()
        ..addAll([
          for (final a in areas)
            for (final o in (a['objectives'] as List))
              if (o['collapsed'] == 1) o['id'] as String,
        ]);
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
                  DBHelper().setObjectivesCollapsed(_allObjectiveIds, false);
                case 'collapse':
                  setState(() => _collapsed.addAll(_allObjectiveIds));
                  DBHelper().setObjectivesCollapsed(_allObjectiveIds, true);
                case 'archived':
                  setState(() => _showArchived = !_showArchived);
                  reload();
                case 'backup':
                  _copyBackup();
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
              const PopupMenuItem(value: 'backup', child: Text('Copy backup')),
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
              onRefresh: reload,
              child: ListView(
                padding: kListPadding,
                children: [
                  for (final a in _areas) ..._areaSection(a),
                  const SizedBox(height: kGapMd),
                  InlineAddField(
                    label: 'Add area',
                    hint: 'Training, Books, Body…',
                    leading: _areaEmojiButton(),
                    onSubmit: (name) async {
                      await DBHelper().insertArea(name, icon: _newAreaEmoji);
                      _newAreaEmoji = '🎯';
                      await reload();
                    },
                  ),
                  // Room to scroll the last row clear of the FAB.
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  /// Puts the whole database on the clipboard as JSON, to paste anywhere that
  /// isn't this phone.
  ///
  /// The clipboard rather than a share sheet or a file: it needs no dependency
  /// and no platform wiring, and pasting into a note is already a backup. Says
  /// how many rows went, because a silent copy gives no reason to believe it
  /// worked.
  Future<void> _copyBackup() async {
    final data = await DBHelper().exportAll();
    final rows = (data['tables'] as Map<String, dynamic>)
        .values
        .fold<int>(0, (n, t) => n + (t as List).length);
    await Clipboard.setData(ClipboardData(text: jsonEncode(data)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $rows rows')),
    );
  }

  /// Expands one objective and reloads — the landing move after a Record
  /// session. The write must precede the reload, which re-seeds [_collapsed]
  /// from the rows. Public so the nav shell can land here from another tab.
  Future<void> reveal(String? objectiveId) async {
    if (objectiveId != null) {
      await DBHelper().setObjectiveCollapsed(objectiveId, false);
    }
    await reload();
  }

  Future<void> _openRecord() async {
    Map<String, dynamic>? last;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RecordScreen(onLogged: (k) => last = k)));
    await reveal(last?['objective_id'] as String?);
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
        // The gesture is the one thing here that can't be seen.
        _hint('Long-press to add an objective', indent: kGapXl),
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
      if (_areas.length > 1)
        SheetAction(
            icon: Icons.swap_vert,
            label: 'Reorder areas',
            onTap: _reorderAreas),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteArea(a)),
    ]);
  }

  Future<void> _reorderAreas() async {
    final ids = await showReorderSheet(context, title: 'Reorder areas', entries: [
      for (final a in _areas)
        (a['id'] as String, '${a['icon'] ?? '🎯'}  ${a['name']}'),
    ]);
    if (ids == null) return;
    await DBHelper().reorderAreas(ids);
    reload();
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
    reload();
  }

  Future<void> _changeAreaEmoji(Map<String, dynamic> a) async {
    final emoji = await pickEmoji(context);
    if (emoji == null) return;
    await DBHelper().updateArea(a['id'], icon: emoji);
    reload();
  }

  Future<void> _renameArea(Map<String, dynamic> a) async {
    final name =
        await promptText(context, title: 'Rename area', initial: a['name']);
    if (name != null && name.isNotEmpty) {
      await DBHelper().updateArea(a['id'], name: name);
      reload();
    }
  }

  Future<void> _confirmDeleteArea(Map<String, dynamic> a) async {
    final ok = await confirmDelete(context,
        title: 'Delete area',
        message: 'Delete "${a['name']}" and everything under it? '
            'Its objectives, key results and their measurements go too.');
    if (!ok) return;
    await DBHelper().deleteArea(a['id']);
    reload();
  }

  // ---------- Objectives ----------

  List<Widget> _objectiveSection(Map<String, dynamic> o) {
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
      onTap: () {
        final id = o['id'] as String;
        setState(() => open ? _collapsed.add(id) : _collapsed.remove(id));
        DBHelper().setObjectiveCollapsed(id, open);
      },
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

  Widget _archivedLabel() => Text('archived',
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));

  /// The objectives shown beside [o] — its area's list as loaded, so with the
  /// archive hidden a reorder renumbers only the visible rows.
  List<Map<String, dynamic>> _objectiveSiblings(Map<String, dynamic> o) {
    final area = _areas.firstWhere((a) => a['id'] == o['area_id']);
    return (area['objectives'] as List).cast<Map<String, dynamic>>();
  }

  void _objectiveMenu(Map<String, dynamic> o) {
    showActionSheet(context, title: o['title'], actions: [
      SheetAction(
          icon: Icons.add, label: 'Add key result', onTap: () => _addKr(o)),
      SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => _renameObjective(o)),
      if (_objectiveSiblings(o).length > 1)
        SheetAction(
            icon: Icons.swap_vert,
            label: 'Reorder objectives',
            onTap: () => _reorderObjectives(o)),
      ..._closeOrReopen(o),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteObjective(o)),
    ]);
  }

  Future<void> _reorderObjectives(Map<String, dynamic> o) async {
    final ids =
        await showReorderSheet(context, title: 'Reorder objectives', entries: [
      for (final s in _objectiveSiblings(o))
        (s['id'] as String, s['title'] as String),
    ]);
    if (ids == null) return;
    await DBHelper().reorderObjectives(ids);
    reload();
  }

  /// Closing a quarter archives the objective and clones it into the next one,
  /// so offering it again on the archive would mint a second copy. An archived
  /// objective gets the way back instead.
  List<SheetAction> _closeOrReopen(Map<String, dynamic> o) {
    if (o['status'] == 'archived') {
      return [
        SheetAction(
            icon: Icons.unarchive_outlined,
            label: 'Reopen',
            onTap: () => _setObjectiveStatus(o, 'active')),
      ];
    }
    return [
      SheetAction(
          icon: Icons.flag_outlined,
          label: 'Close quarter · grade + renew',
          onTap: () => _closeQuarter(o)),
      SheetAction(
          icon: Icons.archive_outlined,
          label: 'Archive without grading',
          onTap: () => _setObjectiveStatus(o, 'archived')),
    ];
  }

  Future<void> _setObjectiveStatus(
      Map<String, dynamic> o, String status) async {
    await DBHelper().updateObjectiveStatus(o['id'], status);
    // Reopening while the archive is hidden would drop the row out of sight;
    // archiving while it's hidden is the point.
    reload();
  }

  Future<void> _renameObjective(Map<String, dynamic> o) async {
    final t = await promptText(context,
        title: 'Rename objective', initial: o['title']);
    if (t != null && t.isNotEmpty) {
      await DBHelper().updateObjective(o['id'], title: t);
      reload();
    }
  }

  Future<void> _confirmDeleteObjective(Map<String, dynamic> o) async {
    final ok = await confirmDelete(context,
        title: 'Delete objective',
        message: 'Delete "${o['title']}" and its key results?');
    if (!ok) return;
    await DBHelper().deleteObjective(o['id']);
    reload();
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
    reload();
  }

  // ---------- Key results ----------

  /// The objective's key results, at the same left edge as everything else. No
  /// add button here either — long-press the objective.
  Widget _krBlock(Map<String, dynamic> o) {
    final krs = (o['key_results'] as List).cast<Map<String, dynamic>>();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: kGapSm),
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
          padding: const EdgeInsets.fromLTRB(kGapXs, kGapSm, kGapXs, kGapSm),
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
              KrValueCell(k, maxWidth: _kKrValueWidth),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openKr(Map<String, dynamic> k) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => KrDetailScreen(kr: k)));
    reload();
  }

  Future<void> _addKr(Map<String, dynamic> o) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => KrEditScreen(objectiveId: o['id'] as String)),
    );
    if (created == true) reload();
  }

  List<Map<String, dynamic>> _krSiblings(Map<String, dynamic> k) {
    final o = [for (final a in _areas) ...(a['objectives'] as List)]
        .cast<Map<String, dynamic>>()
        .firstWhere((o) => o['id'] == k['objective_id']);
    return (o['key_results'] as List).cast<Map<String, dynamic>>();
  }

  void _krMenu(Map<String, dynamic> k) {
    showActionSheet(context, title: k['title'], actions: [
      SheetAction(
          icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editKr(k)),
      if (_krSiblings(k).length > 1)
        SheetAction(
            icon: Icons.swap_vert,
            label: 'Reorder key results',
            onTap: () => _reorderKrs(k)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteKr(k)),
    ]);
  }

  Future<void> _reorderKrs(Map<String, dynamic> k) async {
    final ids =
        await showReorderSheet(context, title: 'Reorder key results', entries: [
      for (final s in _krSiblings(k)) (s['id'] as String, s['title'] as String),
    ]);
    if (ids == null) return;
    await DBHelper().reorderKeyResults(ids);
    reload();
  }

  Future<void> _editKr(Map<String, dynamic> k) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => KrEditScreen(kr: k)));
    if (changed == true) reload();
  }

  Future<void> _confirmDeleteKr(Map<String, dynamic> k) async {
    if (!await confirmDelete(context,
        title: kDeleteKrTitle, message: deleteKrMessage(k['title']))) {
      return;
    }
    await DBHelper().deleteKeyResult(k['id']);
    reload();
  }
}
