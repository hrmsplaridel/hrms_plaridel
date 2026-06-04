import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hrms_plaridel/features/dashboard/presentation/admin/admin_dashboard.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/employee_dashboard.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/main.dart' show kLoginAsKey;
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/auth/theme/login_theme.dart';

const _rememberKey = 'login_remember_v1';
const _rememberEmailKey = 'login_remember_email_v1';

const _kHrmsLogoAsset = 'assets/images/hrmslogo.png';
const _kPlaridelLogoAsset = 'assets/images/Plaridel Logo.jpg';
const _kLoginHeroImageAsset = 'assets/images/PlaridelBuildingC.png';

enum _LoginLogoVariant { hrms, municipality }

/// Shared radii for the login form (right panel / mobile card).
const _kCardRadius = 24.0;
const _kInputRadius = 12.0;
const _kButtonRadius = 12.0;
const _kFieldHeight = 52.0;

/// Wide login split: hero panel vs form panel (≈58% / 42%).
const _kLoginHeroFlex = 11;
const _kLoginFormFlex = 9;
const _kLoginFormMaxWidth = 420.0;
const _kLoginHeroCardMaxWidth = 500.0;

/// Login: wide = hero image + branding left, white form right.
/// Narrow = full-bleed photo with elevated white form card.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _rememberMe = false;
  bool _isLoading = false;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceFade;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    );
    _entranceCtrl.forward();
    _loadRememberedCredentials();
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
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final form = _LoginFormContent(
      emailController: _emailController,
      passwordController: _passwordController,
      passwordFocusNode: _passwordFocusNode,
      rememberMe: _rememberMe,
      isLoading: _isLoading,
      onRememberMeChanged: (v) => setState(() => _rememberMe = v ?? false),
      onLogin: _onLogin,
      onForgotPassword: _onForgotPassword,
      isWebLayout: isWide,
      isMobileLayout: !isWide,
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.offWhite,
      body: isWide
          ? Row(
              children: [
                Expanded(
                  flex: _kLoginHeroFlex,
                  child: FadeTransition(
                    opacity: _entranceFade,
                    child: const _LoginHeroPanel(),
                  ),
                ),
                Expanded(
                  flex: _kLoginFormFlex,
                  child: _LoginFormShell(
                    isWeb: true,
                    maxContentWidth: _kLoginFormMaxWidth,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: FadeTransition(opacity: _entranceFade, child: form),
                  ),
                ),
              ],
            )
          : _LoginFormShell(
              isWeb: true,
              contentPadding: EdgeInsets.zero,
              maxContentWidth: null,
              child: Stack(
                children: [
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final viewInsets = MediaQuery.viewInsetsOf(context);
                        final viewport = MediaQuery.sizeOf(context);
                        final keyboardOpen = viewInsets.bottom > 80;
                        final compactMobile =
                            viewport.width < 430 || viewport.height < 820;
                        final formChild = FadeTransition(
                          opacity: _entranceFade,
                          child: form,
                        );
                        final horizontalInset = compactMobile ? 8.0 : 10.0;
                        final verticalInset = compactMobile ? 8.0 : 12.0;
                        final cardWidth =
                            constraints.maxWidth - horizontalInset * 2;

                        if (keyboardOpen) {
                          return SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              horizontalInset,
                              verticalInset,
                              horizontalInset,
                              viewInsets.bottom + verticalInset,
                            ),
                            child: SizedBox(width: cardWidth, child: formChild),
                          );
                        }

                        return Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalInset,
                              vertical: verticalInset,
                            ),
                            child: SizedBox(width: cardWidth, child: formChild),
                          ),
                        );
                      },
                    ),
                  ),
                  if (Navigator.of(context).canPop())
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                        child: _LoginMobileBackButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _onLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter email and password')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      final errorMessage = await auth.login(email, password);
      if (!mounted) return;
      if (errorMessage == null) {
        await _persistRememberPreference(email);

        final role = auth.user?.role ?? 'employee';
        final isPrivileged = role == 'admin' || role == 'hr';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLoginAsKey, isPrivileged ? 'Admin' : 'Employee');

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => isPrivileged
                ? const AdminDashboard()
                : const EmployeeDashboard(),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onForgotPassword() {
    // Ready for forgot-password flow.
  }
}

