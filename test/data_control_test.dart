// The undo paths: removing a habit's completion for a past day, and grades not
// outliving what they graded. Both are SQL, so both run on a real database.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DBHelper db;

  setUp(() async {
    db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
  });

  Future<int> reviewCount() async =>
      (await (await db.database).query('reviews')).length;

  group('deleting a habit completion', () {
    test('removes the day and rebuilds the streak', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final now = DateTime.now();
      for (var back = 0; back <= 2; back++) {
        await db.addRetroactiveCompletion(
            habitId, now.subtract(Duration(days: back)));
      }
      expect((await db.getHabits()).single['current_streak'], 3);

      await db.deleteCompletionOn(
          habitId, now.subtract(const Duration(days: 1)));

      expect(await db.getCompletionHistory(habitId), hasLength(2));
      // The run is folded from the log, so it shrinks with the day. Still 2
      // rather than 1 because `kMaxStreakGapDays` forgives a single missed day.
      expect((await db.getHabits()).single['current_streak'], 2);
    });

    test('takes the count it fed off the key result', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      final areaId = await db.insertArea('Me');
      final objectiveId = await db.insertObjective(
        areaId: areaId,
        title: 'Mornings',
        start: DateTime.now().subtract(const Duration(days: 60)),
        end: DateTime.now().add(const Duration(days: 60)),
      );
      final krId = await db.insertKeyResult(
          objectiveId: objectiveId,
          title: 'Morning Routine',
          aggregation: 'COUNT',
          target: 20);
      await db.linkHabitToKeyResult(habitId, krId);

      final when = DateTime.now().subtract(const Duration(days: 3));
      await db.addRetroactiveCompletion(habitId, when);
      expect((await db.getKeyResultsById(krId))!['current'], 1);

      await db.deleteCompletionOn(habitId, when);

      expect((await db.getKeyResultsById(krId))!['current'], 0);
    });

    test('a day that was never completed is a no-op', () async {
      final habitId = await db.insertHabit('Me Morning Time');
      await db.toggleHabitCompletion(habitId);

      await db.deleteCompletionOn(
          habitId, DateTime.now().subtract(const Duration(days: 40)));

      expect(await db.getCompletionHistory(habitId), hasLength(1));
    });
  });

  group('grades do not outlive their subject', () {
    /// area → objective → key result, with a grade on each level.
    Future<(String, String, String)> gradedTree() async {
      final areaId = await db.insertArea('Me');
      final objectiveId = await db.insertObjective(
          areaId: areaId,
          title: 'Mornings',
          start: DateTime(2026, 7, 1),
          end: DateTime(2026, 9, 30));
      final krId = await db.insertKeyResult(
          objectiveId: objectiveId,
          title: 'Morning Routine',
          aggregation: 'COUNT',
          target: 20);
      for (final (kind, id) in [
        ('area', areaId),
        ('objective', objectiveId),
        ('key_result', krId)
      ]) {
        await db.saveGrade(
            subjectKind: kind, subjectId: id, period: '2026-Q3', grade: 7);
      }
      return (areaId, objectiveId, krId);
    }

    test('deleting a key result takes its grades', () async {
      final (_, _, krId) = await gradedTree();

      await db.deleteKeyResult(krId);

      expect(await db.getGradeHistory(krId), isEmpty);
      expect(await reviewCount(), 2, reason: 'area and objective keep theirs');
    });

    test('deleting an objective takes its key results\' grades too', () async {
      final (_, objectiveId, krId) = await gradedTree();

      await db.deleteObjective(objectiveId);

      expect(await db.getGradeHistory(objectiveId), isEmpty);
      expect(await db.getGradeHistory(krId), isEmpty,
          reason: 'the key result cascaded away, so its grade must go too');
      expect(await reviewCount(), 1);
    });

    test('deleting an area takes the whole subtree\'s grades', () async {
      final (areaId, _, _) = await gradedTree();

      await db.deleteArea(areaId);

      expect(await reviewCount(), 0);
    });

    test('renewing keeps the grade it just recorded', () async {
      final (_, objectiveId, krId) = await gradedTree();

      await db.renewObjective(objectiveId);

      // The point of grading is the record surviving the quarter closing on it.
      expect(await db.getGradeHistory(krId), hasLength(1));
    });
  });
}
