// The IndexedStack keeps every tab's State alive, so a write made on one tab
// only reaches its siblings because RootNav reloads a tab on entry. This pins
// that mechanism: tick a habit, enter the OKR tab, see the count.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';
import 'package:udi_streaks/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The DB must run on the test isolate — the widget tester's fake async
    // never delivers another isolate's replies, so loads would hang.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  testWidgets('a habit ticked elsewhere shows on the OKR tab on entry',
      (tester) async {
    final db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    final now = DateTime.now();
    final habitId = await db.insertHabit('Me Morning Time');
    final areaId = await db.insertArea('Me');
    final objectiveId = await db.insertObjective(
      areaId: areaId,
      title: 'Mornings',
      start: now.subtract(const Duration(days: 60)),
      end: now.add(const Duration(days: 60)),
    );
    final krId = await db.insertKeyResult(
      objectiveId: objectiveId,
      title: 'Morning Routine',
      aggregation: 'COUNT',
      target: 20,
    );
    await db.linkHabitToKeyResult(habitId, krId);

    await tester.pumpWidget(const MaterialApp(home: RootNav()));
    await tester.pump();

    // Written straight through DBHelper: the tab being entered must not care
    // which surface made the write.
    await db.toggleHabitCompletion(habitId);

    await tester.tap(find.text('OKR'));
    await tester.pump(); // reload queries
    await tester.pump(); // results land

    expect(find.text('1 / 20'), findsOneWidget);
  });
}
