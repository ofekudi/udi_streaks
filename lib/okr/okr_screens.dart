import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'log_value.dart';
import 'period.dart';

// =========================================================================
// Key result edit — a full page (keyboard-friendly), reached from KR detail
// =========================================================================

class KrEditScreen extends StatefulWidget {
  final Map<String, dynamic>? kr; // null = create a new key result
  final String? objectiveId;
  const KrEditScreen({super.key, this.kr, this.objectiveId});
  @override
  State<KrEditScreen> createState() => _KrEditScreenState();
}

class _KrEditScreenState extends State<KrEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _target;
  late final TextEditingController _unit;
  late String _agg;
  late String _direction;
  String? _targetError;

  @override
  void initState() {
    super.initState();
    final k = widget.kr;
    _title = TextEditingController(text: k?['title'] ?? '');
    _target = TextEditingController(
        text: k?['target_value'] != null
            ? fmtNum(k!['target_value'] as num)
            : '');
    _unit = TextEditingController(text: k?['unit'] ?? '');
    _agg = (k?['aggregation'] as String?) ?? 'LATEST';
    _direction = k?['direction'] ?? 'UP';
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  /// A single toggle button showing ↑ / ↓ — "higher is better" vs "lower is
  /// better". Tapping flips it.
  Widget _directionToggle() {
    final up = _direction == 'UP';
    final color = up ? Colors.green : Colors.orange;
    return Tooltip(
      message: up ? 'Higher is better' : 'Lower is better',
      child: Material(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(kGapMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(kGapMd),
          onTap: () => setState(() => _direction = up ? 'DOWN' : 'UP'),
          child: SizedBox(
            width: kTapTarget,
            height: kTapTarget,
            child: Center(
              child: Icon(
                up
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: color.shade800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kr == null ? 'New key result' : 'Edit key result'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: kFormPadding,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: kGapXl),
          const SectionHeader('How do you want to measure it?'),
          for (final a in kAggregations)
            RadioListTile<String>(
              value: a.value,
              groupValue: _agg,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(a.label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              subtitle:
                  Text(a.explainer, style: Theme.of(context).textTheme.bodySmall),
              onChanged: (v) => setState(() => _agg = v!),
            ),
          const SizedBox(height: kGapMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: kGapXs),
                child: _directionToggle(),
              ),
              const SizedBox(width: kGapSm),
              Expanded(
                flex: 3,
                // Plain text, not a number pad: [parseValue] also takes
                // "3x10" and "10,9,8", which a numeric keypad can't type.
                child: TextField(
                  controller: _target,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) {
                    if (_targetError != null) {
                      setState(() => _targetError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Target',
                    hintText: 'e.g. 30, 3x10',
                    errorText: _targetError,
                  ),
                ),
              ),
              if (_agg != 'COUNT') ...[
                const SizedBox(width: kGapSm),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: kGapSm),
          Text(
              'Leave the target empty to just track it over time — no goal, just the trend.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: kGapXl),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final db = DBHelper();
    final k = widget.kr;
    final unit = _unit.text.trim().isEmpty ? null : _unit.text.trim();
    // An empty target is deliberate ("just track the trend"); junk isn't —
    // flag it rather than letting it silently clear an existing target.
    final rawTarget = _target.text.trim();
    final target = parseValue(rawTarget);
    if (rawTarget.isNotEmpty && target == null) {
      setState(() => _targetError = 'Enter a number — e.g. 30, 3x10 or 10,9,8');
      return;
    }
    // Window is inferred, not asked: a "Latest" level always shows the newest
    // value (all-time); Count/Total goals accumulate within the objective.
    final window = _agg == 'LATEST' ? 'ALL' : 'OBJECTIVE';

    if (k == null) {
      await db.insertKeyResult(
        objectiveId: widget.objectiveId,
        title: title,
        aggregation: _agg,
        target: target,
        direction: _direction,
        unit: unit,
        windowMode: window,
      );
    } else {
      await db.updateKeyResult(
        k['id'] as String,
        title: title,
        aggregation: _agg,
        target: target,
        clearTarget: target == null,
        direction: _direction,
        unit: unit,
        windowMode: window,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }
}

// =========================================================================
// KR detail — inline logging + history graph + list + grades
// =========================================================================

class KrDetailScreen extends StatefulWidget {
  final Map<String, dynamic> kr;
  final bool editable;
  const KrDetailScreen({super.key, required this.kr, this.editable = true});
  @override
  State<KrDetailScreen> createState() => _KrDetailScreenState();
}

class _KrDetailScreenState extends State<KrDetailScreen> {
  late Map<String, dynamic> kr;
  final _logValue = TextEditingController();
  List<Map<String, dynamic>> _series = [];
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _grades = [];
  bool _byQuarter = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    kr = widget.kr;
    _load();
  }

  @override
  void dispose() {
    _logValue.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = DBHelper();
    final trackableId = kr['trackable_id'] as String?;
    final krId = kr['id'] as String;
    // Refresh the computed KR state (only for real key results).
    if (widget.editable) {
      final rows = await db.getKeyResultsById(krId);
      if (rows != null) kr = rows;
    }
    final series = await db.getMeasurementSeries(
        trackableId: trackableId,
        keyResultId: trackableId == null ? krId : null);
    final periods = await db.getPeriodSummaries(
        trackableId: trackableId,
        keyResultId: trackableId == null ? krId : null,
        aggregation: kr['aggregation'] ?? 'SUM');
    final grades = await db.getGradeHistory(krId);
    if (!mounted) return;
    setState(() {
      _series = series;
      _periods = periods;
      _grades = grades;
      _loading = false;
    });
  }

  int? _gradeFor(String period) {
    for (final g in _grades) {
      if (g['period'] == period) return g['grade'] as int?;
    }
    return null;
  }

  Future<void> _log() async {
    final raw = _logValue.text.trim();
    if (!await logKrValue(kr, raw)) {
      if (raw.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(kLogValueHelp)));
      }
      return;
    }
    _logValue.clear();
    if (mounted) FocusScope.of(context).unfocus();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unit = kr['unit'] ?? '';
    final points =
        _series.map((m) => (m['value'] as num).toDouble()).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(kr['title']),
        actions: [
          if (widget.editable)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => KrEditScreen(kr: kr)),
                );
                if (changed == true) _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: kFormPadding,
              children: [
                // Inline logger — no modal, no keyboard cover.
                Row(children: [
                  Expanded(
                    child: LogValueField(
                      controller: _logValue,
                      unit: kr['unit'] as String?,
                      onSubmit: _log,
                    ),
                  ),
                  const SizedBox(width: kGapSm),
                  FilledButton(onPressed: _log, child: const Text('Add')),
                ]),
                const SizedBox(height: kGapLg),
                Card(
                  child: Padding(
                    padding: kFormPadding,
                    child: Column(children: [
                      Text('${fmtNum(kr['current'])} $unit',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if (kr['target'] != null)
                        Text('target ${fmtNum(kr['target'])} $unit',
                            style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
                const SizedBox(height: kGapMd),
                if (points.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: kListPadding,
                      child: Sparkline(points, height: 80),
                    ),
                  ),
                const SizedBox(height: kGapMd),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('By quarter')),
                    ButtonSegment(value: false, label: Text('By entry')),
                  ],
                  selected: {_byQuarter},
                  onSelectionChanged: (s) =>
                      setState(() => _byQuarter = s.first),
                ),
                const SizedBox(height: kGapSm),
                if (_byQuarter)
                  for (final p in _periods)
                    ListTile(
                      dense: true,
                      title: Text(p['period']),
                      subtitle: Text('${fmtNum(p['value'])} $unit'),
                      trailing: _gradeFor(p['period']) == null
                          ? null
                          : GradeBar(_gradeFor(p['period'])),
                    )
                else
                  for (final m in _series.reversed)
                    ListTile(
                      dense: true,
                      title: Text(fmtDate(DateTime.parse(m['recorded_at']))),
                      subtitle: (m['note'] != null) ? Text(m['note']) : null,
                      trailing: Text('${fmtNum(m['value'])} $unit'),
                    ),
                if ((_byQuarter && _periods.isEmpty) ||
                    (!_byQuarter && _series.isEmpty))
                  const Padding(
                    padding: EdgeInsets.all(kGapXl),
                    child: Center(child: Text('No entries yet.')),
                  ),
              ],
            ),
    );
  }
}

// =========================================================================
// Quarter close — grade each KR 1..10, then renew
// =========================================================================

class QuarterCloseScreen extends StatefulWidget {
  final Map<String, dynamic> objective;
  final List<Map<String, dynamic>> krs;
  const QuarterCloseScreen(
      {super.key, required this.objective, required this.krs});
  @override
  State<QuarterCloseScreen> createState() => _QuarterCloseScreenState();
}

class _QuarterCloseScreenState extends State<QuarterCloseScreen> {
  final Map<String, int> _grades = {};
  late String _period;

  @override
  void initState() {
    super.initState();
    _period =
        Period.ofDate(DateTime.parse(widget.objective['start_date'])).id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Close $_period')),
      body: ListView(
        padding: kFormPadding,
        children: [
          Text('Grade each key result 1–10 (your own view).',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7))),
          const SizedBox(height: kGapMd),
          for (final k in widget.krs) _gradeRow(k),
          const SizedBox(height: kGapSm),
          Text('Grades save to history · reflection stays in your pen ✍️',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: kGapXl),
          FilledButton(
            onPressed: _saveAndRenew,
            child: const Text('Save grades & renew for next quarter'),
          ),
          const SizedBox(height: kGapSm),
          OutlinedButton(
            onPressed: _saveAndArchive,
            child: const Text('Save grades & archive'),
          ),
        ],
      ),
    );
  }

  Widget _gradeRow(Map<String, dynamic> k) {
    final id = k['id'] as String;
    final g = _grades[id] ?? 0;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: kListPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(k['title'],
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700))),
              Text('score ${fmtScore(k['score'] as double?)}',
                  style: theme.textTheme.bodySmall),
            ]),
            Row(children: [
              Text('grade', style: theme.textTheme.labelSmall),
              Expanded(
                child: Slider(
                  value: g.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$g',
                  onChanged: (v) => setState(() => _grades[id] = v.round()),
                ),
              ),
              SizedBox(
                width: kGapXl,
                child: Text('$g',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _saveGrades() async {
    final db = DBHelper();
    for (final entry in _grades.entries) {
      if (entry.value > 0) {
        await db.saveGrade(
          subjectKind: 'key_result',
          subjectId: entry.key,
          period: _period,
          grade: entry.value,
        );
      }
    }
  }

  Future<void> _saveAndRenew() async {
    await _saveGrades();
    await DBHelper().renewObjective(widget.objective['id']);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _saveAndArchive() async {
    await _saveGrades();
    await DBHelper().updateObjectiveStatus(widget.objective['id'], 'archived');
    if (mounted) Navigator.pop(context, true);
  }
}

// =========================================================================
// History tab — pick something to see over time
// =========================================================================

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});
  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<Map<String, dynamic>> _krs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final krs = await DBHelper().getAllKeyResultsWithProgress();
    if (!mounted) return;
    setState(() {
      _krs = krs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Over time'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _krs.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(kGapXl),
                  child: Text(
                      'Nothing to show yet.\nAdd key results, then tap one to see it over time.',
                      textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: kListPadding,
                    children: [
                      for (final k in _krs)
                        Card(
                          margin: const EdgeInsets.only(bottom: kGapSm),
                          child: ListTile(
                            title: Text(k['title']),
                            subtitle: Text(
                                '${fmtNum(k['current'])} ${k['unit'] ?? ''}'
                                    .trim()),
                            trailing: const Icon(Icons.show_chart),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => KrDetailScreen(kr: k)),
                            ).then((_) => _load()),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

