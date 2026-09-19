import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';

void main() {
  test('former department heads retain read-only review history access', () {
    final access = LocatorReviewerAccess.fromJson(const {
      'isDeptHead': true,
      'canReviewPending': false,
      'hasReviewHistory': true,
    });

    expect(access.canAccessReviewSection, isTrue);
    expect(access.canReviewPending, isFalse);
    expect(access.hasReviewHistory, isTrue);
  });

  test('legacy capability responses remain supported', () {
    final access = LocatorReviewerAccess.fromJson(const {'isDeptHead': true});

    expect(access.canAccessReviewSection, isTrue);
    expect(access.canReviewPending, isTrue);
    expect(access.hasReviewHistory, isFalse);
  });
}
