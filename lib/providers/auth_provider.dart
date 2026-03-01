import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central auth state. Listen to Supabase auth changes and expose current user
/// plus helpers (displayName, email, avatarPath). Call [refreshUser] after
/// profile/avatar updates so UI using [AuthProvider] stays in sync.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _user = Supabase.instance.client.auth.currentUser;
    Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthStateChange);
  }

  User? _user;

  User? get user => _user;

  /// Display name from user_metadata['full_name'] or email prefix.
  String get displayName {
    if (_user == null) return '';
    final name = _user!.userMetadata?['full_name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    return _user!.email?.split('@').first ?? '';
  }

  String get email => _user?.email ?? '';

  /// Storage path for avatar from user_metadata['avatar_path'].
  String? get avatarPath =>
      _user?.userMetadata?['avatar_path'] as String?;

  void _onAuthStateChange(AuthState data) {
    final newUser = data.session?.user;
    if (_user?.id != newUser?.id) {
      _user = newUser;
      notifyListeners();
    }
  }

  /// Refetch current user from Supabase (e.g. after updating profile or avatar).
  Future<void> refreshUser() async {
    try {
      final response = await Supabase.instance.client.auth.getUser();
      final newUser = response.user;
      if (_user?.id != newUser?.id || _user?.userMetadata != newUser?.userMetadata) {
        _user = newUser;
        notifyListeners();
      }
    } catch (_) {
      // Keep existing state on error
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    _user = null;
    notifyListeners();
  }
}
