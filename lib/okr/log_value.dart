import '../db_helper.dart';
import '../ui/kit.dart';

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

/// The one-tap "+1" for COUNT-style key results.
Future<void> bumpKr(Map<String, dynamic> kr) {
  return DBHelper().logMeasurement(
    keyResultId: kr['trackable_id'] == null ? kr['id'] as String : null,
    trackableId: kr['trackable_id'] as String?,
    value: 1,
  );
}
