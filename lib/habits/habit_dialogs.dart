import 'package:flutter/material.dart';

import '../db_helper.dart';
import '../ui/kit.dart';

/// A single-field name dialog, used for renaming a habit.
///
/// Returns the name as typed — deliberately not trimmed, matching the
/// original — or null if dismissed. Replaces a hand-rolled
/// `TextEditingController` + `AlertDialog` block in `main.dart`.
Future<String?> promptHabitName(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initial = '',
  String hint = 'Habit name',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      actionLabel: actionLabel,
      initial: initial,
      hint: hint,
    ),
  );
}

/// The "start a new streak" flow: pick an emoji, name the habit, save.
///
/// Returns true when a habit was created. The emoji is prefixed onto the name
/// because habits have no icon column — unlike OKR areas, which do.
Future<bool> addHabitFlow(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _AddHabitDialog(),
  );
  if (name == null) return false;
  await DBHelper().insertHabit(name);
  return true;
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String actionLabel;
  final String initial;
  final String hint;

  const _NameDialog({
    required this.title,
    required this.actionLabel,
    required this.initial,
    required this.hint,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Matches the original: an empty name is ignored and the dialog stays open.
  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

class _AddHabitDialog extends StatefulWidget {
  const _AddHabitDialog();

  @override
  State<_AddHabitDialog> createState() => _AddHabitDialogState();
}

class _AddHabitDialogState extends State<_AddHabitDialog> {
  final _controller = TextEditingController();

  /// Null until the user picks one — the placeholder renders greyed out.
  String? _emoji;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickEmoji(context);
    if (picked == null || !mounted) return;
    setState(() => _emoji = picked);
  }

  /// Matches the original: "Done" always closes the dialog, and only a
  /// non-empty name is actually saved.
  void _submit() {
    final text = _controller.text;
    Navigator.of(context)
        .pop(text.isEmpty ? null : (_emoji == null ? text : '$_emoji $text'));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Start a new streak!'),
      content: Row(
        children: [
          GestureDetector(
            onTap: _pick,
            child: Container(
              padding: const EdgeInsets.all(kGapSm),
              margin: const EdgeInsets.only(right: kGapSm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kGapSm),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _emoji ?? '😊',
                style: TextStyle(
                  fontSize: 24,
                  color: _emoji == null ? Colors.grey : null,
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration:
                  const InputDecoration(hintText: 'Type something here'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}
