import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'close_period.dart';
import 'period.dart';
import 'rows.dart';

/// The quarters that have been closed, newest first.
///
/// Reached from the OKR tab's overflow rather than a tab of its own: it is a
/// page you open a few times a year, and the shell is two tabs on purpose.
class PastPeriodsScreen extends StatefulWidget {
  const PastPeriodsScreen({super.key});

  @override
  State<PastPeriodsScreen> createState() => _PastPeriodsScreenState();
}

class _PastPeriodsScreenState extends State<PastPeriodsScreen> {
  List<({Period period, double? score, int objectives})> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DBHelper();
    final rows = <({Period period, double? score, int objectives})>[];
    for (final p in await db.closedPeriods()) {
      final s = await db.periodSummary(p);
      rows.add((period: p, score: s.score, objectives: s.scorable));
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past periods')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(kGapXl),
                    child: Text('No closed periods yet', style: kTypeMeta),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        kGapSm, kGapMd, kGapSm, kGapMd),
                    children: [for (final r in _rows) _row(r)],
                  ),
                ),
    );
  }

  Widget _row(({Period period, double? score, int objectives}) r) {
    return AppCard(
      child: InkWell(
        onTap: () => _open(r.period),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kTapTarget),
          child: Padding(
            padding: const EdgeInsets.all(kGapMd),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.period.label, style: kTypeObjective),
                      const SizedBox(height: kGapXs),
                      Text(
                          '${r.objectives} key result'
                          '${r.objectives == 1 ? '' : 's'}',
                          style: kTypeMeta),
                    ],
                  ),
                ),
                Text(fmtPct(r.score), style: kTypeNumber),
                const SizedBox(width: kGapXs),
                const Icon(Icons.chevron_right, size: 20, color: kInkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(Period p) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => PeriodReportScreen(period: p)));
    _load();
  }
}

/// One closed quarter, read-only: the tree as it stood, each key result with
/// where it finished, what it scored and the grade you gave it.
///
/// It is the same outline as the OKR tab — [AreaHeading], one [AppCard] per
/// objective — so a quarter you closed in April reads as the thing you were
/// looking at in April, not as a report about it.
///
/// The numbers are folded from the log on every read, like everywhere else;
/// nothing about a closed period is stored except its grades and the row that
/// says it closed.
class PeriodReportScreen extends StatefulWidget {
  final Period period;
  const PeriodReportScreen({super.key, required this.period});

  @override
  State<PeriodReportScreen> createState() => _PeriodReportScreenState();
}

class _PeriodReportScreenState extends State<PeriodReportScreen> {
  List<Map<String, dynamic>> _tree = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tree = await DBHelper().getPeriodTree(widget.period);
    if (!mounted) return;
    setState(() {
      _tree = tree;
      _loading = false;
    });
  }

  /// Re-enters the score step over this period. Only the scoring: carrying
  /// again would clone every objective a second time, which is the same reason
  /// the tree withholds a close on an objective already archived.
  Future<void> _scoreAgain() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClosePeriodScreen(period: widget.period, scoreOnly: true),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.period.label),
        actions: [
          if (!_loading && _tree.isNotEmpty)
            TextButton(
                onPressed: _scoreAgain, child: const Text('Score again')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tree.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(kGapXl),
                    child: Text('Nothing in ${widget.period.label}',
                        style: kTypeMeta),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      kGapSm, 0, kGapSm, kGapMd),
                  children: [
                    for (final a in _tree) ...[
                      AreaHeading(a),
                      for (final o in (a['objectives'] as List)
                          .cast<Map<String, dynamic>>())
                        _objectiveCard(o),
                    ],
                  ],
                ),
    );
  }

  Widget _objectiveCard(Map<String, dynamic> o) {
    final krs = (o['key_results'] as List).cast<Map<String, dynamic>>();
    final grade = o['grade'] as int?;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kGapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Text(o['title'] as String,
                              style: kTypeObjective)),
                      const SizedBox(width: kGapSm),
                      Text(fmtPct(o['score'] as double?), style: kTypeNumber),
                    ],
                  ),
                  const SizedBox(height: kGapSm),
                  Row(
                    children: [
                      Expanded(
                        child: ScoreBar(o['score'] as double? ?? 0,
                            label: o['title'] as String, height: kBarThick),
                      ),
                      if (grade != null) ...[
                        const SizedBox(width: kGapSm),
                        GradeBar(grade),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            for (final k in krs) ...[
              const AppRule(),
              _krRow(k),
            ],
          ],
        ),
      ),
    );
  }

  Widget _krRow(Map<String, dynamic> k) {
    final grade = k['grade'] as int?;
    final title = k['title'] as String;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: kTypeKr)),
              const SizedBox(width: kGapSm),
              KrValueCell(k, maxWidth: 110),
            ],
          ),
          const SizedBox(height: kGapSm),
          Row(
            children: [
              Expanded(
                child: k['target'] != null
                    ? ScoreBar(k['score'] as double? ?? 0,
                        label: title, height: kBarThin)
                    : const SizedBox.shrink(),
              ),
              if (grade != null) ...[
                const SizedBox(width: kGapSm),
                GradeBar(grade),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
