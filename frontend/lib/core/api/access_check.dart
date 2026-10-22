import 'package:dio/dio.dart';

/// Null means access could not be checked; callers retain their current state.
/// An empty result represents explicit authentication/authorization rejection.
Future<Map<String, dynamic>?> fetchAccessCheck(
  Future<Map<String, dynamic>?> Function() load,
) async {
  try {
    return await load();
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) return {};
    return null;
  } catch (_) {
    return null;
  }
}
