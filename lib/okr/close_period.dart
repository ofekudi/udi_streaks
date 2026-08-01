import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'log_value.dart';
import 'period.dart';
import 'rows.dart';

/// Closing a period and opening the next one, in three steps: **score** every
/// objective, decide what **carries** forward, then **close**.
///
/// It replaced a per-objective "Close quarter" on the objective's long-press
/// sheet. That version could grade one objective at a time and nothing recorded
/// that the quarter itself was over, so closing was twelve separate acts you
/// could silently half-finish.
///
/// One objective per card, not one key result per card. Objectives are the
/// level that carries a decision *and* now a grade of its own, and a full tree
/// is a dozen objectives against three dozen key results — far enough past the
/// dozen-or-so where one-at-a-time starts reading slower than a list. It is
/// also the grain Record already fills at.
///
/// **Every tap writes.** A grade upserts the moment it is set and a carry
/// decision runs the moment its button is pressed, so there is no draft, no
/// progress to store, and resuming is just re-entering: the score step finds
/// its grades in `reviews`, and the carry step only ever lists objectives still
/// active. That is also why the flow has no discard guard, unlike
/// `RecordObjectiveScreen` — the one exception is the adjust-targets panel,
/// which does hold typed text until its button commits.
class ClosePeriodScreen extends StatefulWidget {
  final Period period;

  /// Skips the carry and close steps, for re-scoring a period that is already
  /// closed. Carrying can't be re-run — a second pass would clone every
  /// objective again — but a grade is just an opinion you can change.
  final bool scoreOnly;

  const ClosePeriodScreen(
      {super.key, required this.period, this.scoreOnly = false});

  @override
  State<ClosePeriodScreen> createState() => _ClosePeriodScreenState();
}

/// Which step the flow is on. [done] is not a card — it pops.
enum _Step { score, carry, close, done }

class _ClosePeriodScreenState extends State<ClosePeriodScreen> {
  _Step _step = _Step.score;
  int _index = 0;
  bool _loading = true;

  /// Areas → objectives → key results for the period, reloaded whenever a
  /// decision changes what is left to do.
  List<Map<String, dynamic>> _tree = [];

  ({double? score, int scored, int scorable, int carried, int dropped})?
      _summary;

  /// True once anything was written, so the tab behind knows to reload even if
  /// the flow is abandoned half-way.
  bool _changed = false;

  /// How many objectives the carry step started with. Its queue shrinks as each
  /// decision archives a row, so the position has to be counted from the far
  /// end — otherwise the card is forever "1 of n" while n falls.
  int _carryTotal = 0;

  /// The adjust-targets panel has text in it. The only unsaved state in the
  /// whole flow, and the only reason it needs a guard.
  bool _adjustDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Period get _period => widget.period;

  Future<void> _load() async {
    final tree = await DBHelper().getPeriodTree(_period);
    if (!mounted) return;
    setState(() {
      _tree = tree;
      _loading = false;
    });
  }

  // ---------- The work list ----------

  /// Every objective in the period, area attached, in tree order — so the flow
  /// reads as the same outline as the tab and honours the same Reorder choices.
  List<({Map<String, dynamic> area, Map<String, dynamic> objective})>
      get _all => [
            for (final a in _tree)
              for (final o in (a['objectives'] as List).cast<Map<String, dynamic>>())
                (area: a, objective: o),
          ];

  /// What the current step still has to get through. Scoring covers the whole
  /// period, including objectives already carried — a grade stays editable.
  /// Carrying only ever offers objectives still active, which is what makes
  /// re-entering after a half-finished close pick up where it left off.
  List<({Map<String, dynamic> area, Map<String, dynamic> objective})>
      get _queue => _step == _Step.carry
          ? [
              for (final e in _all)
                if (e.objective['status'] != 'archived') e,
            ]
          : _all;

  // ---------- Writes ----------

  Future<void> _grade(String kind, String id, int grade) async {
    await DBHelper().saveGrade(
      subjectKind: kind,
      subjectId: id,
      period: _period.id,
      grade: grade,
    );
    _changed = true;
    await _load();
  }