/// Building photo + orange wash + bottom scrim.
class _LoginHeroBackground extends StatelessWidget {
  const _LoginHeroBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _kLoginHeroImageAsset,
          fit: BoxFit.cover,
          alignment: const Alignment(0.05, -0.1),
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
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.42, 1.0],
              colors: [
                LoginTheme.bluePrimary.withValues(alpha: 0.34),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.45),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.7, 1.0],
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Left panel on wide screens — centered glass card over the hero photo.
class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _LoginHeroBackground(),
        SafeArea(
          child: Stack(
            children: [
              if (Navigator.of(context).canPop())
                const Positioned(
                  top: 8,
                  left: 8,
                  child: _LoginBackButton(showLabel: true),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kLoginHeroCardMaxWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.22),
                                    Colors.white.withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.38),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  28,
                                  28,
                                  24,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _LoginBranding(
                                      lightText: true,
                                      compact: false,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Serving the municipal workforce with\n'
                                      'modern, secure HR services.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontSize: 14,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const _SecureAccessPill(light: true),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _LoginHeroFeatureRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 28,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: Text(
              '© ${DateTime.now().year} Municipality of Plaridel',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Trust highlights on the web hero panel.
class _LoginHeroFeatureRow extends StatelessWidget {
  const _LoginHeroFeatureRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: const [
        _LoginHeroFeatureChip(
          icon: Icons.verified_user_outlined,
          label: 'Secure login',
        ),
        _LoginHeroFeatureChip(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Admin portal',
        ),
        _LoginHeroFeatureChip(
          icon: Icons.badge_outlined,
          label: 'Employee portal',
        ),
        _LoginHeroFeatureChip(
          icon: Icons.schedule_outlined,
          label: '24/7 access',
        ),
      ],
    );
  }
}

class _LoginHeroFeatureChip extends StatelessWidget {
  const _LoginHeroFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginFormShell extends StatelessWidget {
  const _LoginFormShell({
    required this.child,
    this.isWeb = false,
    this.contentPadding,
    this.maxContentWidth = _kLoginFormMaxWidth,
  });

  final Widget child;
  final bool isWeb;
  final EdgeInsetsGeometry? contentPadding;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isWeb
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFAFBFC),
                  Color(0xFFF3F5F8),
                  Color(0xFFFFF8F4),
                ],
                stops: [0.0, 0.55, 1.0],
              )
            : null,
        color: isWeb ? null : const Color(0xFFFAFBFC),
        border: const Border(left: BorderSide(color: Color(0xFFEBEEF2))),
      ),
      child: Stack(
        children: [
          if (isWeb) ...[
            Positioned.fill(
              child: CustomPaint(painter: _LoginWebGridPainter()),
            ),
            Positioned(
              right: 24,
              top: 48,
              child: Opacity(
                opacity: 0.045,
                child: Text(
                  'HRMS',
                  style: TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -4,
                    color: AppTheme.letterheadNavy,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: 80,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      LoginTheme.bluePrimary.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -30,
              bottom: 120,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.letterheadNavy.withValues(alpha: 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
          SafeArea(
            child: isWeb
                ? Center(
                    child: SingleChildScrollView(
                      padding:
                          contentPadding ??
                          const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 12,
                          ),
                      child: maxContentWidth == null
                          ? child
                          : ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxContentWidth!,
                              ),
                              child: child,
                            ),
                    ),
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 36,
                      ),
                      child: child,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Back control on the mobile login card (light background).
class _LoginMobileBackButton extends StatelessWidget {
  const _LoginMobileBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        color: AppTheme.textPrimary,
        tooltip: 'Back',
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
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    const Text(
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

class _SecureAccessPill extends StatelessWidget {
  const _SecureAccessPill({this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: light ? Colors.white : LoginTheme.bluePrimary,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Secure access for municipal employees and HR staff.',
              style: TextStyle(
                color: light ? Colors.white : LoginTheme.bluePrimary,
                fontSize: light ? 13 : 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    if (!light) {
      return Container(
        decoration: BoxDecoration(
          color: LoginTheme.bluePrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.2),
          ),
        ),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LoginBranding extends StatelessWidget {
  const _LoginBranding({required this.lightText, required this.compact});

  final bool lightText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleColor = lightText ? Colors.white : AppTheme.textPrimary;
    final subtitleColor = lightText
        ? Colors.white.withValues(alpha: 0.92)
        : AppTheme.textSecondary;
    final logoSize = compact ? 72.0 : 88.0;

    final logo = _MunicipalityLogoCircle(
      size: logoSize,
      variant: _LoginLogoVariant.municipality,
      borderColor: lightText
          ? Colors.white.withValues(alpha: 0.45)
          : AppTheme.dashHairline,
      shadowAlpha: lightText ? 0.2 : 0.08,
    );

    final titles = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'Municipality of Plaridel',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: titleColor,
            fontSize: compact ? 20 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            height: 1.15,
            shadows: lightText
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Human Resource Management System',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: subtitleColor,
            fontSize: compact ? 11 : 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
            height: 1.3,
          ),
        ),
      ],
    );

    if (compact) {
      return Column(children: [logo, const SizedBox(height: 14), titles]);
    }

    return Row(
      children: [
        logo,
        const SizedBox(width: 18),
        Expanded(child: titles),
      ],
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
    required this.onRememberMeChanged,
    required this.onLogin,
    required this.onForgotPassword,
    this.isWebLayout = false,
    this.isMobileLayout = false,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool rememberMe;
  final bool isLoading;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final bool isWebLayout;
  final bool isMobileLayout;

  @override
  Widget build(BuildContext context) {
    final subtitleColor = AppTheme.textSecondary;
    final viewport = MediaQuery.sizeOf(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 80;
    final isCardForm = isWebLayout || isMobileLayout;
    final compactMobile =
        isMobileLayout && (viewport.width < 430 || viewport.height < 820);
    final veryCompactMobile =
        isMobileLayout && (viewport.width < 360 || viewport.height < 720);
    final compact = isWebLayout || compactMobile;

    final logoGap = veryCompactMobile ? 8.0 : (compact ? 12.0 : 24.0);
    final badgeGap = veryCompactMobile ? 10.0 : (compact ? 12.0 : 22.0);
    final titleGap = compact ? 8.0 : 10.0;
    final dividerBottomGap = veryCompactMobile ? 8.0 : (compact ? 10.0 : 14.0);
    final subtitleGap = veryCompactMobile
        ? 14.0
        : (compact ? 16.0 : (isWebLayout ? 22.0 : 28.0));
    final fieldGap = veryCompactMobile ? 10.0 : (compact ? 12.0 : 14.0);
    final actionGap = veryCompactMobile ? 12.0 : (compact ? 14.0 : 18.0);
    final buttonGap = veryCompactMobile ? 14.0 : (compact ? 16.0 : 20.0);
    final footerTopGap = veryCompactMobile ? 8.0 : (compact ? 10.0 : 14.0);
    final footerBottomGap = veryCompactMobile ? 8.0 : (compact ? 10.0 : 16.0);

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCardForm) ...[
          Center(child: _LoginFormLogo(compact: compact)),
          SizedBox(height: logoGap),
          Center(child: _LoginWebPortalBadge()),
          SizedBox(height: badgeGap),
        ],
        Text(
          'Welcome back',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: compact
                ? (veryCompactMobile ? 25 : 26)
                : (isWebLayout ? 26 : 34),
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.05,
          ),
        ),
        SizedBox(height: titleGap),
        Center(
          child: Container(
            width: compact ? 44 : 52,
            height: 3,
            margin: EdgeInsets.only(bottom: dividerBottomGap),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [LoginTheme.bluePrimary, LoginTheme.blueLight],
              ),
            ),
          ),
        ),
        Text(
          'Sign in to continue to your HRMS portal',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: subtitleColor.withValues(alpha: 0.95),
            fontSize: compact ? 14 : 16,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: subtitleGap),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LoginTextField(
                controller: emailController,
                label: 'Email',
                hintText: 'name@plaridel.gov.ph',
                icon: Icons.mail_outline_rounded,
                nextFocusNode: passwordFocusNode,
                autofillHints: const [AutofillHints.email],
                premium: isCardForm,
              ),
              SizedBox(height: fieldGap),
              _PasswordTextField(
                controller: passwordController,
                focusNode: passwordFocusNode,
                onSubmitted: onLogin,
                premium: isCardForm,
              ),
            ],
          ),
        ),
        SizedBox(height: actionGap),
        _LoginRememberForgotRow(
          rememberMe: rememberMe,
          onRememberMeChanged: onRememberMeChanged,
          onForgotPassword: onForgotPassword,
          compact: compactMobile,
        ),
        SizedBox(height: buttonGap),
        _LoginToHrmsButton(
          onPressed: isLoading ? null : onLogin,
          isLoading: isLoading,
          premium: isCardForm,
          compact: compact,
        ),
        if (!keyboardOpen) ...[
          SizedBox(height: footerTopGap),
          const Divider(height: 1, color: Color(0xFFEBEEF2)),
          SizedBox(height: footerBottomGap),
          _LoginFooterLinks(compact: compactMobile),
        ],
      ],
    );

    return _LoginFormCard(isMobileLayout: isMobileLayout, child: fields);
  }
}

