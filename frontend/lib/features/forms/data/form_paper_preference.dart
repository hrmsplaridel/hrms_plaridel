import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, on this device, the paper size chosen for each printable form.
class FormPaperPreference {
  const FormPaperPreference._();

  static String _key(String module, String formKey) =>
      'form_paper_size.$module.$formKey';

  static Future<String?> load(String module, String formKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(module, formKey));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String module,
    String formKey,
    String paperSizeId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(module, formKey), paperSizeId);
    } catch (_) {}
  }
}
