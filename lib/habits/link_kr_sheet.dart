import 'package:flutter/material.dart';

import '../ui/kit.dart';

/// The picker for "Link to OKR": the COUNT key results a habit can feed.
///
/// Presentation only — the caller loads the rows and performs the link, as the
/// rest of the habits tab does. Returns the chosen key result id, or null when
/// dismissed.
Future<String?> showLinkKrSheet(
  BuildContext context,
  List<Map<String, dynamic>> keyResults, {
  required String habitId,
}) {
  return showAppSheet<String>(
    context,
    title: 'Link to OKR',
    heightFactor: 0.7,
    builder: (sheetContext) => keyResults.isEmpty
        ? const _Empty()
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final kr in keyResults)
                _KrRow(
                  kr: kr,
                  habitId: habitId,
                  onTap: () => Navigator.pop(sheetContext, kr['id'] as String),
                ),
            ],
          ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kGapXl),
      child: Column(
        children: [
          Icon(Icons.link_off, size: 40, color: scheme.outline),
          const SizedBox(height: kGapMd),
          // States the constraint, which is the part that can't be seen: an
          // empty sheet otherwise reads as broken.
          Text(
            'No Count key result on an active objective',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }
}

/// One key result: its title, the objective beneath it, and the target on the
/// right — the two-line shape the OKR tree uses.
class _KrRow extends StatelessWidget {
  final Map<String, dynamic> kr;
  final String habitId;
  final VoidCallback onTap;

  const _KrRow({required this.kr, required this.habitId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final owner = kr['linked_habit_name'] as String?;
    // A key result already fed by *this* habit is the current link, not a
    // conflict — it just isn't worth re-picking.
    final takenByOther = owner != null && kr['habit_id'] != habitId;

    final target = kr['target_raw'] as String? ??
        (kr['target_value'] == null
            ? null
            : fmtNum(kr['target_value'] as num?));

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !takenByOther,
      leading: Icon(
        takenByOther ? Icons.link : Icons.add_link,
        color: takenByOther ? scheme.outline : scheme.primary,
      ),
      title: Text(
        kr['title'] as String,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        takenByOther
            ? 'Linked to "$owner"'
            : (kr['objective_title'] as String? ?? ''),
        style: TextStyle(
          fontSize: 13,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      trailing: target == null
          ? null
          : Text(
              target,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
      onTap: takenByOther ? null : onTap,
    );
  }
}
