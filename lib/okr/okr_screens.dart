import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../db_helper.dart';
import 'home_trackers.dart';
import 'period.dart';
import 'widgets.dart';

/// A simple centered rename dialog (keyboard re-centers it above the field).
Future<String?> promptText(BuildContext context,
    {required String title, required String initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}

// =========================================================================
// OKR tab — areas with rollup
// =========================================================================

class GoalsTab extends StatefulWidget {
  const GoalsTab({super.key});
  @override
  State<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends State<GoalsTab> {
  List<Map<String, dynamic>> _areas = [];
  bool _loading = true;
  String _newAreaEmoji = '🎯';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _areaEmojiButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickAreaEmoji,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(_newAreaEmoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }

  void _pickAreaEmoji() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            setState(() => _newAreaEmoji = emoji.emoji);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _load() async {
    final areas = await DBHelper().getAreasWithRollup();
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Period.current();
    final pct = (p.fractionElapsed * 100).round();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('${p.label} · $pct% elapsed'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text('Areas & objectives',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                for (final a in _areas) _areaCard(context, a),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InlineAddField(
                    label: 'Add area',
                    hint: 'Training, Books, Body…',
                    leading: _areaEmojiButton(),
                    onSubmit: (name) async {
                      await DBHelper().insertArea(name, icon: _newAreaEmoji);
                      _newAreaEmoji = '🎯';
                      await _load();
                    },
                  ),
                ),
                const Divider(height: 36),
                const HomeTrackers(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _areaCard(BuildContext context, Map<String, dynamic> a) {
    final score = a['score'] as double?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Text(a['icon'] ?? '🎯', style: const TextStyle(fontSize: 26)),
        title: Text(a['name'],
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (score != null) ...[
                ScoreBar(score),
                const SizedBox(height: 4),
              ],
              Text('${a['objective_count']} objectives',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        trailing: score == null
            ? const Icon(Icons.chevron_right)
            : Text(fmtScore(score),
                style: const TextStyle(fontWeight: FontWeight.w800)),
        onLongPress: () => _areaMenu(a),
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => AreaScreen(area: a)));
          _load();
        },
      ),
    );
  }

  void _areaMenu(Map<String, dynamic> a) {
    showActionSheet(context, title: a['name'], actions: [
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
          onTap: () => _confirmDelete(a)),
    ]);
  }

  void _changeAreaEmoji(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SizedBox(
        height: 320,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) async {
            Navigator.pop(context);
            await DBHelper().updateArea(a['id'], icon: emoji.emoji);
            _load();
          },
        ),
      ),
    );
  }

  Future<void> _renameArea(Map<String, dynamic> a) async {
    final name =
        await promptText(context, title: 'Rename area', initial: a['name']);
    if (name != null && name.isNotEmpty) {
      await DBHelper().updateArea(a['id'], name: name);
      _load();
    }
  }

  void _confirmDelete(Map<String, dynamic> a) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete area'),
        content: Text(
            'Delete "${a['name']}" and its objectives? Logged measurements are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await DBHelper().deleteArea(a['id']);
              if (context.mounted) Navigator.pop(context);
              _load();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Area screen — objectives
// =========================================================================

class AreaScreen extends StatefulWidget {
  final Map<String, dynamic> area;
  const AreaScreen({super.key, required this.area});
  @override
  State<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends State<AreaScreen> {
  List<Map<String, dynamic>> _objectives = [];
  bool _loading = true;

  String get areaId => widget.area['id'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final objs = await DBHelper().getObjectivesWithProgress(areaId);
    if (!mounted) return;
    setState(() {
      _objectives = objs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.area['icon'] ?? ''} ${widget.area['name']}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final o in _objectives) _objectiveCard(o),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InlineAddField(
                    label: 'Add objective',
                    hint: 'Get stronger, Read more…',
                    onSubmit: (title) async {
                      final p = Period.current();
                      await DBHelper().insertObjective(
                          areaId: areaId,
                          title: title,
                          start: p.start,
                          end: p.end);
                      await _load();
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _objectiveCard(Map<String, dynamic> o) {
    final score = o['score'] as double?;
    final archived = o['status'] == 'archived';
    final krCount = (o['key_results'] as List).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Row(children: [
          Expanded(
              child: Text(o['title'],
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          if (archived)
            const Text('archived',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (score != null) ScoreBar(score),
              const SizedBox(height: 4),
              Text('$krCount key results',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        trailing: score == null
            ? null
            : Text(fmtScore(score),
                style: const TextStyle(fontWeight: FontWeight.w800)),
        onLongPress: () => _objectiveMenu(o),
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      ObjectiveScreen(objective: o, area: widget.area)));
          _load();
        },
      ),
    );
  }

  void _objectiveMenu(Map<String, dynamic> o) {
    showActionSheet(context, title: o['title'], actions: [
      SheetAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () => _renameObjective(o)),
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

  void _confirmDeleteObjective(Map<String, dynamic> o) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete objective'),
        content: Text(
            'Delete "${o['title']}" and its key results? Logged measurements are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await DBHelper().deleteObjective(o['id']);
              if (context.mounted) Navigator.pop(context);
              _load();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Objective screen — key results, session logging, quarter close
// =========================================================================

class ObjectiveScreen extends StatefulWidget {
  final Map<String, dynamic> objective;
  final Map<String, dynamic> area;
  const ObjectiveScreen(
      {super.key, required this.objective, required this.area});
  @override
  State<ObjectiveScreen> createState() => _ObjectiveScreenState();
}

class _ObjectiveScreenState extends State<ObjectiveScreen> {
  List<Map<String, dynamic>> _krs = [];
  double? _score;
  bool _loading = true;

  String get objId => widget.objective['id'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final krs = await DBHelper()
        .getKeyResultsWithProgress(objId, objective: widget.objective);
    double sum = 0, w = 0;
    for (final k in krs) {
      final s = k['score'];
      if (s is double) {
        final ww = (k['weight'] as num?)?.toDouble() ?? 1;
        sum += s * ww;
        w += ww;
      }
    }
    if (!mounted) return;
    setState(() {
      _krs = krs;
      _score = w > 0 ? sum / w : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.objective['title']),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'close') _closeQuarter();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'close', child: Text('Close quarter · grade + renew')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text(fmtScore(_score),
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                      Text(
                          '${fmtDate(DateTime.parse(widget.objective['start_date']))} → ${fmtDate(DateTime.parse(widget.objective['end_date']))}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                for (final k in _krs) _krTile(k),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final created = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => KrEditScreen(
                              objectiveId: objId,
                              areaId: widget.area['id'],
                            ),
                          ),
                        );
                        if (created == true) _load();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add key result'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _krTile(Map<String, dynamic> k) {
    final score = k['score'] as double?;
    final agg = k['aggregation'];
    final cur = k['current'];
    final target = k['target'];
    final unit = k['unit'] ?? '';
    final down = k['direction'] == 'DOWN';
    String valueLine;
    if (agg == 'CADENCE' || agg == 'RECENCY') {
      final ds = k['days_since'];
      valueLine = ds == null ? 'never' : '$ds days ago';
    } else if (target != null) {
      valueLine = '${fmtNum(cur)} / ${fmtNum(target)} $unit';
    } else {
      valueLine = '${fmtNum(cur)} $unit · no target';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(k['title'],
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(valueLine, style: const TextStyle(fontSize: 12)),
                const Spacer(),
                if (k['overdue'] == true)
                  const PacePill('behind')
                else
                  PacePill(k['on_pace']),
              ]),
              if (score != null) ...[
                const SizedBox(height: 5),
                ScoreBar(score, down: down),
              ],
            ],
          ),
        ),
        onLongPress: () => _krMenu(k),
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => KrDetailScreen(
                        kr: k,
                        areaId: widget.area['id'],
                      )));
          _load();
        },
      ),
    );
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
      context,
      MaterialPageRoute(
          builder: (_) => KrEditScreen(kr: k, areaId: widget.area['id'])),
    );
    if (changed == true) _load();
  }

  void _confirmDeleteKr(Map<String, dynamic> k) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete key result'),
        content: Text(
            'Delete "${k['title']}"? Its logged measurements are removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await DBHelper().deleteKeyResult(k['id']);
              if (context.mounted) Navigator.pop(context);
              _load();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _closeQuarter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuarterCloseScreen(
          objective: widget.objective,
          krs: _krs,
        ),
      ),
    ).then((_) => _load());
  }
}

