import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/api/avatar_url.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

/// Reusable avatar that shows the user's profile image (from API /api/files/avatar/:userId)
/// when available, and falls back to the HRMS [logo.png] filling the circle.
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

  static const _logoAsset = 'assets/images/logo.png';

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

    final bg = backgroundColor ?? Colors.white;
    final diameter = radius * 2;

    if (resolvedUserId.isEmpty || resolvedPath.isEmpty) {
      return _circularImage(
        diameter: diameter,
        background: bg,
        child: Image.asset(
          _logoAsset,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _personFallback(radius),
        ),
      );
    }

    final imageUrl = userAvatarImageUrl(
      resolvedUserId,
      avatarPath: resolvedPath,
    );

    return _circularImage(
      diameter: diameter,
      background: bg,
      child: Image.network(
        imageUrl,
        key: ValueKey(imageUrl),
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => Image.asset(
          _logoAsset,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _personFallback(radius),
        ),
      ),
    );
  }

  Widget _circularImage({
    required double diameter,
    required Color background,
    required Widget child,
  }) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _personFallback(double radius) {
    return ColoredBox(
      color: AppTheme.primaryNavy,
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: placeholderIconColor ?? Colors.white,
          size: radius * 1.2,
        ),
      ),
    );
  }
}
