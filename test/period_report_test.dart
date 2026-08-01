// A period reconstructs from what is already stored: an objective belongs to
// the quarter its `start_date` falls in, so a renewal's clone lands in the next
// one and a closed quarter can be read back without a lineage column.
//
// Also the two things the overflow menu asks before drawing itself — which
// period a close would act on, and which ones are already closed.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';
import 'package:udi_streaks/okr/period.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DBHelper db;
  late String areaId;

  final q3 = const Period(2026, 3);
  final q4 = const Period(2026, 4);

  Future<String> objectiveIn(Period p, String title) => db.insertObjective(
      areaId: areaId, title: title, start: p.start, end: p.end);

  setUp(() async {
    db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    areaId = await db.insertArea('Training');
  });

  group('getPeriodTree', () {
    test('holds the objectives that started in that period, and no others',
        () async {
      await objectiveIn(q3, 'Get stronger');
      await objectiveIn(q4, 'Keep it up');

      final tree = await db.getPeriodTree(q3);

      final titles = [
        for (final a in tree)
          for (final o in (a['objectives'] as List)) o['title'],
      ];
      expect(titles, ['Get stronger']);
    });

    test('a renewal puts its clone in the next period, not this one', () async {
      final id = await objectiveIn(q3, 'Get stronger');
      await db.insertKeyResult(
          objectiveId: id, title: 'Squat', aggregation: 'LATEST', target: 36);

      await db.renewObjective(id);

      Future<List<String>> titlesIn(Period p) async => [
            for (final a in await db.getPeriodTree(p))
              for (final o in (a['objectives'] as List)) o['title'] as String,
          ];
      expect(await titlesIn(q3), ['Get stronger']);
      expect(await titlesIn(q4), ['Get stronger'],
          reason: 'the clone, under the same name, one quarter along');
    });

    test('archived objectives still count towards the rollup', () async {
      final id = await objectiveIn(q3, 'Get stronger');
      final kr = await db.insertKeyResult(
          objectiveId: id, title: 'Squat', aggregation: 'SUM', target: 100);
      await db.logMeasurement(
          keyResultId: kr, value: 50, at: DateTime(2026, 8, 1));
      await db.updateObjectiveStatus(id, 'archived');

      final tree = await db.getPeriodTree(q3);

      // getAreasWithRollup excludes archived rows on purpose — a closed quarter
      // must not drag the live one around. Here being archived is the normal
      // end state, so excluding them would score a finished quarter at nothing.
      expect(tree.single['score'], closeTo(0.5, 0.001));
    });

    test('carries each row its grade, and null where none was given', () async {
      final id = await objectiveIn(q3, 'Get stronger');
      final kr = await db.insertKeyResult(
          objectiveId: id, title: 'Squat', aggregation: 'SUM', target: 100);
      await db.saveGrade(
          subjectKind: 'key_result', subjectId: kr, period: q3.id, grade: 7);
      await db.saveGrade(
          subjectKind: 'objective', subjectId: id, period: q3.id, grade: 8);

      final objective =
          (await db.getPeriodTree(q3)).single['objectives'][0] as Map;

      expect(objective['grade'], 8);
      expect((objective['key_results'] as List).single['grade'], 7);
    });

    test('a grade from another quarter is not picked up', () async {
      final id = await objectiveIn(q3, 'Get stronger');
      await db.saveGrade(
          subjectKind: 'objective', subjectId: id, period: q4.id, grade: 9);

      final objective =
          (await db.getPeriodTree(q3)).single['objectives'][0] as Map;

      expect(objective['grade'], isNull);
    });

    test('an area with nothing in the period drops out', () async {
      await db.insertArea('Reading');
      await objectiveIn(q3, 'Get stronger');

      final tree = await db.getPeriodTree(q3);

      expect(tree.map((a) => a['name']), ['Training']);
    });
  });

  group('closablePeriod', () {
    test('is null with nothing active', () async {
      expect(await db.closablePeriod(), isNull);
    });

    test('is the oldest period that still has an active objective', () async {
      await objectiveIn(const Period(2026, 1), 'Old');
      await objectiveIn(Period.current(), 'Now');

      expect((await db.closablePeriod())?.id, '2026-Q1');
    });

    test('ignores archived objectives', () async {
      final old = await objectiveIn(const Period(2026, 1), 'Old');
      await db.updateObjectiveStatus(old, 'archived');
      await objectiveIn(Period.current(), 'Now');

      expect((await db.closablePeriod())?.id, Period.current().id);
    });

    test('goes quiet when everything active is still ahead of us', () async {
      // What closing the current quarter early leaves behind: clones sitting in
      // the next one. Offering to close that too would loop forever.
      await objectiveIn(Period.current().next, 'Next quarter');

      expect(await db.closablePeriod(), isNull);
    });
  });

  group('closedPeriods', () {
    test('is empty until a period is closed', () async {
      expect(await db.closedPeriods(), isEmpty);
    });

    test('lists closed periods newest first', () async {
      await db.closePeriod(const Period(2026, 1));
      await db.closePeriod(q3);
      await db.closePeriod(const Period(2025, 4));

      expect((await db.closedPeriods()).map((p) => p.id),
          ['2026-Q3', '2026-Q1', '2025-Q4']);
    });

    test('closing twice leaves one row — re-running a close is not a second one',
        () async {
      await db.closePeriod(q3);
      await db.closePeriod(q3);

      expect(await db.closedPeriods(), hasLength(1));
    });

    test('a period record has no grade on it', () async {
      await db.closePeriod(q3);

      final row = (await (await db.database).query('reviews',
              where: 'subject_kind = ?',
              whereArgs: [DBHelper.periodSubjectKind]))
          .single;
      // The user ranks key results and objectives, never the quarter. This row
      // is a marker: what it carries is `graded_at`.
      expect(row['grade'], isNull);
      expect(row['subject_id'], q3.id);
      expect(row['graded_at'], isNotNull);
    });

    test('deleting the area a period held does not take the period with it',
        () async {
      await objectiveIn(q3, 'Get stronger');
      await db.closePeriod(q3);

      await db.deleteArea(areaId);

      expect((await db.closedPeriods()).map((p) => p.id), [q3.id],
          reason: 'a record that a quarter happened outlives its contents');
    });
  });

  group('periodSummary', () {
    test('counts what was graded, carried and dropped', () async {
      final carried = await objectiveIn(q3, 'Get stronger');
      final krA = await db.insertKeyResult(
          objectiveId: carried,
          title: 'Squat',
          aggregation: 'SUM',
          target: 100);
      await db.insertKeyResult(
          objectiveId: carried,
          title: 'Volume',
          aggregation: 'SUM',
          target: 100);
      final dropped = await objectiveIn(q3, 'Read more');
      await db.saveGrade(
          subjectKind: 'key_result', subjectId: krA, period: q3.id, grade: 7);

      await db.renewObjective(carried);
      await db.updateObjectiveStatus(dropped, 'archived');

      final s = await db.periodSummary(q3);
      expect(s.scored, 1);
      expect(s.scorable, 2);
      expect(s.carried, 1);
      expect(s.dropped, 1);
    });

    test('nothing decided yet reads as nothing carried or dropped', () async {
      await objectiveIn(q3, 'Get stronger');

      final s = await db.periodSummary(q3);
      expect(s.carried, 0);
      expect(s.dropped, 0);
    });
  });
}
