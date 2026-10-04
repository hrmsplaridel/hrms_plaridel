import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/admin_dashboard.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/features/mayor/presentation/pages/mayor_dashboard_page.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/main.dart' show kLoginAsKey;
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/auth/theme/login_theme.dart';
import 'package:hrms_plaridel/shared/utils/time_greeting.dart';

const _rememberKey = 'login_remember_v1';
const _rememberEmailKey = 'login_remember_email_v1';

const _kPlaridelLogoAsset = 'assets/images/Plaridel Logo.jpg';
const _kHrmsLogoAsset = 'assets/images/hrmslogo.png';
const _kLoginHeroImageAsset = 'assets/images/PlaridelBuildingC.png';
const _kCardRadius = 18.0;
const _kInputRadius = 12.0;
const _kButtonRadius = 12.0;
const _kFieldHeight = 50.0;
const _kLoginFormMaxWidth = 440.0;
const _kSplitBreakpoint = 1000.0;
const _kDesktopBreakpoint = 1280.0;
const _kWaveWidth = 80.0;

enum _LoginLayout { desktop, tablet, mobile }

_LoginLayout _layoutForWidth(double width) {
  if (width >= _kDesktopBreakpoint) return _LoginLayout.desktop;
  if (width >= _kSplitBreakpoint) return _LoginLayout.tablet;
  return _LoginLayout.mobile;
}

/// Login: wide = hero image + branding left, light form right.
/// Narrow = minimal centered login on a warm canvas (no card).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _formError;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceFade;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _entranceCtrl.forward();
    _loadRememberedCredentials();
  }

  void _triggerShake() {
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberKey) ?? false;
    final savedEmail = prefs.getString(_rememberEmailKey);
    if (!mounted) return;
    setState(() {
      _rememberMe = remember;
      if (remember && savedEmail != null && savedEmail.isNotEmpty) {
        _emailController.text = savedEmail;
      }
    });
  }

  Future<void> _persistRememberPreference(String email) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_rememberKey, true);
      await prefs.setString(_rememberEmailKey, email);
    } else {
      await prefs.remove(_rememberKey);
      await prefs.remove(_rememberEmailKey);
    }
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _shakeCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Widget _shakeForm(Widget child) {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final t = _shakeCtrl.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 6) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }

  Widget _form({required bool embeddedCard, bool minimal = false}) {
    return _LoginFormContent(
      emailController: _emailController,
      passwordController: _passwordController,
      passwordFocusNode: _passwordFocusNode,
      rememberMe: _rememberMe,
      isLoading: _isLoading,
      formError: _formError,
      embeddedCard: embeddedCard,
      minimal: minimal,
      onRememberMeChanged: (v) => setState(() => _rememberMe = v ?? false),
      onLogin: _onLogin,
      onForgotPassword: _onForgotPassword,
      onClearError: () {
        if (_formError != null) setState(() => _formError = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF6F4F1),
      body: FadeTransition(
        opacity: _entranceFade,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = _layoutForWidth(constraints.maxWidth);
            return layout == _LoginLayout.mobile
                ? _buildStacked(context, canPop: canPop)
                : _buildSplit(
                    context,
                    width: constraints.maxWidth,
                    layout: layout,
                    canPop: canPop,
                  );
          },
        ),
      ),
    );
  }

  Widget _buildSplit(
    BuildContext context, {
    required double width,
    required _LoginLayout layout,
    required bool canPop,
  }) {
    final desktop = layout == _LoginLayout.desktop;
    final formWidth = (width * 0.445).clamp(500.0, 700.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          right: formWidth * 0.42,
          child: _LoginHeroPanel(
            compact: !desktop,
            showBack: canPop,
            contentRightInset: formWidth * 0.58,
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: formWidth,
          child: _LoginRightShelf(child: _shakeForm(_form(embeddedCard: true))),
        ),
      ],
    );
  }

  Widget _buildStacked(BuildContext context, {required bool canPop}) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 360 ? 22.0 : 30.0;
    return ColoredBox(
      color: const Color(0xFFFFF9F4),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _LoginMinimalWashPainter()),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        28,
                        horizontal,
                        20,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (canPop)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _LoginIconBackButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    light: false,
                                  ),
                                ),
                              _shakeForm(
                                _form(embeddedCard: false, minimal: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        _triggerShake();
        setState(() => _formError = 'Please enter email and password');
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _formError = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final errorMessage = await auth.login(email, password);
      if (!mounted) return;
      if (errorMessage == null) {
        await _persistRememberPreference(email);

        final role = auth.user?.role ?? 'employee';
        final isPrivileged = role == 'admin' || role == 'hr';
        final isMayor = role == 'mayor';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          kLoginAsKey,
          isMayor ? 'Mayor' : (isPrivileged ? 'Admin' : 'Employee'),
        );

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => isMayor
                ? const MayorDashboardPage()
                : (isPrivileged
                      ? const AdminDashboard()
                      : const EmployeeDashboard()),
          ),
        );
      } else {
        _triggerShake();
        setState(() => _formError = errorMessage);
      }
    } catch (e) {
      if (mounted) {
        _triggerShake();
        setState(() => _formError = 'Login failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailController.text.trim();
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => _ForgotPasswordDialog(initialEmail: email),
    );
    if (reset != true || !mounted) return;

    _passwordController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password reset. You can now sign in with the new password.',
        ),
      ),
    );
  }
}

