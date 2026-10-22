import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/access_check.dart';

void main() {
  test(
    'temporary failures preserve verified access and initial unknown state',
    () async {
      for (final status in [null, 429, 500, 503]) {
        final result = await fetchAccessCheck(
          () async => throw DioException(
            requestOptions: RequestOptions(path: '/access'),
            type: status == null
                ? DioExceptionType.connectionTimeout
                : DioExceptionType.badResponse,
            response: status == null
                ? null
                : Response(
                    requestOptions: RequestOptions(path: '/access'),
                    statusCode: status,
                  ),
          ),
        );
        expect(result, isNull);
        bool? allowed = true;
        if (result != null) allowed = result['allowed'] == true;
        expect(allowed, isTrue);
      }
      expect(
        await fetchAccessCheck(() async => throw StateError('unavailable')),
        isNull,
      );
    },
  );
  test(
    'successful revocation and explicit authentication denial replace access',
    () async {
      expect(await fetchAccessCheck(() async => {'allowed': false}), {
        'allowed': false,
      });
      expect(await fetchAccessCheck(() async => {'allowed': true}), {
        'allowed': true,
      });
      for (final status in [401, 403]) {
        final result = await fetchAccessCheck(
          () async => throw DioException(
            requestOptions: RequestOptions(path: '/access'),
            response: Response(
              requestOptions: RequestOptions(path: '/access'),
              statusCode: status,
            ),
          ),
        );
        expect(result, isEmpty);
      }
      expect(await fetchAccessCheck(() async => null), isNull);
    },
  );
}
