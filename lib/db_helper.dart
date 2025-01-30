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
      version: 1,
      onCreate: _onCreate,
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
      final completion = await db.query(
        'habit_completions',
        where: 'habit_id = ? AND completed_at >= ?',
        whereArgs: [habit['id'], today.toIso8601String()],
        limit: 1,
      );

      final streaks = await getHabitStreaks(habit['id']);

      // Create a new map with all the original data plus the completed_today status
      mutableHabits.add({
        ...habit,
        'completed_today': completion.isNotEmpty,
        'current_streak': streaks['current_streak'],
        'longest_streak': streaks['longest_streak'],
        'streak_at_risk': streaks['streak_at_risk'],
        'streak_start_date': streaks['streak_start_date'],
        'negative_streak': streaks['negative_streak'],
      });
    }

    // Sort habits by current streak in descending order
    mutableHabits.sort((a, b) =>
        (b['current_streak'] as int).compareTo(a['current_streak'] as int));

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
      int totalGaps = 0;

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
          if (difference == 1) {
            // Consecutive days
            currentCount++;
            streakStartDate = dateOnly;
          } else if (difference == 2) {
            // One day gap
            totalGaps++;
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
        if (difference == 1) {
          countForLongest++;
        } else {
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
}
