import 'package:flutter/material.dart';

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

