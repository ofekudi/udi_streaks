// Unit tests for the quarter/period logic that drives OKR windows,
// renewal, and grade history. Pure Dart — no platform DB needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/okr/period.dart';

void main() {
  test('quarter is derived from month', () {
    expect(Period.ofDate(DateTime(2026, 1, 15)).quarter, 1);
    expect(Period.ofDate(DateTime(2026, 7, 24)).quarter, 3);
    expect(Period.ofDate(DateTime(2026, 12, 31)).quarter, 4);
  });

  test('id and label formatting', () {
    final p = Period(2026, 3);
    expect(p.id, '2026-Q3');
    expect(p.label, 'Q3 2026');
  });

  test('start and end bound the quarter', () {
    final q3 = Period(2026, 3);
    expect(q3.start, DateTime(2026, 7, 1));
    expect(q3.end.isBefore(DateTime(2026, 10, 1)), isTrue);
    expect(q3.end.isAfter(DateTime(2026, 9, 30)), isTrue);
  });

  test('next rolls over the year at Q4', () {
    expect(Period(2026, 3).next.id, '2026-Q4');
    expect(Period(2026, 4).next.id, '2027-Q1');
  });

  test('parse round-trips', () {
    expect(Period.parse('2026-Q3')!.id, '2026-Q3');
    expect(Period.parse('nope'), isNull);
  });

  test('fractionElapsed is bounded 0..1', () {
    final f = Period.current().fractionElapsed;
    expect(f >= 0 && f <= 1, isTrue);
  });
}
