/// The key-result scoring engine, as pure functions.
///
/// Extracted from `DBHelper.computeKr` / `_resolveWindow` so the rules that
/// decide "what is my number and am I on pace" can be unit tested without a
/// database. `DBHelper.computeKr` is now just a query plus a call to
/// [computeKrState].
library;

import 'period.dart';

/// A KR is scored over a date window chosen by its `window_mode`.
typedef KrWindow = (DateTime start, DateTime end);

/// Default look-back for `ROLLING` key results.
const int kDefaultRollingDays = 7;

/// A score this far above the elapsed fraction counts as ahead of pace.
const double kAheadMargin = 0.05;

/// A score this far below the elapsed fraction still counts as on track.
const double kBehindMargin = 0.1;

/// Resolves the date window a KR is measured over.
///
/// `OBJECTIVE` (the default) uses the parent objective's dates, falling back to
/// the current quarter when the KR is not attached to one.
KrWindow resolveWindow({
  String? mode,
  int? windowDays,
  DateTime? objectiveStart,
  DateTime? objectiveEnd,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  switch (mode ?? 'OBJECTIVE') {
    case 'ROLLING':
      final days = windowDays ?? kDefaultRollingDays;
      return (at.subtract(Duration(days: days)), at);
    case 'YEAR':
      return (DateTime(at.year, 1, 1), DateTime(at.year, 12, 31, 23, 59, 59));
    case 'ALL':
      return (DateTime(1970), at);
    case 'OBJECTIVE':
    default:
      if (objectiveStart != null && objectiveEnd != null) {
        return (objectiveStart, objectiveEnd);
      }
      final p = Period.current();
      return (p.start, p.end);
  }
}

/// Folds the measurements in the window into the KR's current value.
///
/// [valuesNewestFirst] must be ordered newest first, matching the
/// `recorded_at DESC` query that feeds it — `LATEST` reads the head.
/// `SUM` and `COUNT` of an empty log are 0; `LATEST` of an empty log is null.
double? aggregateValues(List<double> valuesNewestFirst, String aggregation) {
  switch (aggregation) {
    case 'COUNT':
      return valuesNewestFirst.length.toDouble();
    case 'LATEST':
      return valuesNewestFirst.isEmpty ? null : valuesNewestFirst.first;
    default: // SUM
      return valuesNewestFirst.fold<double>(0, (a, b) => a + b);
  }
}

/// Progress toward [target] as a 0..1 fraction, or null when the KR is
/// track-only (no target) or has no value yet.
///
/// A `DOWN` key result is one where lower is better, so the ratio inverts.
double? scoreFor({
  required double? current,
  required double? target,
  required String direction,
}) {
  if (target == null || target == 0 || current == null) return null;
  final raw = direction == 'DOWN'
      ? (current <= 0 ? 1.0 : target / current)
      : current / target;
  return raw.clamp(0.0, 1.0);
}

/// How far through the window we are, 0..1. Only time-boxed modes pace
/// themselves; `ROLLING` and `ALL` compare against a full window.
double paceFraction({
  required String mode,
  required DateTime start,
  required DateTime end,
  DateTime? now,
}) {
  if (mode != 'OBJECTIVE' && mode != 'YEAR') return 1.0;
  final total = end.difference(start).inSeconds;
  if (total <= 0) return 1.0;
  final elapsed = (now ?? DateTime.now()).difference(start).inSeconds;
  return (elapsed / total).clamp(0.0, 1.0);
}

/// `ahead` / `on_track` / `behind`, or null when the KR has no score.
String? paceFor({required double? score, required double fractionElapsed}) {
  if (score == null) return null;
  if (score >= (fractionElapsed + kAheadMargin).clamp(0.0, 1.0)) return 'ahead';
  if (score >= fractionElapsed - kBehindMargin) return 'on_track';
  return 'behind';
}

/// The computed state of a key result. [toMap] is the exact shape
/// `DBHelper.computeKr` has always returned, so callers merging it into a KR
/// row are unaffected.
class KrComputation {
  final double? current;
  final double? target;
  final double? score;
  final String? unit;
  final String? onPace;
  final String aggregation;
  final String direction;

  const KrComputation({
    required this.current,
    required this.target,
    required this.score,
    required this.unit,
    required this.onPace,
    required this.aggregation,
    required this.direction,
  });

  Map<String, dynamic> toMap() => {
        'current': current,
        'target': target,
        'score': score,
        'unit': unit,
        'on_pace': onPace,
        'aggregation': aggregation,
        'direction': direction,
      };
}

/// Folds a KR's measurements into its current value, score and pace.
KrComputation computeKrState({
  required String aggregation,
  required String direction,
  required String mode,
  required double? target,
  required String? unit,
  required List<double> valuesNewestFirst,
  required DateTime start,
  required DateTime end,
  DateTime? now,
}) {
  final current = aggregateValues(valuesNewestFirst, aggregation);
  final score = scoreFor(current: current, target: target, direction: direction);
  return KrComputation(
    current: current,
    target: target,
    score: score,
    unit: unit,
    onPace: paceFor(
      score: score,
      fractionElapsed:
          paceFraction(mode: mode, start: start, end: end, now: now),
    ),
    aggregation: aggregation,
    direction: direction,
  );
}
