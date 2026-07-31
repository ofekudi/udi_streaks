// Recording is two steps: the Record page lists objectives, and the objective
// you pick fills all of its key results at once. A blank field means "didn't do
// it", and one commit writes the rest. A COUNT is the exception — its tap is
// already the record.
//
// Leaving with text still in a field asks first, because a measurement can
// always be deleted afterwards but typing can't be recovered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';
import 'package:udi_streaks/okr/log_value.dart';
import 'package:udi_streaks/okr/record_screen.dart';
import 'package:udi_streaks/ui/kit.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The DB must run on the test isolate — the widget tester's fake async
    // never delivers another isolate's replies, so loads would hang.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late DBHelper db;
  late String bench;
  late String squat;
  late String deadlift;
  late String books;

  setUp(() async {
    db = DBHelper();
    await db.openAt(inMemoryDatabasePath);
    final now = DateTime.now();

    Future<String> objective(String areaId, String title) => db.insertObjective(
          areaId: areaId,
          title: title,
          start: now.subtract(const Duration(days: 30)),
          end: now.add(const Duration(days: 60)),
        );
    Future<String> kr(String objectiveId, String title, String aggregation,
            double target, String? unit) =>
        db.insertKeyResult(
          objectiveId: objectiveId,
          title: title,
          aggregation: aggregation,
          target: target,
          unit: unit,
        );

    final training = await db.insertArea('Training');
    final muscle = await objective(training, 'Increase muscle mass');
    bench = await kr(muscle, 'Bench press', 'LATEST', 36, 'reps');
    squat = await kr(muscle, 'Squat', 'LATEST', 90, 'kg');
    deadlift = await kr(muscle, 'Deadlift', 'LATEST', 110, 'kg');

    final mind = await db.insertArea('Mind');
    final read = await objective(mind, 'Read more');
    books = await kr(read, 'Read 12 books', 'COUNT', 12, null);

    // Nothing to record in this one — it must not be offered.
    await objective(mind, 'Learn to sail');
  });

  /// A host to push from, so the pages have a back button to test the guard
  /// with, and somewhere to land when they pop.
  Widget host() => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RecordScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      );

  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Step 1 then step 2: the picker, then the objective's fill page.
  Future<void> openObjective(WidgetTester tester, String title) async {
    await openPicker(tester);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  /// The value field belonging to the row that carries [title] — by row rather
  /// than by index, so the test doesn't depend on two key results inserted in
  /// the same millisecond sorting one way.
  Finder fieldOf(String title) => find.descendant(
        of: find
            .ancestor(of: find.text(title), matching: find.byType(Column))
            .first,
        matching: find.byType(LogValueField),
      );

  Future<List<Map<String, dynamic>>> entries(String krId) =>
      db.getMeasurementSeries(keyResultId: krId);

  group('the picker', () {
    testWidgets('lists objectives under their area, with what each holds',
        (tester) async {
      await openPicker(tester);

      expect(find.text('TRAINING'), findsOneWidget);
      expect(find.text('MIND'), findsOneWidget);
      expect(find.text('Increase muscle mass'), findsOneWidget);
      expect(find.text('3 key results'), findsOneWidget);
      expect(find.text('Read more'), findsOneWidget);
      expect(find.text('1 key result'), findsOneWidget);
    });

    testWidgets('an objective with no key results is not offered',
        (tester) async {
      await openPicker(tester);

      expect(find.text('Learn to sail'), findsNothing);
    });

    testWidgets('no key results anywhere states just that', (tester) async {
      await db.openAt(inMemoryDatabasePath); // a fresh, empty database
      await openPicker(tester);

      expect(find.text('No key results yet'), findsOneWidget);
    });
  });

  group('the fill page', () {
    testWidgets('two filled fields write two measurements, the blank one none',
        (tester) async {
      await openObjective(tester, 'Increase muscle mass');

      await tester.enterText(fieldOf('Bench press'), '3x12');
      await tester.enterText(fieldOf('Squat'), '85');
      await tester.pump();

      expect(find.text('Log 2'), findsOneWidget);
      await tester.tap(find.text('Log 2'));
      await tester.pumpAndSettle();

      final benchRows = await entries(bench);
      expect(benchRows, hasLength(1));
      expect(benchRows.single['value'], 36);
      // The notation the user typed survives; "85" adds nothing over its number.
      expect(benchRows.single['note'], '3x12');

      final squatRows = await entries(squat);
      expect(squatRows, hasLength(1));
      expect(squatRows.single['value'], 85);
      expect(squatRows.single['note'], isNull);

      expect(await entries(deadlift), isEmpty);

      // Committed fields empty out, so the bar falls back to nothing pending.
      expect(find.text('Log 2'), findsNothing);
      expect(find.text('Log'), findsOneWidget);
    });

    testWidgets('an unparseable field keeps its text, the good one still writes',
        (tester) async {
      await openObjective(tester, 'Increase muscle mass');

      await tester.enterText(fieldOf('Bench press'), 'heavy');
      await tester.enterText(fieldOf('Squat'), '85');
      await tester.pump();

      await tester.tap(find.text('Log 2'));
      await tester.pumpAndSettle();

      expect(await entries(squat), hasLength(1));
      expect(await entries(bench), isEmpty);
      // The text stays put so it can be fixed rather than retyped.
      expect(find.text('heavy'), findsOneWidget);
      expect(find.text(kLogValueHelp), findsOneWidget);
      expect(find.text('Log 1'), findsOneWidget);
    });

    testWidgets('a COUNT records on the tap, with nothing to commit',
        (tester) async {
      await openObjective(tester, 'Read more');

      await tester.tap(find.byTooltip('+1'));
      await tester.pumpAndSettle();

      final rows = await entries(books);
      expect(rows, hasLength(1));
      expect(rows.single['value'], 1);
      // Every key result here is a COUNT, so there is no commit bar at all.
      expect(find.text('Log'), findsNothing);
    });
  });

  group('the discard guard', () {
    testWidgets('leaving with a filled field asks, and keeping writes nothing',
        (tester) async {
      await openObjective(tester, 'Increase muscle mass');

      await tester.enterText(fieldOf('Squat'), '85');
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Discard 1 unlogged value?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(find.text('85'), findsOneWidget);
      expect(await entries(squat), isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Back on the picker, one step out rather than all the way.
      expect(find.text('Increase muscle mass'), findsOneWidget);
      expect(find.text('3 key results'), findsOneWidget);
      expect(await entries(squat), isEmpty);
    });

    testWidgets('leaving with every field empty pops without asking',
        (tester) async {
      await openObjective(tester, 'Increase muscle mass');

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('3 key results'), findsOneWidget);
    });
  });
}
