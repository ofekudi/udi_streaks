// Closing a period end to end: score every objective, decide what carries, and
// close. The contract this pins is that **every tap writes** — no draft, no
// buffered decisions — because that is what makes quitting half-way and coming
// back work with nothing stored to remember where you were.
//
// The adjust-targets panel is the one exception, and the one thing that asks
// before it is thrown away.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';
import 'package:udi_streaks/okr/close_period.dart';
import 'package:udi_streaks/okr/log_value.dart';
import 'package:udi_streaks/okr/period.dart';
import 'package:udi_streaks/okr/period_report.dart';
import 'package:udi_streaks/ui/kit.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The DB must run on the test isolate — the widget tester's fake async
    // never delivers another isolate's replies, so loads would hang.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late DBHelper db;
  late Period period;
  late String areaId;
  late String stronger;
  late String squat;

  late String reading;

  setUp(() async {
    db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    period = Period.current();
    areaId = await db.insertArea('Training', icon: '🏋️');
    stronger = await db.insertObjective(
        areaId: areaId,
        title: 'Get stronger',
        start: period.start,
        end: period.end);
    squat = await db.insertKeyResult(
        objectiveId: stronger,
        title: 'Squat',
        aggregation: 'LATEST',
        target: 36,
        targetRaw: '3x12',
        baseline: 30,
        baselineRaw: '3x10');
    await db.insertKeyResult(
        objectiveId: stronger,
        title: 'Sessions',
        aggregation: 'COUNT',
        target: 24);
    reading = await db.insertObjective(
        areaId: areaId,
        title: 'Read more',
        start: period.start,
        end: period.end);
    await db.insertKeyResult(
        objectiveId: reading, title: 'Books', aggregation: 'COUNT', target: 6);
  });

  /// The flow under a pushed route, so back has somewhere to land.
  Widget host({bool scoreOnly = false}) => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ClosePeriodScreen(
                          period: period, scoreOnly: scoreOnly))),
              child: const Text('open'),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester, {bool scoreOnly = false}) async {
    await tester.pumpWidget(host(scoreOnly: scoreOnly));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Grades the row whose title is [title] by tapping [grade]/10 along its bar.
  Future<void> gradeRow(
      WidgetTester tester, String title, int grade) async {
    final input = find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Column)).first,
      matching: find.byType(GradeInput),
    );
    final box = tester.getRect(input.first);
    // Land in the middle of the nth segment, over the bar rather than the
    // number that sits after it.
    final barWidth = box.width - 32;
    await tester.tapAt(
        Offset(box.left + barWidth * (grade - 0.5) / 10, box.center.dy));
    await tester.pumpAndSettle();
  }

  Future<int?> gradeOf(String kind, String id) =>
      db.getGrade(kind, id, period.id);

  Future<List<Map<String, dynamic>>> objectivesIn(Period p) async =>
      (await db.database).query('objectives',
          where: 'start_date >= ? AND start_date <= ?',
          whereArgs: [p.start.toIso8601String(), p.end.toIso8601String()]);

  group('the score step', () {
    testWidgets('opens on the first objective, under its area', (tester) async {
      await open(tester);

      expect(find.text('Score ${period.label}'), findsOneWidget);
      expect(find.text('TRAINING'), findsOneWidget);
      expect(find.text('Get stronger'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      // One objective at a time, so the next one is not on screen.
      expect(find.text('Read more'), findsNothing);
    });

    testWidgets('a key result states where it landed and what it scored',
        (tester) async {
      await db.logMeasurement(keyResultId: squat, value: 33, note: '3x11');
      await open(tester);

      // Notation on both sides, and the raw 0..1 the grade is given against.
      expect(find.text('3x11 / 3x12'), findsOneWidget);
      expect(find.text('0.50'), findsOneWidget);
    });

    testWidgets('grading a key result writes it on the tap', (tester) async {
      await open(tester);

      await gradeRow(tester, 'Squat', 7);

      expect(await gradeOf('key_result', squat), 7);
    });

    testWidgets('the objective takes a grade of its own', (tester) async {
      await open(tester);

      await gradeRow(tester, 'This objective', 8);

      expect(await gradeOf('objective', stronger), 8);
    });

    testWidgets('Next walks to the second objective, then hands over',
        (tester) async {
      await open(tester);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Read more'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);

      await tester.tap(find.text('Done scoring'));
      await tester.pumpAndSettle();
      expect(find.text('Carry into ${period.next.label}'), findsWidgets);
    });

    testWidgets('a grade already given comes back filled in', (tester) async {
      await db.saveGrade(
          subjectKind: 'key_result',
          subjectId: squat,
          period: period.id,
          grade: 6);

      await open(tester);

      expect(find.text('6'), findsOneWidget);
    });
  });

  group('the carry step', () {
    Future<void> reachCarry(WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done scoring'));
      await tester.pumpAndSettle();
    }

    testWidgets('carrying clones into the next period and archives the original',
        (tester) async {
      await reachCarry(tester);

      await tester.tap(find.widgetWithText(
          FilledButton, 'Carry into ${period.next.label}'));
      await tester.pumpAndSettle();

      expect(await objectivesIn(period.next), hasLength(1));
      final old = await (await db.database)
          .query('objectives', where: 'id = ?', whereArgs: [stronger]);
      expect(old.single['status'], 'archived');
    });

    testWidgets("Don't carry archives without cloning", (tester) async {
      await reachCarry(tester);

      await tester.tap(find.text("Don't carry"));
      await tester.pumpAndSettle();

      expect(await objectivesIn(period.next), isEmpty);
      final old = await (await db.database)
          .query('objectives', where: 'id = ?', whereArgs: [stronger]);
      expect(old.single['status'], 'archived');
    });

    testWidgets('a decided objective drops out and the count moves on',
        (tester) async {
      await reachCarry(tester);
      expect(find.text('1 of 2'), findsOneWidget);

      await tester.tap(find.text("Don't carry"));
      await tester.pumpAndSettle();

      expect(find.text('Read more'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('adjusting carries the new target, in the notation typed',
        (tester) async {
      await reachCarry(tester);

      await tester.tap(find.text('Adjust targets…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '3x14');
      await tester.tap(find.widgetWithText(
          FilledButton, 'Carry into ${period.next.label}'));
      await tester.pumpAndSettle();

      final cloned = (await (await db.database).query('key_results',
              where: 'objective_id = ?',
              whereArgs: [(await objectivesIn(period.next)).single['id']]))
          .firstWhere((k) => k['title'] == 'Squat');
      expect(cloned['target_value'], 42);
      expect(cloned['target_raw'], '3x14');
    });

    testWidgets('a field cleared to blank leaves that key result behind',
        (tester) async {
      await reachCarry(tester);

      await tester.tap(find.text('Adjust targets…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.widgetWithText(
          FilledButton, 'Carry into ${period.next.label}'));
      await tester.pumpAndSettle();

      final cloned = await (await db.database).query('key_results',
          where: 'objective_id = ?',
          whereArgs: [(await objectivesIn(period.next)).single['id']]);
      expect(cloned.map((k) => k['title']), ['Sessions']);
    });

    testWidgets('clearing every field says so instead of cloning a shell',
        (tester) async {
      await reachCarry(tester);

      await tester.tap(find.text('Adjust targets…'));
      await tester.pumpAndSettle();
      for (final f in find.byType(TextField).evaluate()) {
        await tester.enterText(find.byWidget(f.widget), '');
      }
      await tester.tap(find.widgetWithText(
          FilledButton, 'Carry into ${period.next.label}'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing left to carry'), findsOneWidget);
      expect(await objectivesIn(period.next), isEmpty);
    });

    testWidgets('an unparseable target is refused and nothing is written',
        (tester) async {
      await reachCarry(tester);

      await tester.tap(find.text('Adjust targets…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'heavier');
      await tester.tap(find.widgetWithText(
          FilledButton, 'Carry into ${period.next.label}'));
      await tester.pumpAndSettle();

      expect(find.text(kLogValueHelp), findsOneWidget);
      expect(await objectivesIn(period.next), isEmpty);
    });
  });

  group('the discard guard', () {
    Future<void> reachAdjust(WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done scoring'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adjust targets…'));
      await tester.pumpAndSettle();
    }

    testWidgets('leaving with a changed target asks first', (tester) async {
      await reachAdjust(tester);
      await tester.enterText(find.byType(TextField).first, '3x14');
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Discard the targets you typed?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('3x14'), findsOneWidget);
    });

    testWidgets('opening the panel and changing nothing does not ask',
        (tester) async {
      await reachAdjust(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back out of carry lands on the score step, not a dialog.
      expect(find.text('Discard the targets you typed?'), findsNothing);
      expect(find.text('Score ${period.label}'), findsOneWidget);
    });

    testWidgets('the score step never asks — every grade is already written',
        (tester) async {
      await open(tester);
      await gradeRow(tester, 'Squat', 7);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(await gradeOf('key_result', squat), 7);
    });
  });

  group('closing, and picking it up again', () {
    testWidgets('the summary states the period, then closes it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done scoring'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FilledButton, 'Carry into ${period.next.label}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't carry"));
      await tester.pumpAndSettle();

      expect(find.text('Carried'), findsOneWidget);
      expect(find.text('1 objective'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(
          FilledButton, 'Close ${period.label}'));
      await tester.pumpAndSettle();

      expect((await db.closedPeriods()).map((p) => p.id), [period.id]);
    });

    testWidgets(
        'reopening after a half-finished close skips what was already decided',
        (tester) async {
      // One objective carried, then the flow abandoned.
      await db.renewObjective(stronger);

      await open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done scoring'));
      await tester.pumpAndSettle();

      // Scoring still covers both — a grade stays editable — but carrying only
      // ever offers what is still active.
      expect(find.text('Read more'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
    });

    testWidgets('scoreOnly re-enters the grades and never offers to carry',
        (tester) async {
      await open(tester, scoreOnly: true);

      await gradeRow(tester, 'Squat', 9);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done scoring'));
      await tester.pumpAndSettle();

      expect(await gradeOf('key_result', squat), 9);
      expect(find.text('open'), findsOneWidget,
          reason: 'it popped rather than moving on to carry');
      expect(await objectivesIn(period.next), isEmpty);
    });
  });

  group('the way back', () {
    /// `PastPeriodsScreen` pushed on its own, as the overflow menu does it.
    Widget pastHost() => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PastPeriodsScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('a closed period is listed, and opens as the tree it was',
        (tester) async {
      await db.saveGrade(
          subjectKind: 'key_result',
          subjectId: squat,
          period: period.id,
          grade: 7);
      await db.closePeriod(period);

      await tester.pumpWidget(pastHost());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(period.label), findsOneWidget);

      await tester.tap(find.text(period.label));
      await tester.pumpAndSettle();

      // The same outline as the tab: area heading, objectives, key results.
      expect(find.text('TRAINING'), findsOneWidget);
      expect(find.text('Get stronger'), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
      expect(find.byType(GradeBar), findsWidgets);
    });

    testWidgets('with nothing closed it says so', (tester) async {
      await tester.pumpWidget(pastHost());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('No closed periods yet'), findsOneWidget);
    });

    testWidgets('"Score again" re-enters the grades and does not carry',
        (tester) async {
      await db.closePeriod(period);

      await tester.pumpWidget(pastHost());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(period.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Score again'));
      await tester.pumpAndSettle();

      expect(find.text('Score ${period.label}'), findsOneWidget);
      await gradeRow(tester, 'Squat', 5);
      expect(await gradeOf('key_result', squat), 5);
      expect(await objectivesIn(period.next), isEmpty);
    });
  });

  group('GradeInput', () {
    testWidgets('the bar is a full-width tap target', (tester) async {
      await open(tester);

      final box = tester.getRect(find.byType(GradeInput).first);
      expect(box.height, greaterThanOrEqualTo(kTapTarget));
    });

    testWidgets('where you tap is the grade you get', (tester) async {
      await open(tester);

      await gradeRow(tester, 'Squat', 1);
      expect(await gradeOf('key_result', squat), 1);

      await gradeRow(tester, 'Squat', 10);
      expect(await gradeOf('key_result', squat), 10);

      await gradeRow(tester, 'Squat', 4);
      expect(await gradeOf('key_result', squat), 4);
    });

    testWidgets('an ungraded row reads as a dash, not a zero', (tester) async {
      await open(tester);

      expect(find.text('–'), findsWidgets);
      expect(find.text('0'), findsNothing);
    });
  });
}
