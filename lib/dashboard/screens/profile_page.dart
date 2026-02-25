import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../landingpage/constants/app_theme.dart';

const String _avatarBucket = 'avatars';

/// Full-screen profile page (e.g. from admin menu). Uses [ProfileContent] for the body.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          color: AppTheme.textPrimary,
        ),
        title: Text('My Profile', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: ProfileContent(),
      ),
    );
  }
}

/// Reusable profile content: account info (name, email) and change password. Used in [ProfilePage] and employee dashboard My Profile.
class ProfileContent extends StatefulWidget {
  const ProfileContent({super.key});

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  final _nameController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  bool _passwordLoading = false;
  bool _imageLoading = false;
  String? _message;
  String? _passwordMessage;
  String? _avatarPath; // storage path from user_metadata
  String? _avatarUrl;  // signed or public URL for display
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadAvatarUrl();
  }

  void _loadUser() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final name = user.userMetadata?['full_name'] as String? ?? user.email?.split('@').first ?? '';
      _nameController.text = name;
      _avatarPath = user.userMetadata?['avatar_path'] as String?;
    }
  }

  Future<void> _loadAvatarUrl() async {
    if (_avatarPath == null || _avatarPath!.isEmpty) return;
    try {
      final url = await Supabase.instance.client.storage.from(_avatarBucket).createSignedUrl(_avatarPath!, 3600);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {
      if (mounted) setState(() => _avatarUrl = null);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailFocusNode.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;
    final ext = result.files.single.extension ?? 'jpg';
    if (ext.isEmpty) return;
    final path = '${user.id}/avatar.$ext';
    setState(() { _imageLoading = true; _message = null; });
    try {
      await Supabase.instance.client.storage.from(_avatarBucket).uploadBinary(path, Uint8List.fromList(bytes), fileOptions: const FileOptions(upsert: true));
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'avatar_path': path}));
      if (mounted) {
        setState(() { _avatarPath = path; _imageLoading = false; });
        await _loadAvatarUrl();
        if (mounted) setState(() => _message = 'Profile image updated');
      }
    } catch (e) {
      if (mounted) setState(() { _imageLoading = false; _message = 'Image upload failed: $e'; });
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _message = 'Name is required');
      return;
    }
    setState(() { _loading = true; _message = null; });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(data: {'full_name': name}));
      if (mounted) setState(() { _loading = false; _message = 'Profile updated'; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _message = 'Failed: $e'; });
    }
  }

  Future<void> _changePassword() async {
    final newPass = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    if (newPass.length < 6) {
      setState(() => _passwordMessage = 'Password must be at least 6 characters');
      return;
    }
    if (newPass != confirm) {
      setState(() => _passwordMessage = 'New passwords do not match');
      return;
    }
    setState(() { _passwordLoading = true; _passwordMessage = null; });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: newPass));
      if (mounted) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() { _passwordLoading = false; _passwordMessage = 'Password updated'; });
      }
    } catch (e) {
      if (mounted) setState(() { _passwordLoading = false; _passwordMessage = 'Failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSection(
          title: 'Account',
          children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _imageLoading ? null : _pickAndUploadAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: AppTheme.primaryNavy.withOpacity(0.1),
                          backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                          child: _avatarUrl == null
                              ? Icon(Icons.person_rounded, size: 56, color: AppTheme.primaryNavy.withOpacity(0.5))
                              : null,
                        ),
                        if (_imageLoading)
                          const Positioned(
                            right: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryNavy,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _avatarPath == null ? 'Add profile image' : 'Change photo',
                    style: TextStyle(fontSize: 13, color: AppTheme.primaryNavy, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: email,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
                filled: true,
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: TextStyle(color: _message == 'Profile updated' ? Colors.green.shade700 : Colors.red.shade700, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _saveProfile,
                icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 20),
                label: Text(_loading ? 'Saving...' : 'Save profile'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _ProfileSection(
          title: 'Password',
          children: [
            TextFormField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: 'Current password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrent ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'New password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            if (_passwordMessage != null) ...[
              const SizedBox(height: 12),
              Text(_passwordMessage!, style: TextStyle(color: _passwordMessage == 'Password updated' ? Colors.green.shade700 : Colors.red.shade700, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _passwordLoading ? null : _changePassword,
                icon: _passwordLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.lock_reset_rounded, size: 20),
                label: Text(_passwordLoading ? 'Updating...' : 'Change password'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(title, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ],
    );
  }
}
