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
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        '${widget.habit['name']} - History',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _history.length,
          itemBuilder: (context, index) => ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: kGapSm, vertical: kGapXs),
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Text(
                '${_history.length - index}',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            title: Text(
              _history[index]['date'],
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close',
              style: TextStyle(
                  color: scheme.primary, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: _reportRetroactively,
          child: Text('Report Retroactively',
              style: TextStyle(
                  color: scheme.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
