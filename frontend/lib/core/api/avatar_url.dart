import 'config.dart';

/// Builds the HTTP URL for [userId]'s avatar served by the API.
///
/// [avatarPath] (e.g. `avatars/<uuid>.jpg`) is appended as a cache-buster query
/// param so clients reload the image after upload without a stale bitmap.
String userAvatarImageUrl(
  String userId, {
  String? avatarPath,
  int? cacheRevision,
}) {
  final id = userId.trim();
  if (id.isEmpty) return '';
  final base = '${ApiConfig.baseUrl}/api/files/avatar/$id';
  final path = (avatarPath ?? '').trim();
  if (path.isEmpty) return base;
  final v = Uri.encodeComponent(path);
  if (cacheRevision != null) {
    return '$base?v=$v&r=$cacheRevision';
  }
  return '$base?v=$v';
}
