// The 6 → 7 migration, which adds `objectives.collapsed`, and the setters the
// accordion persists through.
//
// Opening a fresh database at `version: 6` would not test this: `_onCreate`
// always builds the current schema, so the ALTER TABLE would never run. So the
// v6 schema is declared here and the database is then reopened through
// DBHelper, which is the only way to exercise `_onUpgrade` for real.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udi_streaks/db_helper.dart';

/// Verbatim transcription of the schema as of version 6 (git a021d06), which is
/// what sits on a device that has not yet taken this change. Do not tidy this,
/// and do not add the new column: its absence is the point.
const List<String> v6Schema = [
  '''
  CREATE TABLE habits(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE habit_completions(
    id TEXT PRIMARY KEY,
    habit_id TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE habit_skips(
    id TEXT PRIMARY KEY,
    habit_id TEXT NOT NULL,
    skipped_at TEXT NOT NULL,
    FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE areas(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    icon TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE objectives(
    id TEXT PRIMARY KEY,
    area_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(area_id) REFERENCES areas(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE trackables(
    id TEXT PRIMARY KEY,
    area_id TEXT,
    name TEXT NOT NULL,
    kind TEXT,
    unit TEXT,
    default_aggregation TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY(area_id) REFERENCES areas(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE key_results(
    id TEXT PRIMARY KEY,
    objective_id TEXT,
    trackable_id TEXT,
    title TEXT NOT NULL,
    aggregation TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'MEASUREMENT',
    target_value REAL,
    target_raw TEXT,
    baseline_value REAL,
    baseline_raw TEXT,
    direction TEXT NOT NULL DEFAULT 'UP',
    unit TEXT,
    window_mode TEXT NOT NULL DEFAULT 'OBJECTIVE',
    window_days INTEGER,
    cadence_days INTEGER,
    category TEXT,
    habit_id TEXT,
    weight REAL NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY(objective_id) REFERENCES objectives(id) ON DELETE CASCADE,
    FOREIGN KEY(trackable_id) REFERENCES trackables(id) ON DELETE SET NULL,
    FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE executions(
    id TEXT PRIMARY KEY,
    area_id TEXT,
    trackable_id TEXT,
    type_label TEXT,
    performed_at TEXT NOT NULL,
    duration_min INTEGER,
    feel INTEGER,
    note TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY(area_id) REFERENCES areas(id) ON DELETE SET NULL,
    FOREIGN KEY(trackable_id) REFERENCES trackables(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE measurements(
    id TEXT PRIMARY KEY,
    execution_id TEXT,
    key_result_id TEXT,
    trackable_id TEXT,
    value REAL NOT NULL DEFAULT 1,
    unit TEXT,
    category TEXT,
    note TEXT,
    recorded_at TEXT NOT NULL,
    habit_completion_id TEXT REFERENCES habit_completions(id)
      ON DELETE CASCADE,
    FOREIGN KEY(execution_id) REFERENCES executions(id) ON DELETE CASCADE,
    FOREIGN KEY(key_result_id) REFERENCES key_results(id) ON DELETE CASCADE,
    FOREIGN KEY(trackable_id) REFERENCES trackables(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE reviews(
    id TEXT PRIMARY KEY,
    subject_kind TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    period TEXT NOT NULL,
    grade INTEGER,
    note TEXT,
    graded_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_meas_kr ON measurements(key_result_id, recorded_at)',
  'CREATE INDEX idx_meas_trk ON measurements(trackable_id, recorded_at)',
  'CREATE INDEX idx_exec_area ON executions(area_id, performed_at)',
  'CREATE INDEX idx_rev_subj ON reviews(subject_kind, subject_id, period)',
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String path;

  /// A version-6 database on disk with one area and two objectives — the state
  /// a real install upgrades from. It has to be a file, not in-memory, so it
  /// survives being closed and reopened.
  setUp(() async {
    path = join(await databaseFactory.getDatabasesPath(),
        'collapse_migration_test_${DateTime.now().microsecondsSinceEpoch}.db');
    await databaseFactory.deleteDatabase(path);

    final db = await databaseFactory.openDatabase(path);
    for (final statement in v6Schema) {
      await db.execute(statement);
    }
    await db.setVersion(6);

    final now = DateTime.now().toIso8601String();
    await db.insert('areas', {'id': 'a1', 'name': 'Me', 'created_at': now});
    for (final id in ['o1', 'o2']) {
      await db.insert('objectives', {
        'id': id,
        'area_id': 'a1',
        'title': 'Objective $id',
        'start_date': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
        'end_date':
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.close();
  });

  tearDown(() => databaseFactory.deleteDatabase(path));

  test('upgrading from 6 adds collapsed, defaulting to expanded', () async {
    final helper = DBHelper();
    final db = await helper.openAt(path);

    expect(await db.getVersion(), DBHelper.schemaVersion);

    final objs = await helper.getObjectivesWithProgress('a1');
    expect([for (final o in objs) o['collapsed']], [0, 0]);
  });

  test('setObjectiveCollapsed round-trips and leaves updated_at alone',
      () async {
    final helper = DBHelper();
    await helper.openAt(path);

    final before =
        (await helper.getObjectivesWithProgress('a1')).first['updated_at'];

    await helper.setObjectiveCollapsed('o1', true);
    var objs = await helper.getObjectivesWithProgress('a1');
    expect({for (final o in objs) o['id']: o['collapsed']},
        {'o1': 1, 'o2': 0});
    expect(objs.first['updated_at'], before);

    await helper.setObjectiveCollapsed('o1', false);
    objs = await helper.getObjectivesWithProgress('a1');
    expect([for (final o in objs) o['collapsed']], [0, 0]);
  });

  test('setObjectivesCollapsed folds and unfolds the lot', () async {
    final helper = DBHelper();
    await helper.openAt(path);

    await helper.setObjectivesCollapsed(['o1', 'o2'], true);
    var objs = await helper.getObjectivesWithProgress('a1');
    expect([for (final o in objs) o['collapsed']], [1, 1]);

    await helper.setObjectivesCollapsed(['o2'], false);
    objs = await helper.getObjectivesWithProgress('a1');
    expect({for (final o in objs) o['id']: o['collapsed']},
        {'o1': 1, 'o2': 0});
  });
}
