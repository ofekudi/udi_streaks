import 'package:flutter/material.dart';
import '../db_helper.dart';
import 'okr_screens.dart';
import '../ui/kit.dart';

/// "Quick log" — a flat list of every key result you've defined, so you can
/// log any of them without drilling into its objective. It is NOT a separate
/// kind of thing: these are your existing key results. COUNT-style results get
/// a one-tap +1; others open to enter a value.
class HomeTrackers extends StatefulWidget {
  const HomeTrackers({super.key});
  @override
  State<HomeTrackers> createState() => _HomeTrackersState();
}

class _HomeTrackersState extends State<HomeTrackers> {
  List<Map<String, dynamic>> _krs = [];
  bool _loaded = false;
  String? _logOpenFor; // KR id whose inline value field is open
  final _entry = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final krs = await DBHelper().getAllKeyResultsWithProgress();
    if (!mounted) return;
    setState(() {
      _krs = krs;
      _loaded = true;
    });
  }

  bool _isCount(Map<String, dynamic> k) => k['aggregation'] == 'COUNT';

  String _valueLine(Map<String, dynamic> k) {
    final unit = k['unit'] ?? '';
    if (k['target'] != null) {
      return '${fmtNum(k['current'])} / ${fmtNum(k['target'])} $unit';
    }
    return '${fmtNum(k['current'])} $unit';
  }

  Future<void> _bump(Map<String, dynamic> k) async {
    await DBHelper().logMeasurement(
      keyResultId: k['trackable_id'] == null ? k['id'] as String : null,
      trackableId: k['trackable_id'] as String?,
      value: 1,
    );
    _load();
  }

  Future<void> _logValue(Map<String, dynamic> k) async {
    final raw = _entry.text.trim();
    final v = parseValue(raw);
    if (v == null) {
      if (raw.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter a number — e.g. 30, 3x10 or 10,9,8')));
      }
      return;
    }
    await DBHelper().logMeasurement(
      keyResultId: k['trackable_id'] == null ? k['id'] as String : null,
      trackableId: k['trackable_id'] as String?,
      value: v,
      unit: k['unit'] as String?,
      // Keep the exact notation ("10,9,8", "3x10") so the history remembers it.
      note: raw == fmtNum(v) ? null : raw,
    );
    _entry.clear();
    if (mounted) {
      setState(() => _logOpenFor = null);
      FocusScope.of(context).unfocus();
    }
    _load();
  }

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
          subtitle: Text(_valueLine(k)),
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
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => KrEditScreen(kr: k)),
          );
          if (changed == true) _load();
        },
      ),
      SheetAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onTap: () => _confirmDelete(k),
      ),
    ]);
  }

  Future<void> _confirmDelete(Map<String, dynamic> k) async {
    if (!await confirmDelete(context,
        title: kDeleteKrTitle, message: deleteKrMessage(k['title']))) {
      return;
    }
    await DBHelper().deleteKeyResult(k['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Quick log',
            subtitle:
                'Log any of your key results in one tap — no need to open its objective. Counts get a +1; others open to enter a value.'),
        if (_loaded && _krs.isEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: kGapXs, vertical: kGapSm),
            child: Text(
              'No key results yet. Add an area and objective above, then add key results to log here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        for (final k in _krs) _row(k),
      ],
    );
  }
}