String _readApiError(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
  }
  return fallback;
}

class _LoginHeroImage extends StatelessWidget {
  const _LoginHeroImage({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _kLoginHeroImageAsset,
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              LoginTheme.brandingGradientStart,
              LoginTheme.brandingGradientEnd,
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginHeroOverlay extends StatelessWidget {
  const _LoginHeroOverlay();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x990A0A0A), Color(0x330A0A0A), Color(0x00000000)],
              stops: [0.0, 0.42, 0.82],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xE6E85D04), Color(0x99E85D04), Color(0x00E85D04)],
              stops: [0.0, 0.28, 0.62],
            ),
          ),
        ),
      ],
    );
  }
}

/// Left panel: municipal hall photo, headline, and trust marks.
class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel({
    required this.compact,
    required this.showBack,
    required this.contentRightInset,
  });

  final bool compact;
  final bool showBack;
  final double contentRightInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _LoginHeroImage(alignment: Alignment(0.12, 0.08)),
        const _LoginHeroOverlay(),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final short = constraints.maxHeight < 720;
              final brand = _LoginHeroTopBrand(compact: compact);
              final lower = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LoginHeroHeadline(compact: compact || short),
                  SizedBox(height: compact ? 18 : 28),
                  _LoginHeroFeatures(compact: compact || short),
                  const SizedBox(height: 18),
                  Text(
                    '“Public service is a work of heart.”',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: compact ? 12.5 : 14,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 22 : 36,
                  16,
                  contentRightInset + (compact ? 22 : 36),
                  20,
                ),
                child: LayoutBuilder(
                  builder: (context, contentConstraints) =>
                      SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: contentConstraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showBack) ...[
                                    const _LoginBackButton(showLabel: true),
                                    const SizedBox(height: 12),
                                  ],
                                  brand,
                                  const SizedBox(height: 24),
                                ],
                              ),
                              lower,
                            ],
                          ),
                        ),
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoginHeroTopBrand extends StatelessWidget {
  const _LoginHeroTopBrand({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MunicipalityLogoCircle(
          size: compact ? 48 : 64,
          borderColor: Colors.white,
          shadowAlpha: 0.18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Municipality of Plaridel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Human Resource Management System',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Integrated Solutions for a Better Public Service',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 3,
                decoration: BoxDecoration(
                  color: LoginTheme.blueLight,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginHeroHeadline extends StatelessWidget {
  const _LoginHeroHeadline({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 32.0 : 44.0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Empowering\n'),
                TextSpan(
                  text: 'Our People,\n',
                  style: TextStyle(color: LoginTheme.blueLight),
                ),
                const TextSpan(text: 'Building a Better Plaridel'),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: titleSize,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A secure and efficient Human Resource Management System\nfor a more progressive and responsive municipality.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: compact ? 13 : 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginHeroFeatures extends StatelessWidget {
  const _LoginHeroFeatures({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.verified_user_outlined, 'Secure', 'Your data is protected'),
      (Icons.groups_outlined, 'For Our People', 'Support municipal employees'),
      (
        Icons.settings_outlined,
        'Modern HR Services',
        'Efficient and digital processes',
      ),
      (
        Icons.bar_chart_rounded,
        'Better Service',
        'A stronger Plaridel tomorrow',
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(width: compact ? 10 : 18),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: compact ? 40 : 46,
                  height: compact ? 40 : 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Icon(items[i].$1, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  items[i].$2,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 11 : 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  items[i].$3,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: compact ? 10 : 11,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LoginWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final wave = math.min(_kWaveWidth, w);
    final h = size.height;
    final path = Path()
      ..moveTo(wave * 0.77, 0)
      ..cubicTo(wave * 0.08, h * 0.14, wave, h * 0.34, wave * 0.38, h * 0.52)
      ..cubicTo(0, h * 0.68, wave * 0.85, h * 0.86, wave * 0.15, h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _LoginRightShelf extends StatelessWidget {
  const _LoginRightShelf({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ClipPath(
            clipper: _LoginWaveClipper(),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFF8F3),
                gradient: RadialGradient(
                  center: Alignment.bottomRight,
                  radius: 1.2,
                  colors: [Color(0xFFFFE3CB), Color(0xFFFFF8F3)],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            // Reserve the full wave width so content never meets its edge.
            padding: const EdgeInsets.only(left: _kWaveWidth + 16, right: 24),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                primary: false,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _kLoginFormMaxWidth,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginIconBackButton extends StatelessWidget {
  const _LoginIconBackButton({required this.onPressed, required this.light});

  final VoidCallback onPressed;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: light ? Colors.white.withValues(alpha: 0.18) : Colors.white,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        tooltip: 'Back',
        icon: Icon(
          Icons.arrow_back_rounded,
          color: light ? Colors.white : AppTheme.textPrimary,
        ),
      ),
    );
  }
}

class _LoginBackButton extends StatelessWidget {
  const _LoginBackButton({this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (showLabel) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.white.withValues(alpha: 0.18),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      child: IconButton(
        padding: const EdgeInsets.all(10),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(
          Icons.arrow_back_rounded,
          size: 24,
          color: Colors.white,
        ),
        tooltip: 'Back',
      ),
    );
  }
}

class _LoginFormContent extends StatelessWidget {
  const _LoginFormContent({
    required this.emailController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.rememberMe,
    required this.isLoading,
    required this.formError,
    required this.embeddedCard,
    this.minimal = false,
    required this.onRememberMeChanged,
    required this.onLogin,
    required this.onForgotPassword,
    required this.onClearError,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool rememberMe;
  final bool isLoading;
  final String? formError;
  final bool embeddedCard;
  final bool minimal;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final VoidCallback onClearError;

  @override
  Widget build(BuildContext context) {
    final showFieldError = formError == 'Please enter email and password';
    final emailEmpty = emailController.text.trim().isEmpty;
    final passwordEmpty = passwordController.text.isEmpty;

    if (minimal) {
      return Column(
        key: const ValueKey('mobile-minimal-login'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LoginMinimalBrand(),
          if (formError != null) ...[
            const SizedBox(height: 16),
            _LoginInlineError(message: formError!),
          ],
          const SizedBox(height: 30),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LoginTextField(
                  controller: emailController,
                  label: 'Email Address',
                  mobile: true,
                  hintText: 'name@plaridel.gov.ph',
                  icon: Icons.mail_outline_rounded,
                  nextFocusNode: passwordFocusNode,
                  autofillHints: const [AutofillHints.email],
                  error: showFieldError && emailEmpty,
                  onChanged: (_) => onClearError(),
                ),
                const SizedBox(height: 18),
                _PasswordTextField(
                  mobile: true,
                  controller: passwordController,
                  focusNode: passwordFocusNode,
                  onSubmitted: onLogin,
                  error: showFieldError && passwordEmpty,
                  onChanged: (_) => onClearError(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LoginRememberForgotRow(
            mobile: true,
            rememberMe: rememberMe,
            onRememberMeChanged: onRememberMeChanged,
            onForgotPassword: onForgotPassword,
          ),
          const SizedBox(height: 22),
          _LoginToHrmsButton(
            mobile: true,
            onPressed: isLoading ? null : onLogin,
            isLoading: isLoading,
          ),
          const SizedBox(height: 22),
          const _LoginMinimalSecureNote(),
          const SizedBox(height: 32),
          const _LoginFooterLinks(mobile: true),
        ],
      );
    }

    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (embeddedCard) ...[
          const _LoginCardHeader(),
          const SizedBox(height: 14),
          const _LoginSecurityPill(),
        ] else
          const _LoginMobileCardHeader(),
        if (formError != null) ...[
          const SizedBox(height: 14),
          _LoginInlineError(message: formError!),
        ],
        SizedBox(height: embeddedCard ? 16 : 24),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LoginTextField(
                controller: emailController,
                label: embeddedCard ? 'Email' : 'Email Address',
                mobile: !embeddedCard,
                hintText: 'name@plaridel.gov.ph',
                icon: Icons.mail_outline_rounded,
                nextFocusNode: passwordFocusNode,
                autofillHints: const [AutofillHints.email],
                error: showFieldError && emailEmpty,
                onChanged: (_) => onClearError(),
              ),
              SizedBox(height: embeddedCard ? 14 : 18),
              _PasswordTextField(
                mobile: !embeddedCard,
                controller: passwordController,
                focusNode: passwordFocusNode,
                onSubmitted: onLogin,
                error: showFieldError && passwordEmpty,
                onChanged: (_) => onClearError(),
              ),
            ],
          ),
        ),
        SizedBox(height: embeddedCard ? 8 : 14),
        _LoginRememberForgotRow(
          mobile: !embeddedCard,
          rememberMe: rememberMe,
          onRememberMeChanged: onRememberMeChanged,
          onForgotPassword: onForgotPassword,
        ),
        SizedBox(height: embeddedCard ? 16 : 20),
        _LoginToHrmsButton(
          mobile: !embeddedCard,
          onPressed: isLoading ? null : onLogin,
          isLoading: isLoading,
        ),
        if (!embeddedCard) ...[
          const SizedBox(height: 24),
          const Divider(height: 1, color: Color(0xFFE9EDF2)),
          const SizedBox(height: 14),
          const _LoginFooterLinks(mobile: true),
        ],
      ],
    );

    final card = DecoratedBox(
      key: embeddedCard ? null : const ValueKey('mobile-login-card'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(embeddedCard ? _kCardRadius : 28),
        border: embeddedCard
            ? null
            : Border.all(color: LoginTheme.bluePrimary.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: embeddedCard ? 0.08 : 0.05),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          embeddedCard || MediaQuery.sizeOf(context).width >= 360 ? 24 : 18,
          embeddedCard ? 22 : 64,
          embeddedCard || MediaQuery.sizeOf(context).width >= 360 ? 24 : 18,
          embeddedCard ? 18 : 26,
        ),
        child: cardBody,
      ),
    );

    if (!embeddedCard) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                key: const ValueKey('mobile-login-crest'),
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: LoginTheme.bluePrimary.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Image.asset(
                  _kHrmsLogoAsset,
                  fit: BoxFit.contain,
                  semanticLabel: 'HRMS system logo',
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (embeddedCard) ...[
          const _LoginLiveHeader(),
          const SizedBox(height: 16),
        ],
        card,
        const SizedBox(height: 16),
        _LoginFooterLinks(mobile: !embeddedCard),
      ],
    );
  }
}

class _LoginMinimalBrand extends StatelessWidget {
  const _LoginMinimalBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _MunicipalityLogoCircle(
          size: 76,
          borderColor: Color(0xFFE8ECF0),
          shadowAlpha: 0.06,
        ),
        const SizedBox(height: 12),
        const Text(
          'Municipality of',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF707784),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const Text(
          'Plaridel',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF172033),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Human Resource Management\nSystem',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF707784),
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: 46,
          height: 3.5,
          decoration: BoxDecoration(
            color: LoginTheme.bluePrimary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF172033),
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Sign in to continue to your HRMS portal.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF707784),
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _LoginMinimalSecureNote extends StatelessWidget {
  const _LoginMinimalSecureNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 15, color: Color(0xFF707784)),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Secure access for municipal employees',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF707784),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginMinimalWashPainter extends CustomPainter {
  const _LoginMinimalWashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final top = Paint()..color = const Color(0x14F45A00);
    canvas.drawOval(
      Rect.fromCircle(
        center: Offset(size.width * 0.92, size.height * 0.06),
        radius: size.shortestSide * 0.42,
      ),
      top,
    );
    final bottom = Paint()..color = const Color(0x12E85D04);
    canvas.drawOval(
      Rect.fromCircle(
        center: Offset(size.width * 0.02, size.height * 0.92),
        radius: size.shortestSide * 0.38,
      ),
      bottom,
    );
  }

  @override
  bool shouldRepaint(covariant _LoginMinimalWashPainter oldDelegate) => false;
}

class _LoginMobileCardHeader extends StatelessWidget {
  const _LoginMobileCardHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.06),
            border: Border.all(
              color: LoginTheme.bluePrimary.withValues(alpha: 0.18),
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Official HRMS Portal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: LoginTheme.bluePrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Welcome Back',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF172B42),
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sign in to continue to your HRMS portal.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF667085), fontSize: 14, height: 1.4),
        ),
      ],
    );
  }
}

class _LoginCardHeader extends StatelessWidget {
  const _LoginCardHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _MunicipalityLogoCircle(
          size: 58,
          borderColor: Color(0xFFE8ECF0),
          shadowAlpha: 0.08,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Municipality of Plaridel',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              Text(
                'Human Resource Management System',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Official HRMS Portal',
                style: TextStyle(
                  color: LoginTheme.bluePrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginSecurityPill extends StatelessWidget {
  const _LoginSecurityPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: LoginTheme.bluePrimary,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Secure access for municipal employees and HR staff.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginLiveHeader extends StatefulWidget {
  const _LoginLiveHeader();

  @override
  State<_LoginLiveHeader> createState() => _LoginLiveHeaderState();
}

class _LoginLiveHeaderState extends State<_LoginLiveHeader> {
  late Timer _timer;
  late DateTime _now;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final h = _now.hour == 0
        ? 12
        : (_now.hour > 12 ? _now.hour - 12 : _now.hour);
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    final ampm = _now.hour < 12 ? 'AM' : 'PM';
    return '$h:$m:$s $ampm';
  }

  String get _dateLabel {
    return '${_weekdays[_now.weekday - 1]}, ${_months[_now.month - 1]} ${_now.day}, ${_now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final greeting = timeOfDayGreeting();
    final dateBlock = Row(
      children: [
        const Icon(
          Icons.wb_sunny_rounded,
          color: LoginTheme.bluePrimary,
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dateLabel,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _timeLabel,
                style: const TextStyle(
                  color: LoginTheme.bluePrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final greetingBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$greeting!',
          style: const TextStyle(
            color: LoginTheme.bluePrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'Have a productive day!',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            360 * MediaQuery.textScalerOf(context).scale(14) / 14) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dateBlock,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: greetingBlock),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dateBlock),
            const SizedBox(width: 8),
            Flexible(child: greetingBlock),
          ],
        );
      },
    );
  }
}

class _LoginInlineError extends StatelessWidget {
  const _LoginInlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEF9A9A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Colors.red.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginRememberForgotRow extends StatelessWidget {
  const _LoginRememberForgotRow({
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onForgotPassword,
    this.mobile = false,
  });

  final bool mobile;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final rememberControl = _RememberMeControl(
      mobile: mobile,
      rememberMe: rememberMe,
      onChanged: onRememberMeChanged,
    );
    final forgotButton = _ForgotPasswordButton(
      onPressed: onForgotPassword,
      mobile: mobile,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            (mobile ? 230 : 300) *
                MediaQuery.textScalerOf(context).scale(14) /
                14) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rememberControl,
              Align(alignment: Alignment.centerRight, child: forgotButton),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: rememberControl),
            if (mobile) Expanded(child: forgotButton) else forgotButton,
          ],
        );
      },
    );
  }
}

