import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';
import 'habit_detail_sheet.dart';
import 'habit_dialogs.dart';
import 'habit_history_dialog.dart';
import 'habit_tile.dart';
import 'link_kr_sheet.dart';
import 'widget_sync.dart';

/// The habits tab: today's list, plus the flows to add, edit and review one.
///
/// This screen owns loading and persistence; the tile, sheet and dialogs it
/// composes are all presentation-only and report back what the user chose.
class HabitsScreen extends StatefulWidget {
  final String title;

  /// The Record FAB's action, injected by the nav shell: the capture page it
  /// pushes lives in okr/, which habits/ doesn't import.
  final Future<void> Function() onRecord;

  const HabitsScreen(
      {super.key, required this.title, required this.onRecord});

  @override
  State<HabitsScreen> createState() => HabitsScreenState();
}

class HabitsScreenState extends State<HabitsScreen>
    with WidgetsBindingObserver {
  static const _sync = WidgetSync();

  List<Map<String, dynamic>> _habits = [];

  /// False only until the first load lands, so an empty first frame doesn't look
  /// like an empty list.
  bool _loaded = false;

  /// Today's state for a habit whose write is still in flight, keyed by id. The
  /// tick reads this first, so it flips under the finger rather than after a
  /// round-trip through sqflite.
  final Map<String, HabitDayState> _pending = {};

  /// Emoji for the habit being typed — null until picked, so the well shows a
  /// greyed placeholder. Prefixed onto the name: habits have no icon column.
  String? _newHabitEmoji;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
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
  /// Public so the nav shell can reload the tab on entry.
  ///
  /// The widget push is not awaited. It is best-effort by design — there may be
  /// no widget placed, and on iOS there is no widget at all — so nothing the
  /// user is waiting on should sit behind a platform channel.
  Future<void> reload() async {
    final habits = await DBHelper().getHabits();
    if (mounted) {
      setState(() {
        _habits = habits;
        _loaded = true;
        _pending.clear();
      });
    }
    _sync.push();
  }

  Future<void> _toggle(Map<String, dynamic> habit) async {
    final id = habit['id'] as String;
    final skipped = habit['skipped_today'] == true;
    // Show the outcome now; [reload] clears this once the row says it itself.
    setState(() => _pending[id] = skipped
        ? HabitDayState.open
        : HabitDayState.of(habit) == HabitDayState.done
            ? HabitDayState.open
            : HabitDayState.done);
    // Tapping the tick of a skipped habit un-skips it rather than completing it.
    if (skipped) {
      await DBHelper().toggleHabitSkip(id);
    } else {
      await DBHelper().toggleHabitCompletion(id);
    }
    await reload();
  }

  Future<void> _open(Map<String, dynamic> habit) async {
    final action = await showHabitDetailSheet(context, habit);
    if (action == null || !mounted) return;

    switch (action) {
      case HabitAction.rename:
        await _rename(habit);
      case HabitAction.toggleComplete:
        await DBHelper().toggleHabitCompletion(habit['id']);
        await reload();
      case HabitAction.toggleSkip:
        await DBHelper().toggleHabitSkip(habit['id']);
        await reload();
      case HabitAction.link:
        await _link(habit);
      case HabitAction.unlink:
        await DBHelper().unlinkHabit(habit['id']);
        await reload();
      case HabitAction.history:
        await _showHistory(habit);
      case HabitAction.delete:
        await _delete(habit);
    }
  }

  /// Points the habit at a COUNT key result, so completing it also counts there.
  Future<void> _link(Map<String, dynamic> habit) async {
    // Loaded before the sheet opens, as the history dialog does.
    final krs = await DBHelper().getLinkableKeyResults();
    if (!mounted) return;
    final krId = await showLinkKrSheet(context, krs, habitId: habit['id']);
    if (krId == null) return;
    await DBHelper().linkHabitToKeyResult(habit['id'], krId);
    await reload();
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
    await reload();
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
        onChanged: reload,
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
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                // The same inset the OKR tab uses, so both tabs' cards land on
                // one edge.
                padding: const EdgeInsets.fromLTRB(
                    kGapSm, kGapMd, kGapSm, kGapMd),
                children: [
                  if (_habits.isEmpty)
                    const EmptyState(
                        Icons.check_circle_outline, 'No streaks yet')
                  else
                    // One card holding the day, ruled between rows — the same
                    // containment the OKR tab gives an objective and its key
                    // results.
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < _habits.length; i++) ...[
                            if (i > 0) const AppRule(),
                            HabitTile(
                              habit: _habits[i],
                              pending: _pending[_habits[i]['id']],
                              onToggle: () => _toggle(_habits[i]),
                              onOpen: () => _open(_habits[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kGapXs),
                    child: InlineAddField(
                      label: 'Add streak',
                      hint: 'Type something here',
                      leading: EmojiWell(
                        emoji: _newHabitEmoji ?? '',
                        placeholder: '😊',
                        onTap: () async {
                          final emoji = await pickEmoji(context);
                          if (emoji != null) {
                            setState(() => _newHabitEmoji = emoji);
                          }
                        },
                      ),
                      onSubmit: (name) async {
                        await DBHelper().insertHabit(_newHabitEmoji == null
                            ? name
                            : '$_newHabitEmoji $name');
                        _newHabitEmoji = null;
                        await reload();
                      },
                    ),
                  ),
                  // Room to scroll the last row clear of the FAB.
                  const SizedBox(height: kFabGutter),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'habits_fab',
        onPressed: widget.onRecord,
        icon: const Icon(Icons.add),
        label: const Text('Record'),
      ),
    );
  }
}
