import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/notifications/data/notification_preference_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unknown categories stay enabled', () {
    expect(
      NotificationPreferenceStore.isCategoryEnabled(const {}, 'mystery'),
      isTrue,
    );
  });

  test('managed categories default to enabled then persist', () async {
    final loaded = await NotificationPreferenceStore.load();
    for (final cat in NotificationPreferenceStore.managedCategories) {
      expect(loaded[cat], isTrue);
    }
    await NotificationPreferenceStore.setCategory(
      NotificationPreferenceStore.leave,
      false,
    );
    final again = await NotificationPreferenceStore.load();
    expect(again[NotificationPreferenceStore.leave], isFalse);
    expect(again[NotificationPreferenceStore.locator], isTrue);
  });

  test('migrates legacy leave preference once', () async {
    SharedPreferences.setMockInitialValues({
      NotificationPreferenceStore.legacyLeaveKey: false,
    });
    final loaded = await NotificationPreferenceStore.load();
    expect(loaded[NotificationPreferenceStore.leave], isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(
        NotificationPreferenceStore.prefKey(NotificationPreferenceStore.leave),
      ),
      isFalse,
    );
  });
}
