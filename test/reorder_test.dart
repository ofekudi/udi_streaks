// Reordering writes sort_order, and the list queries read it back. The order
// survives a round trip through SQL, so this runs against a real database.

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

  Future<String> newObjective(String areaId, String title) {
    final now = DateTime.now();
    return db.insertObjective(
      areaId: areaId,
      title: title,
      start: now.subtract(const Duration(days: 30)),
      end: now.add(const Duration(days: 60)),
    );
  }

  group('areas', () {
    test('reorder is what getAreas returns', () async {
      final a = await db.insertArea('A');
      final b = await db.insertArea('B');
      final c = await db.insertArea('C');

      await db.reorderAreas([c, a, b]);

      final names = [for (final r in await db.getAreas()) r['name']];
      expect(names, ['C', 'A', 'B']);
    });

    test('an insert after a reorder lands last, not mid-list', () async {
      final a = await db.insertArea('A');
      final b = await db.insertArea('B');
      await db.reorderAreas([b, a]);

      await db.insertArea('New');

      final names = [for (final r in await db.getAreas()) r['name']];
      expect(names, ['B', 'A', 'New']);
    });
  });

  group('objectives', () {
    test('reorder within an area, without touching another area', () async {
      final area = await db.insertArea('Me');
      final other = await db.insertArea('Work');
      final x = await newObjective(area, 'X');
      final y = await newObjective(area, 'Y');
      await newObjective(other, 'Elsewhere');

      await db.reorderObjectives([y, x]);

      final titles = [
        for (final o in await db.getObjectivesWithProgress(area)) o['title']
      ];
      expect(titles, ['Y', 'X']);
      final elsewhere = await db.getObjectivesWithProgress(other);
      expect(elsewhere.single['title'], 'Elsewhere');
    });

    test('an insert after a reorder lands last in its own area', () async {
      final area = await db.insertArea('Me');
      final x = await newObjective(area, 'X');
      final y = await newObjective(area, 'Y');
      await db.reorderObjectives([y, x]);

      await newObjective(area, 'New');

      final titles = [
        for (final o in await db.getObjectivesWithProgress(area)) o['title']
      ];
      expect(titles, ['Y', 'X', 'New']);
    });
  });

  group('key results', () {
    test('reorder within an objective', () async {
      final area = await db.insertArea('Me');
      final objective = await newObjective(area, 'Mornings');
      Future<String> kr(String title) => db.insertKeyResult(
          objectiveId: objective, title: title, aggregation: 'COUNT');
      final p = await kr('P');
      final q = await kr('Q');
      final r = await kr('R');

      await db.reorderKeyResults([r, p, q]);

      final titles = [
        for (final k in await db.getKeyResultsWithProgress(objective))
          k['title']
      ];
      expect(titles, ['R', 'P', 'Q']);
    });
  });
}
