import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notifies when [setPreferredViewTag] runs so all pin icons stay in sync (only one home).
class StartupHomePinListenable extends ChangeNotifier {
  StartupHomePinListenable._();
  static final instance = StartupHomePinListenable._();

  void notifyPinChanged() => notifyListeners();
}

/// Which screen opens after startup when the user pinned a "Views" page (`landing` = Default).
///
/// Legacy key `pt_startup_prefer_customized_v1` is synced when setting preference for compatibility.
class StartupViewStorage {
  static const _kViewKeyV2 = 'pt_startup_view_v2';
  static const String viewLanding = 'landing';
  static const String viewOverview = 'overview';
  static const String viewProject = 'project';

  /// Canonical tags: [viewLanding], [viewOverview], [viewProject].
  static Future<String> getPreferredViewTag() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kViewKeyV2)?.trim();
    final v = raw ?? '';
    if (v == viewOverview || v == viewProject || v == viewLanding) {
      return v;
    }
    final oldPinned = p.getBool('pt_startup_prefer_customized_v1') ?? false;
    return oldPinned ? viewOverview : viewLanding;
  }

  /// Persists startup route and mirrors legacy bool (`overview` ↔ pinned Customized).
  static Future<void> setPreferredViewTag(String tag) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kViewKeyV2, tag);
    await p.setBool(
      'pt_startup_prefer_customized_v1',
      tag == viewOverview,
    );
    StartupHomePinListenable.instance.notifyPinChanged();
  }

  /// Legacy API — prefer [getPreferredViewTag].
  static Future<bool> isCustomizedPinned() async {
    final t = await getPreferredViewTag();
    return t == viewOverview;
  }

  /// Legacy API — prefer [setPreferredViewTag].
  static Future<void> setPreferCustomized(bool v) async {
    await setPreferredViewTag(v ? viewOverview : viewLanding);
  }
}
