import 'package:dio/dio.dart';

import 'client_device_header.dart';
import 'config.dart';
import 'token_storage.dart';

/// HTTP client for the HRMS backend API.
/// Attaches access JWT from [TokenStorage] and refreshes via [POST /auth/refresh] on 401.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio _dio;

  /// Single in-flight refresh so concurrent 401s share one refresh call.
  static Future<bool>? _refreshInFlight;

  Dio get dio => _dio;

  void init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.instance.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          try {
            options.headers['X-HRMS-Device'] = await ClientDeviceHeader.build();
          } catch (_) {}
          return handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final opts = error.requestOptions;

          if (status != 401) {
            return handler.next(error);
          }
          if (opts.extra['skipAuthRefresh'] == true) {
            return handler.next(error);
          }

          final path = opts.path;
          if (path == '/auth/refresh' ||
              path == '/auth/login' ||
              path == '/auth/register') {
            await TokenStorage.instance.clearAllTokens();
            return handler.next(error);
          }
          if (opts.extra['_authRetried'] == true) {
            await TokenStorage.instance.clearAllTokens();
            return handler.next(error);
          }

          final refreshed = await _refreshSessionShared();
          if (!refreshed) {
            await TokenStorage.instance.clearAllTokens();
            return handler.next(error);
          }

          final access = await TokenStorage.instance.getToken();
          if (access == null || access.isEmpty) {
            await TokenStorage.instance.clearAllTokens();
            return handler.next(error);
          }

          final next = opts.copyWith(
            headers: Map<String, dynamic>.from(opts.headers)
              ..['Authorization'] = 'Bearer $access',
            extra: Map<String, dynamic>.from(opts.extra)
              ..['_authRetried'] = true,
          );

          try {
            final response = await _dio.fetch(next);
            return handler.resolve(response);
          } catch (e) {
            if (e is DioException) {
              return handler.next(e);
            }
            rethrow;
          }
        },
      ),
    );
  }

  static Future<bool> _refreshSessionShared() {
    _refreshInFlight ??= _performRefresh().whenComplete(
      () => _refreshInFlight = null,
    );
    return _refreshInFlight!;
  }

  static Future<bool> _performRefresh() async {
    final refresh = await TokenStorage.instance.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final deviceHeader = await ClientDeviceHeader.build();
      final plain = Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 45),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-HRMS-Device': deviceHeader,
          },
        ),
      );

      final res = await plain.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );

      final data = res.data;
      if (data == null) return false;
      final access = data['token'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (access == null || access.isEmpty) return false;

      await TokenStorage.instance.setTokens(
        access: access,
        refresh: newRefresh,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// GET request. [path] is relative to base URL (e.g. '/auth/me').
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// POST request.
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// PUT request.
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// PATCH request.
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// DELETE request.
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Upload a file (e.g. avatar) as multipart. [filePath] is the local path.
  /// [fieldName] is the form field name (backend expects 'file' for avatar).
  Future<Response<T>> uploadFile<T>(
    String path, {
    required String filePath,
    String? fileName,
    String fieldName = 'file',
    Map<String, dynamic>? extraFields,
    Options? options,
  }) async {
    final formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath, filename: fileName),
      ...?extraFields,
    });
    return _dio.post<T>(
      path,
      data: formData,
      options: _multipartOptions(options),
    );
  }

  /// Upload from bytes (e.g. from file_picker). [fileName] is used for the part.
  Future<Response<T>> uploadBytes<T>(
    String path, {
    required List<int> bytes,
    required String fileName,
    String fieldName = 'file',
    Map<String, dynamic>? extraFields,
    Options? options,
  }) async {
    final formData = FormData.fromMap({
      fieldName: MultipartFile.fromBytes(bytes, filename: fileName),
      ...?extraFields,
    });
    return _dio.post<T>(
      path,
      data: formData,
      options: _multipartOptions(options),
    );
  }

  /// Base client defaults to JSON; multipart must not send application/json.
  static Options _multipartOptions(Options? options) {
    final merged = Map<String, dynamic>.from(options?.headers ?? {});
    merged.remove(Headers.contentTypeHeader);
    return (options ?? Options()).copyWith(
      contentType: 'multipart/form-data',
      headers: merged,
    );
  }
}
