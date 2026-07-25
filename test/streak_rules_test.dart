import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/habits/streak_rules.dart';

/// [now] is pinned so these tests never depend on the wall clock.
final now = DateTime(2026, 7, 25, 9, 30);

/// A completion [d] days before [now], at an arbitrary time of day.
DateTime ago(int d) => DateTime(2026, 7, 25 - d, 18, 42);

/// Completions must reach `computeStreaks` newest-first, as the query orders them.
StreakSummary summarise(List<int> daysAgo) =>
    computeStreaks(daysAgo.map(ago).toList(), now: now);

void main() {
  test('no completions yields the empty summary', () {
    final s = computeStreaks([], now: now);
    expect(s.currentStreak, 0);
    expect(s.longestStreak, 0);
    expect(s.streakAtRisk, isFalse);
    expect(s.streakStartDate, isNull);
    expect(s.negativeStreak, 0);
  });

  test('consecutive days build a streak', () {
    final s = summarise([0, 1, 2, 3]);
    expect(s.currentStreak, 4);
    expect(s.longestStreak, 4);
    expect(s.streakAtRisk, isFalse);
    expect(s.streakStartDate, DateTime(2026, 7, 22));
    expect(s.negativeStreak, 0);
  });

  test('a single missed day keeps the streak alive', () {
    // Completed today and 2 days ago — yesterday was missed.
    final s = summarise([0, 2, 3]);
    expect(s.currentStreak, 3);
    expect(s.streakAtRisk, isFalse);
  });

  test('missing two days breaks the run', () {
    // Gap of 3 days between the newest completion and the one before it.
    final s = summarise([0, 3, 4]);
    expect(s.currentStreak, 1, reason: 'only today is in the current run');
    expect(s.longestStreak, 2, reason: 'the older pair is the longest run');
  });

  test('at risk after exactly one full day missed', () {
    final s = summarise([2, 3, 4]);
    expect(s.streakAtRisk, isTrue);
    expect(s.currentStreak, 3);
    expect(s.negativeStreak, 0);
  });

  test('three days idle zeroes the streak and starts a negative one', () {
    final s = summarise([3, 4, 5]);
    expect(s.currentStreak, 0);
    expect(s.streakAtRisk, isFalse);
    expect(s.streakStartDate, isNull);
    expect(s.negativeStreak, 0, reason: 'day 3 is the boundary, not yet negative');
    expect(s.longestStreak, 3, reason: 'history is still counted');
  });

  test('negative streak accumulates beyond the break threshold', () {
    expect(summarise([5]).negativeStreak, -2);
    expect(summarise([10]).negativeStreak, -7);
  });

  test('longest streak survives a later break', () {
    // A 4-long run a while back, then a fresh 1-long run today.
    final s = summarise([0, 6, 7, 8, 9]);
    expect(s.currentStreak, 1);
    expect(s.longestStreak, 4);
  });

  test('time of day is ignored — only the calendar date counts', () {
    final s = computeStreaks([
      DateTime(2026, 7, 25, 0, 1),
      DateTime(2026, 7, 24, 23, 59),
    ], now: now);
    expect(s.currentStreak, 2);
  });
}
