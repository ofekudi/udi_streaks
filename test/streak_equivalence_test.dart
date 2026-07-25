// Differential test: the original `DBHelper.getHabitStreaks` body (ported
// verbatim from git commit 8451f0d, lines 325-444, with only the db.query
// replaced by an injected list) must agree with the extracted `computeStreaks`
// on randomized histories. Temporary scaffolding — delete once satisfied.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/habits/streak_rules.dart';

/// Verbatim transcription of the original algorithm. Do not tidy this.
Map<String, dynamic> original(List<DateTime> parsedCompletions, DateTime now) {
  final completions = parsedCompletions;

  if (completions.isEmpty) {
    return {
      'current_streak': 0,
      'longest_streak': 0,
      'streak_at_risk': false,
      'streak_start_date': null,
      'negative_streak': 0
    };
  }

  int currentStreak = 0;
  int longestStreak = 0;
  int currentCount = 0;
  bool streakAtRisk = false;
  DateTime? streakStartDate;
  int negativeStreak = 0;

  final today = now.copyWith(
      hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

  final mostRecentCompletion = completions.first;
  final mostRecentCompletionDate = DateTime(mostRecentCompletion.year,
      mostRecentCompletion.month, mostRecentCompletion.day);
  final todayDate = DateTime(today.year, today.month, today.day);
  final daysSinceLastCompletion =
      todayDate.difference(mostRecentCompletionDate).inDays;

  if (daysSinceLastCompletion >= 3) {
    currentStreak = 0;
    streakAtRisk = false;
    streakStartDate = null;
    negativeStreak = -(daysSinceLastCompletion - 3);
  } else {
    negativeStreak = 0;
    DateTime? lastDate;

    for (var completedAt in completions) {
      final dateOnly =
          DateTime(completedAt.year, completedAt.month, completedAt.day);

      if (lastDate == null) {
        currentCount = 1;
        lastDate = dateOnly;
        streakStartDate = dateOnly;
      } else {
        final difference = lastDate.difference(dateOnly).inDays;
        if (difference <= 2) {
          currentCount++;
          streakStartDate = dateOnly;
        } else {
          break;
        }
        lastDate = dateOnly;
      }
    }

    currentStreak = currentCount;
    streakAtRisk = daysSinceLastCompletion == 2;
  }

  DateTime? lastDateForLongest;
  int countForLongest = 0;

  for (var completedAt in completions) {
    final dateOnly =
        DateTime(completedAt.year, completedAt.month, completedAt.day);

    if (lastDateForLongest == null) {
      countForLongest = 1;
      lastDateForLongest = dateOnly;
    } else {
      final difference = lastDateForLongest.difference(dateOnly).inDays;
      if (difference <= 2) {
        countForLongest++;
      } else {
        if (countForLongest > longestStreak) {
          longestStreak = countForLongest;
        }
        countForLongest = 1;
      }
      lastDateForLongest = dateOnly;
    }
  }

  if (countForLongest > longestStreak) {
    longestStreak = countForLongest;
  }

  return {
    'current_streak': currentStreak,
    'longest_streak': longestStreak,
    'streak_at_risk': streakAtRisk,
    'streak_start_date': streakStartDate,
    'negative_streak': negativeStreak
  };
}

void main() {
  test('extracted rule matches the original on 20000 random histories', () {
    final rng = Random(20260725);
    final now = DateTime(2026, 7, 25, 11, 5);
    var compared = 0;

    for (var iteration = 0; iteration < 20000; iteration++) {
      // A random set of distinct days within the last ~40, newest first,
      // each at a random time of day.
      final span = 1 + rng.nextInt(40);
      final days = <int>{};
      final howMany = rng.nextInt(12);
      for (var i = 0; i < howMany; i++) {
        days.add(rng.nextInt(span));
      }
      final sorted = days.toList()..sort();
      final completions = [
        for (final d in sorted)
          DateTime(2026, 7, 25 - d, rng.nextInt(24), rng.nextInt(60)),
      ];

      final expected = original(completions, now);
      final actual = computeStreaks(completions, now: now).toMap();

      expect(actual, expected,
          reason: 'mismatch for ${completions.map((c) => c.toIso8601String())}');
      compared++;
    }

    expect(compared, 20000);
  });

  test('also matches when several completions land on the same day', () {
    final rng = Random(7);
    final now = DateTime(2026, 7, 25, 11, 5);

    for (var iteration = 0; iteration < 5000; iteration++) {
      final howMany = rng.nextInt(10);
      final offsets = [for (var i = 0; i < howMany; i++) rng.nextInt(10)]
        ..sort();
      final completions = [
        for (final d in offsets)
          DateTime(2026, 7, 25 - d, rng.nextInt(24), rng.nextInt(60)),
      ];

      expect(computeStreaks(completions, now: now).toMap(),
          original(completions, now));
    }
  });
}
