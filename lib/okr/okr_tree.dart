import 'package:flutter/material.dart';

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
/// **Hierarchy comes from containment, never from horizontal offset.** An
/// objective and its key results are one filled card, and every row in the tree
/// starts on the same edge — `kGapSm` of page padding plus `kGapMd` of card
/// padding — with an area heading spending that column on its emoji and the two
/// title levels on their titles. The chevron is trailing for the same reason: a
/// leading one occupied 24dp and pushed an objective's own title in to 32 while
/// its key results stayed at 4, so a child rendered left of its parent.
/// Indenting the children instead was tried and reverted — it left 136dp of
/// title on a 360dp phone. Weight tells the levels apart: an objective is
/// `titleSmall` w700, a key result `bodyMedium` w600.
/// `test/okr_tree_layout_test.dart` pins the shared edge.
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

  @override
  Widget build(BuildContext context) {
    final p = Period.current();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('${p.label} · ${fmtPct(p.fractionElapsed)} elapsed'),
        actions: [
          // Areas reorder from here rather than from a row's long-press: every
          // other level reorders from its parent, and an area's parent is the
          // tab.
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'archived':
                  setState(() => _showArchived = !_showArchived);
                  reload();
                case 'reorder':
                  _reorderAreas();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archived',
                child: Text(_showArchived
                    ? 'Hide archived objectives'
                    : 'Show archived objectives'),
              ),
              if (_areas.length > 1)
                const PopupMenuItem(
                    value: 'reorder', child: Text('Reorder areas')),
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
                // Narrower than [kListPadding]: the objective cards carry their
                // own inset, and together the two put every title at kGapMd +
                // kGapSm from the screen edge.
                padding:
                    const EdgeInsets.fromLTRB(kGapSm, kGapMd, kGapSm, kGapMd),
                children: [
                  for (final a in _areas) ..._areaSection(a),
                  const SizedBox(height: kGapMd),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kGapXs),
                    child: InlineAddField(
                      label: 'Add area',
                      hint: 'Training, Books, Body…',
                      leading: _areaEmojiButton(),
                      onSubmit: (name) async {
                        await DBHelper().insertArea(name, icon: _newAreaEmoji);
                        _newAreaEmoji = '🎯';
                        await reload();
                      },
                    ),
                  ),
                  // Room to scroll the last row clear of the FAB.
                  const SizedBox(height: 80),
                ],
              ),
            ),
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
        _hint('Long-press to add an objective'),
      for (final o in objectives) _objectiveCard(o),
    ];
  }

  Widget _hint(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapMd, kGapXs, kGapMd, kGapSm),
      child: Text(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  /// A quiet uppercase label, not a row you can enter. Long-press is the menu.
  ///
  /// The rule beneath is what anchors the heading to the cards under it. Its
  /// rollup is a percent rather than a bar: an area is a heading, and a bar
  /// here would read as a fourth row in the accordion.
  Widget _areaHeading(Map<String, dynamic> a) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final score = a['score'] as double?;
    final label = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: muted,
    );
    return InkWell(
      onLongPress: () => _areaMenu(a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kGapMd, kGapLg, kGapMd, kGapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(a['icon'] ?? '🎯', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: kGapSm),
                Expanded(
                  child:
                      Text((a['name'] as String).toUpperCase(), style: label),
                ),
                if (score != null) Text(fmtPct(score), style: label),
              ],
            ),
            const SizedBox(height: kGapSm),
            Divider(
                height: 1,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant),
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
          icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editArea(a)),
      if ((a['objectives'] as List).length > 1)
        SheetAction(
            icon: Icons.swap_vert,
            label: 'Reorder objectives',
            onTap: () => _reorderObjectives(a)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteArea(a)),
    ]);
  }

  Future<void> _reorderAreas() async {
    final ids =
        await showReorderSheet(context, title: 'Reorder areas', entries: [
      for (final a in _areas)
        (a['id'] as String, '${a['icon'] ?? '🎯'}  ${a['name']}'),
    ]);
    if (ids == null) return;
    await DBHelper().reorderAreas(ids);
    reload();
  }

  /// The emoji well next to the "Add area" field.
  Widget _areaEmojiButton() {
    return EmojiWell(
      emoji: _newAreaEmoji,
      onTap: () async {
        final emoji = await pickEmoji(context);
        if (emoji != null) setState(() => _newAreaEmoji = emoji);
      },
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

  /// Emoji and name in one dialog, written in one [DBHelper.updateArea] call.
  Future<void> _editArea(Map<String, dynamic> a) async {
    final edit = await promptNameAndEmoji(context,
        title: 'Edit area',
        initialName: a['name'] as String,
        initialEmoji: (a['icon'] as String?) ?? '🎯');
    if (edit == null) return;
    await DBHelper().updateArea(a['id'], name: edit.name, icon: edit.emoji);
    reload();
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

  /// An objective and its key results as one card. Containment is what says a
  /// key result belongs to the objective above it, which is what lets every row
  /// share one left edge.
  Widget _objectiveCard(Map<String, dynamic> o) {
    final scheme = Theme.of(context).colorScheme;
    final open = _isExpanded(o['id'] as String);
    final archived = o['status'] == 'archived';
    return Card(
      margin: const EdgeInsets.only(bottom: kGapSm),
      elevation: 0,
      // An archived card sits a tone deeper, so it reads as shelved rather than
      // dressed differently. Not `surfaceContainerLowest`, which is pure white
      // and would glow against the page.
      color: archived ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      // The fill alone left the card's edge ambiguous at a glance — it is only
      // a tone off the page. The outline is what closes it.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusCard),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      // Keeps the header's ink ripple inside the rounded corners.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _objectiveHeader(o, open),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? _krBlock(o)
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }

  /// The card's own row: title, trailing chevron, and the objective's rollup as
  /// a bar the full width of the card — the same width every key result's bar
  /// gets, so the two can be compared by eye.
  Widget _objectiveHeader(Map<String, dynamic> o, bool open) {
    final theme = Theme.of(context);
    final score = o['score'] as double?;
    final archived = o['status'] == 'archived';
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: () {
          final id = o['id'] as String;
          setState(() => open ? _collapsed.add(id) : _collapsed.remove(id));
          DBHelper().setObjectiveCollapsed(id, open);
        },
        onLongPress: () => _objectiveMenu(o),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kTapTarget),
          child: Padding(
            padding: const EdgeInsets.all(kGapMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
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
                        ],
                      ),
                    ),
                    const SizedBox(width: kGapSm),
                    // No tap target of its own — the whole header toggles.
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 180),
                      turns: open ? 0 : -0.25,
                      child: Icon(Icons.expand_more,
                          size: 20, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                if (score != null) ...[
                  const SizedBox(height: kGapSm),
                  ScoreBar(score, label: o['title'] as String),
                ],
              ],
            ),
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

  void _objectiveMenu(Map<String, dynamic> o) {
    showActionSheet(context, title: o['title'], actions: [
      SheetAction(
          icon: Icons.add, label: 'Add key result', onTap: () => _addKr(o)),
      SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => _renameObjective(o)),
      if ((o['key_results'] as List).length > 1)
        SheetAction(
            icon: Icons.swap_vert,
            label: 'Reorder key results',
            onTap: () => _reorderKrs(o)),
      ..._closeOrReopen(o),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDeleteObjective(o)),
    ]);
  }

  /// The area's objectives as loaded, so with the archive hidden a reorder
  /// renumbers only the visible rows.
  Future<void> _reorderObjectives(Map<String, dynamic> a) async {
    final ids =
        await showReorderSheet(context, title: 'Reorder objectives', entries: [
      for (final o in (a['objectives'] as List).cast<Map<String, dynamic>>())
        (o['id'] as String, o['title'] as String),
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
          label: 'Archive',
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

  /// The objective's key results, inside its card and at the same left edge as
  /// everything else. No add button here either — long-press the objective.
  ///
  /// Ruled: one rule splits the objective's own summary from its children, and
  /// one between every pair of rows says where a key result ends. Proximity
  /// alone couldn't — a row's own title sits 8dp above its bar and only 16dp
  /// below the previous row's, so a bar read as easily up as down.
  Widget _krBlock(Map<String, dynamic> o) {
    final krs = (o['key_results'] as List).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rule(),
        if (krs.isEmpty)
          _hint('No key results yet — long-press the objective to add one.'),
        for (var i = 0; i < krs.length; i++) ...[
          if (i > 0) _rule(),
          _krRow(krs[i]),
        ],
        const SizedBox(height: kGapXs),
      ],
    );
  }

  /// A hairline inside a card, inset to the card's own text column.
  Widget _rule() => Divider(
        height: 1,
        thickness: 0.5,
        indent: kGapMd,
        endIndent: kGapMd,
        color: Theme.of(context).colorScheme.outlineVariant,
      );

  /// Two lines — title and value, then the bar. The number shares the first
  /// line so the bar can span the card, matching the objective's above it.
  Widget _krRow(Map<String, dynamic> k) {
    final theme = Theme.of(context);
    final score = k['score'] as double?;
    return InkWell(
      onTap: () => _openKr(k),
      onLongPress: () => _krMenu(k),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kTapTarget),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                // A two-line title and a value carrying a delta must top-align,
                // not centre against each other.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(k['title'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: kGapSm),
                  KrValueCell(k, maxWidth: _kKrValueWidth),
                ],
              ),
              if (k['target'] != null) ...[
                const SizedBox(height: kGapSm),
                ScoreBar(score ?? 0,
                    down: krWantsDown(k), label: k['title'] as String),
              ],
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

  Future<void> _reorderKrs(Map<String, dynamic> o) async {
    final ids =
        await showReorderSheet(context, title: 'Reorder key results', entries: [
      for (final k in (o['key_results'] as List).cast<Map<String, dynamic>>())
        (k['id'] as String, k['title'] as String),
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
