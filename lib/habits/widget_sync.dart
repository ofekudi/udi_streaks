import 'package:home_widget/home_widget.dart';

import '../core/dates.dart';
import '../db_helper.dart';

/// Pushes today's progress to the Android home-screen widget.
///
/// Previously a private method on the habits screen's State, which meant the
/// only way to refresh the widget was to be looking at that screen. Keeping it
/// standalone lets any mutation trigger a resync.
class WidgetSync {
  /// Must match the `AppWidgetProvider` registered in AndroidManifest.xml.
  static const String providerName = 'StreakWidgetProvider';

  const WidgetSync();

  /// Recomputes the completed/total counts and hands them to the widget.
  ///
  /// Best effort: there is no widget on iOS and none may be placed on Android,
  /// so a failure here must never surface to the user or block a habit write.
  Future<void> push() async {
    try {
      final counts = await DBHelper().getTodayStreakCounts();
      await HomeWidget.saveWidgetData<int>('completed', counts['completed']!);
      await HomeWidget.saveWidgetData<int>('total', counts['total']!);
      await HomeWidget.saveWidgetData<String>(
          'lastUpdateDate', ymd(DateTime.now()));
      await HomeWidget.updateWidget(name: providerName);
    } catch (_) {
      // Nothing actionable — the widget simply keeps its previous numbers.
    }
  }
}
