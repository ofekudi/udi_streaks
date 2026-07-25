import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'log_value.dart';
import 'okr_screens.dart';

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

/// Case-insensitive substring match on the key result's title or its
/// objective's. An empty query matches everything, in order.
List<Map<String, dynamic>> matching(
    List<Map<String, dynamic>> krs, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return krs;
  bool hit(Object? s) => s is String && s.toLowerCase().contains(q);
  return [
    for (final k in krs)
      if (hit(k['title']) || hit(k['objective_title'])) k,
  ];
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
/// daily should be at the top. Reviewing the hierarchy is the tree's job.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  List<Map<String, dynamic>> _krs = [];
  bool _loading = true;
  String _query = '';
  String? _logOpenFor; // KR id whose inline value field is open
  final _entry = TextEditingController();
  final _search = TextEditingController();

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
    _entry.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final krs = await DBHelper().getAllKeyResultsWithProgress();
    if (!mounted) return;
    final ordered =
        _order == null ? byRecency(krs) : inStoredOrder(krs, _order!);
    setState(() {
      _order ??= [for (final k in ordered) k['id'] as String];
      _krs = ordered;
      _loading = false;
    });
  }

  bool _isCount(Map<String, dynamic> k) => k['aggregation'] == 'COUNT';

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
    _load();
  }

  Future<void> _logValue(Map<String, dynamic> k) async {
    final raw = _entry.text.trim();
    if (!await logKrValue(k, raw)) {
      if (raw.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(kLogValueHelp)));
      }
      return;
    }
    _entry.clear();
    if (mounted) {
      setState(() => _logOpenFor = null);
      FocusScope.of(context).unfocus();
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = matching(_krs, _query);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Record'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search key results',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: _krs.isEmpty
                      ? _empty('No key results yet')
                      : visible.isEmpty
                          ? _empty('No key result matches "$_query".')
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(
                                  kGapMd, 0, kGapMd, kGapXl),
                              children: [for (final k in visible) _row(k)],
                            ),
                ),
              ],
            ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(kGapXl),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  Widget _row(Map<String, dynamic> k) {
    final id = k['id'] as String;
    final open = _logOpenFor == id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: kGapXs),
          title: Text(k['title'],
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          subtitle:
              Text(_subtitle(k), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _isCount(k)
              ? IconButton.filledTonal(
                  tooltip: '+1',
                  icon: const Icon(Icons.add),
                  onPressed: () => _bump(k),
                )
              : IconButton.filledTonal(
                  tooltip: 'Log a value',
                  icon: Icon(open ? Icons.close : Icons.add),
                  onPressed: () => setState(() {
                    _logOpenFor = open ? null : id;
                    _entry.clear();
                  }),
                ),
          onTap: () => _open(k),
          onLongPress: () => _menu(k),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGapXs, 0, kGapSm, kGapSm),
            child: Row(children: [
              Expanded(
                child: LogValueField(
                  controller: _entry,
                  autofocus: true,
                  unit: k['unit'] as String?,
                  onSubmit: () => _logValue(k),
                ),
              ),
              const SizedBox(width: kGapSm),
              FilledButton(
                  onPressed: () => _logValue(k), child: const Text('Log')),
            ]),
          ),
      ],
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
