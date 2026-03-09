import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client.dart';
import '../../../api/config.dart';
import '../../../landingpage/constants/app_theme.dart';
import '../../../providers/auth_provider.dart';

/// Breakpoint above which the profile uses a two-column web layout.
const double _profileWebBreakpoint = 900;

/// Full-screen profile page (e.g. from admin menu). Uses [ProfileContent] for the body.
/// Responsive: adaptive padding and scroll behavior for web vs mobile.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= _profileWebBreakpoint;
    final padding = isWeb ? 32.0 : 16.0;

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
        title: Text(
          'My Profile',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: isWeb ? 20 : 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: isWeb ? 32 : 20,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWeb ? 1000 : double.infinity,
            ),
            child: const ProfileContent(),
          ),
        ),
      ),
    );
  }
}

/// Reusable profile content: account info (name, email, phone) and change password. Used in [ProfilePage] and employee dashboard My Profile.
class ProfileContent extends StatefulWidget {
  const ProfileContent({super.key});

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  bool _passwordLoading = false;
  bool _imageLoading = false;
  bool _resettingPassword = false;
  String? _message;
  String? _passwordMessage;
  String? _avatarPath;
  String? _avatarUrl;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loadedFromAuth = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedFromAuth) {
      final auth = context.read<AuthProvider>();
      if (auth.user != null) {
        _nameController.text = auth.displayName;
        _avatarPath = auth.avatarPath;
        _phoneController.text = auth.user!.contactNumber ?? '';
        _loadedFromAuth = true;
        // Always try avatar URL when we have userId; Image.network errorBuilder handles 404
        _avatarUrl = _avatarUrlFor(auth.user!.id);
      }
    }
  }

  /// Build avatar URL with optional cache-bust. Pass [cacheBust] after upload to force reload.
  String _avatarUrlFor(String userId, {bool cacheBust = false}) {
    final base = '${ApiConfig.baseUrl}/api/files/avatar/$userId';
    return cacheBust
        ? '$base?t=${DateTime.now().millisecondsSinceEpoch}'
        : base;
  }

  /// Returns a simple strength label and color for the given password.
  static ({String label, Color color}) _passwordStrength(String value) {
    if (value.isEmpty) return (label: '', color: Colors.grey);
    final hasLower = value.contains(RegExp(r'[a-z]'));
    final hasUpper = value.contains(RegExp(r'[A-Z]'));
    final hasDigit = value.contains(RegExp(r'[0-9]'));
    final hasSpecial = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    final length = value.length;
    int score = 0;
    if (length >= 6) score++;
    if (length >= 10) score++;
    if (hasLower && hasUpper) score++;
    if (hasDigit) score++;
    if (hasSpecial) score++;
    if (score <= 1) return (label: 'Weak', color: Colors.red.shade700);
    if (score <= 3) return (label: 'Medium', color: Colors.orange.shade700);
    return (label: 'Strong', color: Colors.green.shade700);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailFocusNode.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordReset() async {
    final email = context.read<AuthProvider>().email;
    if (email.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No email on file. Cannot send reset link.'),
          ),
        );
      return;
    }
    setState(() => _resettingPassword = true);
    try {
      await ApiClient.instance.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('If that email exists, a reset link will be sent.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _resettingPassword = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null)
      return;
    final bytes = result.files.single.bytes!;
    setState(() {
      _imageLoading = true;
      _message = null;
    });
    try {
      await ApiClient.instance.uploadBytes(
        '/api/upload/avatar',
        bytes: bytes,
        fileName: 'avatar.jpg',
      );
      if (mounted) {
        await context.read<AuthProvider>().refreshUser();
        _avatarPath = context.read<AuthProvider>().avatarPath;
        _avatarUrl = _avatarUrlFor(user.id, cacheBust: true);
        setState(() {
          _imageLoading = false;
          _message = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _imageLoading = false;
          _message = 'Image upload failed: $e';
        });
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty) {
      setState(() => _message = 'Name is required');
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await ApiClient.instance.patch(
        '/auth/me',
        data: {
          'full_name': name,
          'contact_number': phone.isNotEmpty ? phone : null,
        },
      );
      if (mounted) {
        await context.read<AuthProvider>().refreshUser();
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = 'Failed: $e';
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final currentPass = _currentPasswordController.text;
    final newPass = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    if (currentPass.isEmpty) {
      setState(() => _passwordMessage = 'Enter current password');
      return;
    }
    if (newPass.length < 6) {
      setState(
        () => _passwordMessage = 'Password must be at least 6 characters',
      );
      return;
    }
    if (newPass != confirm) {
      setState(() => _passwordMessage = 'New passwords do not match');
      return;
    }
    setState(() {
      _passwordLoading = true;
      _passwordMessage = null;
    });
    try {
      await ApiClient.instance.post(
        '/auth/change-password',
        data: {'current_password': currentPass, 'new_password': newPass},
      );
      if (mounted) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        setState(() {
          _passwordLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated.')));
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString();
        setState(() {
          _passwordLoading = false;
          _passwordMessage = err.contains('401')
              ? 'Current password is incorrect'
              : 'Failed: $e';
        });
      }
    }
  }

  Widget _buildAccountSection(BuildContext context, String email, bool isWeb) {
    final avatarSize = isWeb ? 56.0 : 48.0;
    final avatarRadius = isWeb ? 52.0 : 44.0;

    return _ProfileSection(
      title: 'Account',
      icon: Icons.person_outline_rounded,
      isCompact: !isWeb,
      padding: isWeb ? 24 : 16,
      children: [
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _imageLoading ? null : _pickAndUploadAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    _avatarUrl != null
                        ? ClipOval(
                            child: Image.network(
                              _avatarUrl!,
                              width: avatarRadius * 2,
                              height: avatarRadius * 2,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor: AppTheme.primaryNavy
                                    .withOpacity(0.1),
                                child: Icon(
                                  Icons.person_rounded,
                                  size: avatarSize,
                                  color: AppTheme.primaryNavy.withOpacity(0.5),
                                ),
                              ),
                            ),
                          )
                        : CircleAvatar(
                            radius: avatarRadius,
                            backgroundColor: AppTheme.primaryNavy.withOpacity(
                              0.1,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              size: avatarSize,
                              color: AppTheme.primaryNavy.withOpacity(0.5),
                            ),
                          ),
                    if (_imageLoading)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Container(
                        padding: EdgeInsets.all(isWeb ? 8 : 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: isWeb ? 20 : 18,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: isWeb ? 10 : 8),
              Text(
                _avatarPath == null ? 'Add profile image' : 'Change photo',
                style: TextStyle(
                  fontSize: isWeb ? 13 : 12,
                  color: AppTheme.primaryNavy,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isWeb ? 24 : 20),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Full name',
            hintText: 'Enter your full name',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge_outlined),
            contentPadding: isWeb
                ? null
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        SizedBox(height: isWeb ? 16 : 12),
        TextFormField(
          controller: _phoneController,
          decoration: InputDecoration(
            labelText: 'Phone (optional)',
            hintText: 'e.g. 09XX XXX XXXX',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.phone_outlined),
            contentPadding: isWeb
                ? null
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          keyboardType: TextInputType.phone,
        ),
        SizedBox(height: isWeb ? 16 : 12),
        TextFormField(
          initialValue: email,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Email',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
            filled: true,
            fillColor: AppTheme.lightGray.withOpacity(0.5),
            helperText: isWeb
                ? 'Used for login. Change via your account provider if needed.'
                : null,
            helperStyle: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            contentPadding: isWeb
                ? null
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        if (_message != null) ...[
          SizedBox(height: isWeb ? 12 : 8),
          Text(
            _message!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
          ),
        ],
        SizedBox(height: isWeb ? 20 : 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _saveProfile,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 20),
            label: Text(_loading ? 'Saving...' : 'Save profile'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              padding: EdgeInsets.symmetric(vertical: isWeb ? 14 : 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordSection(
    BuildContext context,
    ({String label, Color color}) strength,
    bool isWeb,
  ) {
    final newPass = _newPasswordController.text;

    return _ProfileSection(
      title: 'Password',
      icon: Icons.lock_outline_rounded,
      isCompact: !isWeb,
      padding: isWeb ? 24 : 16,
      children: [
        TextFormField(
          controller: _currentPasswordController,
          obscureText: _obscureCurrent,
          decoration: InputDecoration(
            labelText: 'Current password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureCurrent
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            contentPadding: isWeb
                ? null
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        SizedBox(height: isWeb ? 16 : 12),
        TextFormField(
          controller: _newPasswordController,
          obscureText: _obscureNew,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'New password',
            hintText: 'At least 6 characters',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNew
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            contentPadding: isWeb
                ? null
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        if (newPass.isNotEmpty) ...[
          SizedBox(height: isWeb ? 6 : 4),
          Row(
            children: [
              Text(
                'Strength: ',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              Text(
                strength.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: strength.color,
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: isWeb ? 16 : 12),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm new password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            contentPadding: isWeb
                ? null
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        if (_passwordMessage != null) ...[
          SizedBox(height: isWeb ? 12 : 8),
          Text(
            _passwordMessage!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
          ),
        ],
        SizedBox(height: isWeb ? 12 : 10),
        TextButton.icon(
          onPressed: _resettingPassword ? null : _sendPasswordReset,
          icon: _resettingPassword
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mail_outline_rounded, size: 18),
          label: Text(
            isWeb
                ? 'Forgot password? Send reset link to email'
                : 'Forgot password?',
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: isWeb ? 8 : 12),
          ),
        ),
        SizedBox(height: isWeb ? 20 : 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _passwordLoading ? null : _changePassword,
            icon: _passwordLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_reset_rounded, size: 20),
            label: Text(_passwordLoading ? 'Updating...' : 'Change password'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              padding: EdgeInsets.symmetric(vertical: isWeb ? 14 : 16),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthProvider>().email;
    final newPass = _newPasswordController.text;
    final strength = _passwordStrength(newPass);
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= _profileWebBreakpoint;

    final accountSection = _buildAccountSection(context, email, isWeb);
    final passwordSection = _buildPasswordSection(context, strength, isWeb);

    if (isWeb) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: accountSection),
          const SizedBox(width: 24),
          Expanded(child: passwordSection),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountSection,
        const SizedBox(height: 20),
        passwordSection,
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    this.icon,
    required this.children,
    this.isCompact = false,
    this.padding = 20,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;
  final bool isCompact;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final titleSize = isCompact ? 12.0 : 13.0;
    final radius = isCompact ? 12.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: isCompact ? 8 : 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: isCompact ? 16 : 18,
                  color: AppTheme.primaryNavy,
                ),
                SizedBox(width: isCompact ? 6 : 8),
              ],
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isCompact ? 0.03 : 0.04),
                blurRadius: isCompact ? 8 : 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
