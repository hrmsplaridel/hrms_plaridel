import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../constants/login_theme.dart';
import '../../admin/screens/admin_dashboard.dart';
import '../../employee/screens/employee_dashboard.dart';
import '../../main.dart' show kLoginAsKey;

/// Login screen: left = blue branding/illustration, right = white form.
/// Reference: Welcome Back, Email/Employee ID, Password, Remember Me, Forgot Password, Login to HRMS.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          if (isWide) Expanded(flex: 6, child: _BrandingSection()),
          Expanded(
            flex: isWide ? 4 : 1,
            child: _LoginFormSection(
              emailController: _emailController,
              passwordController: _passwordController,
              passwordFocusNode: _passwordFocusNode,
              rememberMe: _rememberMe,
              isLoading: _isLoading,
              onRememberMeChanged: (v) =>
                  setState(() => _rememberMe = v ?? false),
              onLogin: _onLogin,
              onForgotPassword: _onForgotPassword,
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
        final auth = context.read<AuthProvider>();
        final role = auth.user?.role ?? 'employee';
        final isAdmin = role == 'admin';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLoginAsKey, isAdmin ? 'Admin' : 'Employee');

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                isAdmin ? const AdminDashboard() : const EmployeeDashboard(),
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
    // TODO: navigate to forgot password
  }
}

/// Left panel: blue gradient, HR logo/title, tagline, illustration.
class _BrandingSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/images/Building.jpg'),
          fit: BoxFit.cover,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LoginTheme.brandingGradientStart,
            LoginTheme.brandingGradientEnd,
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 56),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 120,
                      height: 120,
                      color: Colors.white.withOpacity(0.2),
                      child: Image.asset(
                        'assets/images/Plaridel Logo.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.shield_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Municipality of Plaridel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'HUMAN RESOURCE MANAGEMENT SYSTEM',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Text(
                'Modernizing Human Resource Services',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right panel: white form — Welcome Back, Email/Employee ID, Password, Remember Me, Forgot Password, Login.
class _LoginFormSection extends StatelessWidget {
  const _LoginFormSection({
    required this.emailController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.rememberMe,
    required this.isLoading,
    required this.onRememberMeChanged,
    required this.onLogin,
    required this.onForgotPassword,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool rememberMe;
  final bool isLoading;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFD65A00),
      child: SafeArea(
        child: Stack(
          children: [
            if (kIsWeb)
              Positioned(
                top: 0,
                left: 0,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  color: Colors.white,
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      const Text(
                    'Welcome Back!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                      const SizedBox(height: 4),
                      Text(
                        'Please login to your account',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _LoginTextField(
                        controller: emailController,
                        hint: 'Email',
                        icon: Icons.mail_outline,
                        nextFocusNode: passwordFocusNode,
                      ),
                      const SizedBox(height: 16),
                      _PasswordTextField(
                        controller: passwordController,
                        focusNode: passwordFocusNode,
                        onSubmitted: onLogin,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: rememberMe,
                              onChanged: onRememberMeChanged,
                              activeColor: Colors.white,
                              checkColor: const Color(0xFFD65A00),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Remember Me',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: onForgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Forgot Password?'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _LoginToHrmsButton(
                        onPressed: isLoading ? null : onLogin,
                        isLoading: isLoading,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            '© 2026 HRMS',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '|',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '|',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Terms of Use',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.nextFocusNode,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final FocusNode? nextFocusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => nextFocusNode?.requestFocus(),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: const Color(0xFFD65A00),
          size: 22,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.white,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        hintText: 'Password',
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: Color(0xFFD65A00),
          size: 22,
        ),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: const Color(0xFFD65A00),
            size: 22,
          ),
          tooltip: _obscure ? 'Show password' : 'Hide password',
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(
            color: Colors.white,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

class _LoginToHrmsButton extends StatelessWidget {
  const _LoginToHrmsButton({this.onPressed, this.isLoading = false});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: onPressed != null && !isLoading
              ? Colors.white
              : Colors.white70,
          boxShadow: [
            BoxShadow(
              color: LoginTheme.bluePrimary.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Login to HRMS',
                      style: TextStyle(
                        color: const Color(0xFFD65A00),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