class _LoginRememberForgotRow extends StatelessWidget {
  const _LoginRememberForgotRow({
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onForgotPassword,
    this.compact = false,
  });

  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onForgotPassword;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rememberControl = _RememberMeControl(
      rememberMe: rememberMe,
      onChanged: onRememberMeChanged,
      compact: compact,
    );
    final forgotButton = _ForgotPasswordButton(
      onPressed: onForgotPassword,
      compact: compact,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              rememberControl,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: forgotButton),
            ],
          );
        }

        return Row(
          children: [
            Flexible(child: rememberControl),
            SizedBox(width: compact ? 8 : 12),
            forgotButton,
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
    this.compact = false,
  });

  final bool rememberMe;
  final ValueChanged<bool?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          child: GestureDetector(
            onTap: () => onChanged(!rememberMe),
            child: Text(
              'Remember me',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary.withValues(alpha: 0.85),
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ForgotPasswordButton extends StatelessWidget {
  const _ForgotPasswordButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: LoginTheme.bluePrimary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Forgot password?',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: compact ? 13 : 14,
        ),
      ),
    );
  }
}

/// White login card with shadow — web and mobile full-page form.
class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({required this.child, this.isMobileLayout = false});

  final Widget child;
  final bool isMobileLayout;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final compactMobile =
        isMobileLayout && (screenSize.width < 430 || screenSize.height < 820);
    final horizontalPadding = isMobileLayout
        ? (compactMobile ? 22.0 : 28.0)
        : 28.0;
    final topPadding = isMobileLayout ? (compactMobile ? 22.0 : 32.0) : 26.0;
    final bottomPadding = isMobileLayout ? (compactMobile ? 20.0 : 28.0) : 22.0;
    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compactMobile ? 22 : _kCardRadius),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            LoginTheme.bluePrimary.withValues(alpha: 0.02),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.1),
            blurRadius: isMobileLayout ? 40 : 56,
            offset: Offset(0, isMobileLayout ? 14 : 20),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: isMobileLayout ? 24 : 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isMobileLayout
            ? screenWidth - (compactMobile ? 16 : 20)
            : _kLoginFormMaxWidth,
      ),
      child: card,
    );
  }
}

