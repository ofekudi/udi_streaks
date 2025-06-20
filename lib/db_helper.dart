import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
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

      // Count completed habits for today (excluding skipped ones)
      for (var habit in habits) {
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
}
