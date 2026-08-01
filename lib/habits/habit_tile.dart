import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/kit.dart';

/// Whether a habit is done, skipped or still open today.
///
/// The colours are the app's four meanings, not a palette of their own: done is
/// [kAccent], the same as a key result making progress; skipped is [kCaution],
/// the same as a streak at risk; open is unfilled.
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
        HabitDayState.done => kAccent,
        HabitDayState.skipped => kCaution,
        HabitDayState.open => kInkFaint,
      };
}

/// The day's tick: a rounded box that fills when the habit is done, carries a
/// slash when skipped, and is an empty outline while the day is still open.
///
/// It animates and it fires a haptic, because this is the app's one gesture. It
/// also draws from [done] rather than from the database, so the row can flip
/// under the finger and let the write settle behind it.
class HabitCheck extends StatelessWidget {
  final HabitDayState state;
  final VoidCallback onTap;

  const HabitCheck({super.key, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = state == HabitDayState.done;
    final skipped = state == HabitDayState.skipped;
    return InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      radius: kTapTarget / 2,
      child: SizedBox(
        width: kTapTarget,
        height: kTapTarget,
        child: Center(
          child: AnimatedContainer(
            duration: motion(context, kDurFast),
            curve: kCurve,
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: done ? kAccent : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: done
                    ? kAccent
                    : skipped
                        ? kCaution
                        : kHairline,
                width: 1.5,
              ),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : skipped
                      ? const Icon(Icons.remove, size: 14, color: kCaution)
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The streak count chip: a flame with the current run, a restart arrow when
/// the run is over but history exists, or the negative count once the habit has
/// been idle past the break threshold.
///
/// The number is the loudest thing on the row, which is the point of the app.
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
    final broken = negativeStreak < 0;
    final color = broken ? kDanger : kAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kGapSm, vertical: 3),
      decoration: BoxDecoration(
        color: broken ? kDanger.withValues(alpha: 0.08) : kAccentDim,
        borderRadius: BorderRadius.circular(kRadiusChip),
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
            size: 13,
            color: broken ? kDanger : currentStreak > 0 ? kAccent : kInkFaint,
          ),
          const SizedBox(width: kGapXs),
          Text('${broken ? negativeStreak : currentStreak}',
              style: kTypeNumber.copyWith(fontSize: 15, color: color)),
          // Show the record alongside the current run only when it is better.
          if (!broken && longestStreak > currentStreak)
            Text(' / $longestStreak',
                style: kTypeMetaNum.copyWith(
                    color: kAccent.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

/// One row in the habits list: the day's tick, the name, an at-risk warning,
/// the streak badge, and the date the current run started.
class HabitTile extends StatelessWidget {
  final Map<String, dynamic> habit;

  /// Tapping the tick: completes, or un-skips a skipped habit.
  final VoidCallback onToggle;

  /// Tapping the row opens the detail sheet.
  final VoidCallback onOpen;

  /// Overrides today's state while a write is in flight, so the tick responds to
  /// the finger instead of to sqflite.
  final HabitDayState? pending;

  const HabitTile({
    super.key,
    required this.habit,
    required this.onToggle,
    required this.onOpen,
    this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final state = pending ?? HabitDayState.of(habit);
    final start = habit['streak_start_date'];

    final badge = StreakBadge(
      currentStreak: habit['current_streak'] as int,
      longestStreak: habit['longest_streak'] as int,
      negativeStreak: habit['negative_streak'] as int,
    );

    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kGapSm, kGapSm, kGapMd, kGapSm),
          child: Row(
            children: [
              HabitCheck(state: state, onTap: onToggle),
              const SizedBox(width: kGapSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      habit['name'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: kTypeKr.copyWith(
                        decoration: state == HabitDayState.done
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: kInkFaint,
                        color: state == HabitDayState.open ? kInk : kInkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      start != null
                          ? 'Since ${fmtDayMonth(DateTime.parse(start.toString()))}'
                          : 'No active streak',
                      style: kTypeMeta,
                    ),
                  ],
                ),
              ),
              if (state == HabitDayState.open && habit['streak_at_risk'] == true)
                const Padding(
                  padding: EdgeInsets.only(right: kGapSm),
                  child: Tooltip(
                    message: 'Streak resets tomorrow',
                    child: Icon(Icons.warning_amber_rounded,
                        color: kCaution, size: 18),
                  ),
                ),
              if (badge.isVisible) badge,
            ],
          ),
        ),
      ),
    );
  }
}
