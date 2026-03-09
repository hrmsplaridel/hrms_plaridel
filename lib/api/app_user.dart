/// User model from API (replaces Supabase User).
/// Used by [AuthProvider]; matches backend /auth/me and /auth/login response.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.role,
    this.fullName,
    this.avatarPath,
    this.contactNumber,
  });

  final String id;
  final String email;
  final String? role;
  final String? fullName;
  final String? avatarPath;
  final String? contactNumber;

  /// For compatibility with code that used Supabase User.userMetadata.
  /// e.g. userMetadata['full_name'], userMetadata['avatar_path'], userMetadata['phone'].
  Map<String, dynamic> get userMetadata => {
        if (fullName != null) 'full_name': fullName,
        if (avatarPath != null) 'avatar_path': avatarPath,
        if (contactNumber != null) 'phone': contactNumber,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final meta = json['user_metadata'] as Map<String, dynamic>?;
    return AppUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String?,
      fullName: json['full_name'] as String? ?? meta?['full_name'] as String?,
      avatarPath: json['avatar_path'] as String? ?? meta?['avatar_path'] as String?,
      contactNumber: json['contact_number'] as String? ?? meta?['phone'] as String?,
    );
  }
}
