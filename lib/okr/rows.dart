import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'log_value.dart';

/// An area as a quiet uppercase heading, not a row you can enter — an area has
/// no properties worth a screen. The rule beneath is what anchors the heading to
/// the cards under it. Its rollup is a percent rather than a bar: a bar here
/// would read as one more row in the list.
///
/// Shared by the OKR tree and the Record page, which show the same outline.
/// Gestures belong to the caller — the tree wraps this in the long-press menu,
/// the Record page wraps it in nothing.
class AreaHeading extends StatelessWidget {
  final Map<String, dynamic> area;

  const AreaHeading(this.area, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = area['score'] as double?;
    final label = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapMd, kGapLg, kGapMd, kGapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(area['icon'] ?? '🎯', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: kGapSm),
              Expanded(
                child: Text((area['name'] as String).toUpperCase(),
                    style: label),
              ),
              if (score != null) Text(fmtPct(score), style: label),
            ],
          ),
          const SizedBox(height: kGapSm),
          Divider(
              height: 1,
              thickness: 0.5,
              color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

/// `3x10 / 3x12 reps`, or just the current value when the key result is
/// track-only. Both sides read as the notation that was typed. Scales down
/// rather than wrapping.
///
/// Shared by the OKR tree's rows and the key-result detail screen, so the number
/// a key result shows can't differ between the two places it's read.
class KrValueCell extends StatelessWidget {
  final Map<String, dynamic> kr;

  /// How much width the number may claim. The tree passes less than the default
  /// because there it shares a row with a title; the detail screen, which has
  /// the row to itself, takes the default.
  final double maxWidth;

  /// One step down to `bodySmall`, matching the [DeltaText] beneath it. The
  /// objective fill page states the number beside a field that has to stay
  /// comfortably tappable, and the number is the half that can afford to give.
  final bool dense;

  const KrValueCell(this.kr,
      {super.key, this.maxWidth = 140, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium;
    final unit = kr['unit'] ?? '';
    final text = kr['target'] != null
        ? '${currentLabel(kr)} / ${targetLabel(kr)} $unit'
        : '${currentLabel(kr)} $unit';
    final delta = krDelta(kr);
    return ConstrainedBox(
      // 140 fits "30 / 500 reps · 3x10"; longer text scales down.
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(text.trim(),
                maxLines: 1,
                style: style?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (delta != null) DeltaText(delta, down: krWantsDown(kr)),
        ],
      ),
    );
  }
}

/// The tree's key-result row, standing on its own at the top of the detail
/// screen: title and value on one line, the bar spanning the width beneath
/// them. The screen it heads says everything else about the key result, so it
/// states the number and nothing more.
///
/// Its shape tracks the tree's `_krRow` deliberately — the row you tapped and
/// the screen it opens must not read differently.
class KrSummaryRow extends StatelessWidget {
  final Map<String, dynamic> kr;

  const KrSummaryRow(this.kr, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(kr['title'],
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: kGapSm),
            KrValueCell(kr),
          ],
        ),
        if (kr['target'] != null) ...[
          const SizedBox(height: kGapSm),
          ScoreBar(kr['score'] as double? ?? 0,
              down: krWantsDown(kr), label: kr['title'] as String),
        ],
      ],
    );
  }
}
