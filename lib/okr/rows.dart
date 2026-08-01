import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'log_value.dart';

/// The emoji standing for an area. Areas created before the picker existed have
/// none, and a heading with a hole in it reads as a bug rather than as an
/// absence.
String areaIcon(Map<String, dynamic> area) => area['icon'] ?? '🎯';

/// An area as a quiet uppercase heading, not a row you can enter — an area has
/// no properties worth a screen. The rule beneath is what anchors the heading to
/// the cards under it. Its rollup is a percent rather than a bar: a bar here
/// would read as one more row in the list.
///
/// The label is the smallest, faintest type in the tree, and the rollup beside
/// it is not: a heading marks a section, the number is a fact about it. Sharing
/// one style made the two compete, and put the uppercase tracking on a percent.
///
/// Shared by the OKR tree and the Record page, which show the same outline.
/// Gestures belong to the caller — the tree wraps this in the long-press menu,
/// the Record page wraps it in nothing.
class AreaHeading extends StatelessWidget {
  final Map<String, dynamic> area;

  const AreaHeading(this.area, {super.key});

  @override
  Widget build(BuildContext context) {
    final score = area['score'] as double?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGapMd, kGapLg, kGapMd, kGapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A fixed column, so labels line up across areas however wide the
              // emoji is. Left-aligned inside it: the emoji is what stands in
              // the shared left edge that the tree's titles keep.
              SizedBox(
                width: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(areaIcon(area),
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: kGapSm),
              Expanded(
                child: Text((area['name'] as String).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kTypeAreaLabel),
              ),
              if (score != null)
                Text(fmtPct(score),
                    style: kTypeMetaNum.copyWith(
                        color: kInk, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: kGapSm),
          const AppRule.flush(),
        ],
      ),
    );
  }
}

/// `3x10 / 3x12 reps`, or just the current value when the key result is
/// track-only. Both sides read as the notation that was typed. Scales down
/// rather than wrapping.
///
/// The current value carries the weight and the ink; the target and unit recede
/// to [kTypeUnit]. It is one `Text.rich` rather than several `Text`s so the cell
/// still reads as one string — to the eye, and to anything looking for "1 / 20".
///
/// Shared by the OKR tree's rows and the key-result detail screen, so the number
/// a key result shows can't differ between the two places it's read.
class KrValueCell extends StatelessWidget {
  final Map<String, dynamic> kr;

  /// How much width the number may claim. The tree passes less than the default
  /// because there it shares a row with a title; the detail screen, which has
  /// the row to itself, takes the default.
  final double maxWidth;

  /// One step down, matching the [DeltaText] beneath it. The objective fill page
  /// states the number beside a field that has to stay comfortably tappable, and
  /// the number is the half that can afford to give.
  final bool dense;

  /// Matches the size of the title the cell sits beside — 15 on the detail
  /// screen, 14 in the tree, 13 when [dense]. Equal sizes are what keeps the two
  /// on one baseline: a `FittedBox` reports no baseline to align against.
  final double? fontSize;

  const KrValueCell(this.kr,
      {super.key, this.maxWidth = 140, this.dense = false, this.fontSize});

  @override
  Widget build(BuildContext context) {
    final size = fontSize ?? (dense ? 13 : 14);
    final value = kTypeNumber.copyWith(fontSize: size);
    final rest = kTypeUnit.copyWith(fontSize: size - 1);
    final unit = (kr['unit'] ?? '') as String;
    final delta = krDelta(kr);
    return ConstrainedBox(
      // The default fits "30 / 500 reps"; longer notation scales down.
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: currentLabel(kr), style: value),
                if (kr['target'] != null)
                  TextSpan(text: ' / ${targetLabel(kr)}', style: rest),
                if (unit.isNotEmpty) TextSpan(text: ' $unit', style: rest),
              ]),
              maxLines: 1,
            ),
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
/// the screen it opens must not read differently. Here the pair is sized at 15
/// because the key result is the page's subject; in the tree both drop to 14.
class KrSummaryRow extends StatelessWidget {
  final Map<String, dynamic> kr;

  const KrSummaryRow(this.kr, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(kr['title'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: kTypeObjective),
            ),
            const SizedBox(width: kGapSm),
            KrValueCell(kr, fontSize: 15),
          ],
        ),
        if (kr['target'] != null) ...[
          const SizedBox(height: kGapSm),
          ScoreBar(kr['score'] as double? ?? 0,
              label: kr['title'] as String, height: kBarThick),
        ],
      ],
    );
  }
}
