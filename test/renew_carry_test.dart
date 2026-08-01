// Renewal on the close flow's terms: an objective can carry forward with a key
// result left behind, or with one aiming at a new number. The plain call — no
// overrides — must still do exactly what it did before, which is what
// data_control_test pins from the other side.
//
// SQL and a transaction, so a real database.

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
  late String objectiveId;

  /// One objective in the current quarter with three key results: a Value one
  /// carrying notation, a Total, and a Count a habit can feed.
  Future<(String squat, String volume, String sessions)> tree() async {
    final squat = await db.insertKeyResult(
        objectiveId: objectiveId,
        title: 'Squat',
        aggregation: 'LATEST',
        target: 36,
        targetRaw: '3x12',
        baseline: 30,
        baselineRaw: '3x10',
        unit: 'reps');
    final volume = await db.insertKeyResult(
        objectiveId: objectiveId,
        title: 'Volume',
        aggregation: 'SUM',
        target: 10000,
        unit: 'kg');
    final sessions = await db.insertKeyResult(
        objectiveId: objectiveId,
        title: 'Sessions',
        aggregation: 'COUNT',
        target: 24);
    return (squat, volume, sessions);
  }

  Future<List<Map<String, dynamic>>> clonedKrs(String newId) async =>
      (await db.database).query('key_results',
          where: 'objective_id = ?', whereArgs: [newId], orderBy: 'title ASC');

  setUp(() async {
    db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    areaId = await db.insertArea('Training');
    final p = Period.current();
    objectiveId = await db.insertObjective(
        areaId: areaId, title: 'Get stronger', start: p.start, end: p.end);
  });

  group('carrying everything, unchanged', () {
    test('clones every key result with its target intact', () async {
      await tree();

      final newId = await db.renewObjective(objectiveId);

      final krs = await clonedKrs(newId);
      expect(krs.map((k) => k['title']), ['Sessions', 'Squat', 'Volume']);
      final squat = krs.firstWhere((k) => k['title'] == 'Squat');
      expect(squat['target_value'], 36);
      expect(squat['target_raw'], '3x12',
          reason: 'the notation is part of the target, not decoration');
    });

    test('the original is archived and the clone is in the next quarter',
        () async {
      await tree();
      final p = Period.current();

      final newId = await db.renewObjective(objectiveId);

      final rows = await (await db.database).query('objectives');
      final old = rows.firstWhere((o) => o['id'] == objectiveId);
      final fresh = rows.firstWhere((o) => o['id'] == newId);
      expect(old['status'], 'archived');
      expect(fresh['status'], 'active');
      expect(Period.ofDate(DateTime.parse(fresh['start_date'] as String)).id,
          p.next.id);
    });
  });

  group('leaving a key result behind', () {
    test('the dropped one is absent from the clone, the rest carry', () async {
      final (_, volume, _) = await tree();

      final newId =
          await db.renewObjective(objectiveId, dropKeyResults: {volume});

      final krs = await clonedKrs(newId);
      expect(krs.map((k) => k['title']), ['Sessions', 'Squat']);
    });

    test('its measurements stay with the quarter it was logged in', () async {
      final (_, volume, _) = await tree();
      await db.logMeasurement(keyResultId: volume, value: 2500);

      await db.renewObjective(objectiveId, dropKeyResults: {volume});

      // Dropping is about the next quarter, never about the record of this one.
      expect(await db.getMeasurementSeries(keyResultId: volume), hasLength(1));
    });

    test('a habit whose key result is dropped ends up linked to nothing',
        () async {
      final (_, _, sessions) = await tree();
      final habitId = await db.insertHabit('Gym');
      await db.linkHabitToKeyResult(habitId, sessions);

      final newId =
          await db.renewObjective(objectiveId, dropKeyResults: {sessions});

      final krs = await clonedKrs(newId);
      expect(krs.any((k) => k['habit_id'] == habitId), isFalse,
          reason: 'there is no clone to hand the link to');
      final old = await db.getKeyResultsById(sessions);
      expect(old!['habit_id'], isNull,
          reason: 'and the archived copy lets go of it either way');
    });
  });

  group('raising a target', () {
    test('the clone aims at the new number, in the notation it was typed',
        () async {
      final (squat, _, _) = await tree();

      final newId = await db.renewObjective(objectiveId,
          newTargets: {squat: (value: 42, raw: '3x14')});

      final cloned =
          (await clonedKrs(newId)).firstWhere((k) => k['title'] == 'Squat');
      expect(cloned['target_value'], 42);
      expect(cloned['target_raw'], '3x14');
    });

    test('a plain number clears the notation rather than mislabelling itself',
        () async {
      final (squat, _, _) = await tree();

      final newId = await db
          .renewObjective(objectiveId, newTargets: {squat: (value: 40, raw: null)});

      final cloned =
          (await clonedKrs(newId)).firstWhere((k) => k['title'] == 'Squat');
      expect(cloned['target_value'], 40);
      expect(cloned['target_raw'], isNull,
          reason: '"3x12" beside 40 would be a lie about what the goal is');
    });

    test('untouched key results keep theirs', () async {
      final (squat, _, _) = await tree();

      final newId = await db.renewObjective(objectiveId,
          newTargets: {squat: (value: 42, raw: '3x14')});

      final volume =
          (await clonedKrs(newId)).firstWhere((k) => k['title'] == 'Volume');
      expect(volume['target_value'], 10000);
    });

    test('the baseline still comes from the last entry, not the new target',
        () async {
      final (squat, _, _) = await tree();
      await db.logMeasurement(keyResultId: squat, value: 33, note: '3x11');

      final newId = await db.renewObjective(objectiveId,
          newTargets: {squat: (value: 42, raw: '3x14')});

      final cloned =
          (await clonedKrs(newId)).firstWhere((k) => k['title'] == 'Squat');
      expect(cloned['baseline_value'], 33);
      expect(cloned['baseline_raw'], '3x11',
          reason: 'a raised target does not move where the quarter starts');
    });
  });

  test('dropping and retargeting compose in one pass', () async {
    final (squat, volume, _) = await tree();

    final newId = await db.renewObjective(
      objectiveId,
      dropKeyResults: {volume},
      newTargets: {squat: (value: 42, raw: '3x14')},
    );

    final krs = await clonedKrs(newId);
    expect(krs.map((k) => k['title']), ['Sessions', 'Squat']);
    expect(krs.firstWhere((k) => k['title'] == 'Squat')['target_value'], 42);
  });

  test('an objective that is not there is a no-op, not a half-renewal',
      () async {
    final before = (await (await db.database).query('objectives')).length;

    final returned = await db.renewObjective('no-such-id');

    expect(returned, 'no-such-id');
    expect((await (await db.database).query('objectives')), hasLength(before),
        reason: 'the transaction wrote nothing');
  });
}
