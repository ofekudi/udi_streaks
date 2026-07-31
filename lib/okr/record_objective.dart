import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'log_value.dart';
import 'okr_screens.dart';
import 'rows.dart';

/// What a key result's number may claim, sharing its line with a title. Less
/// than the tree gives it, and `dense`: on this page the number sits above a
/// field that has to stay comfortably tappable, so the number is what gives.
const double _kKrValueWidth = 96;

/// What the value field claims, sharing its line with the bar. It carries no
/// unit — the row above it already reads `80 / 90 kg` — and what gets typed in
/// it is short: `85`, `3x12`, `10,9,8`.
const double _kFieldWidth = 100;

/// One objective's key results, all fillable at once — the second step of
/// recording, reached by tapping an objective on [RecordScreen].
///
/// Filling is objective-scoped: a workout is every key result under one
/// objective, not rows scattered through everything. Knowing the objective is
/// also what makes the rows readable — it's the page title, so no row has to
/// repeat it, and each one is the tree's own two-line row with the field on the
/// bar's line.
///
/// Every value key result holds its own text until one commit writes them all.
/// A blank field is a key result you didn't do, which is why there is no
/// selection step.
class RecordObjectiveScreen extends StatefulWidget {
  final Map<String, dynamic> objective;

  /// Fired on every successful log with the row that took it, so the tab that
  /// opened Record can land on what was recorded. Forwarded straight through
  /// from [RecordScreen].
  final void Function(Map<String, dynamic> kr)? onLogged;

  const RecordObjectiveScreen(
      {super.key, required this.objective, this.onLogged});

  @override
  State<RecordObjectiveScreen> createState() => _RecordObjectiveScreenState();
}

class _RecordObjectiveScreenState extends State<RecordObjectiveScreen> {
  List<Map<String, dynamic>> _krs = [];
  bool _loading = true;

  /// One controller per value key result, by id. Kept for the visit only —
  /// nothing here is persisted, and leaving with text in it asks first.
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final krs = await DBHelper().getKeyResultsWithProgress(
      widget.objective['id'] as String,
      objective: widget.objective,
    );
    if (!mounted) return;
    final live = {for (final k in krs) k['id'] as String};
    setState(() {
      _krs = krs;
      _loading = false;
      // A row can be deleted from its long-press sheet mid-visit.
      for (final id in _fields.keys.toList()) {
        if (!live.contains(id)) _fields.remove(id)!.dispose();
      }
    });
  }

  bool _isCount(Map<String, dynamic> k) => k['aggregation'] == 'COUNT';

  /// The key results that take a typed value. A COUNT doesn't: its tap is the
  /// record, so it has nothing pending.
  Iterable<Map<String, dynamic>> get _valueKrs =>
      _krs.where((k) => !_isCount(k));

  /// The commit bar's count and the exit guard both read every field, so a
  /// keystroke in any one of them rebuilds the page.
  TextEditingController _fieldFor(String id) => _fields.putIfAbsent(id, () {
        final c = TextEditingController();
        c.addListener(() {
          if (mounted) setState(() {});
        });
        return c;
      });

  String _textFor(Map<String, dynamic> k) =>
      _fields[k['id']]?.text.trim() ?? '';

  int get _filled => _valueKrs.where((k) => _textFor(k).isNotEmpty).length;

  Future<void> _bump(Map<String, dynamic> k) async {
    await bumpKr(k);
    widget.onLogged?.call(k);
    _load();
  }

  /// Writes every filled field, one measurement each. A row whose text doesn't
  /// parse keeps it, so the pass can be fixed rather than retyped.
  Future<void> _logAll() async {
    final pending = [
      for (final k in _valueKrs)
        if (_textFor(k).isNotEmpty) k,
    ];
    if (pending.isEmpty) return;
    var rejected = false;
    for (final k in pending) {
      if (await logKrValue(k, _textFor(k))) {
        _fields[k['id']]?.clear();
        widget.onLogged?.call(k);
      } else {
        rejected = true;
      }
    }
    if (!mounted) return;
    if (rejected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(kLogValueHelp)));
    }
    FocusScope.of(context).unfocus();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _filled == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final count = _filled;
        if (await confirmDiscard(context,
            title:
                'Discard $count unlogged ${count == 1 ? 'value' : 'values'}?')) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.objective['title']),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _krs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(kGapXl),
                      child: Text('No key results yet'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        kGapSm, kGapMd, kGapSm, kGapMd),
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < _krs.length; i++) ...[
                              if (i > 0) const AppRule(),
                              _row(_krs[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
        bottomNavigationBar:
            _loading || _valueKrs.isEmpty ? null : _commitBar(),
      ),
    );
  }

  Widget _commitBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _filled == 0 ? null : _logAll,
              child: Text(_filled == 0 ? 'Log' : 'Log $_filled'),
            ),
          ),
        ),
      );

  /// The tree's key-result row with a field on it: title and number on the
  /// first line, the bar and the field sharing the second. Tapping the row
  /// opens the key result; the field and the `+1` take their own taps.
  Widget _row(Map<String, dynamic> k) {
    final theme = Theme.of(context);
    final score = k['score'] as double?;
    final title = k['title'] as String;
    return InkWell(
      onTap: () => _open(k),
      onLongPress: () => _menu(k),
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
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: kGapSm),
                KrValueCell(k, maxWidth: _kKrValueWidth, dense: true),
              ],
            ),
            const SizedBox(height: kGapSm),
            Row(
              children: [
                Expanded(
                  child: k['target'] != null
                      ? ScoreBar(score ?? 0,
                          down: krWantsDown(k), label: title)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: kGapMd),
                SizedBox(
                  width: _kFieldWidth,
                  child: _isCount(k)
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: IconButton.filledTonal(
                            tooltip: '+1',
                            icon: const Icon(Icons.add),
                            onPressed: () => _bump(k),
                          ),
                        )
                      // No unit and no hint: `KrValueCell` states both on the
                      // line above, so repeating them only cost width.
                      : LogValueField(
                          controller: _fieldFor(k['id'] as String),
                          hintText: '',
                          compact: true,
                          onSubmit: _logAll,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _open(Map<String, dynamic> k) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => KrDetailScreen(kr: k)),
    ).then((_) => _load());
  }

  void _menu(Map<String, dynamic> k) {
    showActionSheet(context, title: k['title'], actions: [
      SheetAction(
          icon: Icons.edit_outlined, label: 'Edit', onTap: () => _editKr(k)),
      SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _confirmDelete(k)),
    ]);
  }

  Future<void> _editKr(Map<String, dynamic> k) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => KrEditScreen(kr: k)),
    );
    if (changed == true) _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> k) async {
    if (!await confirmDelete(context,
        title: kDeleteKrTitle, message: deleteKrMessage(k['title']))) {
      return;
    }
    await DBHelper().deleteKeyResult(k['id']);
    _load();
  }
}
