// The Habits tab carries the same "Record" FAB as the OKR tab, and backing out
// of the Record page lands on the OKR tab with the last-logged key result's
// objective expanded — the write through `reveal` must beat `reload`'s
// re-seed of the collapse set, or the landing would show a folded objective.
// Nothing logged means no jump.

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

  Future<String> seedCollapsedKr(DBHelper db) async {
    final now = DateTime.now();
    final areaId = await db.insertArea('Me');
    final objectiveId = await db.insertObjective(
      areaId: areaId,
      title: 'Mornings',
      start: now.subtract(const Duration(days: 60)),
      end: now.add(const Duration(days: 60)),
    );
    await db.insertKeyResult(
      objectiveId: objectiveId,
      title: 'Morning Routine',
      aggregation: 'COUNT',
      target: 20,
    );
    await db.setObjectiveCollapsed(objectiveId, true);
    return objectiveId;
  }

  testWidgets('recording from the Habits tab lands on the OKR tab, expanded',
      (tester) async {
    final db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    await seedCollapsedKr(db);

    await tester.pumpWidget(const MaterialApp(home: RootNav()));
    await tester.pump();

    // The Habits tab is on-stage, so this is its FAB, not the OKR tab's.
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    // Recording is two steps: pick the objective, then log into its key result.
    await tester.tap(find.text('Mornings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('+1'));
    await tester.pump();

    // Out of the fill page, then out of the picker — the second pop is the one
    // the shell is awaiting.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The KR row is only visible when its objective is expanded.
    expect(find.text('Morning Routine'), findsOneWidget);
    expect(find.text('1 / 20'), findsOneWidget);
  });

  testWidgets('closing Record without logging stays on the Habits tab',
      (tester) async {
    final db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    await seedCollapsedKr(db);
    await db.insertHabit('Me Morning Time');

    await tester.pumpWidget(const MaterialApp(home: RootNav()));
    await tester.pump();

    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Me Morning Time'), findsOneWidget);
    expect(find.text('Morning Routine'), findsNothing);
  });

  testWidgets('the inline field adds a streak, emoji un-prefixed by default',
      (tester) async {
    final db = DBHelper();
    await db.openAt(inMemoryDatabasePath);

    await tester.pumpWidget(const MaterialApp(home: RootNav()));
    await tester.pump();

    await tester.tap(find.text('Add streak'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Drink water');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(); // insert + reload queries
    await tester.pump(); // results land

    expect(find.text('Drink water'), findsOneWidget);
  });
}
