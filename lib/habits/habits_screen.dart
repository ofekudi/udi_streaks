import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'habit_detail_sheet.dart';
import 'habit_dialogs.dart';
import 'habit_history_dialog.dart';
import 'habit_tile.dart';
import 'widget_sync.dart';

/// The habits tab: today's list, plus the flows to add, edit and review one.
///
/// This screen owns loading and persistence; the tile, sheet and dialogs it
/// composes are all presentation-only and report back what the user chose.
class HabitsScreen extends StatefulWidget {
  final String title;

  const HabitsScreen({super.key, required this.title});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen>
    with WidgetsBindingObserver {
  static const _sync = WidgetSync();

  List<Map<String, dynamic>> _habits = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The widget can go stale while backgrounded — most obviously at midnight.
    if (state == AppLifecycleState.resumed) _sync.push();
  }

  /// Reloads the list and pushes the new counts to the home-screen widget.
  Future<void> _refresh() async {
    final habits = await DBHelper().getHabits();
    if (mounted) setState(() => _habits = habits);
    await _sync.push();
  }

  Future<void> _toggle(Map<String, dynamic> habit) async {
    // Tapping the icon of a skipped habit un-skips it rather than completing it.
    if (habit['skipped_today'] == true) {
      await DBHelper().toggleHabitSkip(habit['id']);
    } else {
      await DBHelper().toggleHabitCompletion(habit['id']);
    }
    await _refresh();
  }

  Future<void> _add() async {
    if (await addHabitFlow(context)) await _refresh();
  }

  Future<void> _open(Map<String, dynamic> habit) async {
    final action = await showHabitDetailSheet(context, habit);
    if (action == null || !mounted) return;

    switch (action) {
      case HabitAction.rename:
        await _rename(habit);
      case HabitAction.toggleComplete:
        await DBHelper().toggleHabitCompletion(habit['id']);
        await _refresh();
      case HabitAction.toggleSkip:
        await DBHelper().toggleHabitSkip(habit['id']);
        await _refresh();
      case HabitAction.history:
        await _showHistory(habit);
      case HabitAction.delete:
        await _delete(habit);
    }
  }

  Future<void> _rename(Map<String, dynamic> habit) async {
    final name = await promptHabitName(
      context,
      title: 'Edit Habit Name',
      actionLabel: 'Save',
      initial: habit['name'],
      hint: 'Enter new name',
    );
    if (name == null) return;
    await DBHelper().updateHabitName(habit['id'], name);
    await _refresh();
  }

  Future<void> _showHistory(Map<String, dynamic> habit) async {
    // Loaded before the dialog opens so it renders fully populated.
    final history = await DBHelper().getCompletionHistory(habit['id']);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => HabitHistoryDialog(
        habit: habit,
        initialHistory: history,
        onChanged: _refresh,
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> habit) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete Habit',
      message: 'Are you sure you want to delete "${habit['name']}"?',
    );
    if (!ok) return;
    await DBHelper().deleteHabit(habit['id']);
    await _refresh();
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
          : ListView.separated(
              itemCount: _habits.length,
              separatorBuilder: (context, _) => Divider(
                height: 1,
                thickness: 0.5,
                color:
                    Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                indent: 72,
              ),
              itemBuilder: (context, index) {
                final habit = _habits[index];
                return HabitTile(
                  habit: habit,
                  onToggle: () => _toggle(habit),
                  onOpen: () => _open(habit),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habits_fab',
        onPressed: _add,
        tooltip: 'Add Habit',
        child: const Icon(Icons.add),
      ),
    );
  }
}
