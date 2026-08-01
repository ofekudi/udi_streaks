import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'record_objective.dart';
import 'rows.dart';

/// The objectives worth recording into: those with at least one key result.
/// An objective with none has nothing to record, so it's left out rather than
/// offered as a dead end.
List<Map<String, dynamic>> recordable(List<Map<String, dynamic>> objectives) => [
      for (final o in objectives)
        if ((o['key_results'] as List).isNotEmpty) o,
    ];

/// The capture surface, behind the "Record" FAB on both tabs: **pick the
/// objective, then fill its key results** on [RecordObjectiveScreen].
///
/// Two steps rather than one flat list, because filling is objective-scoped —
/// a workout is every key result under one objective. A flat list had to repeat
/// each key result's objective on the row itself, and that third line is what
/// made the rows unreadable.
///
/// It mirrors the tree: area headings, one card per objective, `sort_order`
/// throughout, so the Reorder choices carry over and the two screens read as the
/// same outline. Archived objectives are absent — you don't log into a closed
/// quarter.
class RecordScreen extends StatefulWidget {
  /// Fired on every successful log with the row that took it, so the caller
  /// can land on what was recorded. A pop result can't carry this — the system
  /// back gesture pops with null. Passed straight down to the fill page, which
  /// is where logging happens.
  final void Function(Map<String, dynamic> kr)? onLogged;

  const RecordScreen({super.key, this.onLogged});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  List<Map<String, dynamic>> _areas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final areas = await DBHelper().getAreasWithRollup();
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _loading = false;
    });
  }

  /// Areas that still have something to record, so an area whose objectives all
  /// drop out loses its heading too.
  List<(Map<String, dynamic>, List<Map<String, dynamic>>)> get _sections => [
        for (final a in _areas)
          if (recordable((a['objectives'] as List).cast<Map<String, dynamic>>())
              case final objectives when objectives.isNotEmpty)
            (a, objectives),
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : sections.isEmpty
              ? const Center(
                  child: EmptyState(Icons.flag_outlined, 'No key results yet'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      kGapSm, kGapMd, kGapSm, kGapMd),
                  children: [
                    for (final (area, objectives) in sections) ...[
                      AreaHeading(area),
                      for (final o in objectives) _objectiveCard(o),
                    ],
                    const SizedBox(height: kGapXl),
                  ],
                ),
    );
  }

  /// The objective as a way in: its title, how much it holds, and its rollup —
  /// the same card the tree gives it, with a chevron where the tree has its
  /// key results.
  Widget _objectiveCard(Map<String, dynamic> o) {
    final score = o['score'] as double?;
    final title = o['title'] as String;
    final n = (o['key_results'] as List).length;
    return AppCard(
      child: InkWell(
        onTap: () => _openObjective(o),
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
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: kTypeObjective),
                    ),
                    const SizedBox(width: kGapSm),
                    Text('$n KR', style: kTypeMetaNum),
                    const SizedBox(width: kGapXs),
                    const Icon(Icons.chevron_right,
                        size: 20, color: kInkFaint),
                  ],
                ),
                if (score != null) ...[
                  const SizedBox(height: kGapSm),
                  ScoreBar(score, label: title, height: kBarThick),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openObjective(Map<String, dynamic> o) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RecordObjectiveScreen(objective: o, onLogged: widget.onLogged),
      ),
    );
    // The bars behind are stale the moment anything was logged.
    _load();
  }
}
