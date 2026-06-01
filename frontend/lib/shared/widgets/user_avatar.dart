import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/avatar_url.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

/// Reusable avatar that shows the user's profile image (from API /api/files/avatar/:userId)
/// when available, and falls back to the orange/person icon when not.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.userId,
    this.avatarPath,
    required this.radius,
    this.backgroundColor,
    this.placeholderIconColor,
  });

  /// When omitted, uses the signed-in user from [AuthProvider].
  final String? userId;

  /// Storage path from `avatar_path` (e.g. `avatars/<uuid>.jpg`). When omitted,
  /// uses [AuthProvider.avatarPath] for the resolved [userId].
  final String? avatarPath;
  final double radius;
  final Color? backgroundColor;
  final Color? placeholderIconColor;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final resolvedUserId = (userId ?? auth.user?.id ?? '').trim();
    final resolvedPath = () {
      final passed = (avatarPath ?? '').trim();
      if (passed.isNotEmpty) return passed;
      if (userId == null || userId == auth.user?.id) {
        return (auth.avatarPath ?? '').trim();
      }
      return passed;
    }();

    final bg = backgroundColor ?? AppTheme.primaryNavy;
    final iconColor = placeholderIconColor ?? Colors.white;
    final diameter = radius * 2;

    if (resolvedUserId.isEmpty || resolvedPath.isEmpty) {
      return _placeholder(radius, bg, iconColor);
    }

    final imageUrl = userAvatarImageUrl(
      resolvedUserId,
      avatarPath: resolvedPath,
    );

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg.withValues(alpha: 0.15),
      child: ClipOval(
        child: Image.network(
          imageUrl,
          key: ValueKey(imageUrl),
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person_rounded, color: iconColor, size: radius * 1.2),
        ),
      ),
    );
  }

  Widget _placeholder(double radius, Color bg, Color iconColor) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Icon(Icons.person_rounded, color: iconColor, size: radius * 1.2),
    );
  }
}
