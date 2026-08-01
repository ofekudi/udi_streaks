import 'package:flutter/material.dart';

import '../ui/kit.dart';

/// What the user picked from a habit's detail sheet. The sheet itself performs
/// no writes — the screen owns persistence and refreshing.
enum HabitAction {
  rename,
  toggleComplete,
  toggleSkip,
  link,
  unlink,
  history,
  delete
}

/// The bottom sheet shown when a habit row is tapped.
///
/// On [showAppSheet], like its sibling `link_kr_sheet.dart`: the handle, the
/// title, the close button and the safe area all come from the shell — the last
/// of which is what keeps "Delete habit" out of the home-indicator gesture zone.
///
/// Returns the chosen action, or null if dismissed.
Future<HabitAction?> showHabitDetailSheet(
  BuildContext context,
  Map<String, dynamic> habit,
) {
  return showAppSheet<HabitAction>(
    context,
    title: habit['name'] as String,
    heightFactor: 0.7,
    builder: (_) => _HabitDetailSheet(habit: habit),
  );
}

class _HabitDetailSheet extends StatelessWidget {
  final Map<String, dynamic> habit;

  const _HabitDetailSheet({required this.habit});

  @override
  Widget build(BuildContext context) {
    final done = habit['completed_today'] == true;
    final skipped = habit['skipped_today'] == true;
    final linkedKr = habit['linked_kr_title'] as String?;
    final created = DateTime.parse(habit['created_at']);

    void choose(HabitAction action) => Navigator.pop(context, action);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Created ${fmtDayMonth(created)} ${created.year}',
            style: kTypeMeta),
        const SizedBox(height: kGapSm),
        const AppRule.flush(),
        _action(
          icon: done ? Icons.check_circle : Icons.circle_outlined,
          color: done ? kAccent : kInkFaint,
          label: done ? 'Completed today' : 'Mark as completed',
          onTap: () => choose(HabitAction.toggleComplete),
        ),
        // A completed habit cannot also be skipped.
        if (!done)
          _action(
            icon: skipped ? Icons.undo : Icons.not_interested,
            color: kCaution,
            label: skipped ? 'Unskip for today' : 'Skip for today',
            onTap: () => choose(HabitAction.toggleSkip),
          ),
        // The name is the sheet's title now, so renaming is an action like any
        // other rather than a tappable heading with a pencil on it.
        _action(
          icon: Icons.drive_file_rename_outline,
          color: kInkSoft,
          label: 'Rename',
          onTap: () => choose(HabitAction.rename),
        ),
        // Completing this habit also counts toward the linked key result,
        // so the link belongs beside the completion actions.
        if (linkedKr == null)
          _action(
            icon: Icons.add_link,
            color: kInkSoft,
            label: 'Link to OKR',
            onTap: () => choose(HabitAction.link),
          )
        else
          _action(
            icon: Icons.link_off,
            color: kInkSoft,
            label: 'Unlink from "$linkedKr"',
            onTap: () => choose(HabitAction.unlink),
          ),
        _action(
          icon: Icons.history,
          color: kInkSoft,
          label: 'Completion history',
          onTap: () => choose(HabitAction.history),
        ),
        _action(
          icon: Icons.delete_outline,
          color: kDanger,
          label: 'Delete habit',
          destructive: true,
          onTap: () => choose(HabitAction.delete),
        ),
      ],
    );
  }

  /// Every row the same size, destructive or not — colour is what marks the
  /// destructive one, not weight.
  Widget _action({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 22),
      title: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: destructive ? kTypeKr.copyWith(color: kDanger) : kTypeKr),
      onTap: onTap,
    );
  }
}
