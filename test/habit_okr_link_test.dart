// The habit → COUNT key result link. These flows are FK cascades and SQL, not
// pure rules, so they run against a real SQLite database rather than being
// restated as a pure function that would only test itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DBHelper db;

  /// A fresh database per test, so one test's links can't leak into the next.
  setUp(() async {
    db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
  });

  /// An active objective with one key result on it. The window is wide enough
  /// that a backdated completion still falls inside it.
  Future<String> newKr({
    String title = 'Morning Routine',
    double target = 20,
    String aggregation = 'COUNT',
    String status = 'active',
  }) async {
    final now = DateTime.now();
    final areaId = await db.insertArea('Me');
    final objectiveId = await db.insertObjective(
      areaId: areaId,
      title: 'Mornings',
      start: now.subtract(const Duration(days: 60)),
      end: now.add(const Duration(days: 60)),
    );
    if (status != 'active') {
      await db.updateObjectiveStatus(objectiveId, status);
    }
    return db.insertKeyResult(
      objectiveId: objectiveId,
      title: title,
      aggregation: aggregation,
      target: target,
    );
  }

  /// The key result's folded `current` — what the OKR tree renders.
  Future<double?> current(String krId) async =>
      (await db.getKeyResultsById(krId))!['current'] as double?;

  Future<List<Map<String, Object?>>> measurements(String krId) async =>
      (await db.database)
          .query('measurements', where: 'key_result_id = ?', whereArgs: [krId]);

  group('completing a linked habit', () {
    test('counts toward the key result', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);

      expect(await current(krId), 0, reason: 'linking is not retroactive');

      await db.toggleHabitCompletion(habitId);

      expect(await current(krId), 1);
    });

    test('un-completing takes the count back off', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);

      await db.toggleHabitCompletion(habitId);
      expect(await current(krId), 1);

      // Deleting the completion cascades to the measurement it produced.
      await db.toggleHabitCompletion(habitId);

      expect(await current(krId), 0);
      expect(await measurements(krId), isEmpty);
    });

    test('an unlinked habit logs nothing', () async {
      final habitId = await db.insertHabit('Unrelated');
      final krId = await newKr();

      await db.toggleHabitCompletion(habitId);

      expect(await current(krId), 0);
      expect(await measurements(krId), isEmpty);
    });

    test('a non-COUNT key result is not fed', () async {
      final habitId = await db.insertHabit('Weigh in');
      final krId = await newKr(aggregation: 'LATEST', target: 75);
      await db.linkHabitToKeyResult(habitId, krId);

      await db.toggleHabitCompletion(habitId);

      // A completion says "I did it", which is not a new weight reading.
      expect(await measurements(krId), isEmpty);
    });

    test('a retroactive completion counts on the day it happened', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);

      final when = DateTime.now().subtract(const Duration(days: 5));
      await db.addRetroactiveCompletion(habitId, when);

      expect(await current(krId), 1);
      final at = DateTime.parse(
          (await measurements(krId)).single['recorded_at']! as String);
      expect((at.year, at.month, at.day), (when.year, when.month, when.day));
    });

    test('every completion counts, so the count tracks the streak', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);

      final now = DateTime.now();
      for (var back = 1; back <= 3; back++) {
        await db.addRetroactiveCompletion(
            habitId, now.subtract(Duration(days: back)));
      }
      await db.toggleHabitCompletion(habitId);

      expect(await current(krId), 4);
    });
  });

  group('the link itself', () {
    test('a second link replaces the first', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final first = await newKr(title: 'Morning Routine');
      final second = await newKr(title: 'Evening Routine');

      await db.linkHabitToKeyResult(habitId, first);
      await db.linkHabitToKeyResult(habitId, second);
      await db.toggleHabitCompletion(habitId);

      expect(await current(first), 0);
      expect(await current(second), 1);
    });

    test('unlinking keeps the counts already logged', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);
      await db.toggleHabitCompletion(habitId);

      await db.unlinkHabit(habitId);

      expect(await current(krId), 1, reason: 'that day did happen');
      expect((await db.getHabits()).single['linked_kr_id'], isNull);
    });

    test('a habit completed after unlinking stops counting', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);
      await db.unlinkHabit(habitId);

      await db.toggleHabitCompletion(habitId);

      expect(await current(krId), 0);
    });

    test('renewing the objective moves the link to the new quarter', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final oldKr = await newKr(title: 'Morning Routine');
      await db.linkHabitToKeyResult(habitId, oldKr);
      await db.toggleHabitCompletion(habitId);

      final objectiveId =
          (await db.getKeyResultsById(oldKr))!['objective_id'] as String;
      await db.renewObjective(objectiveId);

      // Exactly one key result may claim the habit, otherwise which one a
      // completion feeds comes down to row order.
      final newKrId = (await db.getHabits()).single['linked_kr_id'] as String?;
      expect(newKrId, isNotNull);
      expect(newKrId, isNot(oldKr));
      expect((await db.getKeyResultsById(oldKr))!['habit_id'], isNull);
      expect(await current(oldKr), 1, reason: 'last quarter keeps its count');
    });

    test('getHabits carries the linked key result', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr(title: 'Morning Routine');
      await db.linkHabitToKeyResult(habitId, krId);

      final habit = (await db.getHabits()).single;

      expect(habit['linked_kr_id'], krId);
      expect(habit['linked_kr_title'], 'Morning Routine');
    });

    test('the picker offers active COUNT key results only', () async {
      final krId = await newKr(title: 'Morning Routine');
      await newKr(title: 'Body Weight', aggregation: 'LATEST');
      await newKr(title: 'Old count', status: 'archived');

      final offered = await db.getLinkableKeyResults();

      expect([for (final k in offered) k['id']], [krId]);
    });

    test('the picker names the habit already holding a link', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);

      final offered = await db.getLinkableKeyResults();

      expect(offered.single['linked_habit_name'], 'Me Morning Time');
      expect(offered.single['habit_id'], habitId);
    });
  });

  group('deletion', () {
    test('deleting the habit removes its counts and the link', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);
      await db.toggleHabitCompletion(habitId);
      expect(await current(krId), 1);

      await db.deleteHabit(habitId);

      expect(await current(krId), 0);
      final kr = await db.getKeyResultsById(krId);
      expect(kr, isNotNull, reason: 'the key result outlives the habit');
      expect(kr!['habit_id'], isNull);
    });

    test('deleting the key result leaves the habit and its streak', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final krId = await newKr();
      await db.linkHabitToKeyResult(habitId, krId);
      await db.toggleHabitCompletion(habitId);

      await db.deleteKeyResult(krId);

      final habit = (await db.getHabits()).single;
      expect(habit['completed_today'], isTrue);
      expect(habit['current_streak'], 1);
      expect(habit['linked_kr_id'], isNull);
    });
  });
}
