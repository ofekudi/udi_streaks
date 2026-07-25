import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/okr/period.dart';
import 'package:udi_streaks/okr/scoring.dart';

final now = DateTime(2026, 7, 25, 12);

void main() {
  group('aggregateValues', () {
    test('SUM adds everything, and is 0 for an empty log', () {
      expect(aggregateValues([3, 2, 1], 'SUM'), 6);
      expect(aggregateValues([], 'SUM'), 0);
    });

    test('COUNT counts entries', () {
      expect(aggregateValues([9, 9, 9], 'COUNT'), 3);
      expect(aggregateValues([], 'COUNT'), 0);
    });

    test('LATEST reads the head of the newest-first list, null when empty', () {
      expect(aggregateValues([82.1, 83.0, 84.4], 'LATEST'), 82.1);
      expect(aggregateValues([], 'LATEST'), isNull);
    });

    test('an unknown aggregation falls back to SUM', () {
      expect(aggregateValues([1, 2], 'NONSENSE'), 3);
    });
  });

  group('scoreFor', () {
    test('UP is current over target, clamped to 1', () {
      expect(scoreFor(current: 5, target: 10, direction: 'UP'), 0.5);
      expect(scoreFor(current: 30, target: 10, direction: 'UP'), 1.0);
    });

    test('DOWN inverts — lower is better', () {
      expect(scoreFor(current: 100, target: 80, direction: 'DOWN'), 0.8);
      expect(scoreFor(current: 70, target: 80, direction: 'DOWN'), 1.0);
    });

    test('DOWN treats a non-positive current as a perfect score', () {
      expect(scoreFor(current: 0, target: 80, direction: 'DOWN'), 1.0);
      expect(scoreFor(current: -5, target: 80, direction: 'DOWN'), 1.0);
    });

    test('track-only key results have no score', () {
      expect(scoreFor(current: 5, target: null, direction: 'UP'), isNull);
      expect(scoreFor(current: 5, target: 0, direction: 'UP'), isNull);
      expect(scoreFor(current: null, target: 10, direction: 'UP'), isNull);
    });
  });

  group('paceFraction', () {
    test('only time-boxed modes pace themselves', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 12, 31);
      for (final mode in ['ROLLING', 'ALL']) {
        expect(paceFraction(mode: mode, start: start, end: end, now: now), 1.0,
            reason: mode);
      }
    });

    test('OBJECTIVE and YEAR interpolate across the window', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 1, 11);
      final half = paceFraction(
          mode: 'OBJECTIVE', start: start, end: end, now: DateTime(2026, 1, 6));
      expect(half, closeTo(0.5, 0.01));
    });

    test('a zero-length or inverted window is treated as fully elapsed', () {
      final d = DateTime(2026, 5, 1);
      expect(paceFraction(mode: 'YEAR', start: d, end: d, now: now), 1.0);
    });

    test('is clamped outside the window', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 2, 1);
      expect(
          paceFraction(
              mode: 'YEAR', start: start, end: end, now: DateTime(2025, 6, 1)),
          0.0);
      expect(
          paceFraction(
              mode: 'YEAR', start: start, end: end, now: DateTime(2027, 6, 1)),
          1.0);
    });
  });

  group('paceFor', () {
    test('bands sit at +0.05 and -0.1 around the elapsed fraction', () {
      expect(paceFor(score: 0.55, fractionElapsed: 0.5), 'ahead');
      expect(paceFor(score: 0.549, fractionElapsed: 0.5), 'on_track');
      expect(paceFor(score: 0.4, fractionElapsed: 0.5), 'on_track');
      expect(paceFor(score: 0.399, fractionElapsed: 0.5), 'behind');
    });

    test('a fully elapsed window still lets a perfect score read as ahead', () {
      // (1.0 + 0.05) clamps to 1.0, so score == 1 qualifies.
      expect(paceFor(score: 1.0, fractionElapsed: 1.0), 'ahead');
      expect(paceFor(score: 0.95, fractionElapsed: 1.0), 'on_track');
      expect(paceFor(score: 0.5, fractionElapsed: 1.0), 'behind');
    });

    test('no score means no pace', () {
      expect(paceFor(score: null, fractionElapsed: 0.5), isNull);
    });
  });

  group('resolveWindow', () {
    test('ROLLING looks back the configured number of days', () {
      final (start, end) = resolveWindow(mode: 'ROLLING', windowDays: 30, now: now);
      expect(end, now);
      expect(start, now.subtract(const Duration(days: 30)));
    });

    test('ROLLING defaults to a week', () {
      final (start, _) = resolveWindow(mode: 'ROLLING', now: now);
      expect(start, now.subtract(const Duration(days: kDefaultRollingDays)));
    });

    test('YEAR spans the calendar year', () {
      final (start, end) = resolveWindow(mode: 'YEAR', now: now);
      expect(start, DateTime(2026, 1, 1));
      expect(end, DateTime(2026, 12, 31, 23, 59, 59));
    });

    test('ALL reaches back to the epoch', () {
      final (start, end) = resolveWindow(mode: 'ALL', now: now);
      expect(start, DateTime(1970));
      expect(end, now);
    });

    test('OBJECTIVE uses the parent objective dates when present', () {
      final s = DateTime(2026, 4, 1);
      final e = DateTime(2026, 6, 30);
      expect(
        resolveWindow(mode: 'OBJECTIVE', objectiveStart: s, objectiveEnd: e),
        (s, e),
      );
    });

    test('OBJECTIVE falls back to the current quarter when detached', () {
      final p = Period.current();
      expect(resolveWindow(mode: 'OBJECTIVE'), (p.start, p.end));
      expect(resolveWindow(mode: null), (p.start, p.end),
          reason: 'a missing mode defaults to OBJECTIVE');
    });
  });

  group('computeKrState', () {
    test('a mid-quarter SUM key result reports value, score and pace', () {
      final r = computeKrState(
        aggregation: 'SUM',
        direction: 'UP',
        mode: 'OBJECTIVE',
        target: 100,
        unit: 'km',
        valuesNewestFirst: [10, 20, 20],
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 11),
        now: DateTime(2026, 1, 6),
      );
      expect(r.current, 50);
      expect(r.score, 0.5);
      expect(r.onPace, 'on_track');
      expect(r.unit, 'km');
      expect(r.toMap()['on_pace'], 'on_track');
    });

    test('a track-only key result has no score or pace', () {
      final r = computeKrState(
        aggregation: 'COUNT',
        direction: 'UP',
        mode: 'ALL',
        target: null,
        unit: null,
        valuesNewestFirst: [1, 1],
        start: DateTime(2026, 1, 1),
        end: now,
      );
      expect(r.current, 2);
      expect(r.score, isNull);
      expect(r.onPace, isNull);
    });

    test('toMap uses the legacy key names the UI reads', () {
      final r = computeKrState(
        aggregation: 'SUM',
        direction: 'UP',
        mode: 'ALL',
        target: 10,
        unit: 'reps',
        valuesNewestFirst: [10],
        start: DateTime(2026, 1, 1),
        end: now,
      );
      expect(
          r.toMap().keys,
          containsAll([
            'current',
            'target',
            'score',
            'unit',
            'on_pace',
            'aggregation',
            'direction'
          ]));
    });
  });
}
