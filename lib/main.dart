import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:home_widget/home_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UdiStreaks',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Never Miss Twice'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  int _counter = 0;
  final TextEditingController _textController = TextEditingController();
  List<Map<String, dynamic>> _habits = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHabits();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Update widget when app resumes to ensure synchronization
    if (state == AppLifecycleState.resumed) {
      _updateHomeWidget();
    }
  }

  Future<void> _loadHabits() async {
    final habits = await DBHelper().getHabits();
    setState(() {
      _habits = habits;
      _counter = habits.length;
    });
    // Update widget after loading habits
    await _updateHomeWidget();
  }

  Future<void> _updateHomeWidget() async {
    try {
      final streakCounts = await DBHelper().getTodayStreakCounts();
      await HomeWidget.saveWidgetData<int>('completed', streakCounts['completed']!);
      await HomeWidget.saveWidgetData<int>('total', streakCounts['total']!);
      await HomeWidget.updateWidget(
        name: 'StreakWidgetProvider',
      );
    } catch (e) {
      return;
    }
  }

  // Helper method to ensure widget updates after any habit change
  Future<void> _refreshHabitsAndUpdateWidget() async {
    await _loadHabits();
    // Additional explicit widget update to ensure synchronization
    await _updateHomeWidget();
  }

  void _incrementCounter() {
    String? selectedEmoji; // Default is null
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Start a new streak!'),
              content: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (BuildContext context) {
                          return SizedBox(
                            height: 350,
                            child: EmojiPicker(
                              onEmojiSelected: (category, emoji) {
                                setState(() => selectedEmoji = emoji.emoji);
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        selectedEmoji ?? '😊',
                        style: TextStyle(
                          fontSize: 24,
                          color: selectedEmoji == null ? Colors.grey : null,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                          hintText: "Type something here"),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Done'),
                  onPressed: () async {
                    if (_textController.text.isNotEmpty) {
                      final habitName = selectedEmoji != null
                          ? '$selectedEmoji ${_textController.text}'
                          : _textController.text;
                      await DBHelper().insertHabit(habitName);
                      await _refreshHabitsAndUpdateWidget();
                    }
                    _textController.clear();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: _habits.isEmpty
          ? const Center(
              child: Text('No habits yet. Add one by tapping the + button!'),
            )
          : ListView.builder(
              itemCount: _habits.length,
              itemBuilder: (context, index) {
                final habit = _habits[index];
                return Column(
                  children: [
                    ListTile(
                      leading: IconButton(
                        icon: Icon(
                          habit['completed_today']
                              ? Icons.check_circle
                              : habit['skipped_today']
                                  ? Icons.not_interested
                                  : Icons.circle_outlined,
                          color: habit['completed_today']
                              ? Colors.green
                              : habit['skipped_today']
                                  ? Colors.orange
                                  : Colors.grey,
                          size: 28,
                        ),
                        onPressed: () async {
                          if (habit['skipped_today']) {
                            // If skipped, un-skip it
                            await DBHelper().toggleHabitSkip(habit['id']);
                          } else {
                            // If not skipped, toggle completion
                            await DBHelper().toggleHabitCompletion(habit['id']);
                          }
                          await _refreshHabitsAndUpdateWidget();
                        },
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              habit['name'],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                decoration: habit['completed_today']
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: habit['completed_today']
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7)
                                    : habit['skipped_today']
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.3)
                                        : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (!habit['completed_today'] &&
                              !habit['skipped_today'] &&
                              habit['streak_at_risk'] == true)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Tooltip(
                                message:
                                    'Complete today or your streak will reset tomorrow!',
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  size: 22,
                                ),
                              ),
                            ),
                          if (habit['current_streak'] > 0 ||
                              habit['longest_streak'] > 0 ||
                              habit['negative_streak'] < 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: habit['negative_streak'] < 0
                                    ? Colors.red.withOpacity(0.1)
                                    : Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    habit['negative_streak'] < 0
                                        ? Icons.close_rounded
                                        : habit['current_streak'] > 0
                                            ? Icons.local_fire_department
                                            : Icons.restart_alt,
                                    size:
                                        habit['negative_streak'] < 0 ? 20 : 18,
                                    color: habit['negative_streak'] < 0
                                        ? Colors.red
                                        : habit['current_streak'] > 0
                                            ? Colors.orange
                                            : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    habit['negative_streak'] < 0
                                        ? '${habit['negative_streak']}'
                                        : '${habit['current_streak']}',
                                    style: TextStyle(
                                      color: habit['negative_streak'] < 0
                                          ? Colors.red
                                          : Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      height: 1.0,
                                    ),
                                  ),
                                  if (habit['longest_streak'] >
                                          habit['current_streak'] &&
                                      habit['negative_streak'] >= 0)
                                    Text(
                                      ' / ${habit['longest_streak']}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer
                                            .withOpacity(0.7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          habit['streak_start_date'] != null
                              ? 'Since: ${DateTime.parse(habit['streak_start_date'].toString()).toString().split(' ')[0]}'
                              : 'No active streak',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (BuildContext context) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24, horizontal: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            onTap: () {
                                              Navigator.pop(
                                                  context); // Close bottom sheet
                                              final TextEditingController
                                                  nameController =
                                                  TextEditingController(
                                                      text: habit['name']);
                                              showDialog(
                                                context: context,
                                                builder:
                                                    (BuildContext context) {
                                                  return AlertDialog(
                                                    title: const Text(
                                                        'Edit Habit Name'),
                                                    content: TextField(
                                                      controller:
                                                          nameController,
                                                      decoration:
                                                          const InputDecoration(
                                                        hintText:
                                                            "Enter new name",
                                                      ),
                                                      autofocus: true,
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        child: const Text(
                                                            'Cancel'),
                                                        onPressed: () {
                                                          Navigator.of(context)
                                                              .pop();
                                                        },
                                                      ),
                                                      TextButton(
                                                        child:
                                                            const Text('Save'),
                                                        onPressed: () async {
                                                          if (nameController
                                                              .text
                                                              .isNotEmpty) {
                                                            await DBHelper()
                                                                .updateHabitName(
                                                                    habit['id'],
                                                                    nameController
                                                                        .text);
                                                            await _refreshHabitsAndUpdateWidget();
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                          }
                                                        },
                                                      ),
                                                    ],
                                                  );
                                                },
                                              );
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                      horizontal: 4),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      habit['name'],
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleSmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.edit,
                                                    size: 20,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withOpacity(0.85),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Created on ${DateTime.parse(habit['created_at']).toString().split(' ')[0]}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.7),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      habit['completed_today']
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: habit['completed_today']
                                          ? Colors.green
                                          : Colors.grey,
                                      size: 28,
                                    ),
                                    title: Text(
                                      habit['completed_today']
                                          ? 'Completed Today'
                                          : 'Mark as Completed',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    onTap: () async {
                                      await DBHelper()
                                          .toggleHabitCompletion(habit['id']);
                                      await _refreshHabitsAndUpdateWidget();
                                      Navigator.pop(context);
                                    },
                                  ),
                                  if (!habit['completed_today'])
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        habit['skipped_today']
                                            ? Icons.undo
                                            : Icons.not_interested,
                                        color: habit['skipped_today']
                                            ? Colors.blue
                                            : Colors.orange,
                                        size: 28,
                                      ),
                                      title: Text(
                                        habit['skipped_today']
                                            ? 'Unskip for Today'
                                            : 'Skip for Today',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      onTap: () async {
                                        await DBHelper()
                                            .toggleHabitSkip(habit['id']);
                                        await _refreshHabitsAndUpdateWidget();
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.history,
                                      size: 28,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    title: const Text(
                                      'Completion History',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    onTap: () async {
                                      Navigator.pop(
                                          context); // Close bottom sheet
                                      final history = await DBHelper()
                                          .getCompletionHistory(habit['id']);
                                      if (context.mounted) {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: Text(
                                                '${habit['name']} - History',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              content: SizedBox(
                                                width: double.maxFinite,
                                                child: ListView.builder(
                                                  shrinkWrap: true,
                                                  itemCount: history.length,
                                                  itemBuilder:
                                                      (context, index) {
                                                    final entry =
                                                        history[index];
                                                    return ListTile(
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      leading: CircleAvatar(
                                                        backgroundColor: Theme
                                                                .of(context)
                                                            .colorScheme
                                                            .primaryContainer,
                                                        child: Text(
                                                          '${history.length - index}',
                                                          style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .onPrimaryContainer,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                      title: Text(
                                                        entry['date'],
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  child: Text(
                                                    'Close',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                                TextButton(
                                                  child: Text(
                                                    'Report Retroactively',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  onPressed: () async {
                                                    final DateTime? pickedDate =
                                                        await showDatePicker(
                                                      context: context,
                                                      initialDate:
                                                          DateTime.now(),
                                                      firstDate: DateTime(2000),
                                                      lastDate: DateTime.now(),
                                                    );

                                                    if (pickedDate != null &&
                                                        context.mounted) {
                                                      await DBHelper()
                                                          .addRetroactiveCompletion(
                                                        habit['id'],
                                                        pickedDate,
                                                      );
                                                      await _refreshHabitsAndUpdateWidget();

                                                      // Refresh the history
                                                      final updatedHistory =
                                                          await DBHelper()
                                                              .getCompletionHistory(
                                                                  habit['id']);

                                                      if (context.mounted) {
                                                        Navigator.of(context)
                                                            .pop(); // Close current dialog
                                                        // Show updated history
                                                        showDialog(
                                                          context: context,
                                                          builder: (BuildContext
                                                              context) {
                                                            return AlertDialog(
                                                              title: Text(
                                                                '${habit['name']} - History',
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                              ),
                                                              content: SizedBox(
                                                                width: double
                                                                    .maxFinite,
                                                                child: ListView
                                                                    .builder(
                                                                  shrinkWrap:
                                                                      true,
                                                                  itemCount:
                                                                      updatedHistory
                                                                          .length,
                                                                  itemBuilder:
                                                                      (context,
                                                                          index) {
                                                                    final entry =
                                                                        updatedHistory[
                                                                            index];
                                                                    return ListTile(
                                                                      contentPadding:
                                                                          const EdgeInsets
                                                                              .symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            4,
                                                                      ),
                                                                      leading:
                                                                          CircleAvatar(
                                                                        backgroundColor: Theme.of(context)
                                                                            .colorScheme
                                                                            .primaryContainer,
                                                                        child:
                                                                            Text(
                                                                          '${updatedHistory.length - index}',
                                                                          style:
                                                                              TextStyle(
                                                                            color:
                                                                                Theme.of(context).colorScheme.onPrimaryContainer,
                                                                            fontWeight:
                                                                                FontWeight.w500,
                                                                            fontSize:
                                                                                14,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      title:
                                                                          Text(
                                                                        entry[
                                                                            'date'],
                                                                        style:
                                                                            const TextStyle(
                                                                          fontSize:
                                                                              14,
                                                                          fontWeight:
                                                                              FontWeight.w400,
                                                                        ),
                                                                      ),
                                                                    );
                                                                  },
                                                                ),
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  child: Text(
                                                                    'Close',
                                                                    style:
                                                                        TextStyle(
                                                                      color: Theme.of(
                                                                              context)
                                                                          .colorScheme
                                                                          .primary,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                  onPressed:
                                                                      () {
                                                                    Navigator.of(
                                                                            context)
                                                                        .pop();
                                                                  },
                                                                ),
                                                                TextButton(
                                                                  child: Text(
                                                                    'Report Retroactively',
                                                                    style:
                                                                        TextStyle(
                                                                      color: Theme.of(
                                                                              context)
                                                                          .colorScheme
                                                                          .primary,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                  onPressed:
                                                                      () async {
                                                                    final DateTime?
                                                                        pickedDate =
                                                                        await showDatePicker(
                                                                      context:
                                                                          context,
                                                                      initialDate:
                                                                          DateTime
                                                                              .now(),
                                                                      firstDate:
                                                                          DateTime(
                                                                              2000),
                                                                      lastDate:
                                                                          DateTime
                                                                              .now(),
                                                                    );

                                                                    if (pickedDate !=
                                                                            null &&
                                                                        context
                                                                            .mounted) {
                                                                      await DBHelper()
                                                                          .addRetroactiveCompletion(
                                                                        habit[
                                                                            'id'],
                                                                        pickedDate,
                                                                      );
                                                                      await _refreshHabitsAndUpdateWidget();
                                                                      Navigator.of(
                                                                              context)
                                                                          .pop();
                                                                      // Show the history dialog again with updated data
                                                                      if (context
                                                                          .mounted) {
                                                                        Navigator.of(context)
                                                                            .pop();
                                                                      }
                                                                    }
                                                                  },
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        );
                                                      }
                                                    }
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      }
                                    },
                                  ),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 28,
                                    ),
                                    title: const Text(
                                      'Delete Habit',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(
                                          context); // Close bottom sheet
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: const Text('Delete Habit'),
                                            content: Text(
                                                'Are you sure you want to delete "${habit['name']}"?'),
                                            actions: [
                                              TextButton(
                                                child: const Text('Cancel'),
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                },
                                              ),
                                              TextButton(
                                                child: const Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                                onPressed: () async {
                                                  await DBHelper()
                                                      .deleteHabit(habit['id']);
                                                  await _refreshHabitsAndUpdateWidget();
                                                  Navigator.of(context).pop();
                                                },
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                    if (index < _habits.length - 1)
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.2),
                        indent: 72,
                      ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Add Habit',
        child: const Icon(Icons.add),
      ),
    );
  }
}
