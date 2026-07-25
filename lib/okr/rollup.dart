/// How child scores roll up into a parent score.
///
/// These two rules were previously written out at three call sites — the
/// objective rollup existed identically in both `DBHelper` and
/// `_ObjectiveScreenState`, free to drift apart.
library;

/// An objective's score: the mean of its key-result scores, weighted by each
/// KR's `weight` (default 1).
///
/// Key results with no score (track-only, or nothing logged yet) are left out
/// entirely rather than counted as zero. Returns null when nothing is scorable.
double? weightedScore(Iterable<Map<String, dynamic>> keyResults) {
  double weightedSum = 0, weights = 0;
  for (final k in keyResults) {
    final score = k['score'];
    if (score is double) {
      final weight = (k['weight'] as num?)?.toDouble() ?? 1;
      weightedSum += score * weight;
      weights += weight;
    }
  }
  return weights > 0 ? weightedSum / weights : null;
}

/// An area's score: the plain mean of its objectives' scores, ignoring
/// unscored objectives. Returns null when nothing is scorable.
double? meanScore(Iterable<Map<String, dynamic>> objectives) {
  final scores = objectives.map((o) => o['score']).whereType<double>();
  if (scores.isEmpty) return null;
  return scores.reduce((a, b) => a + b) / scores.length;
}
