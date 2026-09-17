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

DioException _networkError(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/api/leave/submit'),
  type: type,
);

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

  test('identifies an unconfirmed offline leave submission', () {
    expect(
      userFacingApiError(
        _networkError(DioExceptionType.connectionError),
        operationMayHaveCompleted: true,
      ),
      'No internet connection or the server is unreachable. Submission was not confirmed. Refresh My Leave before submitting again.',
    );
  });

  test('identifies an unconfirmed timed-out leave submission', () {
    expect(
      userFacingApiError(
        _networkError(DioExceptionType.receiveTimeout),
        operationMayHaveCompleted: true,
      ),
      'Submission timed out and was not confirmed. Refresh My Leave before submitting again.',
    );
  });

  test('does not hide a backend response for a failed submission', () {
    expect(
      userFacingApiError(
        _apiError(
          statusCode: 409,
          data: {'error': 'A leave request already covers these dates.'},
        ),
        operationMayHaveCompleted: true,
      ),
      'A leave request already covers these dates.',
    );
  });
}
