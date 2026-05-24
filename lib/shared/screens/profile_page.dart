import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/app_user.dart';
import '../../../api/client.dart';
import '../../../api/config.dart';
import '../../../landingpage/constants/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/structured_address_fields.dart';
import '../widgets/dashboard_header_actions.dart';
import '../widgets/profile_account_tab_skeleton.dart';
import '../widgets/profile_app_settings_panels.dart';
import '../widgets/profile_modern_ui.dart';
import '../widgets/settings_password_security_extras.dart';

/// Breakpoint for two-column profile body (uses available content width).
const double _profileWideBreakpoint = 720;

/// Profile body shown inside the admin/employee dashboard (sidebar stays visible).
class DashboardProfilePanel extends StatelessWidget {
  const DashboardProfilePanel({super.key, this.initialTab, this.onBack});

  final ProfilePageTab? initialTab;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        child: ProfileContent(initialTab: initialTab, onBack: onBack),
      ),
    );
  }
}

/// Full-screen profile (fallback). Prefer [DashboardProfilePanel] in dashboards.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.sizeOf(context).width >= 900 ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.dashPanelOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          color: AppTheme.dashTextPrimaryOf(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: MediaQuery.sizeOf(context).width >= 900 ? 20 : 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
        child: const SizedBox(
          width: double.infinity,
          child: ProfileContent(),
        ),
      ),
    );
  }
}

/// Reusable profile content: account info (name, email, phone) and change password. Used in [ProfilePage] and Settings.
class ProfileContent extends StatefulWidget {
  const ProfileContent({
    super.key,
    this.showAccountSection = true,
    this.showPasswordSection = true,
    this.showAppSettings = true,
    this.initialTab,
    this.onBack,
  });

  /// When false, only the password card is shown (e.g. Settings → Password tab).
  final bool showAccountSection;

  /// When false, only the account card is shown.
  final bool showPasswordSection;

  /// Notification, preference, and about (formerly in Settings).
  final bool showAppSettings;

  final ProfilePageTab? initialTab;

  /// Pops dashboard settings / returns to the previous screen.
  final VoidCallback? onBack;

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthdateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _streetController = TextEditingController();
  final _addressFormKey = GlobalKey<StructuredAddressFormState>();
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
  String? _sexValue;
  String? _civilStatusValue;
  String? _suffixValue;
  DateTime? _birthdateValue;
  String? _nationalityValue;
  late ProfilePageTab _profileTab;
  late Set<ProfilePageTab> _mountedTabs;

  @override
  void initState() {
    super.initState();
    _profileTab = widget.initialTab ?? _defaultTab();
    _mountedTabs = {_profileTab};
  }

  void _onProfileTabSelected(ProfilePageTab tab) {
    if (_profileTab == tab) return;
    setState(() {
      _profileTab = tab;
      _mountedTabs.add(tab);
    });
  }

  List<ProfilePageTab> _visibleProfileTabs() {
    final tabs = <ProfilePageTab>[];
    if (widget.showAccountSection) tabs.add(ProfilePageTab.account);
    if (widget.showPasswordSection) tabs.add(ProfilePageTab.security);
    if (widget.showAppSettings) {
      tabs.add(ProfilePageTab.notification);
      tabs.add(ProfilePageTab.preference);
      tabs.add(ProfilePageTab.about);
    }
    return tabs;
  }

  ProfilePageTab _defaultTab() {
    if (widget.showAccountSection) return ProfilePageTab.account;
    if (widget.showPasswordSection) return ProfilePageTab.security;
    if (widget.showAppSettings) return ProfilePageTab.notification;
    return ProfilePageTab.account;
  }

