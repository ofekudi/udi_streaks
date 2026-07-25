import '../db_helper.dart';
import '../ui/kit.dart';
import 'scoring.dart';

/// What to tell the user when [logKrValue] rejects their text.
const kLogValueHelp = 'Enter a number — e.g. 30, 3x10 or 10,9,8';

/// Parses [raw] and writes one measurement for [kr]. Returns false when the
/// text isn't something [parseValue] understands — the caller shows
/// [kLogValueHelp]. The raw notation ("3x10", "10,9,8") is kept in `note` so
/// the history remembers how the number was entered.
///
/// Shared by the Record page and the key-result detail screen, which offer the
/// same logging affordance.
Future<bool> logKrValue(Map<String, dynamic> kr, String raw) async {
  final v = parseValue(raw);
  if (v == null) return false;
  await DBHelper().logMeasurement(
    keyResultId: kr['trackable_id'] == null ? kr['id'] as String : null,
    trackableId: kr['trackable_id'] as String?,
    value: v,
    unit: kr['unit'] as String?,
    note: raw == fmtNum(v) ? null : raw,
  );
  return true;
}

/// [kr]'s `target_raw` as a ` · 3x10` suffix, empty when it's null. Display
/// only — scoring runs on the parsed `target_value`.
String targetNotation(Map<String, dynamic> kr) {
  final raw = kr['target_raw'] as String?;
  return raw == null ? '' : ' · $raw';
}

/// [kr]'s `baseline_raw` or the parsed `baseline_value`, empty when it has no
/// starting point.
String baselineLabel(Map<String, dynamic> kr) {
  final raw = kr['baseline_raw'] as String?;
  if (raw != null) return raw;
  final value = kr['baseline_value'] as num?;
  return value == null ? '' : fmtNum(value);
}

/// [wantsDown] for a key-result row.
bool krWantsDown(Map<String, dynamic> kr) => wantsDown(
      baseline: (kr['baseline_value'] as num?)?.toDouble(),
      target: (kr['target'] as num?)?.toDouble(),
      direction: (kr['direction'] ?? 'UP') as String,
    );

/// How much the newest entry moved from the one before it, or null when there's
/// nothing to compare against — see [previousValue].
double? krDelta(Map<String, dynamic> kr) {
  final previous = (kr['previous'] as num?)?.toDouble();
  final current = (kr['current'] as num?)?.toDouble();
  if (previous == null || current == null) return null;
  return current - previous;
}

/// The one-tap "+1" for COUNT-style key results.
Future<void> bumpKr(Map<String, dynamic> kr) {
  return DBHelper().logMeasurement(
    keyResultId: kr['trackable_id'] == null ? kr['id'] as String : null,
    trackableId: kr['trackable_id'] as String?,
    value: 1,
  );
}
