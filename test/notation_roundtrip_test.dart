// "3x12" must survive from the edit form to every row that shows it. The
// notation lives in SQLite columns and is read back through the same merged
// maps the screens use, so this runs against a real database.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';
import 'package:udi_streaks/okr/log_value.dart';
import 'package:udi_streaks/ui/kit.dart';

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

  /// A Value key result written the way `KrEditScreen._save` writes one.
  Future<String> newKr({
    double? target = 36,
    String? targetRaw = '3x12',
    double? baseline = 30,
    String? baselineRaw = '3x10',
    String aggregation = 'LATEST',
  }) async {
    final now = DateTime.now();
    final areaId = await db.insertArea('Training');
    final objectiveId = await db.insertObjective(
      areaId: areaId,
      title: 'Increase muscle mass',
      start: now.subtract(const Duration(days: 20)),
      end: now.add(const Duration(days: 70)),
    );
    return db.insertKeyResult(
      objectiveId: objectiveId,
      title: 'Regular push ups',
      aggregation: aggregation,
      target: target,
      targetRaw: targetRaw,
      baseline: baseline,
      baselineRaw: baselineRaw,
      unit: 'reps',
      windowMode: aggregation == 'LATEST' ? 'ALL' : 'OBJECTIVE',
    );
  }

  /// The row exactly as the OKR tree reads it: through the area rollup.
  Future<Map<String, dynamic>> treeRow() async {
    final areas = await db.getAreasWithRollup();
    final objectives = areas.single['objectives'] as List;
    return (objectives.single['key_results'] as List)
        .cast<Map<String, dynamic>>()
        .single;
  }

  test('the tree shows the notation on both sides, not the parsed numbers',
      () async {
    await newKr();
    final k = await treeRow();
    expect(targetLabel(k), '3x12');
    expect(currentLabel(k),
        '3x10'); // nothing logged: the baseline is where it stands
    expect(k['score'], 0.0);
  });

  test('a logged entry reads as the notation it was logged with', () async {
    final id = await newKr();
    await logKrValue({'id': id, 'unit': 'reps'}, '3x11');
    final k = await treeRow();
    expect(currentLabel(k), '3x11');
    expect(targetLabel(k), '3x12');
    expect(k['current'], 33); // the parsed number is what progress uses
    expect(k['score'], 0.5);
  });

  test('editing keeps the notation, and retyping a plain number drops it',
      () async {
    final id = await newKr();
    await db.updateKeyResult(id, target: 36, targetRaw: '3x12');
    expect(targetLabel(await treeRow()), '3x12');

    await db.updateKeyResult(id, target: 36, targetRaw: null);
    expect(targetLabel(await treeRow()), '36');
  });

  test('a key result saved without notation falls back to the number',
      () async {
    await newKr(targetRaw: null, baseline: null, baselineRaw: null);
    final k = await treeRow();
    expect(targetLabel(k), '36');
    expect(currentLabel(k), '0');
  });

  test('history entries read as the notation they were logged with', () async {
    final id = await newKr();
    await logKrValue({'id': id, 'unit': 'reps'}, '3x11');
    await logKrValue({'id': id, 'unit': 'reps'}, '40');
    final series = await db.getMeasurementSeries(keyResultId: id);
    expect(series.map(entryLabel), ['3x11', '40']);
  });

  test('targetLabel also works on a raw key_results row', () async {
    final id = await newKr();
    final raw = (await db.getKeyResultsById(id))!;
    expect(targetLabel(raw), '3x12');
    // A row read straight from the table has no computed `target` key at all.
    expect(targetLabel({'target_value': 36}), '36');
  });

  group('a key result created before target_raw existed', () {
    /// Exactly what `KrEditScreen._save` issues for an existing key result.
    Future<void> saveForm(String id,
        {required String targetText, required String baselineText}) async {
      final target = parseValue(targetText);
      final baseline = parseValue(baselineText);
      await db.updateKeyResult(
        id,
        title: 'Regular push ups',
        aggregation: 'LATEST',
        target: target,
        targetRaw:
            target != null && targetText != fmtNum(target) ? targetText : null,
        clearTarget: target == null,
        baseline: baseline,
        baselineRaw: baseline != null && baselineText != fmtNum(baseline)
            ? baselineText
            : null,
        clearBaseline: baseline == null,
        unit: 'reps',
        windowMode: 'ALL',
      );
    }

    test('reads as the number until the notation is typed', () async {
      final id =
          await newKr(targetRaw: null, baseline: null, baselineRaw: null);
      expect(targetLabel(await treeRow()), '36');

      // Saving the form as it was prefilled changes nothing: "36" is all it has.
      await saveForm(id, targetText: '36', baselineText: '');
      final untouched = await treeRow();
      expect(targetLabel(untouched), '36');
      expect(currentLabel(untouched), '0');

      // Typing it is what stores it, and then every row reads it.
      await saveForm(id, targetText: '3x12', baselineText: '3x10');
      final fixed = await treeRow();
      expect(targetLabel(fixed), '3x12');
      expect(currentLabel(fixed), '3x10');
      expect(fixed['target'], 36); // still 36 underneath, for the score
      expect(fixed['score'], 0.0);
    });
  });

  test('the Record page reads the same labels as the tree', () async {
    await newKr();
    final k = (await db.getAllKeyResultsWithProgress()).single;
    expect(targetLabel(k), '3x12');
    expect(currentLabel(k), '3x10');
  });
}
