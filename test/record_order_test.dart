// The Record page's ordering and filtering, kept as pure functions so they can
// be tested without a database.

import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/okr/record_screen.dart';

Map<String, dynamic> kr(
  String id, {
  String? lastLogged,
  String created = '2026-01-01T00:00:00.000',
  String title = 'Untitled',
  String? objective,
}) =>
    {
      'id': id,
      'title': title,
      'created_at': created,
      'last_logged_at': lastLogged,
      'objective_title': objective,
    };

List<String> ids(List<Map<String, dynamic>> rows) =>
    [for (final r in rows) r['id'] as String];

void main() {
  group('byRecency', () {
    test('newest logged first', () {
      final out = byRecency([
        kr('a', lastLogged: '2026-07-01T10:00:00.000'),
        kr('b', lastLogged: '2026-07-24T09:00:00.000'),
        kr('c', lastLogged: '2026-07-20T23:59:59.000'),
      ]);
      expect(ids(out), ['b', 'c', 'a']);
    });

    test('never-logged sink to the bottom, oldest first', () {
      final out = byRecency([
        kr('new', created: '2026-06-01T00:00:00.000'),
        kr('logged', lastLogged: '2026-01-02T00:00:00.000'),
        kr('older', created: '2026-02-01T00:00:00.000'),
      ]);
      expect(ids(out), ['logged', 'older', 'new']);
    });

    test('ties break on created_at, so the order is deterministic', () {
      const same = '2026-07-24T08:00:00.000';
      final out = byRecency([
        kr('second', lastLogged: same, created: '2026-05-01T00:00:00.000'),
        kr('first', lastLogged: same, created: '2026-03-01T00:00:00.000'),
      ]);
      expect(ids(out), ['first', 'second']);
    });

    test('ISO strings compare across month and year boundaries', () {
      final out = byRecency([
        kr('dec', lastLogged: '2025-12-31T23:00:00.000'),
        kr('jan', lastLogged: '2026-01-01T01:00:00.000'),
        kr('sep', lastLogged: '2025-09-30T23:00:00.000'),
      ]);
      expect(ids(out), ['jan', 'dec', 'sep']);
    });

    test('an empty list stays empty', () {
      expect(byRecency([]), isEmpty);
    });
  });

  group('matching', () {
    final rows = [
      kr('a', title: 'Squat 120kg', objective: 'Get stronger'),
      kr('b', title: 'Read 12 books', objective: 'Read more'),
      kr('c', title: 'Long run 18km'),
    ];

    test('an empty query is the identity', () {
      expect(ids(matching(rows, '')), ['a', 'b', 'c']);
      expect(ids(matching(rows, '   ')), ['a', 'b', 'c']);
    });

    test('matches the title, case-insensitively', () {
      expect(ids(matching(rows, 'SQUAT')), ['a']);
      expect(ids(matching(rows, 'run')), ['c']);
    });

    test('matches the objective title too', () {
      expect(ids(matching(rows, 'stronger')), ['a']);
    });

    test('tolerates a missing objective title', () {
      expect(ids(matching(rows, '18km')), ['c']);
    });

    test('no match returns empty', () {
      expect(matching(rows, 'deadlift'), isEmpty);
    });
  });

  group('inStoredOrder', () {
    test('reapplies a captured order regardless of input order', () {
      final out = inStoredOrder(
        [kr('c'), kr('a'), kr('b')],
        ['a', 'b', 'c'],
      );
      expect(ids(out), ['a', 'b', 'c']);
    });

    test('key results the order does not know about go to the end', () {
      final out = inStoredOrder(
        [
          kr('fresh', created: '2026-07-25T00:00:00.000'),
          kr('a'),
          kr('b'),
        ],
        ['a', 'b'],
      );
      expect(ids(out), ['a', 'b', 'fresh']);
    });

    test('several unknowns keep created_at order', () {
      final out = inStoredOrder(
        [
          kr('y', created: '2026-07-25T00:00:00.000'),
          kr('x', created: '2026-07-24T00:00:00.000'),
          kr('a'),
        ],
        ['a'],
      );
      expect(ids(out), ['a', 'x', 'y']);
    });
  });
}
