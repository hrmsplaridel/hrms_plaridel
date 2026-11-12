import 'package:shared_preferences/shared_preferences.dart';

/// In-app notification categories that the HRMS actually creates today.
///
/// Keep in sync with backend inserts into `user_notifications.category`
/// (leave, locator, overtime, recruitment, training, form_signature, general).
abstract final class NotificationPreferenceStore {
  static const prefPrefix = 'settings_notif_cat_v2_';

  /// Legacy keys from the old cosmetic settings panel (migrated once).
  static const legacyLeaveKey = 'settings_notif_leave_v1';

  static const leave = 'leave';
  static const locator = 'locator';
  static const overtime = 'overtime';
  static const recruitment = 'recruitment';
  static const training = 'training';
  static const formSignature = 'form_signature';
  static const general = 'general';

  static const List<String> managedCategories = [
    leave,
    locator,
    overtime,
    recruitment,
    training,
    formSignature,
    general,
  ];

  static String prefKey(String category) => '$prefPrefix$category';

  static Future<Map<String, bool>> load() async {
    final p = await SharedPreferences.getInstance();
    final out = <String, bool>{};
    for (final cat in managedCategories) {
      final key = prefKey(cat);
      if (p.containsKey(key)) {
        out[cat] = p.getBool(key) ?? true;
        continue;
      }
      // One-time migration for leave from the previous settings panel.
      if (cat == leave && p.containsKey(legacyLeaveKey)) {
        out[cat] = p.getBool(legacyLeaveKey) ?? true;
        await p.setBool(key, out[cat]!);
        continue;
      }
      out[cat] = true;
    }
    return out;
  }

  static Future<void> setCategory(String category, bool enabled) async {
    if (!managedCategories.contains(category)) return;
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey(category), enabled);
  }

  /// Unknown / future categories stay visible so we never hide important alerts.
  static bool isCategoryEnabled(Map<String, bool> prefs, String category) {
    final key = category.trim().toLowerCase();
    if (key.isEmpty) return true;
    if (!prefs.containsKey(key)) return true;
    return prefs[key] ?? true;
  }
}
