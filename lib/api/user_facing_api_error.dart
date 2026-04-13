import 'package:dio/dio.dart';

/// Short, human-readable text for snackbars and dialogs (not developer dumps).
String userFacingApiError(Object error) {
  if (error is DioException) {
    return _dioMessage(error);
  }
  if (error is Exception) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      final inner = raw.substring('Exception: '.length).trim();
      if (inner.isNotEmpty) {
        return inner.length <= 280 ? inner : '${inner.substring(0, 277)}…';
      }
    }
  }
  final s = error.toString();
  if (s.length > 200) {
    return '${s.substring(0, 197)}…';
  }
  return s;
}

String _dioMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    for (final key in ['error', 'message', 'detail', 'details']) {
      final v = data[key];
      if (v == null) continue;
      final text = v.toString().trim();
      if (text.isEmpty) continue;
      if (text.length <= 280) return text;
      return '${text.substring(0, 277)}…';
    }
  }

  final code = e.response?.statusCode;
  switch (code) {
    case 400:
      return 'Invalid request. Check your input and try again.';
    case 401:
    case 403:
      return 'You do not have permission for this action.';
    case 404:
      return 'Resource not found.';
    case 409:
      return 'This conflicts with existing data.';
    case 422:
      return 'Validation failed. Check the form and try again.';
    case 429:
      return 'Too many requests. Please wait and try again.';
    case 500:
      return 'Server error. Please try again later.';
    case 502:
    case 503:
    case 504:
      return 'Server is temporarily unavailable. Please try again shortly.';
    default:
      break;
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Request timed out. Check your connection and try again.';
    case DioExceptionType.connectionError:
      return 'No internet connection or the server is unreachable.';
    case DioExceptionType.cancel:
      return 'Request was cancelled.';
    default:
      if (code != null) {
        return 'Request failed (HTTP $code).';
      }
      return 'Something went wrong. Please try again.';
  }
}
