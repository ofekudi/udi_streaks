// The backup dump. Its whole value is being complete, so the test that matters
// is the one comparing the export list against the live schema.

import 'dart:convert';

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

  test('every table in the schema is exported', () async {
    final rows = await (await db.database).rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    final inSchema = {for (final r in rows) r['name'] as String};

    // A table added to the schema without being added to exportedTables would
    // silently drop out of every backup taken from then on.
    expect(inSchema.difference(DBHelper.exportedTables.toSet()), isEmpty,
        reason: 'tables missing from the export');
    expect(DBHelper.exportedTables.toSet().difference(inSchema), isEmpty,
        reason: 'exported tables that no longer exist');
  });

  test('carries the data, and survives jsonEncode', () async {
    final habitId = await db.insertHabit('Me Morning Time');
    await db.toggleHabitCompletion(habitId);
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
    await db.logMeasurement(keyResultId: krId, value: 1);
    await db.saveGrade(
        subjectKind: 'key_result',
        subjectId: krId,
        period: '2026-Q3',
        grade: 7);

    final data = await db.exportAll();
    final tables = data['tables'] as Map<String, dynamic>;

    expect(data['schema_version'], DBHelper.schemaVersion);
    expect((tables['habits'] as List).single['name'], 'Me Morning Time');
    expect((tables['habit_completions'] as List), hasLength(1));
    expect((tables['key_results'] as List).single['title'], 'Morning Routine');
    expect((tables['measurements'] as List), hasLength(1));
    expect((tables['reviews'] as List).single['grade'], 7);

    // Every column is TEXT/REAL/INTEGER, so the dump must encode as-is.
    final round = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    expect(round['tables']['habits'][0]['id'], habitId);
  });

  test('an empty database exports every table as an empty list', () async {
    final tables = (await db.exportAll())['tables'] as Map<String, dynamic>;

    expect(tables.keys, unorderedEquals(DBHelper.exportedTables));
    for (final entry in tables.entries) {
      expect(entry.value, isEmpty, reason: entry.key);
    }
  });
}
