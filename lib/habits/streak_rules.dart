/// The "never miss twice" streak rule, as pure functions over completion dates.
///
/// Extracted verbatim from `DBHelper.getHabitStreaks` so the rule can be unit
/// tested without a database. The two near-identical walk loops in the original
/// (one for the current streak, one for the longest) are unified here into a
/// single pass that splits the history into runs.
library;

import '../core/dates.dart';

/// A completion may be up to this many days after the previous one and still
/// continue the streak — i.e. you may miss one day, but not two.
const int kMaxStreakGapDays = 2;

/// Days without a completion after which the streak is considered broken and
/// a negative streak starts accumulating.
const int kStreakBreakDays = 3;

/// The derived streak state for a single habit.
class StreakSummary {
  /// Number of completions in the current unbroken run. 0 once broken.
  final int currentStreak;

  /// Longest run ever recorded.
  final int longestStreak;

  /// True when exactly one day has been missed — complete today or lose it.
  final bool streakAtRisk;

  /// Date of the oldest completion in the current run, or null if broken.
  final DateTime? streakStartDate;

  /// Negative count of days broken beyond [kStreakBreakDays]; 0 when not broken.
  final int negativeStreak;

  const StreakSummary({
    required this.currentStreak,
    required this.longestStreak,
    required this.streakAtRisk,
    required this.streakStartDate,
    required this.negativeStreak,
  });

  static const empty = StreakSummary(
    currentStreak: 0,
    longestStreak: 0,
    streakAtRisk: false,
    streakStartDate: null,
    negativeStreak: 0,
  );

  /// The wire format the UI and the home widget already read. Kept so
  /// `getHabitStreaks` can return exactly what it always did.
  Map<String, dynamic> toMap() => {
        'current_streak': currentStreak,
        'longest_streak': longestStreak,
        'streak_at_risk': streakAtRisk,
        'streak_start_date': streakStartDate,
        'negative_streak': negativeStreak,
      };
}

/// One unbroken run of completions, walked newest-first.
class _Run {
  int length = 1;
  DateTime oldest;
  _Run(this.oldest);
}

/// Derives the streak state from [completions], which must be ordered
/// **newest first**. [now] defaults to the current time and exists for tests.
///
/// Note that a run counts completion *records*, not distinct days. Both write
/// paths (`toggleHabitCompletion`, `addRetroactiveCompletion`) reject a second
/// completion on a day that already has one, so in practice the two coincide.
StreakSummary computeStreaks(List<DateTime> completions, {DateTime? now}) {
  if (completions.isEmpty) return StreakSummary.empty;

  final today = startOfDay(now ?? DateTime.now());

  // Split the history into runs wherever the gap exceeds the allowed miss.
  final runs = <_Run>[];
  DateTime? prev;
  for (final completion in completions) {
    final day = startOfDay(completion);
    if (prev == null || prev.difference(day).inDays > kMaxStreakGapDays) {
      runs.add(_Run(day));
    } else {
      runs.last.length++;
      runs.last.oldest = day;
    }
    prev = day;
  }

  final longestStreak =
      runs.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  final daysSinceLast = today.difference(startOfDay(completions.first)).inDays;

  if (daysSinceLast >= kStreakBreakDays) {
    return StreakSummary(
      currentStreak: 0,
      longestStreak: longestStreak,
      streakAtRisk: false,
      streakStartDate: null,
      negativeStreak: -(daysSinceLast - kStreakBreakDays),
    );
  }

  return StreakSummary(
    currentStreak: runs.first.length,
    longestStreak: longestStreak,
    streakAtRisk: daysSinceLast == kMaxStreakGapDays,
    streakStartDate: runs.first.oldest,
    negativeStreak: 0,
  );
}
