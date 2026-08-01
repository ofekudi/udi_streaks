import 'package:flutter/material.dart';

import 'habits/habits_screen.dart';
import 'okr/okr_tree.dart';
import 'okr/record_screen.dart';
import 'ui/theme.dart';
import 'ui/tokens.dart';

void main() {
  // sqflite and home_widget both reach for the binding, so make sure it is up
  // before anything touches them.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UdiStreaks',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootNav(),
    );
  }
}

/// Bottom-nav shell. Habits is the home tab, being the highest-frequency
/// capture; OKR (intent + progress) is the other.
class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  // The IndexedStack keeps every tab's State alive, so a write on one tab
  // never reaches its siblings' one-shot loads. Entering a tab reloads it.
  final _habitsKey = GlobalKey<HabitsScreenState>();
  final _goalsKey = GlobalKey<GoalsTabState>();

  late final _tabs = [
    HabitsScreen(
        key: _habitsKey, title: 'Never Miss Twice', onRecord: _recordFromHabits),
    GoalsTab(key: _goalsKey),
  ];

  /// The Habits tab's Record FAB. The shell brokers it — pushing the OKR
  /// capture page and landing on the OKR tab afterwards — so habits/ keeps
  /// importing nothing from okr/. Not routed through [_select], whose reload
  /// [reveal] already covers.
  Future<void> _recordFromHabits() async {
    Map<String, dynamic>? last;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RecordScreen(onLogged: (k) => last = k)));
    // A Record session can delete a habit-produced measurement, and the
    // cascade un-ticks the habit.
    _habitsKey.currentState?.reload();
    if (last == null) return;
    setState(() => _index = 1);
    await _goalsKey.currentState?.reveal(last!['objective_id'] as String?);
  }

  void _select(int i) {
    if (i == _index) return; // re-tapping the open tab: pull-to-refresh covers it
    setState(() => _index = i);
    switch (i) {
      case 0:
        _habitsKey.currentState?.reload();
      case 1:
        _goalsKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      // The hairline is here rather than in the theme because NavigationBar
      // takes no shape of its own.
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kHairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'Habits'),
            NavigationDestination(
                icon: Icon(Icons.track_changes_outlined),
                selectedIcon: Icon(Icons.track_changes),
                label: 'OKR'),
          ],
        ),
      ),
    );
  }
}