  @override
  void didUpdateWidget(covariant ProfileContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != null &&
        widget.initialTab != oldWidget.initialTab) {
      _profileTab = widget.initialTab!;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedFromAuth) {
      final auth = context.read<AuthProvider>();
      if (auth.user != null) {
        final u = auth.user!;
        _firstNameController.text = u.firstName ?? '';
        _middleNameController.text = u.middleName ?? '';
        _lastNameController.text = u.lastName ?? '';
        _suffixValue = (u.suffix ?? '').trim().isEmpty ? null : u.suffix!.trim();
        _birthdateValue = u.dateOfBirth;
        _birthdateController.text = _formatYmd(_birthdateValue);
        _avatarPath = auth.avatarPath;
        _phoneController.text = u.contactNumber ?? '';
        _nationalityValue =
            (u.nationality ?? '').trim().isEmpty ? null : u.nationality!.trim();
        _streetController.text = '';
        _sexValue = _normalizeSex(u.sex);
        _civilStatusValue = _normalizeCivilStatus(u.civilStatus);
        _loadedFromAuth = true;
        // Always try avatar URL when we have userId; Image.network errorBuilder handles 404
        _avatarUrl = _avatarUrlFor(u.id);
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

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _birthdateController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _emailFocusNode.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  static const List<String> _civilStatusOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Divorced',
  ];

  // Common nationality adjectives (searchable). Includes Filipino and major nationalities.
  static const List<String> _nationalities = [
    'Afghan',
    'Albanian',
    'Algerian',
    'American',
    'Andorran',
    'Angolan',
    'Antiguan',
    'Argentine',
    'Armenian',
    'Australian',
    'Austrian',
    'Azerbaijani',
    'Bahamian',
    'Bahraini',
    'Bangladeshi',
    'Barbadian',
    'Belarusian',
    'Belgian',
    'Belizean',
    'Beninese',
    'Bhutanese',
    'Bolivian',
    'Bosnian',
    'Botswanan',
    'Brazilian',
    'British',
    'Bruneian',
    'Bulgarian',
    'Burkinabe',
    'Burmese',
    'Burundian',
    'Cambodian',
    'Cameroonian',
    'Canadian',
    'Cape Verdean',
    'Central African',
    'Chadian',
    'Chilean',
    'Chinese',
    'Colombian',
    'Comoran',
    'Congolese',
    'Costa Rican',
    'Croatian',
    'Cuban',
    'Cypriot',
    'Czech',
    'Danish',
    'Djiboutian',
    'Dominican',
    'Dutch',
    'East Timorese',
    'Ecuadorian',
    'Egyptian',
    'Emirati',
    'Equatorial Guinean',
    'Eritrean',
    'Estonian',
    'Ethiopian',
    'Fijian',
    'Filipino',
    'Finnish',
    'French',
    'Gabonese',
    'Gambian',
    'Georgian',
    'German',
    'Ghanaian',
    'Greek',
    'Grenadian',
    'Guatemalan',
    'Guinean',
    'Guyanese',
    'Haitian',
    'Honduran',
    'Hungarian',
    'Icelandic',
    'Indian',
    'Indonesian',
    'Iranian',
    'Iraqi',
    'Irish',
    'Israeli',
    'Italian',
    'Ivorian',
    'Jamaican',
    'Japanese',
    'Jordanian',
    'Kazakhstani',
    'Kenyan',
    'Kuwaiti',
    'Kyrgyzstani',
    'Laotian',
    'Latvian',
    'Lebanese',
    'Liberian',
    'Libyan',
    'Liechtensteiner',
    'Lithuanian',
    'Luxembourgish',
    'Macedonian',
    'Malagasy',
    'Malawian',
    'Malaysian',
    'Maldivian',
    'Malian',
    'Maltese',
    'Mauritanian',
    'Mauritian',
    'Mexican',
    'Moldovan',
    'Monacan',
    'Mongolian',
    'Montenegrin',
    'Moroccan',
    'Mozambican',
    'Namibian',
    'Nepalese',
    'New Zealander',
    'Nicaraguan',
    'Nigerien',
    'Nigerian',
    'Norwegian',
    'Omani',
    'Pakistani',
    'Panamanian',
    'Papua New Guinean',
    'Paraguayan',
    'Peruvian',
    'Polish',
    'Portuguese',
    'Qatari',
    'Romanian',
    'Russian',
    'Rwandan',
    'Saudi',
    'Senegalese',
    'Serbian',
    'Seychellois',
    'Sierra Leonean',
    'Singaporean',
    'Slovak',
    'Slovenian',
    'Somali',
    'South African',
    'South Korean',
    'Spanish',
    'Sri Lankan',
    'Sudanese',
    'Swedish',
    'Swiss',
    'Syrian',
    'Taiwanese',
    'Tajikistani',
    'Tanzanian',
    'Thai',
    'Togolese',
    'Tongan',
    'Trinidadian',
    'Tunisian',
    'Turkish',
    'Ugandan',
    'Ukrainian',
    'Uruguayan',
    'Uzbekistani',
    'Venezuelan',
    'Vietnamese',
    'Yemeni',
    'Zambian',
    'Zimbabwean',
  ];

  String? _normalizeSex(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'm' || s == 'male') return 'Male';
    if (s == 'f' || s == 'female') return 'Female';
    return null;
  }

