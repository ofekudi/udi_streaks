import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'log_value.dart';

/// `3x10 / 3x12 reps`, or just the current value when the key result is
/// track-only. Both sides read as the notation that was typed. Scales down
/// rather than wrapping.
///
/// Shared by the OKR tree's rows and the key-result detail screen, so the number
/// a key result shows can't differ between the two places it's read.
class KrValueCell extends StatelessWidget {
  final Map<String, dynamic> kr;

  const KrValueCell(this.kr, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = kr['unit'] ?? '';
    final text = kr['target'] != null
        ? '${currentLabel(kr)} / ${targetLabel(kr)} $unit'
        : '${currentLabel(kr)} $unit';
    final delta = krDelta(kr);
    return ConstrainedBox(
      // Fits "30 / 500 reps · 3x10"; longer text scales down.
      constraints: const BoxConstraints(maxWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(text.trim(),
                maxLines: 1,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (delta != null) DeltaText(delta, down: krWantsDown(kr)),
        ],
      ),
    );
  }
}

/// The tree's key-result row, standing on its own at the top of the detail
/// screen: title, the bar beneath it, and the value in the right-hand column
/// beside both. The screen it heads says everything else about the key result,
/// so it states the number and nothing more.
class KrSummaryRow extends StatelessWidget {
  final Map<String, dynamic> kr;

  const KrSummaryRow(this.kr, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kr['title'],
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (kr['target'] != null) ...[
                const SizedBox(height: kGapSm),
                ScoreBar(kr['score'] as double? ?? 0, down: krWantsDown(kr)),
              ],
            ],
          ),
        ),
        const SizedBox(width: kGapSm),
        KrValueCell(kr),
      ],
    );
  }
}
