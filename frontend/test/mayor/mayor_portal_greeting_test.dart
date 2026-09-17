import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/shared/utils/time_greeting.dart';

void main() {
  test('mayor portal greeting uses time of day and Mayor title', () {
    expect(
      mayorPortalGreeting(DateTime(2026, 9, 15, 8, 13)),
      'Good Morning, Mayor',
    );
    expect(
      mayorPortalGreeting(DateTime(2026, 9, 15, 14, 0)),
      'Good Afternoon, Mayor',
    );
    expect(
      mayorPortalGreeting(DateTime(2026, 9, 15, 19, 0)),
      'Good Evening, Mayor',
    );
  });
}
