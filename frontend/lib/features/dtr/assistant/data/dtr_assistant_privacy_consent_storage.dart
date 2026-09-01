import 'package:shared_preferences/shared_preferences.dart';

class DtrAssistantPrivacyConsentStorage {
  DtrAssistantPrivacyConsentStorage._();

  static String _key(String userId, String provider, String version) {
    final safeProvider = provider.trim().toLowerCase();
    return 'dtr_assistant_external_ai_consent_${userId}_$safeProvider-$version';
  }

  static Future<bool> hasConsent({
    required String userId,
    required String provider,
    required String version,
  }) async {
    if (userId.trim().isEmpty ||
        provider.trim().isEmpty ||
        version.trim().isEmpty) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId, provider, version)) == true;
  }

  static Future<void> grantConsent({
    required String userId,
    required String provider,
    required String version,
  }) async {
    if (userId.trim().isEmpty ||
        provider.trim().isEmpty ||
        version.trim().isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId, provider, version), true);
  }
}
