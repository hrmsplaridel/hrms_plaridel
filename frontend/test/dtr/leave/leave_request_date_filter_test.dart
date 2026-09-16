import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/utils/leave_request_date_filter.dart';

void main() {
  final septemberStart = DateTime(2026, 9, 1);
  final septemberEnd = DateTime(2026, 9, 30);

  test('includes a request crossing the beginning of the filter', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 8, 30),
        requestEnd: DateTime(2026, 9, 2),
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isTrue,
    );
  });

  test('includes a request crossing the end of the filter', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 9, 29),
        requestEnd: DateTime(2026, 10, 2),
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isTrue,
    );
  });

  test('includes requests touching either inclusive boundary', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 8, 28),
        requestEnd: septemberStart,
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isTrue,
    );
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: septemberEnd,
        requestEnd: DateTime(2026, 10, 2),
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isTrue,
    );
  });

  test('excludes requests entirely before or after the filter', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 8, 1),
        requestEnd: DateTime(2026, 8, 31),
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isFalse,
    );
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 10, 1),
        requestEnd: DateTime(2026, 10, 2),
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isFalse,
    );
  });

  test('supports a single filter boundary', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 8, 30),
        requestEnd: DateTime(2026, 9, 2),
        filterStart: septemberStart,
        filterEnd: null,
      ),
      isTrue,
    );
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 10, 1),
        requestEnd: DateTime(2026, 10, 2),
        filterStart: null,
        filterEnd: septemberEnd,
      ),
      isFalse,
    );
  });

  test('treats one missing request endpoint as a single-day request', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: null,
        requestEnd: DateTime(2026, 9, 15, 23, 30),
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isTrue,
    );
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 8, 31),
        requestEnd: null,
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isFalse,
    );
  });

  test('keeps an undated legacy request visible', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: null,
        requestEnd: null,
        filterStart: septemberStart,
        filterEnd: septemberEnd,
      ),
      isTrue,
    );
  });

  test('compares calendar dates without time-of-day differences', () {
    expect(
      leaveRequestOverlapsDateFilter(
        requestStart: DateTime(2026, 9, 30, 23, 59),
        requestEnd: DateTime(2026, 9, 30, 23, 59),
        filterStart: DateTime(2026, 9, 30),
        filterEnd: DateTime(2026, 9, 30),
      ),
      isTrue,
    );
  });
}
