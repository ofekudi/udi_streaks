import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';

/// The completion history for one habit, with the option to backfill a day
/// that was missed.
///
/// This replaces two copies of the same dialog in `main.dart`: the second was
/// opened by the first's "Report Retroactively" button so it could show fresh
/// data, and its own retroactive button was broken — it popped twice and never
/// reopened. Reloading in place removes both the duplication and the bug.
class HabitHistoryDialog extends StatefulWidget {
  final Map<String, dynamic> habit;

  /// Loaded by the caller before the dialog opens, so the list is on screen
  /// immediately — as it was before this was extracted.
  final List<Map<String, dynamic>> initialHistory;

  /// Called after a retroactive completion is added, so the list behind the
  /// dialog and the home widget pick up the new streak numbers.
  final Future<void> Function() onChanged;

  const HabitHistoryDialog({
    super.key,
    required this.habit,
    required this.initialHistory,
    required this.onChanged,
  });

  @override
  State<HabitHistoryDialog> createState() => _HabitHistoryDialogState();
}

class _HabitHistoryDialogState extends State<HabitHistoryDialog> {
  late List<Map<String, dynamic>> _history = widget.initialHistory;

  String get _habitId => widget.habit['id'] as String;

  Future<void> _load() async {
    final history = await DBHelper().getCompletionHistory(_habitId);
    if (!mounted) return;
    setState(() => _history = history);
  }

  /// Long-press a day to take it off, mirroring how an OKR entry is deleted.
  /// Needed because the tile's toggle only reaches today.
  void _dayMenu(String date) {
    showActionSheet(
      context,
      title: date,
      actions: [
        SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete this day',
          destructive: true,
          onTap: () => _deleteDay(date),
        ),
      ],
    );
  }

  Future<void> _deleteDay(String date) async {
    await DBHelper().deleteCompletionOn(_habitId, DateTime.parse(date));
    await widget.onChanged();
    await _load();
  }

  Future<void> _reportRetroactively() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    await DBHelper().addRetroactiveCompletion(_habitId, picked);
    await widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.habit['name']} · History',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: double.maxFinite,
        child: _history.isEmpty
            ? const EmptyState(Icons.event_available, 'Nothing logged yet')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _history.length,
                separatorBuilder: (_, __) => const AppRule(),
                itemBuilder: (context, index) {
                  final date =
                      DateTime.parse(_history[index]['date'] as String);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: kGapSm, vertical: kGapXs),
                    // The count from the bottom up, so the number beside a day
                      // says which day of the run it was.
                    leading: Text('${_history.length - index}',
                        style: kTypeMetaNum.copyWith(color: kAccent)),
                    title: Text(fmtWeekdayDate(date), style: kTypeKr),
                    onLongPress: () =>
                        _dayMenu(_history[index]['date'] as String),
                  );
                },
              ),
      ),
      // Stacked, because "Report retroactively" beside "Close" overflowed a
      // narrow screen.
      actions: [
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: kGapSm,
          children: [
            TextButton(
              onPressed: _reportRetroactively,
              child: const Text('Report retroactively'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    );
  }
}
