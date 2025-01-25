import 'package:flutter/material.dart';
import 'db_helper.dart';

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
      home: const MyHomePage(title: 'UdiStreaks'),
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

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  final TextEditingController _textController = TextEditingController();
  List<Map<String, dynamic>> _habits = [];

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final habits = await DBHelper().getHabits();
    setState(() {
      _habits = habits;
      _counter = habits.length;
    });
  }

  void _incrementCounter() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Start a new streak!'),
          content: TextField(
            controller: _textController,
            decoration: const InputDecoration(hintText: "Type something here"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Done'),
              onPressed: () async {
                if (_textController.text.isNotEmpty) {
                  await DBHelper().insertHabit(_textController.text);
                  _loadHabits();
                }
                _textController.clear();
                Navigator.of(context).pop();
              },
            ),
          ],
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
                return ListTile(
                  leading: IconButton(
                    icon: Icon(
                      habit['completed_today']
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color:
                          habit['completed_today'] ? Colors.green : Colors.grey,
                    ),
                    onPressed: () async {
                      await DBHelper().toggleHabitCompletion(habit['id']);
                      _loadHabits();
                    },
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          habit['name'],
                          style: TextStyle(
                            decoration: habit['completed_today']
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (!habit['completed_today'] &&
                          habit['streak_at_risk'] == true)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message:
                                'Complete today or your streak will reset tomorrow!',
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                        ),
                      if (habit['current_streak'] > 0 ||
                          habit['longest_streak'] > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                habit['current_streak'] > 0
                                    ? Icons.local_fire_department
                                    : Icons.restart_alt,
                                size: 16,
                                color: habit['current_streak'] > 0
                                    ? Colors.orange
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${habit['current_streak']}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              if (habit['longest_streak'] >
                                  habit['current_streak'])
                                Text(
                                  ' / ${habit['longest_streak']}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                        .withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    habit['streak_start_date'] != null
                        ? 'Since: ${DateTime.parse(habit['streak_start_date'].toString()).toString().split(' ')[0]}'
                        : 'No active streak',
                  ),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext context) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: Text(
                                  habit['name'],
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                subtitle: Text(
                                  'Started: ${DateTime.parse(habit['created_at']).toString().split(' ')[0]}',
                                ),
                              ),
                              const Divider(),
                              ListTile(
                                leading: Icon(
                                  habit['completed_today']
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: habit['completed_today']
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                title: Text(
                                  habit['completed_today']
                                      ? 'Completed Today'
                                      : 'Mark as Completed',
                                ),
                                onTap: () async {
                                  await DBHelper()
                                      .toggleHabitCompletion(habit['id']);
                                  _loadHabits();
                                  Navigator.pop(context);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.history),
                                title: const Text('Completion History'),
                                onTap: () async {
                                  Navigator.pop(context); // Close bottom sheet
                                  final history = await DBHelper()
                                      .getCompletionHistory(habit['id']);
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: Text(
                                              '${habit['name']} - History'),
                                          content: SizedBox(
                                            width: double.maxFinite,
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: history.length,
                                              itemBuilder: (context, index) {
                                                final entry = history[index];
                                                return ListTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer,
                                                    child: Text(
                                                      '${history.length - index}',
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onPrimaryContainer,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  title: Text(entry['date']),
                                                );
                                              },
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              child: const Text('Close'),
                                              onPressed: () {
                                                Navigator.of(context).pop();
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
                                leading: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                title: const Text('Delete Habit'),
                                onTap: () {
                                  Navigator.pop(context); // Close bottom sheet
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
                                              _loadHabits();
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
