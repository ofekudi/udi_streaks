import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../ui/kit.dart';

/// Semantic colours for a habit's three daily states. These were previously
/// bare `Colors.green` / `Colors.orange` / `Colors.grey` literals repeated at
/// every call site in `main.dart`.
const Color kDoneColor = Colors.green;
const Color kSkippedColor = Colors.orange;
const Color kIdleColor = Colors.grey;
const Color kBrokenColor = Colors.red;
const Color kUnskipColor = Colors.blue;

/// Whether a habit is done, skipped or still open today.
enum HabitDayState {
  done,
  skipped,
  open;

  static HabitDayState of(Map<String, dynamic> habit) =>
      habit['completed_today'] == true
          ? HabitDayState.done
          : habit['skipped_today'] == true
              ? HabitDayState.skipped
              : HabitDayState.open;

  IconData get icon => switch (this) {
        HabitDayState.done => Icons.check_circle,
        HabitDayState.skipped => Icons.not_interested,
        HabitDayState.open => Icons.circle_outlined,
      };

  Color get color => switch (this) {
        HabitDayState.done => kDoneColor,
        HabitDayState.skipped => kSkippedColor,
        HabitDayState.open => kIdleColor,
      };
}

/// The streak count chip: a flame with the current run, a restart arrow when
/// the run is over but history exists, or a red cross with the negative count
/// once the habit has been idle past the break threshold.
class StreakBadge extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final int negativeStreak;

  const StreakBadge({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.negativeStreak,
  });

  /// Nothing to show for a habit that has never been completed.
  bool get isVisible =>
      currentStreak > 0 || longestStreak > 0 || negativeStreak < 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final broken = negativeStreak < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: kGapXs),
      decoration: BoxDecoration(
        color: broken
            ? kBrokenColor.withValues(alpha: 0.1)
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(kGapMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            broken
                ? Icons.close_rounded
                : currentStreak > 0
                    ? Icons.local_fire_department
                    : Icons.restart_alt,
            size: broken ? 20 : 18,
            color: broken
                ? kBrokenColor
                : currentStreak > 0
                    ? kSkippedColor
                    : kIdleColor,
          ),
          const SizedBox(width: 6),
          Text(
            '${broken ? negativeStreak : currentStreak}',
            style: TextStyle(
              color: broken ? kBrokenColor : scheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              height: 1.0,
            ),
          ),
          // Show the record alongside the current run only when it is better.
          if (!broken && longestStreak > currentStreak)
            Text(
              ' / $longestStreak',
              style: TextStyle(
                color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// One row in the habits list: a state toggle, the name, an at-risk warning,
/// the streak badge, and the date the current run started.
class HabitTile extends StatelessWidget {
  final Map<String, dynamic> habit;

  /// Tapping the leading icon: completes, or un-skips a skipped habit.
  final VoidCallback onToggle;

  /// Tapping the row opens the detail sheet.
  final VoidCallback onOpen;

  const HabitTile({
    super.key,
    required this.habit,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = HabitDayState.of(habit);
    final start = habit['streak_start_date'];

    final badge = StreakBadge(
      currentStreak: habit['current_streak'] as int,
      longestStreak: habit['longest_streak'] as int,
      negativeStreak: habit['negative_streak'] as int,
    );

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: kGapLg, vertical: kGapSm),
      leading: IconButton(
        icon: Icon(state.icon, color: state.color, size: 28),
        onPressed: onToggle,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              habit['name'],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                decoration: state == HabitDayState.done
                    ? TextDecoration.lineThrough
                    : null,
                color: switch (state) {
                  HabitDayState.done =>
                    scheme.onSurface.withValues(alpha: 0.7),
                  HabitDayState.skipped =>
                    scheme.onSurface.withValues(alpha: 0.3),
                  HabitDayState.open => scheme.onSurface,
                },
              ),
            ),
          ),
          if (state == HabitDayState.open && habit['streak_at_risk'] == true)
            Container(
              margin: const EdgeInsets.only(right: kGapSm),
              child: const Tooltip(
                message: 'Complete today or your streak will reset tomorrow!',
                child: Icon(Icons.warning_amber_rounded,
                    color: kSkippedColor, size: 22),
              ),
            ),
          if (badge.isVisible) badge,
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          start != null
              ? 'Since: ${ymd(DateTime.parse(start.toString()))}'
              : 'No active streak',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
      onTap: onOpen,
    );
  }
}