  Future<void> _carry(
    Map<String, dynamic> objective, {
    Set<String>? drop,
    Map<String, ({double value, String? raw})>? targets,
  }) async {
    await DBHelper().renewObjective(
      objective['id'] as String,
      dropKeyResults: drop,
      newTargets: targets,
    );
    _changed = true;
    _adjustDirty = false;
    await _advance();
  }

  Future<void> _drop(Map<String, dynamic> objective) async {
    await DBHelper()
        .updateObjectiveStatus(objective['id'] as String, 'archived');
    _changed = true;
    _adjustDirty = false;
    await _advance();
  }

  /// Moves past the objective just decided. The queue shrinks under us as
  /// carrying archives rows, so the index stays put and the list slides up.
  Future<void> _advance() async {
    await _load();
    if (!mounted) return;
    if (_index >= _queue.length) _nextStep();
  }

  // ---------- Navigation ----------

  void _nextStep() {
    switch (_step) {
      case _Step.score:
        if (widget.scoreOnly) {
          Navigator.pop(context, _changed);
          return;
        }
        setState(() {
          _step = _Step.carry;
          _index = 0;
        });
        _carryTotal = _queue.length;
        if (_queue.isEmpty) _nextStep();
      case _Step.carry:
        _openSummary();
      case _Step.close:
      case _Step.done:
        Navigator.pop(context, _changed);
    }
  }