/// Web form portal badge above the welcome heading.
class _LoginWebPortalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LoginTheme.bluePrimary.withValues(alpha: 0.12),
            AppTheme.letterheadNavy.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LoginTheme.bluePrimary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_rounded, size: 16, color: LoginTheme.bluePrimary),
          const SizedBox(width: 8),
          Text(
            'Official HRMS Portal',
            style: TextStyle(
              color: LoginTheme.bluePrimary.withValues(alpha: 0.95),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle pulse on the web login crest.
class _LoginFormLogoAnimated extends StatefulWidget {
  const _LoginFormLogoAnimated();

  @override
  State<_LoginFormLogoAnimated> createState() => _LoginFormLogoAnimatedState();
}

class _LoginFormLogoAnimatedState extends State<_LoginFormLogoAnimated>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.97,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: const _LoginFormLogo(),
    );
  }
}

/// Small crest centered at the top of the login card (right panel).
class _LoginFormLogo extends StatelessWidget {
  const _LoginFormLogo({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final seal = compact ? 56.0 : 80.0;
    return Container(
      padding: EdgeInsets.all(compact ? 3 : 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LoginTheme.bluePrimary.withValues(alpha: 0.2),
            AppTheme.letterheadNavy.withValues(alpha: 0.08),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.16),
            blurRadius: compact ? 14 : 20,
            offset: Offset(0, compact ? 5 : 8),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.12),
            width: 2,
          ),
        ),
        child: _MunicipalityLogoCircle(
          size: seal,
          variant: _LoginLogoVariant.hrms,
          borderColor: const Color(0xFFE8ECF0),
          shadowAlpha: 0.12,
        ),
      ),
    );
  }
}

