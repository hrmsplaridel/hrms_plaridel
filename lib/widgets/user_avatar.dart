import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../landingpage/constants/app_theme.dart';
import '../providers/auth_provider.dart';

const String _avatarBucket = 'avatars';

/// Reusable avatar that shows the user's uploaded profile image (from Supabase Storage)
/// when available, and falls back to the orange/person icon when not.
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
    _init();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarPath != oldWidget.avatarPath) {
      _init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When no path is passed, use AuthProvider so avatar updates when profile changes.
    if (widget.avatarPath == null || widget.avatarPath!.isEmpty) {
      final providerPath = context.read<AuthProvider>().avatarPath;
      if (providerPath != null && providerPath.isNotEmpty) {
        _loadForPath(providerPath);
      }
    }
  }

  Future<void> _init() async {
    // Prefer the explicit avatarPath passed from callers.
    final passedPath = widget.avatarPath;
    if (passedPath != null && passedPath.isNotEmpty) {
      await _loadForPath(passedPath);
      return;
    }

    // Fallback: use AuthProvider (e.g. when used without a parent passing path).
    try {
      final auth = Supabase.instance.client.auth;
      final response = await auth.getUser();
      final metaPath = response.user?.userMetadata?['avatar_path'] as String?;
      if (metaPath != null && metaPath.isNotEmpty) {
        await _loadForPath(metaPath);
      } else {
        if (mounted) {
          setState(() {
            _imageUrl = null;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _imageUrl = null;
        });
      }
    }
  }

  Future<void> _loadForPath(String path) async {
    try {
      final url = await Supabase.instance.client.storage.from(_avatarBucket).createSignedUrl(path, 3600);
      if (mounted) {
        setState(() {
          _imageUrl = url;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _imageUrl = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppTheme.primaryNavy;
    final iconColor = widget.placeholderIconColor ?? Colors.white;

    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bg.withOpacity(0.15),
        backgroundImage: NetworkImage(_imageUrl!),
        onBackgroundImageError: (_, __) {
          if (mounted) {
            setState(() {
              _imageUrl = null;
            });
          }
        },
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      child: Icon(
        Icons.person_rounded,
        color: iconColor,
        size: widget.radius * 1.2,
      ),
    );
  }
}

