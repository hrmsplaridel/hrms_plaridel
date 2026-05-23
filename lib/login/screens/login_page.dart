import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/screens/admin_dashboard.dart';
import '../../employee/screens/employee_dashboard.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../main.dart' show kLoginAsKey;
import '../../providers/auth_provider.dart';
import '../constants/login_theme.dart';

const _rememberKey = 'login_remember_v1';
const _rememberEmailKey = 'login_remember_email_v1';

/// Shared radii for the login form (right panel / mobile card).
const _kCardRadius = 24.0;
const _kInputRadius = 12.0;
const _kButtonRadius = 12.0;
const _kFieldHeight = 52.0;

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
  late final Animation<Offset> _entranceSlide;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
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
      onDarkBackground: !isWide,
    );

    return Scaffold(
      backgroundColor: isWide ? AppTheme.offWhite : const Color(0xFF1A1A1A),
      body: isWide
          ? Row(
              children: [
                const Expanded(child: _LoginHeroPanel()),
                Expanded(
                  child: _LoginFormShell(
                    child: FadeTransition(
                      opacity: _entranceFade,
                      child: SlideTransition(
                        position: _entranceSlide,
                        child: form,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                const _LoginHeroBackground(),
                SafeArea(
                  child: Column(
                    children: [
                      if (Navigator.of(context).canPop())
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                            child: _LoginBackButton(compact: true),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: _LoginBranding(lightText: true, compact: true),
                      ),
                      const Spacer(),
                      FadeTransition(
                        opacity: _entranceFade,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(_entranceFade),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(32),
                            ),
                            child: ColoredBox(
                              color: const Color(0xFFFAFBFC),
                              child: form,
                            ),
                          ),
                        ),
                      ),
                    ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
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
          'assets/images/PlaridelBuildingC.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
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

/// Left panel on wide screens (image layer unchanged).
class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _LoginHeroBackground(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (Navigator.of(context).canPop())
                  const _LoginBackButton(showLabel: true),
                const Spacer(),
                const _LoginBranding(lightText: true, compact: false),
                const SizedBox(height: 28),
                const _SecureAccessPill(light: true),
                const Spacer(flex: 2),
              ],
            ),
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

class _LoginFormShell extends StatelessWidget {
  const _LoginFormShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border(
          left: BorderSide(color: Color(0xFFEBEEF2)),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _LoginBackButton extends StatelessWidget {
  const _LoginBackButton({
    this.compact = false,
    this.showLabel = false,
  });

  final bool compact;
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
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 14,
                  vertical: compact ? 8 : 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: compact ? 18 : 20,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 13 : 14,
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
        padding: EdgeInsets.all(compact ? 8 : 10),
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(
          Icons.arrow_back_rounded,
          size: compact ? 22 : 24,
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
            color: light ? Colors.black : LoginTheme.bluePrimary,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Secure access for municipal employees and HR staff.',
              style: TextStyle(
                color: light ? Colors.black : LoginTheme.bluePrimary,
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
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.38),
            ),
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
    final titleColor = lightText ? Colors.black : AppTheme.textPrimary;
    final subtitleColor = lightText
        ? Colors.black.withValues(alpha: 0.85)
        : AppTheme.textSecondary;
    final logoSize = compact ? 72.0 : 88.0;

    final logo = _MunicipalityLogoCircle(
      size: logoSize,
      borderColor: lightText
          ? Colors.white.withValues(alpha: 0.45)
          : AppTheme.dashHairline,
      shadowAlpha: lightText ? 0.2 : 0.08,
    );

    final titles = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
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
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 8,
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
      return Column(
        children: [logo, const SizedBox(height: 14), titles],
      );
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
    required this.onDarkBackground,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool rememberMe;
  final bool isLoading;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final subtitleColor = AppTheme.textSecondary;
    final centered = !onDarkBackground;

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (centered || onDarkBackground) ...[
          const Center(child: _LoginFormLogo()),
          const SizedBox(height: 28),
        ],
        Text(
          'Welcome back',
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.08,
          ),
        ),
        SizedBox(height: centered ? 12 : 10),
        if (centered)
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    LoginTheme.bluePrimary,
                    LoginTheme.blueLight.withValues(alpha: 0.85),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: LoginTheme.bluePrimary.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        Text(
          'Sign in to continue to your HRMS portal',
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: subtitleColor.withValues(alpha: 0.95),
            fontSize: 15.5,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (onDarkBackground) ...[
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: _SecureAccessPill(),
          ),
        ],
        const SizedBox(height: 32),
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
        ),
        const SizedBox(height: 20),
        _PasswordTextField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          onSubmitted: onLogin,
        ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            SizedBox(
              height: 22,
              width: 22,
              child: Checkbox(
                value: rememberMe,
                onChanged: onRememberMeChanged,
                activeColor: LoginTheme.bluePrimary,
                checkColor: Colors.white,
                side: const BorderSide(
                  color: Color(0xFFADB5BD),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => onRememberMeChanged(!rememberMe),
              child: Text(
                'Remember me',
                style: TextStyle(
                  color: AppTheme.textPrimary.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: LoginTheme.bluePrimary,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _LoginToHrmsButton(
          onPressed: isLoading ? null : onLogin,
          isLoading: isLoading,
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFEBEEF2)),
        const SizedBox(height: 20),
        const _LoginFooterLinks(),
      ],
    );

    return _LoginFormCard(
      onDarkBackground: onDarkBackground,
      child: fields,
    );
  }
}

/// White login card with shadow — used on desktop and mobile sheet.
class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.child,
    required this.onDarkBackground,
  });

  final Widget child;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        onDarkBackground ? 28 : 44,
        onDarkBackground ? 32 : 48,
        onDarkBackground ? 28 : 44,
        onDarkBackground ? 28 : 40,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          onDarkBackground ? 20 : _kCardRadius,
        ),
        border: Border.all(
          color: onDarkBackground
              ? Colors.transparent
              : const Color(0xFFE8ECF0),
        ),
        boxShadow: [
          BoxShadow(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.05),
            blurRadius: 40,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    if (onDarkBackground) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: child,
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 432),
      child: card,
    );
  }
}