/// Faint grid on the web form panel background.
class _LoginWebGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 32.0;
    final paint = Paint()
      ..color = AppTheme.letterheadNavy.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Circular logo mark — HRMS (form) or municipality seal (hero).
class _MunicipalityLogoCircle extends StatelessWidget {
  const _MunicipalityLogoCircle({
    required this.size,
    required this.borderColor,
    this.variant = _LoginLogoVariant.hrms,
    this.shadowAlpha = 0.08,
  });

  final double size;
  final Color borderColor;
  final _LoginLogoVariant variant;
  final double shadowAlpha;

  @override
  Widget build(BuildContext context) {
    final isHrms = variant == _LoginLogoVariant.hrms;
    final asset = isHrms ? _kHrmsLogoAsset : _kPlaridelLogoAsset;
    final inset = isHrms ? size * 0.12 : 0.0;
    final fit = isHrms ? BoxFit.contain : BoxFit.cover;

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
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(inset),
          child: Image.asset(
            asset,
            fit: fit,
            width: size - inset * 2,
            height: size - inset * 2,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => ColoredBox(
              color: LoginTheme.bluePrimary.withValues(alpha: 0.1),
              child: Icon(
                isHrms ? Icons.hub_rounded : Icons.account_balance_rounded,
                color: LoginTheme.bluePrimary,
                size: size * 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginFooterLinks extends StatelessWidget {
  const _LoginFooterLinks({this.compact = false});

  static const _muted = Color(0xFF6C757D);
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: _muted.withValues(alpha: 0.92),
      fontSize: compact ? 11 : 12,
      fontWeight: FontWeight.w500,
      height: compact ? 1.25 : 1.4,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('© ${DateTime.now().year} HRMS Plaridel', style: base),
        Text('·', style: base.copyWith(color: _muted.withValues(alpha: 0.5))),
        Text(
          'Privacy',
          style: base.copyWith(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text('·', style: base.copyWith(color: _muted.withValues(alpha: 0.5))),
        Text(
          'Terms',
          style: base.copyWith(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LoginTextField extends StatefulWidget {
  const _LoginTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.nextFocusNode,
    this.autofillHints,
    this.premium = false,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final FocusNode? nextFocusNode;
  final Iterable<String>? autofillHints;
  final bool premium;

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

  void _ensureFocus() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _ensureFocus,
          behavior: HitTestBehavior.opaque,
          child: Text(
            widget.label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _kFieldHeight,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.emailAddress,
            autofillHints: widget.autofillHints,
            autocorrect: false,
            textInputAction: TextInputAction.next,
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
              premium: widget.premium,
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
    this.focusNode,
    this.onSubmitted,
    this.premium = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;
  final bool premium;

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

  void _ensureFocus() {
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _ensureFocus,
          behavior: HitTestBehavior.opaque,
          child: const Text(
            'Password',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _kFieldHeight,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
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
              premium: widget.premium,
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

Widget _inputIconBox(IconData icon) {
  return Container(
    width: 38,
    height: 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: LoginTheme.bluePrimary.withValues(alpha: 0.12),
      border: Border.all(color: LoginTheme.bluePrimary.withValues(alpha: 0.08)),
    ),
    child: Icon(icon, color: LoginTheme.bluePrimary, size: 19),
  );
}

InputDecoration _inputDecoration({
  required String hint,
  required IconData icon,
  required bool focused,
  Widget? suffix,
  bool premium = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withValues(alpha: 0.7),
      fontSize: 15,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 10, right: 2),
      child: IgnorePointer(child: _inputIconBox(icon)),
    ),
    prefixIconConstraints: const BoxConstraints(
      minWidth: 54,
      minHeight: _kFieldHeight,
    ),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(
      minWidth: 44,
      minHeight: _kFieldHeight,
    ),
    filled: true,
    fillColor: premium && focused ? Colors.white : const Color(0xFFF6F7F9),
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: BorderSide(
        color: LoginTheme.bluePrimary,
        width: premium ? 2 : 1.5,
      ),
    ),
  );
}

class _LoginToHrmsButton extends StatefulWidget {
  const _LoginToHrmsButton({
    this.onPressed,
    this.isLoading = false,
    this.premium = false,
    this.compact = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final bool premium;
  final bool compact;

  @override
  State<_LoginToHrmsButton> createState() => _LoginToHrmsButtonState();
}

class _LoginToHrmsButtonState extends State<_LoginToHrmsButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  AnimationController? _shineCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.premium) {
      _shineCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _LoginToHrmsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.premium && _shineCtrl == null) {
      _shineCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _shineCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final height = widget.compact ? 50.0 : (widget.premium ? 56.0 : 54.0);

    Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kButtonRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: enabled
              ? [
                  _hover ? LoginTheme.blueLight : const Color(0xFFF0671A),
                  LoginTheme.bluePrimary,
                  LoginTheme.blueDark,
                ]
              : [
                  LoginTheme.bluePrimary.withValues(alpha: 0.45),
                  LoginTheme.blueDark.withValues(alpha: 0.45),
                ],
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: LoginTheme.bluePrimary.withValues(
                    alpha: _hover ? 0.5 : 0.36,
                  ),
                  blurRadius: widget.premium ? 22 : 12,
                  offset: Offset(0, _hover ? 8 : 5),
                ),
                if (widget.premium)
                  BoxShadow(
                    color: AppTheme.letterheadNavy.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isLoading ? null : widget.onPressed,
          borderRadius: BorderRadius.circular(_kButtonRadius),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.premium) ...[
                        const Icon(
                          Icons.login_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Text(
                        'Sign In to HRMS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (widget.premium && _shineCtrl != null) {
      button = AnimatedBuilder(
        animation: _shineCtrl!,
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kButtonRadius),
                    child: CustomPaint(
                      painter: _LoginButtonShinePainter(
                        progress: _shineCtrl!.value,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: button,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: enabled && _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 180),
        child: button,
      ),
    );
  }
}

class _LoginButtonShinePainter extends CustomPainter {
  const _LoginButtonShinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = (progress * 2 - 0.5) * size.width;
    final rect = Rect.fromLTWH(x - 40, 0, 80, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _LoginButtonShinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