  String? _normalizeCivilStatus(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    for (final o in _civilStatusOptions) {
      if (o.toLowerCase() == s.toLowerCase()) return o;
    }
    return null;
  }

  static const List<String> _suffixOptions = [
    'Jr.',
    'Sr.',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final initial = _birthdateValue ?? DateTime(now.year - 25, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      helpText: 'Select birthdate',
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _birthdateValue = picked;
      _birthdateController.text = _formatYmd(picked);
    });
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
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    List<int>? bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      final path = picked.path;
      if (path != null && path.isNotEmpty) {
        try {
          bytes = await picked.xFile.readAsBytes();
        } catch (_) {}
      }
    }
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not read the selected image. Try another file (JPG or PNG).',
          ),
        ),
      );
      return;
    }

    final uploadName = _avatarUploadFileName(picked.name);
    setState(() {
      _imageLoading = true;
      _message = null;
    });
    try {
      await ApiClient.instance.uploadBytes(
        '/api/upload/avatar',
        bytes: bytes,
        fileName: uploadName,
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
      if (!mounted) return;
      final msg = e is DioException
          ? (e.response?.data is Map
              ? (e.response!.data as Map)['error']?.toString()
              : null) ??
              e.message
          : e.toString();
      setState(() {
        _imageLoading = false;
        _message = 'Image upload failed: ${msg ?? e}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image upload failed: ${msg ?? e}')),
      );
    }
  }

  String _avatarUploadFileName(String? originalName) {
    final name = (originalName ?? '').trim().toLowerCase();
    if (name.endsWith('.png')) return 'avatar.png';
    if (name.endsWith('.gif')) return 'avatar.gif';
    if (name.endsWith('.webp')) return 'avatar.webp';
    if (name.endsWith('.jpeg')) return 'avatar.jpeg';
    return 'avatar.jpg';
  }

  Future<void> _saveProfile() async {
    final first = _firstNameController.text.trim();
    final middle = _middleNameController.text.trim();
    final last = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final encodedAddress = _addressFormKey.currentState?.composeEncoded();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _message = 'First name and last name are required');
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
          'first_name': first,
          'middle_name': middle.isNotEmpty ? middle : null,
          'last_name': last,
          'suffix': _suffixValue,
          'date_of_birth': _birthdateValue != null ? _formatYmd(_birthdateValue) : null,
          'contact_number': phone.isNotEmpty ? phone : null,
          'address': encodedAddress,
          'sex': _sexValue,
          'civil_status': _civilStatusValue,
          'nationality': _nationalityValue,
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

  String _dashText(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? '—' : t;
  }

  String _usernameFromEmail(String email) {
    final i = email.indexOf('@');
    if (i <= 0) return email.isEmpty ? '—' : email;
    return email.substring(0, i);
  }

  String _formatYmd(DateTime? d) {
    if (d == null) return '—';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _profileDisplayNameFromAuth(AppUser? user, String authDisplayName) {
    if (authDisplayName.isNotEmpty) return authDisplayName;
    final parts = [
      _firstNameController.text.trim(),
      _middleNameController.text.trim(),
      _lastNameController.text.trim(),
    ].where((p) => p.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ');
    return user?.fullName?.trim().isNotEmpty == true
        ? user!.fullName!.trim()
        : 'User';
  }

  String _roleLabel(AppUser? user) {
    final role = (user?.role ?? 'employee').toLowerCase();
    return switch (role) {
      'admin' => 'Administrator',
      'hr' => 'HR Staff',
      _ => 'Employee',
    };
  }

  Widget _buildAvatarCircle(double radius) {
    return _avatarUrl != null
        ? ClipOval(
            child: Image.network(
              _avatarUrl!,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => CircleAvatar(
                radius: radius,
                backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
                child: Icon(
                  Icons.person_rounded,
                  size: radius,
                  color: AppTheme.primaryNavy.withValues(alpha: 0.5),
                ),
              ),
            ),
          )
        : CircleAvatar(
            radius: radius,
            backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
            child: Icon(
              Icons.person_rounded,
              size: radius,
              color: AppTheme.primaryNavy.withValues(alpha: 0.5),
            ),
          );
  }

  Widget _buildWorkAboutCard(
    BuildContext context,
    String email,
    AppUser? user,
    bool isWeb,
  ) {
    final empId = user != null ? user.displayEmployeeId : '—';

    return ModernProfileCard(
      title: 'About',
      icon: Icons.info_outline_rounded,
      child: Column(
        children: [
          ProfileAboutRow(
            label: 'Employee ID:',
            value: empId,
            icon: Icons.badge_rounded,
          ),
          const ProfileAboutDivider(),
          ProfileAboutRow(
            label: 'Department:',
            value: _dashText(user?.departmentName),
            icon: Icons.apartment_rounded,
          ),
          const ProfileAboutDivider(),
          ProfileAboutRow(
            label: 'Position:',
            value: _dashText(user?.positionName),
            icon: Icons.work_outline_rounded,
          ),
          const ProfileAboutDivider(),
          ProfileAboutRow(
            label: 'Username:',
            value: email.isEmpty ? '—' : _usernameFromEmail(email),
            icon: Icons.alternate_email_rounded,
          ),
          const ProfileAboutDivider(),
          ProfileAboutRow(
            label: 'Date hired:',
            value: _formatYmd(user?.dateHired),
            icon: Icons.event_available_rounded,
          ),
          const ProfileAboutDivider(),
          ProfileAboutRow(
            label: 'Status:',
            value: _dashText(user?.employmentStatus?.replaceAll('_', ' ')),
            icon: Icons.verified_user_outlined,
          ),
          if (user?.employmentType != null &&
              user!.employmentType!.trim().isNotEmpty) ...[
            const ProfileAboutDivider(),
            ProfileAboutRow(
              label: 'Type:',
              value: _dashText(user.employmentType!.replaceAll('_', ' ')),
              icon: Icons.schedule_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountSection(
    BuildContext context,
    String email,
    bool isWeb,
    AppUser? user,
  ) {
    return ModernProfileCard(
      title: 'Personal information',
      icon: Icons.edit_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        LayoutBuilder(
          builder: (context, c) {
            final gapX = isWeb ? 16.0 : 0.0;
            final gapY = isWeb ? 14.0 : 12.0;
            final useTwoCol = isWeb && c.maxWidth >= 760;
            final colWidth = useTwoCol ? (c.maxWidth - gapX) / 2 : c.maxWidth;

            Widget col(Widget child) => SizedBox(width: colWidth, child: child);

            InputDecoration dec({
              required String label,
              String? hint,
              Widget? suffixIcon,
              IconData? icon,
              String? helper,
            }) {
              return AppTheme.dashInputDecoration(
                context,
                labelText: label,
                hintText: hint,
                helperText: helper,
                prefixIcon: icon != null
                    ? Icon(icon, color: AppTheme.primaryNavy)
                    : null,
                suffixIcon: suffixIcon,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isWeb ? 18 : 16,
                  vertical: isWeb ? 16 : 14,
                ),
              );
            }

            final fieldStyle = AppTheme.dashFieldTextStyle(context);

            return Wrap(
              spacing: gapX,
              runSpacing: gapY,
              children: [
                col(
                  TextFormField(
                    controller: _firstNameController,
                    style: fieldStyle,
                    decoration: dec(
                      label: 'First name',
                      hint: 'Enter your first name',
                      icon: Icons.badge_outlined,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                col(
                  TextFormField(
                    controller: _middleNameController,
                    style: fieldStyle,
                    decoration: dec(
                      label: 'Middle name',
                      hint: 'Enter your middle name',
                      icon: Icons.badge_outlined,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                col(
                  TextFormField(
                    controller: _lastNameController,
                    style: fieldStyle,
                    decoration: dec(
                      label: 'Last name',
                      hint: 'Enter your last name',
                      icon: Icons.badge_outlined,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                col(
                  DropdownButtonFormField<String>(
                    initialValue: _suffixValue,
                    items: _suffixOptions
                        .map(
                          (s) => DropdownMenuItem(value: s, child: Text(s)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _suffixValue = v),
                    decoration: dec(
                      label: 'Suffix',
                      icon: Icons.text_fields_rounded,
                    ),
                    isExpanded: true,
                  ),
                ),
                col(
                  DropdownButtonFormField<String>(
                    initialValue: _sexValue,
                    style: fieldStyle,
                    dropdownColor: AppTheme.dashPanelOf(context),
                    items: [
                      DropdownMenuItem(
                        value: 'Male',
                        child: Text('Male', style: fieldStyle),
                      ),
                      DropdownMenuItem(
                        value: 'Female',
                        child: Text('Female', style: fieldStyle),
                      ),
                    ],
                    onChanged: (v) => setState(() => _sexValue = v),
                    decoration: dec(label: 'Gender', icon: Icons.wc_rounded),
                    isExpanded: true,
                  ),
                ),
                col(
                  TextFormField(
                    controller: _birthdateController,
                    style: fieldStyle,
                    readOnly: true,
                    onTap: _pickBirthdate,
                    decoration: dec(
                      label: 'Birthdate',
                      icon: Icons.cake_outlined,
                      helper: 'Tap to select.',
                      suffixIcon: const Icon(Icons.calendar_month_rounded),
                    ),
                  ),
                ),
                col(
                  DropdownButtonFormField<String>(
                    initialValue: _civilStatusValue,
                    style: fieldStyle,
                    dropdownColor: AppTheme.dashPanelOf(context),
                    items: _civilStatusOptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, style: fieldStyle),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _civilStatusValue = v),
                    decoration: dec(
                      label: 'Civil status',
                      icon: Icons.favorite_outline_rounded,
                    ),
                    isExpanded: true,
                  ),
                ),
                col(_buildNationalityField(context, fieldStyle, dec)),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Contact',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.dashTextSecondaryOf(context),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: AppTheme.dashInputDecoration(
            context,
            labelText: 'Phone number',
            hintText: 'e.g. 09XX XXX XXXX',
            prefixIcon:
                const Icon(Icons.phone_outlined, color: AppTheme.primaryNavy),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isWeb ? 18 : 16,
              vertical: isWeb ? 16 : 14,
            ),
          ),
          keyboardType: TextInputType.phone,
        ),
        SizedBox(height: isWeb ? 14 : 12),
        ProfileAboutRow(
          label: 'Email:',
          value: email.isEmpty ? '—' : email,
          icon: Icons.mail_outline_rounded,
        ),
        const SizedBox(height: 8),
        DeferredProfileMount(
          delayFrames: 1,
          placeholder: const ProfileAccountTabSkeleton(),
          builder: () => StructuredAddressForm(
            key: _addressFormKey,
            streetController: _streetController,
            initialRawAddress: user?.address,
            inputDecoration: (hint) => AppTheme.dashInputDecoration(
              context,
              labelText: hint,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isWeb ? 18 : 16,
                vertical: isWeb ? 16 : 14,
              ),
            ),
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
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: isWeb ? 14 : 16,
                horizontal: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
              shadowColor: Colors.black.withValues(alpha: 0.2),
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection(BuildContext context, bool isWeb) {
    final newPass = _newPasswordController.text;
    final strength = ProfilePasswordStrength.evaluate(newPass);
    final fieldStyle = AppTheme.dashFieldTextStyle(context);
    final fieldPad = EdgeInsets.symmetric(
      horizontal: isWeb ? 18 : 16,
      vertical: isWeb ? 16 : 14,
    );
    final visibilityColor = AppTheme.dashTextSecondaryOf(context);

    InputDecoration pwdDec({
      required String label,
      String? hint,
      required Widget suffixIcon,
    }) {
      return AppTheme.dashInputDecoration(
        context,
        labelText: label,
        hintText: hint,
        prefixIcon:
            const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryNavy),
        suffixIcon: suffixIcon,
        contentPadding: fieldPad,
      );
    }

    Widget visibilityToggle(bool obscure, VoidCallback onToggle) {
      return IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: visibilityColor,
        ),
        onPressed: onToggle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModernProfileCard(
          title: 'Change password',
          icon: Icons.lock_reset_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProfileSecurityTipBanner(),
              const SizedBox(height: 18),
              ProfileInsetSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _currentPasswordController,
                      style: fieldStyle,
                      obscureText: _obscureCurrent,
                      decoration: pwdDec(
                        label: 'Current password',
                        suffixIcon: visibilityToggle(
                          _obscureCurrent,
                          () => setState(
                            () => _obscureCurrent = !_obscureCurrent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isWeb ? 16 : 14),
                    TextFormField(
                      controller: _newPasswordController,
                      style: fieldStyle,
                      obscureText: _obscureNew,
                      onChanged: (_) => setState(() {}),
                      decoration: pwdDec(
                        label: 'New password',
                        hint: 'At least 6 characters',
                        suffixIcon: visibilityToggle(
                          _obscureNew,
                          () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                    ),
                    if (newPass.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ProfilePasswordStrengthMeter(strength: strength),
                    ],
                    SizedBox(height: isWeb ? 16 : 14),
                    TextFormField(
                      controller: _confirmPasswordController,
                      style: fieldStyle,
                      obscureText: _obscureConfirm,
                      decoration: pwdDec(
                        label: 'Confirm new password',
                        suffixIcon: visibilityToggle(
                          _obscureConfirm,
                          () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_passwordMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dashIsDark(context)
                        ? const Color(0xFFC62828).withValues(alpha: 0.15)
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.dashIsDark(context)
                          ? const Color(0xFFC62828).withValues(alpha: 0.35)
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _passwordMessage!,
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Material(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _resettingPassword ? null : _sendPasswordReset,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mail_outline_rounded,
                          size: 20,
                          color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isWeb
                                ? 'Forgot password? Send a reset link to your email'
                                : 'Forgot password? Email reset link',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryNavy,
                            ),
                          ),
                        ),
                        if (_resettingPassword)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.primaryNavy.withValues(alpha: 0.7),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
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
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _passwordLoading ? 'Updating…' : 'Save new password',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: isWeb ? 14 : 16,
                      horizontal: isWeb ? 28 : 24,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SettingsPasswordSecurityExtras(),
      ],
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    ProfilePageTab tab, {
    required String email,
    required AppUser? user,
    required bool isWide,
  }) {
    switch (tab) {
      case ProfilePageTab.account:
        return DeferredProfileMount(
          key: const ValueKey('profile_tab_account'),
          builder: () => _buildAccountTabLayout(context, email, isWide, user),
        );
      case ProfilePageTab.security:
        return _buildPasswordSection(context, isWide);
      case ProfilePageTab.notification:
        return const ProfileNotificationSettingsPanel(
          key: ValueKey('profile_tab_notification'),
        );
      case ProfilePageTab.preference:
        return const ProfilePreferenceSettingsPanel(
          key: ValueKey('profile_tab_preference'),
        );
      case ProfilePageTab.about:
        return const ProfileAboutSettingsPanel(
          key: ValueKey('profile_tab_about'),
        );
    }
  }

  /// [IndexedStack] keeps visited tabs alive so switching is instant (no
  /// [DeferredProfileMount] state reuse between different tabs).
  Widget _buildActiveTabBody(
    BuildContext context, {
    required String email,
    required AppUser? user,
    required bool isWide,
  }) {
    final tabs = _visibleProfileTabs();
    final index = tabs.indexOf(_profileTab);
    if (index < 0) return const SizedBox.shrink();

    return IndexedStack(
      index: index,
      sizing: StackFit.loose,
      children: [
        for (final tab in tabs)
          if (_mountedTabs.contains(tab))
            KeyedSubtree(
              key: ValueKey(tab),
              child: _buildTabContent(
                context,
                tab,
                email: email,
                user: user,
                isWide: isWide,
              ),
            )
          else
            const SizedBox.shrink(),
      ],
    );
  }

  bool get _showTabBar {
    var count = 0;
    if (widget.showAccountSection) count++;
    if (widget.showPasswordSection) count++;
    if (widget.showAppSettings) count += 3;
    return count > 1;
  }

  Widget _buildNationalityField(
    BuildContext context,
    TextStyle fieldStyle,
    InputDecoration Function({
      required String label,
      IconData? icon,
      String? helper,
      Widget? suffixIcon,
    }) dec,
  ) {
    return Autocomplete<String>(
      initialValue: _nationalityValue != null
          ? TextEditingValue(text: _nationalityValue!)
          : null,
      optionsBuilder: (query) {
        final q = query.text.trim().toLowerCase();
        if (q.isEmpty) return _nationalities.take(15);
        return _nationalities
            .where((n) => n.toLowerCase().contains(q))
            .take(25);
      },
      onSelected: (v) => setState(() => _nationalityValue = v),
      fieldViewBuilder: (context, controller, focusNode, _) {
        if ((_nationalityValue ?? '').isNotEmpty &&
            controller.text.isEmpty) {
          controller.text = _nationalityValue!;
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          style: fieldStyle,
          decoration: dec(
            label: 'Nationality',
            icon: Icons.public_rounded,
            helper: 'Type to search or enter your nationality.',
          ),
          onChanged: (v) {
            final trimmed = v.trim();
            setState(() {
              _nationalityValue = trimmed.isEmpty ? null : trimmed;
            });
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppTheme.dashPanelOf(context),
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 400),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(opt, style: fieldStyle),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountTabLayout(
    BuildContext context,
    String email,
    bool isWide,
    AppUser? user,
  ) {
    final about = _buildWorkAboutCard(context, email, user, isWide);
    final personal = _buildAccountSection(context, email, isWide, user);

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 34, child: about),
          const SizedBox(width: 24),
          Expanded(flex: 66, child: personal),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        about,
        const SizedBox(height: 16),
        personal,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showA = widget.showAccountSection;
    final showP = widget.showPasswordSection;
    final showSettings = widget.showAppSettings;
    if (!showA && !showP && !showSettings) {
      return const SizedBox.shrink();
    }

    return Selector<AuthProvider, ({String email, AppUser? user, String displayName})>(
      selector: (_, a) => (
        email: a.email,
        user: a.user,
        displayName: a.displayName,
      ),
      builder: (context, auth, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth >= _profileWideBreakpoint;

            return _buildProfileShell(
              context: context,
              displayName: auth.displayName,
              email: auth.email,
              user: auth.user,
              showA: showA,
              showP: showP,
              showSettings: showSettings,
              idLabel: dashboardAccountIdLabel(auth.user),
              isWide: isWide,
            );
          },
        );
      },
    );
  }

  Widget _buildProfileShell({
    required BuildContext context,
    required String displayName,
    required String email,
    required AppUser? user,
    required bool showA,
    required bool showP,
    required bool showSettings,
    required String? idLabel,
    required bool isWide,
  }) {
    final shell = Container(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: AppTheme.dashIsDark(context)
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showA || showP)
            ProfileHeroHeader(
              displayName: _profileDisplayNameFromAuth(
                user,
                displayName,
              ),
              email: email,
              roleLabel: _roleLabel(user),
              idLabel: idLabel,
              wideLayout: isWide,
              onBack: widget.onBack,
              avatar: SizedBox(
                width: 104,
                height: 104,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildAvatarCircle(52),
                    if (_imageLoading)
                      Container(
                        width: 104,
                        height: 104,
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              onChangePhoto:
                  _imageLoading ? null : _pickAndUploadAvatar,
              isUploading: _imageLoading,
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 28 : 16,
              0,
              isWide ? 28 : 16,
              isWide ? 28 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showTabBar) ...[
                  ProfileTabBar(
                    tab: _profileTab,
                    onChanged: _onProfileTabSelected,
                    showAccount: showA,
                    showSecurity: showP,
                    showAppSettings: showSettings,
                  ),
                  const SizedBox(height: 20),
                ],
                _buildActiveTabBody(
                  context,
                  email: email,
                  user: user,
                  isWide: isWide,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return shell;
  }
}