// =========================================================================
// Key result edit — a full page (keyboard-friendly), reached from KR detail
// =========================================================================

class KrEditScreen extends StatefulWidget {
  final Map<String, dynamic>? kr; // null = create a new key result
  final String? objectiveId;
  final String? areaId;
  const KrEditScreen({super.key, this.kr, this.objectiveId, this.areaId});
  @override
  State<KrEditScreen> createState() => _KrEditScreenState();
}

class _KrEditScreenState extends State<KrEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _target;
  late final TextEditingController _unit;
  late String _agg;
  late String _direction;

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
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _direction = up ? 'DOWN' : 'UP'),
          child: SizedBox(
            width: 52,
            height: 52,
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
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 20),
          const Text('How do you want to measure it?',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          for (final a in kAggregations)
            RadioListTile<String>(
              value: a.value,
              groupValue: _agg,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(a.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle:
                  Text(a.explainer, style: const TextStyle(fontSize: 12)),
              onChanged: (v) => setState(() => _agg = v!),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _directionToggle(),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _target,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Target'),
                ),
              ),
              if (_agg != 'COUNT') ...[
                const SizedBox(width: 10),
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
          const SizedBox(height: 8),
          Text(
              'Leave the target empty to just track it over time — no goal, just the trend.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
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
    final target = double.tryParse(_target.text.trim());
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
  final String? areaId;
  final bool editable;
  const KrDetailScreen(
      {super.key, required this.kr, this.areaId, this.editable = true});
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
    final v = parseValue(_logValue.text);
    if (v == null) return;
    await DBHelper().logMeasurement(
      keyResultId: kr['trackable_id'] == null ? kr['id'] as String : null,
      trackableId: kr['trackable_id'] as String?,
      value: v,
      unit: kr['unit'] as String?,
    );
    _logValue.clear();
    FocusScope.of(context).unfocus();
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
                  MaterialPageRoute(
                      builder: (_) =>
                          KrEditScreen(kr: kr, areaId: widget.areaId)),
                );
                if (changed == true) _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Inline logger — no modal, no keyboard cover.
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _logValue,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _log(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'e.g. 30 or 3x10',
                        suffixText: unit,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _log, child: const Text('Add')),
                ]),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text('${fmtNum(kr['current'])} $unit',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800)),
                      if (kr['target'] != null)
                        Text('target ${fmtNum(kr['target'])} $unit',
                            style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                if (points.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Sparkline(points, height: 80),
                    ),
                  ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('By quarter')),
                    ButtonSegment(value: false, label: Text('By entry')),
                  ],
                  selected: {_byQuarter},
                  onSelectionChanged: (s) =>
                      setState(() => _byQuarter = s.first),
                ),
                const SizedBox(height: 8),
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
                    padding: EdgeInsets.all(24),
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
        padding: const EdgeInsets.all(16),
        children: [
          Text('Grade each key result 1–10 (your own view).',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7))),
          const SizedBox(height: 12),
          for (final k in widget.krs) _gradeRow(k),
          const SizedBox(height: 8),
          const Text('Grades save to history · reflection stays in your pen ✍️',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saveAndRenew,
            child: const Text('Save grades & renew for next quarter'),
          ),
          const SizedBox(height: 8),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(k['title'],
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('score ${fmtScore(k['score'] as double?)}',
                  style: const TextStyle(fontSize: 12)),
            ]),
            Row(children: [
              const Text('grade', style: TextStyle(fontSize: 11)),
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
                width: 24,
                child: Text('$g',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
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
                  padding: EdgeInsets.all(32),
                  child: Text(
                      'Nothing to show yet.\nAdd key results, then tap one to see it over time.',
                      textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final k in _krs)
                        Card(
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

