import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';

DioException _apiError({Object? data, int? statusCode, String? message}) {
  final options = RequestOptions(path: '/api/attendance-policies');
  return DioException(
    requestOptions: options,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: statusCode,
            data: data,
          ),
    message: message,
    type: DioExceptionType.badResponse,
  );
}

void main() {
  test('uses a structured backend error message', () {
    expect(
      userFacingApiError(
        _apiError(
          statusCode: 409,
          data: {'error': 'Policy has already been used.'},
        ),
      ),
      'Policy has already been used.',
    );
  });

  test('handles a non-JSON gateway response without throwing', () {
    expect(
      userFacingApiError(
        _apiError(
          statusCode: 502,
          data: '<html>Bad Gateway</html>',
          message: 'Bad response',
        ),
      ),
      'Server is temporarily unavailable. Please try again shortly.',
    );
  });

  test('handles an empty error response without throwing', () {
    expect(
      userFacingApiError(_apiError(statusCode: 500)),
      'Server error. Please try again later.',
    );
  });
}
