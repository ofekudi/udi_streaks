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

  Future<Map<String, int>> getHabitStreaks(String habitId) async {
    final Database db = await database;
    final completions = await db.query(
      'habit_completions',
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'completed_at DESC',
    );

    if (completions.isEmpty) {
      return {'current_streak': 0, 'longest_streak': 0};
    }

    int currentStreak = 0;
    int longestStreak = 0;
    int currentCount = 0;
    DateTime? lastDate;

    // Get today's date at midnight for comparison
    final today = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    // Check if the most recent completion is from today or yesterday
    final mostRecentCompletion =
        DateTime.parse(completions.first['completed_at'] as String);
    final daysSinceLastCompletion =
        today.difference(mostRecentCompletion).inDays;

    // If more than 1 day has passed since last completion, current streak is 0
    if (daysSinceLastCompletion > 1) {
      currentStreak = 0;
    } else {
      // Calculate current streak
      for (var completion in completions) {
        final completedAt =
            DateTime.parse(completion['completed_at'] as String);
        final dateOnly =
            DateTime(completedAt.year, completedAt.month, completedAt.day);

        if (lastDate == null) {
          currentCount = 1;
          lastDate = dateOnly;
        } else {
          final difference = lastDate.difference(dateOnly).inDays;

          if (difference == 1) {
            // Consecutive day
            currentCount++;
          } else {
            // More than one day gap, streak is broken
            break;
          }
          lastDate = dateOnly;
        }
      }
      currentStreak = currentCount;
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
          // Consecutive day
          countForLongest++;
        } else {
          // Streak broken, check if this was the longest
          if (countForLongest > longestStreak) {
            longestStreak = countForLongest;
          }
          countForLongest = 1;
        }
        lastDateForLongest = dateOnly;
      }
    }

    // Check one last time for the longest streak
    if (countForLongest > longestStreak) {
      longestStreak = countForLongest;
    }

    return {
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
    };
  }
}
