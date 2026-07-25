// Differential test: the original `computeKr` fold and `_resolveWindow`,
// transcribed verbatim from commit 8451f0d (db_helper.dart:918-1014) with only
// the db.query replaced by an injected list, must agree with the extracted
// pure functions. Temporary scaffolding.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/okr/period.dart';
import 'package:udi_streaks/okr/scoring.dart';

/// Verbatim transcription of the original `_resolveWindow`. Do not tidy.
(DateTime, DateTime) originalResolveWindow(
    Map<String, dynamic> kr, Map<String, dynamic>? objective, DateTime now) {
  final mode = (kr['window_mode'] ?? 'OBJECTIVE') as String;
  switch (mode) {
    case 'ROLLING':
      final days = (kr['window_days'] as int?) ?? 7;
      return (now.subtract(Duration(days: days)), now);
    case 'YEAR':
      return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
    case 'ALL':
      return (DateTime(1970), now);
    case 'OBJECTIVE':
    default:
      if (objective != null) {
        return (
          DateTime.parse(objective['start_date'] as String),
          DateTime.parse(objective['end_date'] as String)
        );
      }
      final p = Period.current();
      return (p.start, p.end);
  }
}

/// Verbatim transcription of the original `computeKr` body. Do not tidy.
Map<String, dynamic> originalComputeKr(
  Map<String, dynamic> kr,
  List<double> valuesNewestFirst,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  final agg = kr['aggregation'] as String;
  final rows = valuesNewestFirst;

  double sumV = 0;
  double? latestV;
  final count = rows.length;
  for (final r in rows) {
    sumV += r;
  }
  if (rows.isNotEmpty) {
    latestV = rows.first;
  }

  final direction = (kr['direction'] ?? 'UP') as String;
  final double? current = switch (agg) {
    'COUNT' => count.toDouble(),
    'LATEST' => latestV,
    _ => sumV, // SUM
  };

  final target = (kr['target_value'] as num?)?.toDouble();
  double? score;
  if (target != null && target != 0 && current != null) {
    final raw = direction == 'DOWN'
        ? (current <= 0 ? 1.0 : target / current)
        : current / target;
    score = raw.clamp(0.0, 1.0);
  }

  String? onPace;
  if (score != null) {
    final mode = (kr['window_mode'] ?? 'OBJECTIVE') as String;
    double frac = 1.0;
    final total = end.difference(start).inSeconds;
    if ((mode == 'OBJECTIVE' || mode == 'YEAR') && total > 0) {
      frac = (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
    }
    if (score >= (frac + 0.05).clamp(0.0, 1.0)) {
      onPace = 'ahead';
    } else if (score >= frac - 0.1) {
      onPace = 'on_track';
    } else {
      onPace = 'behind';
    }
  }

  return {
    'current': current,
    'target': target,
    'score': score,
    'unit': kr['unit'],
    'on_pace': onPace,
    'aggregation': agg,
    'direction': direction,
  };
}

void main() {
  test('extracted scoring matches the original over random key results', () {
    final rng = Random(4242);
    final now = DateTime(2026, 7, 25, 14, 7);
    const modes = ['ROLLING', 'YEAR', 'ALL', 'OBJECTIVE', null];
    const aggs = ['SUM', 'COUNT', 'LATEST'];
    const dirs = ['UP', 'DOWN', null];

    for (var i = 0; i < 20000; i++) {
      final mode = modes[rng.nextInt(modes.length)];
      final hasObjective = rng.nextBool();
      final kr = <String, dynamic>{
        'aggregation': aggs[rng.nextInt(aggs.length)],
        'direction': dirs[rng.nextInt(dirs.length)],
        'window_mode': mode,
        'window_days': rng.nextBool() ? null : 1 + rng.nextInt(90),
        'target_value': switch (rng.nextInt(4)) {
          0 => null,
          1 => 0,
          2 => rng.nextInt(200) - 50,
          _ => rng.nextDouble() * 100,
        },
        'unit': rng.nextBool() ? null : 'reps',
      };
      final objective = hasObjective
          ? {
              'start_date':
                  DateTime(2026, 1 + rng.nextInt(6), 1).toIso8601String(),
              'end_date':
                  DateTime(2026, 7 + rng.nextInt(6), 28).toIso8601String(),
            }
          : null;

      final values = [
        for (var v = 0; v < rng.nextInt(8); v++)
          (rng.nextDouble() * 60 - 10).roundToDouble(),
      ];

      // --- original ---
      final (oStart, oEnd) = originalResolveWindow(kr, objective, now);
      final expected = originalComputeKr(kr, values, oStart, oEnd, now);

      // --- extracted, mirroring how DBHelper.computeKr now calls it ---
      final m = (kr['window_mode'] ?? 'OBJECTIVE') as String;
      final usesObjective = m != 'ROLLING' && m != 'YEAR' && m != 'ALL';
      final (nStart, nEnd) = resolveWindow(
        mode: m,
        windowDays: kr['window_days'] as int?,
        objectiveStart: usesObjective && objective != null
            ? DateTime.parse(objective['start_date'] as String)
            : null,
        objectiveEnd: usesObjective && objective != null
            ? DateTime.parse(objective['end_date'] as String)
            : null,
        now: now,
      );
      final actual = computeKrState(
        aggregation: kr['aggregation'] as String,
        direction: (kr['direction'] ?? 'UP') as String,
        mode: m,
        target: (kr['target_value'] as num?)?.toDouble(),
        unit: kr['unit'] as String?,
        valuesNewestFirst: values,
        start: nStart,
        end: nEnd,
        now: now,
      ).toMap();
      // `previous` is a post-extraction addition; the original had no notion of
      // it, so it isn't part of the equivalence.
      actual.remove('previous');

      expect((nStart, nEnd), (oStart, oEnd), reason: 'window for $kr');
      expect(actual, expected, reason: 'computation for $kr with $values');
    }
  });
}