class _RememberMeControl extends StatelessWidget {
  const _RememberMeControl({
    required this.rememberMe,
    required this.onChanged,
    this.mobile = false,
  });

  final bool mobile;
  final bool rememberMe;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!rememberMe),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            SizedBox(
              height: 22,
              width: 22,
              child: Checkbox(
                value: rememberMe,
                onChanged: onChanged,
                activeColor: LoginTheme.bluePrimary,
                checkColor: Colors.white,
                side: const BorderSide(color: Color(0xFFADB5BD), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Remember me',
                overflow: mobile ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: mobile ? 12 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForgotPasswordButton extends StatelessWidget {
  const _ForgotPasswordButton({required this.onPressed, this.mobile = false});

  final bool mobile;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: LoginTheme.bluePrimary,
        padding: EdgeInsets.symmetric(horizontal: mobile ? 0 : 8, vertical: 10),
        alignment: mobile ? Alignment.centerRight : Alignment.center,
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Forgot password?',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: mobile ? 12 : 14,
        ),
      ),
    );
  }
}

class _MunicipalityLogoCircle extends StatelessWidget {
  const _MunicipalityLogoCircle({
    required this.size,
    required this.borderColor,
    this.shadowAlpha = 0.08,
  });

  final double size;
  final Color borderColor;
  final double shadowAlpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowAlpha),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          _kPlaridelLogoAsset,
          fit: BoxFit.cover,
          width: size,
          height: size,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.1),
            child: Icon(
              Icons.account_balance_rounded,
              color: LoginTheme.bluePrimary,
              size: size * 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginFooterLinks extends StatelessWidget {
  const _LoginFooterLinks({this.mobile = false});

  final bool mobile;

  static const _muted = Color(0xFF6C757D);

  void _showLegal(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            body,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: LoginTheme.bluePrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: _muted.withValues(alpha: 0.92),
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    final linkStyle = base.copyWith(
      color: LoginTheme.bluePrimary,
      fontWeight: FontWeight.w700,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        if (mobile)
          SizedBox(
            width: double.infinity,
            child: Text(
              '© ${DateTime.now().year} HRMS Plaridel',
              textAlign: TextAlign.center,
              style: base,
            ),
          )
        else ...[
          Text('© ${DateTime.now().year} HRMS Plaridel', style: base),
          Text(
            mobile ? '|' : '·',
            style: base.copyWith(color: _muted.withValues(alpha: 0.5)),
          ),
        ],
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _showLegal(
              context,
              'Privacy',
              'HRMS Plaridel collects and processes personal information only for official human resource management of the Municipality of Plaridel. Access is limited to authorized municipal staff.',
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: mobile ? 14 : 8,
                horizontal: mobile ? 8 : 2,
              ),
              child: Text('Privacy', style: linkStyle),
            ),
          ),
        ),
        Text(
          mobile ? '|' : '·',
          style: base.copyWith(color: _muted.withValues(alpha: 0.5)),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _showLegal(
              context,
              'Terms',
              'This portal is for official use by municipal employees and authorized HR staff. Unauthorized access or misuse of HRMS records is prohibited.',
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: mobile ? 14 : 8,
                horizontal: mobile ? 8 : 2,
              ),
              child: Text('Terms', style: linkStyle),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginTextField extends StatefulWidget {
  const _LoginTextField({
    required this.controller,
    this.mobile = false,
    required this.label,
    required this.hintText,
    required this.icon,
    this.nextFocusNode,
    this.autofillHints,
    this.error = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool mobile;
  final String label;
  final String hintText;
  final IconData icon;
  final FocusNode? nextFocusNode;
  final Iterable<String>? autofillHints;
  final bool error;
  final ValueChanged<String>? onChanged;

  @override
  State<_LoginTextField> createState() => _LoginTextFieldState();
}

class _LoginTextFieldState extends State<_LoginTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() => _focused = _focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(
            minHeight: widget.mobile ? 56 : _kFieldHeight,
          ),
          decoration: widget.mobile
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: LoginTheme.bluePrimary.withValues(
                        alpha: _focused ? 0.10 : 0,
                      ),
                      blurRadius: 8,
                    ),
                  ],
                )
              : null,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.emailAddress,
            autofillHints: widget.autofillHints,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: widget.onChanged,
            onSubmitted: (_) => widget.nextFocusNode?.requestFocus(),
            mouseCursor: SystemMouseCursors.text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: widget.hintText,
              icon: widget.icon,
              focused: _focused,
              error: widget.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordTextField extends StatefulWidget {
  const _PasswordTextField({
    required this.controller,
    this.mobile = false,
    this.focusNode,
    this.onSubmitted,
    this.error = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool mobile;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;
  final bool error;
  final ValueChanged<String>? onChanged;

  @override
  State<_PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<_PasswordTextField> {
  bool _obscure = true;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (widget.focusNode != null) {
      setState(() => _focused = widget.focusNode!.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => widget.focusNode?.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: const Text(
            'Password',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(
            minHeight: widget.mobile ? 56 : _kFieldHeight,
          ),
          decoration: widget.mobile
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: LoginTheme.bluePrimary.withValues(
                        alpha: _focused ? 0.10 : 0,
                      ),
                      blurRadius: 8,
                    ),
                  ],
                )
              : null,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onChanged: widget.onChanged,
            onSubmitted: (_) => widget.onSubmitted?.call(),
            mouseCursor: SystemMouseCursors.text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: 'Enter your password',
              icon: Icons.lock_outline_rounded,
              focused: _focused,
              error: widget.error,
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: LoginTheme.bluePrimary,
                  size: 21,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _inputDecoration({
  required String hint,
  required IconData icon,
  required bool focused,
  bool error = false,
  Widget? suffix,
}) {
  final borderColor = error
      ? const Color(0xFFC62828)
      : focused
      ? LoginTheme.bluePrimary
      : const Color(0xFFE4E7EC);
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withValues(alpha: 0.55),
      fontSize: 15,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 8, right: 2),
      child: IgnorePointer(
        child: Icon(icon, color: LoginTheme.bluePrimary, size: 20),
      ),
    ),
    prefixIconConstraints: const BoxConstraints(
      minWidth: 44,
      minHeight: _kFieldHeight,
    ),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(
      minWidth: 44,
      minHeight: _kFieldHeight,
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: BorderSide(
        color: error ? const Color(0xFFC62828) : LoginTheme.bluePrimary,
        width: 1.6,
      ),
    ),
  );
}

class _LoginToHrmsButton extends StatefulWidget {
  const _LoginToHrmsButton({
    this.onPressed,
    this.isLoading = false,
    this.mobile = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final bool mobile;

  @override
  State<_LoginToHrmsButton> createState() => _LoginToHrmsButtonState();
}

class _LoginToHrmsButtonState extends State<_LoginToHrmsButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final color = !enabled
        ? LoginTheme.bluePrimary.withValues(alpha: 0.45)
        : _pressed
        ? LoginTheme.blueDark
        : _hover
        ? const Color(0xFFF0671A)
        : LoginTheme.bluePrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: enabled && _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: widget.mobile ? 56 : 50,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_kButtonRadius),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: LoginTheme.bluePrimary.withValues(alpha: 0.28),
                      blurRadius: _hover ? 16 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLoading ? null : widget.onPressed,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              borderRadius: BorderRadius.circular(_kButtonRadius),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: widget.isLoading
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Signing in...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Sign In to HRMS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ForgotPasswordStep { requestCode, resetPassword }

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ForgotPasswordStep _step = _ForgotPasswordStep.requestCode;
  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorText;
  String? _infoText;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorText = 'Email is required');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
      _infoText = null;
    });

    try {
      await ApiClient.instance.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _step = _ForgotPasswordStep.resetPassword;
        _infoText =
            'If the account is registered and has a mobile number, an SMS code has been sent.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _readApiError(e, 'Could not request a reset code');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final password = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (code.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorText = 'Code and new password are required');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorText = 'Password must be at least 8 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _errorText = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await ApiClient.instance.post(
        '/auth/reset-password',
        data: {'email': email, 'code': code, 'new_password': password},
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _readApiError(e, 'Could not reset password');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _dialogInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: LoginTheme.bluePrimary, width: 1.5),
      ),
    );
  }

  Widget _statusText() {
    final error = _errorText;
    final info = _infoText;
    if (error == null && info == null) return const SizedBox.shrink();

    final isError = error != null;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        error ?? info!,
        style: TextStyle(
          color: isError ? Colors.red.shade700 : AppTheme.textSecondary,
          fontSize: 13,
          height: 1.35,
          fontWeight: isError ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _requestCodeContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your municipal email. If the account has a mobile number, HRMS will send a reset code by SMS.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _emailController,
          enabled: !_isLoading,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: _dialogInputDecoration(
            label: 'Email',
            hint: 'name@plaridel.gov.ph',
            icon: Icons.mail_outline_rounded,
          ),
          onSubmitted: (_) {
            if (!_isLoading) _requestCode();
          },
        ),
        _statusText(),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      enabled: !_isLoading,
      obscureText: obscure,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      decoration: _dialogInputDecoration(
        label: label,
        hint: 'Enter new password',
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          onPressed: _isLoading ? null : toggle,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
          tooltip: obscure ? 'Show password' : 'Hide password',
        ),
      ),
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }

  Widget _resetPasswordContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the SMS code and choose a new password.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _codeController,
          enabled: !_isLoading,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          decoration: _dialogInputDecoration(
            label: 'SMS code',
            hint: '6-digit code',
            icon: Icons.sms_outlined,
          ).copyWith(counterText: ''),
        ),
        const SizedBox(height: 14),
        _passwordField(
          controller: _newPasswordController,
          label: 'New password',
          obscure: _obscureNewPassword,
          toggle: () => setState(() {
            _obscureNewPassword = !_obscureNewPassword;
          }),
        ),
        const SizedBox(height: 14),
        _passwordField(
          controller: _confirmPasswordController,
          label: 'Confirm password',
          obscure: _obscureConfirmPassword,
          toggle: () => setState(() {
            _obscureConfirmPassword = !_obscureConfirmPassword;
          }),
          onSubmitted: _isLoading ? null : _resetPassword,
        ),
        _statusText(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isResetStep = _step == _ForgotPasswordStep.resetPassword;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LoginTheme.bluePrimary.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.lock_reset_rounded,
              color: LoginTheme.bluePrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Reset password',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isResetStep
                ? _resetPasswordContent()
                : _requestCodeContent(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (isResetStep)
          TextButton(
            onPressed: _isLoading ? null : _requestCode,
            child: const Text('Resend code'),
          ),
        FilledButton(
          onPressed: _isLoading
              ? null
              : isResetStep
              ? _resetPassword
              : _requestCode,
          style: FilledButton.styleFrom(
            backgroundColor: LoginTheme.bluePrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isResetStep ? 'Reset password' : 'Send SMS code'),
        ),
      ],
    );
  }
}
