import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'okr/period.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;
  static const uuid = Uuid();

  factory DBHelper() => _instance;

  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'habits_database.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // Cascade / SET NULL behaviour below relies on FK enforcement,
        // which sqflite leaves off by default.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE habits(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE habit_completions(
        id TEXT PRIMARY KEY,
        habit_id TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE habit_skips(
        id TEXT PRIMARY KEY,
        habit_id TEXT NOT NULL,
        skipped_at TEXT NOT NULL,
        FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE CASCADE
      )
    ''');

    await _createOkrTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle upgrades from version 1 to version 2
    if (oldVersion == 1) {
      await db.execute('''
        CREATE TABLE habit_skips(
          id TEXT PRIMARY KEY,
          habit_id TEXT NOT NULL,
          skipped_at TEXT NOT NULL,
          FOREIGN KEY(habit_id) REFERENCES habits(id) ON DELETE CASCADE
        )
      ''');
    }

    // Version 3: the OKR / life-tracker layer.
    if (oldVersion < 3) {
      await _createOkrTables(db);
    }
  }

  /// Creates the OKR layer: areas -> objectives -> key_results (intent),
  /// executions -> measurements (doing), trackables (catalog), reviews (grades).
  /// Nothing computed is stored; scores/streaks are folded from the log on read.
  Future<void> _createOkrTables(Database db) async {
    await db.execute('''
      CREATE TABLE areas(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
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
    ''');

    await db.execute('''
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
    ''');

    await db.execute('''
      CREATE TABLE key_results(
        id TEXT PRIMARY KEY,
        objective_id TEXT,
        trackable_id TEXT,
        title TEXT NOT NULL,
        aggregation TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'MEASUREMENT',
        target_value REAL,
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
    ''');

    await db.execute('''
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
    ''');

    await db.execute('''
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
        FOREIGN KEY(execution_id) REFERENCES executions(id) ON DELETE CASCADE,
        FOREIGN KEY(key_result_id) REFERENCES key_results(id) ON DELETE CASCADE,
        FOREIGN KEY(trackable_id) REFERENCES trackables(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE reviews(
        id TEXT PRIMARY KEY,
        subject_kind TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        period TEXT NOT NULL,
        grade INTEGER,
        note TEXT,
        graded_at TEXT NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_meas_kr ON measurements(key_result_id, recorded_at)');
    await db.execute(
        'CREATE INDEX idx_meas_trk ON measurements(trackable_id, recorded_at)');
    await db.execute(
        'CREATE INDEX idx_exec_area ON executions(area_id, performed_at)');
    await db.execute(
        'CREATE INDEX idx_rev_subj ON reviews(subject_kind, subject_id, period)');
  }

  Future<String> insertHabit(String name) async {
    final Database db = await database;
    final String id = uuid.v4();

    await db.insert(
      'habits',
      {
        'id': id,
        'name': name,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );

    return id;
  }

  Future<List<Map<String, dynamic>>> getHabits() async {
    final Database db = await database;
    final List<Map<String, dynamic>> habits =
        await db.query('habits', orderBy: 'created_at DESC');

    // Get today's date at midnight for comparison
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    // Create a new list with mutable maps
    final List<Map<String, dynamic>> mutableHabits = [];

    // For each habit, check if it was completed today and get streaks
    for (var habit in habits) {
      // Check if habit is skipped today
      final skip = await db.query(
        'habit_skips',
        where: 'habit_id = ? AND skipped_at >= ?',
        whereArgs: [habit['id'], today.toIso8601String()],
        limit: 1,
      );

      final completion = await db.query(
        'habit_completions',
        where: 'habit_id = ? AND completed_at >= ?',
        whereArgs: [habit['id'], today.toIso8601String()],
        limit: 1,
      );

      final streaks = await getHabitStreaks(habit['id']);

      // Create a new map with all the original data plus the status
      mutableHabits.add({
        ...habit,
        'completed_today': completion.isNotEmpty,
        'skipped_today': skip.isNotEmpty,
        'current_streak': streaks['current_streak'],
        'longest_streak': streaks['longest_streak'],
        'streak_at_risk': streaks['streak_at_risk'],
        'streak_start_date': streaks['streak_start_date'],
        'negative_streak': streaks['negative_streak'],
      });
    }

    // Sort habits: non-skipped habits first (by current streak descending), then skipped habits
    mutableHabits.sort((a, b) {
      // If one is skipped and the other isn't, prioritize the non-skipped one
      if (a['skipped_today'] && !b['skipped_today']) return 1;
      if (!a['skipped_today'] && b['skipped_today']) return -1;
      
      // If both have the same skip status, sort by current streak (descending)
      return (b['current_streak'] as int).compareTo(a['current_streak'] as int);
    });

    return mutableHabits;
  }

  Future<void> toggleHabitCompletion(String habitId) async {
    final Database db = await database;
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    // Check if habit was already completed today
    final completion = await db.query(
      'habit_completions',
      where: 'habit_id = ? AND completed_at >= ?',
      whereArgs: [habitId, today.toIso8601String()],
    );

    if (completion.isEmpty) {
      // Mark as complete
      await db.insert(
        'habit_completions',
        {
          'id': uuid.v4(),
          'habit_id': habitId,
          'completed_at': DateTime.now().toIso8601String(),
        },
      );
    } else {
      // Remove completion
      await db.delete(
        'habit_completions',
        where: 'habit_id = ? AND completed_at >= ?',
        whereArgs: [habitId, today.toIso8601String()],
      );
    }
  }

  Future<void> deleteHabit(String id) async {
    final Database db = await database;
    await db.delete(
      'habits',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> getHabitStreaks(String habitId) async {
    final Database db = await database;
    final completions = await db.query(
      'habit_completions',
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'completed_at DESC',
    );

    if (completions.isEmpty) {
      return {
        'current_streak': 0,
        'longest_streak': 0,
        'streak_at_risk': false,
        'streak_start_date': null,
        'negative_streak': 0
      };
    }

    int currentStreak = 0;
    int longestStreak = 0;
    int currentCount = 0;
    DateTime? lastDate;
    bool streakAtRisk = false;
    DateTime? streakStartDate;
    int negativeStreak = 0;

    // Get today's date at midnight for comparison
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    // Check if the most recent completion is from today or earlier
    final mostRecentCompletion =
        DateTime.parse(completions.first['completed_at'] as String);
    final mostRecentCompletionDate = DateTime(mostRecentCompletion.year,
        mostRecentCompletion.month, mostRecentCompletion.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    final daysSinceLastCompletion =
        todayDate.difference(mostRecentCompletionDate).inDays;

    // Calculate negative streak if more than 3 days have passed
    if (daysSinceLastCompletion >= 3) {
      currentStreak = 0;
      streakAtRisk = false;
      streakStartDate = null;
      // Calculate negative streak (days beyond 3)
      negativeStreak = -(daysSinceLastCompletion - 3);
    } else {
      negativeStreak = 0; // Explicitly set to 0 when not in negative streak
      // Calculate current streak allowing one day gap
      DateTime? lastDate;

      for (var completion in completions) {
        final completedAt =
            DateTime.parse(completion['completed_at'] as String);
        final dateOnly =
            DateTime(completedAt.year, completedAt.month, completedAt.day);

        if (lastDate == null) {
          currentCount = 1;
          lastDate = dateOnly;
          streakStartDate = dateOnly;
        } else {
          final difference = lastDate.difference(dateOnly).inDays;
          if (difference <= 2) {
            // Count the day but don't increment for the gap
            currentCount++;
            streakStartDate = dateOnly;
          } else {
            // More than one day gap, break the streak
            break;
          }
          lastDate = dateOnly;
        }
      }

      currentStreak = currentCount;
      streakAtRisk = daysSinceLastCompletion == 2;
    }

    // Calculate longest streak
    DateTime? lastDateForLongest;
    int countForLongest = 0;

    for (var completion in completions) {
      final completedAt = DateTime.parse(completion['completed_at'] as String);
      final dateOnly =
          DateTime(completedAt.year, completedAt.month, completedAt.day);

      if (lastDateForLongest == null) {
        countForLongest = 1;
        lastDateForLongest = dateOnly;
      } else {
        final difference = lastDateForLongest.difference(dateOnly).inDays;
        if (difference <= 2) {
          // Count the day but don't increment for the gap
          countForLongest++;
        } else {
          // More than one day gap, break the streak
          if (countForLongest > longestStreak) {
            longestStreak = countForLongest;
          }
          countForLongest = 1;
        }
        lastDateForLongest = dateOnly;
      }
    }

    if (countForLongest > longestStreak) {
      longestStreak = countForLongest;
    }

    return {
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'streak_at_risk': streakAtRisk,
      'streak_start_date': streakStartDate,
      'negative_streak': negativeStreak
    };
  }

  Future<List<Map<String, dynamic>>> getCompletionHistory(
      String habitId) async {
    final Database db = await database;
    final completions = await db.query(
      'habit_completions',
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'completed_at DESC',
    );

    // Group completions by date
    final Map<String, int> dateCountMap = {};
    for (var completion in completions) {
      final completedAt = DateTime.parse(completion['completed_at'] as String);
      final dateStr =
          DateTime(completedAt.year, completedAt.month, completedAt.day)
              .toIso8601String()
              .split('T')[0];

      dateCountMap[dateStr] = (dateCountMap[dateStr] ?? 0) + 1;
    }

    // Convert to list of maps
    return dateCountMap.entries
        .map((entry) => {
              'date': entry.key,
              'count': entry.value,
            })
        .toList();
  }

  Future<void> updateHabitName(String id, String newName) async {
    final Database db = await database;
    await db.update(
      'habits',
      {
        'name': newName,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addRetroactiveCompletion(String habitId, DateTime date) async {
    final Database db = await database;
    final targetDate = DateTime(
      date.year,
      date.month,
      date.day,
      12,
      34,
    );

    // Check if habit was already completed on that date
    final completion = await db.query(
      'habit_completions',
      where: 'habit_id = ? AND date(completed_at) = date(?)',
      whereArgs: [habitId, targetDate.toIso8601String()],
    );

    if (completion.isEmpty) {
      // Add retroactive completion
      await db.insert(
        'habit_completions',
        {
          'id': uuid.v4(),
          'habit_id': habitId,
          'completed_at': targetDate.toIso8601String(),
        },
      );
    }
  }

  Future<void> toggleHabitSkip(String habitId) async {
    final Database db = await database;
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    // Check if habit is already skipped today
    final skip = await db.query(
      'habit_skips',
      where: 'habit_id = ? AND skipped_at >= ?',
      whereArgs: [habitId, today.toIso8601String()],
    );

    if (skip.isEmpty) {
      // Skip for today
      await db.insert(
        'habit_skips',
        {
          'id': uuid.v4(),
          'habit_id': habitId,
          'skipped_at': today.toIso8601String(),
        },
      );
    } else {
      // Un-skip (remove skip record)
      await db.delete(
        'habit_skips',
        where: 'habit_id = ? AND skipped_at >= ?',
        whereArgs: [habitId, today.toIso8601String()],
      );
    }
  }

  Future<bool> isHabitSkippedToday(String habitId) async {
    final Database db = await database;
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    final skip = await db.query(
      'habit_skips',
      where: 'habit_id = ? AND skipped_at >= ?',
      whereArgs: [habitId, today.toIso8601String()],
      limit: 1,
    );

    return skip.isNotEmpty;
  }

  Future<void> toggleHabitState(String habitId) async {
    final Database db = await database;
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    // Check current state
    final completion = await db.query(
      'habit_completions',
      where: 'habit_id = ? AND completed_at >= ?',
      whereArgs: [habitId, today.toIso8601String()],
      limit: 1,
    );

    final skip = await db.query(
      'habit_skips',
      where: 'habit_id = ? AND skipped_at >= ?',
      whereArgs: [habitId, today.toIso8601String()],
      limit: 1,
    );

    bool isCompleted = completion.isNotEmpty;
    bool isSkipped = skip.isNotEmpty;

    if (!isCompleted && !isSkipped) {
      // State: Incomplete → Complete
      await db.insert(
        'habit_completions',
        {
          'id': uuid.v4(),
          'habit_id': habitId,
          'completed_at': DateTime.now().toIso8601String(),
        },
      );
    } else if (isCompleted && !isSkipped) {
      // State: Complete → Skip
      // Remove completion
      await db.delete(
        'habit_completions',
        where: 'habit_id = ? AND completed_at >= ?',
        whereArgs: [habitId, today.toIso8601String()],
      );
      // Add skip
      await db.insert(
        'habit_skips',
        {
          'id': uuid.v4(),
          'habit_id': habitId,
          'skipped_at': today.toIso8601String(),
        },
      );
    } else if (!isCompleted && isSkipped) {
      // State: Skip → Incomplete
      // Remove skip
      await db.delete(
        'habit_skips',
        where: 'habit_id = ? AND skipped_at >= ?',
        whereArgs: [habitId, today.toIso8601String()],
      );
    }
  }

  /// Get today's streak counts for widget display
  Future<Map<String, int>> getTodayStreakCounts() async {
    try {
      final Database db = await database;
      final today = DateTime.now().copyWith(
          hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

      // Get all habits
      final habits = await db.query('habits');
      
      int completed = 0;
      int total = habits.length;

      // Count completed habits for today; skipped-today habits drop out of the goal entirely.
      for (var habit in habits) {
        final skip = await db.query(
          'habit_skips',
          where: 'habit_id = ? AND skipped_at >= ?',
          whereArgs: [habit['id'], today.toIso8601String()],
          limit: 1,
        );

        if (skip.isNotEmpty) {
          total--;
          continue;
        }

        final completion = await db.query(
          'habit_completions',
          where: 'habit_id = ? AND completed_at >= ?',
          whereArgs: [habit['id'], today.toIso8601String()],
          limit: 1,
        );

        if (completion.isNotEmpty) {
          completed++;
        }
      }

      return {
        'completed': completed,
        'total': total,
      };
    } catch (e) {
      return {
        'completed': 0,
        'total': 0,
      };
    }
  }

  // =========================================================================
  // OKR layer
  // =========================================================================

  // ---------- Areas ----------

  Future<String> insertArea(String name, {String? icon, int sortOrder = 0}) async {
    final db = await database;
    final id = uuid.v4();
    await db.insert('areas', {
      'id': id,
      'name': name,
      'icon': icon,
      'sort_order': sortOrder,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getAreas() async {
    final db = await database;
    return db.query('areas', orderBy: 'sort_order ASC, created_at ASC');
  }

  Future<void> updateArea(String id, {String? name, String? icon}) async {
    final db = await database;
    final data = <String, Object?>{};
    if (name != null) data['name'] = name;
    if (icon != null) data['icon'] = icon;
    if (data.isEmpty) return;
    await db.update('areas', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteArea(String id) async {
    final db = await database;
    await db.delete('areas', where: 'id = ?', whereArgs: [id]);
  }

  /// Areas with an aggregate score = mean of their objectives' scores.
  Future<List<Map<String, dynamic>>> getAreasWithRollup() async {
    final areas = await getAreas();
    final result = <Map<String, dynamic>>[];
    for (final a in areas) {
      final objs = await getObjectivesWithProgress(a['id'] as String,
          includeArchived: false);
      final scores = objs.map((o) => o['score']).whereType<double>().toList();
      final score =
          scores.isEmpty ? null : scores.reduce((x, y) => x + y) / scores.length;
      result.add({...a, 'score': score, 'objective_count': objs.length});
    }
    return result;
  }

  // ---------- Objectives ----------

  Future<String> insertObjective({
    required String areaId,
    required String title,
    String? description,
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await database;
    final id = uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('objectives', {
      'id': id,
      'area_id': areaId,
      'title': title,
      'description': description,
      'start_date': start.toIso8601String(),
      'end_date': end.toIso8601String(),
      'status': 'active',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> updateObjectiveStatus(String id, String status) async {
    final db = await database;
    await db.update(
      'objectives',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateObjective(String id,
      {String? title, DateTime? start, DateTime? end}) async {
    final db = await database;
    final data = <String, Object?>{
      'updated_at': DateTime.now().toIso8601String()
    };
    if (title != null) data['title'] = title;
    if (start != null) data['start_date'] = start.toIso8601String();
    if (end != null) data['end_date'] = end.toIso8601String();
    await db.update('objectives', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteObjective(String id) async {
    final db = await database;
    await db.delete('objectives', where: 'id = ?', whereArgs: [id]);
  }

  /// Objectives for an area, each with a weighted score and its key results.
  Future<List<Map<String, dynamic>>> getObjectivesWithProgress(
    String areaId, {
    bool includeArchived = true,
  }) async {
    final db = await database;
    final where = includeArchived
        ? 'area_id = ?'
        : "area_id = ? AND status != 'archived'";
    final objs = await db.query('objectives',
        where: where,
        whereArgs: [areaId],
        orderBy: 'sort_order ASC, created_at ASC');
    final result = <Map<String, dynamic>>[];
    for (final o in objs) {
      final krs =
          await getKeyResultsWithProgress(o['id'] as String, objective: o);
      double? score;
      double weightedSum = 0, weights = 0;
      for (final k in krs) {
        final s = k['score'];
        if (s is double) {
          final w = (k['weight'] as num?)?.toDouble() ?? 1;
          weightedSum += s * w;
          weights += w;
        }
      }
      if (weights > 0) score = weightedSum / weights;
      result.add({...o, 'score': score, 'key_results': krs});
    }
    return result;
  }

  /// Clones an objective and its key results into the next quarter, then
  /// archives the original. Non-destructive: measurements are never touched.
  Future<String> renewObjective(String objectiveId) async {
    final db = await database;
    final rows =
        await db.query('objectives', where: 'id = ?', whereArgs: [objectiveId], limit: 1);
    if (rows.isEmpty) return objectiveId;
    final o = rows.first;
    final next = Period.ofDate(DateTime.parse(o['start_date'] as String)).next;
    final newId = uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('objectives', {
      'id': newId,
      'area_id': o['area_id'],
      'title': o['title'],
      'description': o['description'],
      'start_date': next.start.toIso8601String(),
      'end_date': next.end.toIso8601String(),
      'status': 'active',
      'sort_order': o['sort_order'],
      'created_at': now,
      'updated_at': now,
    });
    await db.update('objectives', {'status': 'archived', 'updated_at': now},
        where: 'id = ?', whereArgs: [objectiveId]);
    final krs =
        await db.query('key_results', where: 'objective_id = ?', whereArgs: [objectiveId]);
    for (final k in krs) {
      await db.insert('key_results', {
        'id': uuid.v4(),
        'objective_id': newId,
        'trackable_id': k['trackable_id'],
        'title': k['title'],
        'aggregation': k['aggregation'],
        'source': k['source'],
        'target_value': k['target_value'],
        'direction': k['direction'],
        'unit': k['unit'],
        'window_mode': k['window_mode'],
        'window_days': k['window_days'],
        'cadence_days': k['cadence_days'],
        'category': k['category'],
        'habit_id': k['habit_id'],
        'weight': k['weight'],
        'sort_order': k['sort_order'],
        'created_at': now,
      });
    }
    return newId;
  }

  // ---------- Key results ----------

  Future<String> insertKeyResult({
    String? objectiveId,
    String? trackableId,
    required String title,
    required String aggregation,
    String source = 'MEASUREMENT',
    double? target,
    String direction = 'UP',
    String? unit,
    String windowMode = 'OBJECTIVE',
    int? windowDays,
    int? cadenceDays,
    String? category,
    String? habitId,
    double weight = 1,
  }) async {
    final db = await database;
    final id = uuid.v4();
    await db.insert('key_results', {
      'id': id,
      'objective_id': objectiveId,
      'trackable_id': trackableId,
      'title': title,
      'aggregation': aggregation,
      'source': source,
      'target_value': target,
      'direction': direction,
      'unit': unit,
      'window_mode': windowMode,
      'window_days': windowDays,
      'cadence_days': cadenceDays,
      'category': category,
      'habit_id': habitId,
      'weight': weight,
      'sort_order': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> updateKeyResultTarget(String id, double? target) async {
    final db = await database;
    await db.update('key_results', {'target_value': target},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateKeyResult(
    String id, {
    String? title,
    String? aggregation,
    double? target,
    bool clearTarget = false,
    String? direction,
    String? unit,
    String? windowMode,
    int? windowDays,
    int? cadenceDays,
    String? category,
    String? source,
    String? trackableId,
    String? habitId,
  }) async {
    final db = await database;
    final data = <String, Object?>{};
    if (title != null) data['title'] = title;
    if (aggregation != null) data['aggregation'] = aggregation;
    if (clearTarget) {
      data['target_value'] = null;
    } else if (target != null) {
      data['target_value'] = target;
    }
    if (direction != null) data['direction'] = direction;
    if (unit != null) data['unit'] = unit;
    if (windowMode != null) data['window_mode'] = windowMode;
    if (windowDays != null) data['window_days'] = windowDays;
    if (cadenceDays != null) data['cadence_days'] = cadenceDays;
    if (category != null) data['category'] = category;
    if (source != null) data['source'] = source;
    if (trackableId != null) data['trackable_id'] = trackableId;
    if (habitId != null) data['habit_id'] = habitId;
    if (data.isEmpty) return;
    await db.update('key_results', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteKeyResult(String id) async {
    final db = await database;
    await db.delete('key_results', where: 'id = ?', whereArgs: [id]);
  }

  /// A single key result merged with its live computed state.
  Future<Map<String, dynamic>?> getKeyResultsById(String id) async {
    final db = await database;
    final rows = await db
        .query('key_results', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final k = rows.first;
    Map<String, dynamic>? obj;
    if (k['objective_id'] != null) {
      final o = await db.query('objectives',
          where: 'id = ?', whereArgs: [k['objective_id']], limit: 1);
      obj = o.isNotEmpty ? o.first : null;
    }
    return {...k, ...await computeKr(k, objective: obj)};
  }

  /// Every key result (across all objectives, plus standalone), each with its
  /// computed state — the flat "quick log" list.
  Future<List<Map<String, dynamic>>> getAllKeyResultsWithProgress() async {
    final db = await database;
    final krs = await db.query('key_results', orderBy: 'created_at ASC');
    final result = <Map<String, dynamic>>[];
    for (final k in krs) {
      Map<String, dynamic>? obj;
      if (k['objective_id'] != null) {
        final o = await db.query('objectives',
            where: 'id = ?', whereArgs: [k['objective_id']], limit: 1);
        obj = o.isNotEmpty ? o.first : null;
      }
      result.add({...k, ...await computeKr(k, objective: obj)});
    }
    return result;
  }

  /// Key results for an objective, each merged with its computed state.
  Future<List<Map<String, dynamic>>> getKeyResultsWithProgress(
    String objectiveId, {
    Map<String, dynamic>? objective,
  }) async {
    final db = await database;
    final krs = await db.query('key_results',
        where: 'objective_id = ?',
        whereArgs: [objectiveId],
        orderBy: 'sort_order ASC, created_at ASC');
    Map<String, dynamic>? obj = objective;
    if (obj == null) {
      final o = await db.query('objectives',
          where: 'id = ?', whereArgs: [objectiveId], limit: 1);
      obj = o.isNotEmpty ? o.first : null;
    }
    final result = <Map<String, dynamic>>[];
    for (final k in krs) {
      result.add({...k, ...await computeKr(k, objective: obj)});
    }
    return result;
  }

  // ---------- The engine ----------

  (DateTime, DateTime) _resolveWindow(
      Map<String, dynamic> kr, Map<String, dynamic>? objective) {
    final now = DateTime.now();
    final mode = (kr['window_mode'] ?? 'OBJECTIVE') as String;
    switch (mode) {
      case 'ROLLING':
        final days = (kr['window_days'] as int?) ?? 7;
        return (now.subtract(Duration(days: days)), now);
      case 'YEAR':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31, 23, 59, 59));
      case 'ALL':
        return (DateTime(1970), now);
      case 'OBJECTIVE':
      default:
        if (objective != null) {
          return (
            DateTime.parse(objective['start_date'] as String),
            DateTime.parse(objective['end_date'] as String)
          );
        }
        final p = Period.current();
        return (p.start, p.end);
    }
  }

  /// Folds the log into a KR's current value + auto-score. Nothing is stored.
  /// Returns: current, target, score (null when no target / track-only),
  /// on_pace, overdue, days_since, last_at.
  Future<Map<String, dynamic>> computeKr(
    Map<String, dynamic> kr, {
    Map<String, dynamic>? objective,
  }) async {
    final db = await database;
    final (start, end) = _resolveWindow(kr, objective);
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();
    final agg = kr['aggregation'] as String;

    final rows = await db.query('measurements',
        where: 'key_result_id = ? AND recorded_at >= ? AND recorded_at <= ?',
        whereArgs: [kr['id'], startIso, endIso],
        orderBy: 'recorded_at DESC');

    double sumV = 0;
    double? latestV;
    final count = rows.length;
    for (final r in rows) {
      sumV += (r['value'] as num).toDouble();
    }
    if (rows.isNotEmpty) {
      latestV = (rows.first['value'] as num).toDouble();
    }

    final direction = (kr['direction'] ?? 'UP') as String;
    final double? current = switch (agg) {
      'COUNT' => count.toDouble(),
      'LATEST' => latestV,
      _ => sumV, // SUM
    };

    final target = (kr['target_value'] as num?)?.toDouble();
    double? score;
    if (target != null && target != 0 && current != null) {
      final raw = direction == 'DOWN'
          ? (current <= 0 ? 1.0 : target / current)
          : current / target;
      score = raw.clamp(0.0, 1.0);
    }

    String? onPace;
    if (score != null) {
      final mode = (kr['window_mode'] ?? 'OBJECTIVE') as String;
      double frac = 1.0;
      final total = end.difference(start).inSeconds;
      if ((mode == 'OBJECTIVE' || mode == 'YEAR') && total > 0) {
        frac = (DateTime.now().difference(start).inSeconds / total)
            .clamp(0.0, 1.0);
      }
      if (score >= (frac + 0.05).clamp(0.0, 1.0)) {
        onPace = 'ahead';
      } else if (score >= frac - 0.1) {
        onPace = 'on_track';
      } else {
        onPace = 'behind';
      }
    }

    return {
      'current': current,
      'target': target,
      'score': score,
      'unit': kr['unit'],
      'on_pace': onPace,
      'aggregation': agg,
      'direction': direction,
    };
  }

  // ---------- Logging (executions + measurements) ----------

  Future<void> logMeasurement({
    String? keyResultId,
    String? trackableId,
    required double value,
    String? category,
    String? note,
    String? unit,
    String? executionId,
    DateTime? at,
  }) async {
    final db = await database;
    await db.insert('measurements', {
      'id': uuid.v4(),
      'execution_id': executionId,
      'key_result_id': keyResultId,
      'trackable_id': trackableId,
      'value': value,
      'unit': unit,
      'category': category,
      'note': note,
      'recorded_at': (at ?? DateTime.now()).toIso8601String(),
    });
  }

  Future<void> incrementTally(String keyResultId, {double by = 1}) async {
    await logMeasurement(keyResultId: keyResultId, value: by);
  }

  // ---------- History ----------

  Future<List<Map<String, dynamic>>> getMeasurementSeries({
    String? trackableId,
    String? keyResultId,
  }) async {
    final db = await database;
    if (trackableId != null) {
      return db.query('measurements',
          where: 'trackable_id = ?',
          whereArgs: [trackableId],
          orderBy: 'recorded_at ASC');
    }
    return db.query('measurements',
        where: 'key_result_id = ?',
        whereArgs: [keyResultId],
        orderBy: 'recorded_at ASC');
  }

  /// Per-quarter roll-up of a series, newest first, for the history list.
  Future<List<Map<String, dynamic>>> getPeriodSummaries({
    String? trackableId,
    String? keyResultId,
    String aggregation = 'SUM',
  }) async {
    final series =
        await getMeasurementSeries(trackableId: trackableId, keyResultId: keyResultId);
    final byPeriod = <String, List<double>>{};
    for (final m in series) {
      final p = Period.ofDate(DateTime.parse(m['recorded_at'] as String)).id;
      (byPeriod[p] ??= []).add((m['value'] as num).toDouble());
    }
    final out = <Map<String, dynamic>>[];
    final keys = byPeriod.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final p in keys) {
      final vals = byPeriod[p]!;
      double v;
      switch (aggregation) {
        case 'COUNT':
          v = vals.length.toDouble();
          break;
        case 'MAX':
          v = vals.reduce((a, b) => a > b ? a : b);
          break;
        case 'LATEST':
          v = vals.last;
          break;
        default:
          v = vals.reduce((a, b) => a + b);
      }
      out.add({'period': p, 'value': v, 'count': vals.length});
    }
    return out;
  }

  // ---------- Reviews / grades ----------

  Future<void> saveGrade({
    required String subjectKind,
    required String subjectId,
    required String period,
    int? grade,
    String? note,
  }) async {
    final db = await database;
    final existing = await db.query('reviews',
        where: 'subject_kind = ? AND subject_id = ? AND period = ?',
        whereArgs: [subjectKind, subjectId, period],
        limit: 1);
    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('reviews', {
        'id': uuid.v4(),
        'subject_kind': subjectKind,
        'subject_id': subjectId,
        'period': period,
        'grade': grade,
        'note': note,
        'graded_at': now,
      });
    } else {
      await db.update('reviews', {'grade': grade, 'note': note, 'graded_at': now},
          where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  Future<int?> getGrade(
      String subjectKind, String subjectId, String period) async {
    final db = await database;
    final r = await db.query('reviews',
        where: 'subject_kind = ? AND subject_id = ? AND period = ?',
        whereArgs: [subjectKind, subjectId, period],
        limit: 1);
    if (r.isEmpty) return null;
    return r.first['grade'] as int?;
  }

  Future<List<Map<String, dynamic>>> getGradeHistory(String subjectId) async {
    final db = await database;
    return db.query('reviews',
        where: 'subject_id = ?', whereArgs: [subjectId], orderBy: 'period DESC');
  }
}
