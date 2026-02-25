import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../landingpage/constants/app_theme.dart';

const String _avatarBucket = 'avatars';

/// Shows the user's profile image from Supabase Storage when [avatarPath] is set; otherwise a placeholder.
/// Use in top bar, sidebar, and dropdowns so the profile image is visible everywhere.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    this.avatarPath,
    required this.radius,
    this.backgroundColor,
    this.placeholderIconColor,
  });

  /// Storage path from user_metadata['avatar_path'] (e.g. userId/avatar.jpg).
  final String? avatarPath;
  final double radius;
  final Color? backgroundColor;
  final Color? placeholderIconColor;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.avatarPath != null && widget.avatarPath!.isNotEmpty) {
      _loadUrl();
    }
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarPath != oldWidget.avatarPath) {
      if (widget.avatarPath != null && widget.avatarPath!.isNotEmpty) {
        _loadUrl();
      } else {
        setState(() => _imageUrl = null);
      }
    }
  }

  Future<void> _loadUrl() async {
    try {
      final url = await Supabase.instance.client.storage.from(_avatarBucket).createSignedUrl(widget.avatarPath!, 3600);
      if (mounted) setState(() => _imageUrl = url);
    } catch (_) {
      if (mounted) setState(() => _imageUrl = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppTheme.primaryNavy;
    final iconColor = widget.placeholderIconColor ?? Colors.white;
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg.withOpacity(0.2),
        backgroundImage: NetworkImage(_imageUrl!),
        onBackgroundImageError: (_, __) => setState(() => _imageUrl = null),
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      child: Icon(Icons.person_rounded, color: iconColor, size: widget.radius * 1.2),
    );
  }
}
