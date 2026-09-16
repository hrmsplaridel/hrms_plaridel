import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/management/holidays/pages/manage_holiday.dart';

void main() {
  DioException apiError({Object? data, String? message}) {
    final request = RequestOptions(path: '/api/holidays');
    return DioException(
      requestOptions: request,
      response: data == null
          ? null
          : Response<Object?>(requestOptions: request, data: data),
      message: message,
    );
  }

  test('uses a structured backend error message', () {
    final message = holidayApiErrorMessage(
      apiError(data: {'error': 'Holiday overlaps an existing record.'}),
      'Fallback',
    );

    expect(message, 'Holiday overlaps an existing record.');
  });

  test('uses the Dio message for a non-JSON response', () {
    final message = holidayApiErrorMessage(
      apiError(data: '<html>Bad Gateway</html>', message: 'Bad response: 502'),
      'Fallback',
    );

    expect(message, 'Bad response: 502');
  });

  test('uses the fallback when the response has no useful message', () {
    final message = holidayApiErrorMessage(
      apiError(),
      'Unable to save holiday.',
    );

    expect(message, 'Unable to save holiday.');
  });
}
