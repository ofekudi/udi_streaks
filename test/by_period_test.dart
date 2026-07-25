// The history list's quarter grouping, kept pure so the ordering it relies on
// can be tested without a database or a widget.

import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/okr/period.dart';

Map<String, dynamic> entry(String at) => {'recorded_at': at};

DateTime at(Map<String, dynamic> m) =>
    DateTime.parse(m['recorded_at'] as String);

/// `2026-Q3: 24 Jul, 23 Jul` — the shape the list renders, flattened.
List<String> shape(List<(Period, List<Map<String, dynamic>>)> groups) => [
      for (final (period, entries) in groups)
        '${period.id}: ${entries.map((e) => e['recorded_at']).join(', ')}',
    ];

void main() {
  group('byPeriodDesc', () {
    test('newest quarter first, newest entry first inside it', () {
      final out = byPeriodDesc([
        entry('2026-04-02T09:00:00.000'),
        entry('2026-07-24T09:00:00.000'),
        entry('2026-07-01T09:00:00.000'),
        entry('2026-07-23T09:00:00.000'),
      ], at);

      expect(shape(out), [
        '2026-Q3: 2026-07-24T09:00:00.000, 2026-07-23T09:00:00.000, '
            '2026-07-01T09:00:00.000',
        '2026-Q2: 2026-04-02T09:00:00.000',
      ]);
    });

    test('orders across years, not just within one', () {
      final out = byPeriodDesc([
        entry('2025-11-01T09:00:00.000'),
        entry('2026-02-01T09:00:00.000'),
        entry('2025-02-01T09:00:00.000'),
      ], at);

      expect([for (final (p, _) in out) p.id],
          ['2026-Q1', '2025-Q4', '2025-Q1']);
    });

    test('quarter boundaries land in the right bucket', () {
      final out = byPeriodDesc([
        entry('2026-03-31T23:59:59.000'),
        entry('2026-04-01T00:00:00.000'),
      ], at);

      expect([for (final (p, _) in out) p.id], ['2026-Q2', '2026-Q1']);
    });

    test('an empty log groups into nothing', () {
      expect(byPeriodDesc(<Map<String, dynamic>>[], at), isEmpty);
    });

    test('every entry survives the grouping', () {
      final rows = [
        for (var month = 1; month <= 12; month++)
          entry('2026-${month.toString().padLeft(2, '0')}-15T09:00:00.000'),
      ];

      final out = byPeriodDesc(rows, at);

      expect(out.length, 4, reason: 'four quarters in a year');
      expect(out.fold<int>(0, (n, g) => n + g.$2.length), rows.length);
    });
  });
}
