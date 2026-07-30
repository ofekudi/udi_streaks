// Hierarchy in the OKR tree comes from the objective card, never from a
// horizontal offset. A leading chevron once pushed an objective's own title in
// to 32 while its key results stayed at 4, so a child rendered *left* of its
// parent. This pins the fix: every title in the tree shares one left edge.

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

  testWidgets('an area, its objective and its key result share a left edge',
      (tester) async {
    final db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    final now = DateTime.now();
    final areaId = await db.insertArea('Health');
    final objectiveId = await db.insertObjective(
      areaId: areaId,
      title: 'Get stronger',
      start: now.subtract(const Duration(days: 60)),
      end: now.add(const Duration(days: 60)),
    );
    await db.insertKeyResult(
      objectiveId: objectiveId,
      title: 'Bench press',
      aggregation: 'LATEST',
      target: 100,
    );

    await tester.pumpWidget(const MaterialApp(home: RootNav()));
    await tester.tap(find.text('OKR'));
    await tester.pump(); // reload queries
    await tester.pump(); // results land

    final objective = tester.getTopLeft(find.text('Get stronger')).dx;
    final keyResult = tester.getTopLeft(find.text('Bench press')).dx;

    // The bug, as an assertion: a key result must not sit left of its objective.
    expect(keyResult, objective);

    // The area heading starts on that edge too — its label follows the area's
    // emoji, so the emoji is what stands in the column.
    expect(tester.getTopLeft(find.text('🎯')).dx, objective);
  });
}