  Future<void> _openSummary() async {
    final summary = await DBHelper().periodSummary(_period);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _step = _Step.close;
    });
  }

  void _next() {
    if (_index + 1 < _queue.length) {
      setState(() => _index++);
    } else {
      _nextStep();
    }
  }

  Future<void> _back() async {
    // The only unsaved thing in the flow, so the only place that can ask.
    if (_adjustDirty && !await _confirmLeaveAdjust()) return;
    if (!mounted) return;
    if (_index > 0) {
      setState(() => _index--);
      return;
    }
    if (_step == _Step.carry) {
      setState(() {
        _step = _Step.score;
        _index = _all.isEmpty ? 0 : _all.length - 1;
      });
      return;
    }
    if (mounted) Navigator.pop(context, _changed);
  }

  Future<bool> _confirmLeaveAdjust() async {
    final ok =
        await confirmDiscard(context, title: 'Discard the targets you typed?');
    if (ok) _adjustDirty = false;
    return ok;
  }

  Future<void> _close() async {
    await DBHelper().closePeriod(_period);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Everything else is already written, so leaving costs nothing.
      canPop: !_adjustDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeaveAdjust()) navigator.pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(_title),
          bottom: _loading ? null : _progress(),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _body(),
      ),
    );
  }

  /// The step named, not "Step 2 of 3" — what you are about to do is more use
  /// than where you are in an abstract sequence.
  String get _title => switch (_step) {
        _Step.score => 'Score ${_period.label}',
        _Step.carry => 'Carry into ${_period.next.label}',
        _ => 'Close ${_period.label}',
      };

  PreferredSizeWidget _progress() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kGapLg, 0, kGapLg, kGapSm),
        child: Row(
          children: [
            Expanded(child: _steps()),
            if (_count case final c?) Text(c, style: kTypeMetaNum),
          ],
        ),
      ),
    );
  }

  /// `4 of 12`. The score step walks an index through a fixed list; the carry
  /// step never moves its index, because deciding an objective takes it out of
  /// the queue — so there, position is what has already gone.
  String? get _count {
    final total = _step == _Step.carry ? _carryTotal : _queue.length;
    if (_step == _Step.close || total == 0) return null;
    final at = _step == _Step.carry ? total - _queue.length + 1 : _index + 1;
    return '${at.clamp(1, total)} of $total';
  }

  /// `Score · Carry · Close`, the whole shape of the flow stated up front so
  /// the count above means something. Steps already passed stay filled.
  Widget _steps() {
    if (widget.scoreOnly) return const SizedBox.shrink();
    Widget dot(_Step s, String label) {
      final reached = s.index <= _step.index;
      return Padding(
        padding: const EdgeInsets.only(right: kGapMd),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: reached ? kAccent : kTrack,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: kGapXs),
            Text(label,
                style: kTypeMeta.copyWith(
                    color: reached ? kInk : kInkFaint,
                    fontWeight: s == _step ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );
    }

    return Row(children: [
      dot(_Step.score, 'Score'),
      dot(_Step.carry, 'Carry'),
      dot(_Step.close, 'Close'),
    ]);
  }

  Widget _body() {
    if (_step == _Step.close) return _summaryCard();
    final queue = _queue;
    if (queue.isEmpty) return _empty();
    final entry = queue[_index.clamp(0, queue.length - 1)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(kGapSm, 0, kGapSm, kGapXl),
      children: [
        AreaHeading(entry.area),
        if (_step == _Step.score)
          _ScoreCard(
            key: ValueKey(entry.objective['id']),
            objective: entry.objective,
            onGrade: _grade,
          )
        else
          _CarryCard(
            key: ValueKey(entry.objective['id']),
            objective: entry.objective,
            next: _period.next,
            onCarry: _carry,
            onDrop: _drop,
            onDirty: (dirty) => _adjustDirty = dirty,
          ),
        if (_step == _Step.score) ...[
          const SizedBox(height: kGapLg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kGapMd),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _next,
                child: Text(
                    _index + 1 < queue.length ? 'Next' : 'Done scoring'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kGapXl),
        child: Text(
          _step == _Step.score
              ? 'Nothing in ${_period.label}'
              : 'Every objective is decided',
          style: kTypeMeta,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final s = _summary;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(kGapSm, kGapMd, kGapSm, kGapXl),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(kGapMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_period.label, style: kTypeObjective),
                const SizedBox(height: kGapSm),
                const AppRule.flush(),
                // A rollup, so a percent — the raw 0..1 belongs on the score
                // step, where it is the figure being graded against.
                _summaryRow('Score', fmtPct(s.score)),
                _summaryRow('Scored', '${s.scored} of ${s.scorable}'),
                _summaryRow('Carried', _objectives(s.carried)),
                _summaryRow('Dropped', _objectives(s.dropped)),
              ],
            ),
          ),
        ),
        const SizedBox(height: kGapLg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGapMd),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _close,
              child: Text('Close ${_period.label}'),
            ),
          ),
        ),
      ],
    );
  }

  String _objectives(int n) => '$n objective${n == 1 ? '' : 's'}';

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: kGapMd),
        child: Row(
          children: [
            Expanded(child: Text(label, style: kTypeMeta)),
            Text(value, style: kTypeNumber),
          ],
        ),
      );
}

// =========================================================================
// Score — one objective, its key results, a grade on each
// =========================================================================

/// What the value cell may claim beside a key result's title on this card.
const double _kKrValueWidth = 110;

/// One objective's card in the score step: every key result with where it
/// landed, what it scored, and a grade — then the objective's own.
///
/// The grade is deliberately not a second completeness number. The bar and the
/// raw score already say how far the key result got; the 1–10 asks how well you
/// ran it, which is the thing a log cannot know.
class _ScoreCard extends StatelessWidget {
  final Map<String, dynamic> objective;
  final Future<void> Function(String kind, String id, int grade) onGrade;

  const _ScoreCard({super.key, required this.objective, required this.onGrade});

