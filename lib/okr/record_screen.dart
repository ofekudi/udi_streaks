import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'log_value.dart';
import 'okr_screens.dart';

/// The width of a row's value field, and of the column a COUNT's `+1` sits in.
const double _kFieldWidth = 112;

/// Newest-logged first, never-logged last, `created_at` breaking ties.
///
/// `last_logged_at` and `created_at` are both `toIso8601String()` output, so a
/// plain string compare is also a chronological one — and the explicit tiebreak
/// matters because `List.sort` isn't stable.
List<Map<String, dynamic>> byRecency(List<Map<String, dynamic>> krs) {
  final logged = <Map<String, dynamic>>[];
  final never = <Map<String, dynamic>>[];
  for (final k in krs) {
    (k['last_logged_at'] == null ? never : logged).add(k);
  }
  int byCreated(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (a['created_at'] as String).compareTo(b['created_at'] as String);
  logged.sort((a, b) {
    final c = (b['last_logged_at'] as String)
        .compareTo(a['last_logged_at'] as String);
    return c != 0 ? c : byCreated(a, b);
  });
  never.sort(byCreated);
  return [...logged, ...never];
}

/// Reapplies an order captured earlier by [byRecency]. Key results the order
/// doesn't know about (created while the page was open) go to the end.
List<Map<String, dynamic>> inStoredOrder(
    List<Map<String, dynamic>> krs, List<String> order) {
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  final sorted = [...krs];
  sorted.sort((a, b) {
    final c = (rank[a['id']] ?? order.length)
        .compareTo(rank[b['id']] ?? order.length);
    return c != 0
        ? c
        : (a['created_at'] as String).compareTo(b['created_at'] as String);
  });
  return sorted;
}

/// The capture surface, behind the "Record" FAB on the OKR tab.
///
/// Deliberately flat and recency-ordered rather than mirroring the tree: when
/// you open this you already know what you're logging, and the thing you log
/// daily should be at the top.
///
/// It fills **many key results in one pass** — a field per value key result,
/// all open at once, committed together. A blank field is a key result you
/// didn't do, which is why there's no selection step. Recency ordering is also
/// what stands in for a search box: log five exercises together and they are
/// the top five next time.
class RecordScreen extends StatefulWidget {
  /// Fired on every successful log with the row that took it, so the caller
  /// can land on what was recorded. A pop result can't carry this — the system
  /// back gesture pops with null. Logs made deeper in, on [KrDetailScreen],
  /// don't report; this is the capture list's own ledger.
  final void Function(Map<String, dynamic> kr)? onLogged;

  const RecordScreen({super.key, this.onLogged});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  List<Map<String, dynamic>> _krs = [];
  bool _loading = true;

  /// One controller per value key result, by id, so every row holds its own
  /// text until the whole pass is committed. Kept for the visit only — nothing
  /// here is persisted, and leaving with text in it asks first.
  final Map<String, TextEditingController> _fields = {};

  /// The recency order, captured once per visit. Re-sorting after every log
  /// would yank the row you just tapped out from under your finger; the list
  /// re-orders the next time you open the page, which is what you actually want.
  List<String>? _order;

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
    final krs = await DBHelper().getAllKeyResultsWithProgress();
    if (!mounted) return;
    final ordered =
        _order == null ? byRecency(krs) : inStoredOrder(krs, _order!);
    final live = {for (final k in ordered) k['id'] as String};
    setState(() {
      _order ??= [for (final k in ordered) k['id'] as String];
      _krs = ordered;
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
  Iterable<Map<String, dynamic>> get _valueKrs => _krs.where((k) => !_isCount(k));

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

  String _valueLine(Map<String, dynamic> k) {
    final unit = k['unit'] ?? '';
    if (k['target'] != null) {
      return '${currentLabel(k)} / ${targetLabel(k)} $unit'.trim();
    }
    return '${currentLabel(k)} $unit'.trim();
  }

  /// Value plus its objective — the context a flat list would otherwise lose.
  String _subtitle(Map<String, dynamic> k) {
    final obj = k['objective_title'];
    return obj == null ? _valueLine(k) : '${_valueLine(k)} · $obj';
  }

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
          title: const Text('Record'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _krs.isEmpty
                ? _empty('No key results yet')
                : ListView(
                    padding:
                        const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapXl),
                    children: [for (final k in _krs) _row(k)],
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

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(kGapXl),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  /// Title, where it stands, and its progress — enough to decide what to fill
  /// without leaving the page — beside the field that fills it.
  Widget _row(Map<String, dynamic> k) {
    final theme = Theme.of(context);
    final score = (k['score'] as num?)?.toDouble();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kTapTarget),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _open(k),
              onLongPress: () => _menu(k),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: kGapXs, vertical: kGapSm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k['title'],
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(_subtitle(k),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (k['target'] != null) ...[
                      const SizedBox(height: kGapXs),
                      ScoreBar(score ?? 0,
                          down: krWantsDown(k), label: k['title'] as String),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: kGapSm),
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
                : LogValueField(
                    controller: _fieldFor(k['id'] as String),
                    unit: k['unit'] as String?,
                    hintText: '',
                    onSubmit: _logAll,
                  ),
          ),
        ],
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