/// Small crest centered at the top of the login card (right panel).
class _LoginFormLogo extends StatelessWidget {
  const _LoginFormLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: LoginTheme.bluePrimary.withValues(alpha: 0.15),
          width: 2,
        ),
      ),
      child: const _MunicipalityLogoCircle(
        size: 68,
        borderColor: Color(0xFFE8ECF0),
        shadowAlpha: 0.1,
      ),
    );
  }
}

/// Circular municipality seal with white fill and soft shadow.
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
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/Plaridel Logo.jpg',
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: LoginTheme.bluePrimary.withValues(alpha: 0.1),
            child: Icon(
              Icons.account_balance_rounded,
              color: LoginTheme.bluePrimary,
              size: size * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginFooterLinks extends StatelessWidget {
  const _LoginFooterLinks();

  static const _muted = Color(0xFF6C757D);

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: _muted.withValues(alpha: 0.92),
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
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
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final FocusNode? nextFocusNode;
  final Iterable<String>? autofillHints;

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
        Text(
          widget.label,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
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
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: widget.hintText,
              icon: widget.icon,
              focused: _focused,
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
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

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
        const Text(
          'Password',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
        SizedBox(
          height: _kFieldHeight,
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => widget.onSubmitted?.call(),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: _inputDecoration(
              hint: 'Enter your password',
              icon: Icons.lock_outline_rounded,
              focused: _focused,
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
      border: Border.all(
        color: LoginTheme.bluePrimary.withValues(alpha: 0.08),
      ),
    ),
    child: Icon(icon, color: LoginTheme.bluePrimary, size: 19),
  );
}

InputDecoration _inputDecoration({
  required String hint,
  required IconData icon,
  required bool focused,
  Widget? suffix,
}) {
  final borderColor =
      focused ? LoginTheme.bluePrimary : const Color(0xFFE2E6EA);

  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withValues(alpha: 0.7),
      fontSize: 15,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 10, right: 2),
      child: _inputIconBox(icon),
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
    fillColor: const Color(0xFFF6F7F9),
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: const BorderSide(color: Color(0xFFE2E6EA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kInputRadius),
      borderSide: const BorderSide(color: LoginTheme.bluePrimary, width: 2),
    ),
  );
}

class _LoginToHrmsButton extends StatefulWidget {
  const _LoginToHrmsButton({this.onPressed, this.isLoading = false});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<_LoginToHrmsButton> createState() => _LoginToHrmsButtonState();
}

class _LoginToHrmsButtonState extends State<_LoginToHrmsButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: enabled && _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 180),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kButtonRadius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: enabled
                  ? [
                      _hover
                          ? LoginTheme.blueLight
                          : const Color(0xFFF0671A),
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
                        alpha: _hover ? 0.45 : 0.32,
                      ),
                      blurRadius: _hover ? 18 : 12,
                      offset: Offset(0, _hover ? 6 : 4),
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
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Sign In to HRMS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
