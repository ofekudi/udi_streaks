import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../ui/kit.dart';
import 'habit_tile.dart';

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
/// Returns the chosen action, or null if dismissed.
Future<HabitAction?> showHabitDetailSheet(
  BuildContext context,
  Map<String, dynamic> habit,
) {
  return showModalBottomSheet<HabitAction>(
    context: context,
    builder: (sheetContext) => _HabitDetailSheet(habit: habit),
  );
}

class _HabitDetailSheet extends StatelessWidget {
  final Map<String, dynamic> habit;

  const _HabitDetailSheet({required this.habit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = habit['completed_today'] == true;
    final skipped = habit['skipped_today'] == true;
    final linkedKr = habit['linked_kr_title'] as String?;

    void choose(HabitAction action) => Navigator.pop(context, action);

    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: kGapXl, horizontal: kGapLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Padding(
              padding: const EdgeInsets.only(bottom: kGapLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kGapSm),
                      onTap: () => choose(HabitAction.rename),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: kGapSm, horizontal: kGapXs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                habit['name'],
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                            ),
                            Icon(Icons.edit,
                                size: 20,
                                color:
                                    scheme.primary.withValues(alpha: 0.85)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: kGapXs),
                  Text(
                    'Created on ${ymd(DateTime.parse(habit['created_at']))}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _action(
              icon: done ? Icons.check_circle : Icons.circle_outlined,
              color: done ? kDoneColor : kIdleColor,
              label: done ? 'Completed Today' : 'Mark as Completed',
              onTap: () => choose(HabitAction.toggleComplete),
            ),
            // A completed habit cannot also be skipped.
            if (!done)
              _action(
                icon: skipped ? Icons.undo : Icons.not_interested,
                color: skipped ? kUnskipColor : kSkippedColor,
                label: skipped ? 'Unskip for Today' : 'Skip for Today',
                onTap: () => choose(HabitAction.toggleSkip),
              ),
            // Completing this habit also counts toward the linked key result,
            // so the link belongs beside the completion actions.
            if (linkedKr == null)
              _action(
                icon: Icons.add_link,
                color: scheme.primary,
                label: 'Link to OKR',
                onTap: () => choose(HabitAction.link),
              )
            else
              _action(
                icon: Icons.link_off,
                color: scheme.primary,
                label: 'Unlink from "$linkedKr"',
                onTap: () => choose(HabitAction.unlink),
              ),
            _action(
              icon: Icons.history,
              color: scheme.primary,
              label: 'Completion History',
              onTap: () => choose(HabitAction.history),
            ),
            _action(
              icon: Icons.delete_outline,
              color: kBrokenColor,
              label: 'Delete Habit',
              destructive: true,
              onTap: () => choose(HabitAction.delete),
            ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 28),
      title: Text(
        label,
        style: TextStyle(
          fontSize: destructive ? 16 : 14,
          fontWeight: FontWeight.w500,
          color: destructive ? kBrokenColor : null,
        ),
      ),
      onTap: onTap,
    );
  }
}