  @override
  Widget build(BuildContext context) {
    final krs = (objective['key_results'] as List).cast<Map<String, dynamic>>();
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kGapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
              child: Text(objective['title'] as String, style: kTypeObjective),
            ),
            for (final k in krs) ...[
              const AppRule(),
              _krRow(k),
            ],
            if (krs.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(kGapMd, 0, kGapMd, kGapSm),
                child: Text('No key results', style: kTypeMeta),
              ),
            // A heavier rule: the objective's own grade is a different claim
            // from the rows above it, not one more of them.
            const Padding(
              padding: EdgeInsets.symmetric(vertical: kGapXs),
              child: AppRule.flush(),
            ),
            _objectiveRow(),
          ],
        ),
      ),
    );
  }

  Widget _krRow(Map<String, dynamic> k) {
    final score = k['score'] as double?;
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
              KrValueCell(k, maxWidth: _kKrValueWidth),
            ],
          ),
          if (k['target'] != null) ...[
            const SizedBox(height: kGapSm),
            Row(
              children: [
                Expanded(
                    child: ScoreBar(score ?? 0, label: title, height: kBarThin)),
                const SizedBox(width: kGapSm),
                // The raw 0..1, which is what a grade is given against.
                Text(fmtScore(score), style: kTypeMetaNum),
              ],
            ),
          ],
          GradeInput(
            grade: k['grade'] as int?,
            onChanged: (g) => onGrade('key_result', k['id'] as String, g),
          ),
        ],
      ),
    );
  }

  Widget _objectiveRow() {
    final score = objective['score'] as double?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapMd, kGapSm, kGapMd, kGapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('This objective', style: kTypeKr)),
              Text(fmtScore(score), style: kTypeMetaNum),
            ],
          ),
          const SizedBox(height: kGapSm),
          ScoreBar(score ?? 0,
              label: objective['title'] as String, height: kBarThick),
          GradeInput(
            grade: objective['grade'] as int?,
            onChanged: (g) => onGrade('objective', objective['id'] as String, g),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Carry — what comes into the next period, and on what terms
// =========================================================================

/// One objective's card in the carry step: what it scored, what its key results
/// were aiming at, and the three things you can do with it.
///
/// "Adjust targets" opens a field per key result rather than pushing
/// `KrEditScreen`: the decision is only ever about the number, and leaving the
/// flow to make it would lose the place in the queue. A field cleared to blank
/// drops that key result from the clone, which is the same gesture as setting
/// no target — you are saying it isn't coming.
class _CarryCard extends StatefulWidget {
  final Map<String, dynamic> objective;
  final Period next;
  final Future<void> Function(
    Map<String, dynamic> objective, {
    Set<String>? drop,
    Map<String, ({double value, String? raw})>? targets,
  }) onCarry;
  final Future<void> Function(Map<String, dynamic> objective) onDrop;

  /// Whether the adjust panel is open with something typed in it — the flow's
  /// only unsaved state, which the screen has to know about to guard the exit.
  final ValueChanged<bool> onDirty;

  const _CarryCard({
    super.key,
    required this.objective,
    required this.next,
    required this.onCarry,
    required this.onDrop,
    required this.onDirty,
  });

  @override
  State<_CarryCard> createState() => _CarryCardState();
}

class _CarryCardState extends State<_CarryCard> {
  bool _adjusting = false;

  /// One controller per key result, seeded with the target it is carrying.
  /// Kept for the visit only — nothing here is persisted until the button.
  final Map<String, TextEditingController> _targets = {};
  bool _invalid = false;

  List<Map<String, dynamic>> get _krs =>
      (widget.objective['key_results'] as List).cast<Map<String, dynamic>>();

  @override
  void dispose() {
    for (final c in _targets.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _startAdjusting() {
    for (final k in _krs) {
      _targets[k['id'] as String] ??=
          TextEditingController(text: _seeded(k));
    }
    setState(() => _adjusting = true);
    _syncDirty();
  }

  /// What a key result's field starts at — the target it is already carrying,
  /// or blank when it has none.
  String _seeded(Map<String, dynamic> k) =>
      k['target'] == null ? '' : targetLabel(k);

  /// Dirty only once a field says something different from what it was seeded
  /// with. Opening the panel and closing it again has changed nothing, and
  /// asking about it would train the answer out of the user.
  void _syncDirty() {
    widget.onDirty(_adjusting &&
        _krs.any((k) =>
            (_targets[k['id']]?.text.trim() ?? '') != _seeded(k)));
  }

  /// Splits the fields into "don't carry this one" and "carry it at this
  /// number". A field left as it was is neither, and falls through to the
  /// clone unchanged.
  Future<void> _carryAdjusted() async {
    final drop = <String>{};
    final targets = <String, ({double value, String? raw})>{};
    for (final k in _krs) {
      final id = k['id'] as String;
      final raw = _targets[id]?.text.trim() ?? '';
      if (raw.isEmpty) {
        drop.add(id);
        continue;
      }
      if (raw == targetLabel(k)) continue;
      final v = parseValue(raw);
      if (v == null) {
        setState(() => _invalid = true);
        return;
      }
      // The notation is only worth keeping when it says more than the number.
      targets[id] = (value: v, raw: raw == fmtNum(v) ? null : raw);
    }
    if (drop.length == _krs.length && _krs.isNotEmpty) {
      // Carrying an objective with none of its key results is the same as not
      // carrying it, and leaves an empty shell behind. Say so rather than
      // quietly making one.
      setState(() => _invalid = true);
      return;
    }
    await widget.onCarry(widget.objective, drop: drop, targets: targets);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.objective;
    final score = o['score'] as double?;
    final grade = o['grade'] as int?;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(kGapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(o['title'] as String, style: kTypeObjective),
            const SizedBox(height: kGapXs),
            Row(
              children: [
                if (grade != null) ...[
                  GradeBar(grade),
                  const SizedBox(width: kGapSm),
                ],
                Text(fmtPct(score), style: kTypeMetaNum),
              ],
            ),
            const SizedBox(height: kGapMd),
            const AppRule.flush(),
            const SizedBox(height: kGapSm),
            for (final k in _krs) _krRow(k),
            if (_krs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: kGapSm),
                child: Text('No key results', style: kTypeMeta),
              ),
            if (_invalid)
              Padding(
                padding: const EdgeInsets.only(top: kGapSm),
                child: Text(
                  _krs.isNotEmpty && _allBlank
                      ? "Nothing left to carry — use \"Don't carry\" instead."
                      : kLogValueHelp,
                  style: kTypeMeta.copyWith(color: kDanger),
                ),
              ),
            const SizedBox(height: kGapMd),
            ..._actions(),
          ],
        ),
      ),
    );
  }

  bool get _allBlank =>
      _krs.every((k) => (_targets[k['id']]?.text.trim() ?? '').isEmpty);

  /// `Squat  3x10 → 3x12`, or the same line with the target as a field once
  /// adjusting. Where it is heading is the fact the decision turns on, so the
  /// arrow stays in both states.
  Widget _krRow(Map<String, dynamic> k) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kGapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(k['title'] as String, style: kTypeKr)),
          const SizedBox(width: kGapSm),
          if (!_adjusting)
            Text(
              k['target'] == null
                  ? currentLabel(k)
                  : '${currentLabel(k)} → ${targetLabel(k)}',
              style: kTypeNumber,
            )
          else
            SizedBox(
              width: 96,
              child: TextField(
                controller: _targets[k['id'] as String],
                textAlign: TextAlign.end,
                style: kTypeNumber,
                decoration: const InputDecoration(hintText: 'drop'),
                onChanged: (_) {
                  _syncDirty();
                  if (_invalid) setState(() => _invalid = false);
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    if (_adjusting) {
      return [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _carryAdjusted,
            child: Text('Carry into ${widget.next.label}'),
          ),
        ),
        const SizedBox(height: kGapSm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () {
              setState(() {
                _adjusting = false;
                _invalid = false;
              });
              _syncDirty();
            },
            child: const Text('Cancel'),
          ),
        ),
      ];
    }
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => widget.onCarry(widget.objective),
          child: Text('Carry into ${widget.next.label}'),
        ),
      ),
      const SizedBox(height: kGapSm),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _krs.isEmpty ? null : _startAdjusting,
          child: const Text('Adjust targets…'),
        ),
      ),
      const SizedBox(height: kGapSm),
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => widget.onDrop(widget.objective),
          child: const Text("Don't carry"),
        ),
      ),
    ];
  }
}
