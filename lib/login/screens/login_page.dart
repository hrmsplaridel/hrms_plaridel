import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/login_theme.dart';
import '../models/login_role.dart';
import '../../dashboard/screens/admin_dashboard.dart';
import '../../dashboard/screens/employee_dashboard.dart';

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
  LoginRole _role = LoginRole.admin;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          if (isWide) Expanded(flex: 4, child: _BrandingSection()),
          Expanded(
            flex: isWide ? 6 : 1,
            child: _LoginFormSection(
              emailController: _emailController,
              passwordController: _passwordController,
              passwordFocusNode: _passwordFocusNode,
              rememberMe: _rememberMe,
              role: _role,
              isLoading: _isLoading,
              onRoleChanged: (r) => setState(() => _role = r),
              onRememberMeChanged: (v) => setState(() => _rememberMe = v ?? false),
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
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        final isEmployee = _role == LoginRole.employee;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => isEmployee ? const EmployeeDashboard() : const AdminDashboard(),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        final isEmailNotConfirmed = e.message.toLowerCase().contains('email not confirmed') ||
            e.message.toLowerCase().contains('confirm your email');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEmailNotConfirmed
                  ? 'Please confirm your email first. Check your inbox and click the link from Supabase, then try logging in again.'
                  : e.message,
            ),
            duration: const Duration(seconds: 5),
          ),
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
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 56,
                      height: 56,
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
                          fontSize: 22,
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
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Modernizing Human Resource Services',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.groups_rounded, size: 100, color: Colors.white.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Icon(Icons.business_center_rounded, size: 64, color: Colors.white.withOpacity(0.4)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right panel: white form — Welcome Back, role (Admin/Employee), fields, Remember Me, Forgot Password, Login to HRMS, footer.
class _LoginFormSection extends StatelessWidget {
  const _LoginFormSection({
    required this.emailController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.rememberMe,
    required this.role,
    required this.isLoading,
    required this.onRoleChanged,
    required this.onRememberMeChanged,
    required this.onLogin,
    required this.onForgotPassword,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool rememberMe;
  final LoginRole role;
  final bool isLoading;
  final ValueChanged<LoginRole> onRoleChanged;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LoginTheme.formBackground,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        'Welcome Back!',
                        style: TextStyle(
                          color: LoginTheme.textDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please login to your account',
                        style: TextStyle(
                          color: LoginTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Login as',
                        style: TextStyle(
                          color: LoginTheme.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _RoleSelector(
                        selectedRole: role,
                        onChanged: onRoleChanged,
                      ),
                      const SizedBox(height: 24),
                      _LoginTextField(
                        controller: emailController,
                        hint: 'Email or Employee ID',
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
                              activeColor: LoginTheme.bluePrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Remember Me',
                            style: TextStyle(
                              color: LoginTheme.textDark,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: onForgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: LoginTheme.bluePrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('Forgot Password?'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _LoginToHrmsButton(
                        onPressed: isLoading ? null : onLogin,
                        isLoading: isLoading,
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '© 2026 HRMS',
                            style: TextStyle(
                              color: LoginTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '|',
                            style: TextStyle(color: LoginTheme.textSecondary, fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: LoginTheme.bluePrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Privacy Policy', style: TextStyle(fontSize: 12)),
                          ),
                          Text(
                            '|',
                            style: TextStyle(color: LoginTheme.textSecondary, fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: LoginTheme.bluePrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Terms of Use', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                color: LoginTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({
    required this.selectedRole,
    required this.onChanged,
  });

  final LoginRole selectedRole;
  final ValueChanged<LoginRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleChip(
            label: 'Admin',
            isSelected: selectedRole == LoginRole.admin,
            onTap: () => onChanged(LoginRole.admin),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleChip(
            label: 'Employee',
            isSelected: selectedRole == LoginRole.employee,
            onTap: () => onChanged(LoginRole.employee),
          ),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? LoginTheme.bluePrimary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? LoginTheme.bluePrimary : LoginTheme.borderLight,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : LoginTheme.textDark,
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
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
        prefixIcon: Icon(icon, color: LoginTheme.bluePrimary, size: 22),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LoginTheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LoginTheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LoginTheme.bluePrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        prefixIcon: Icon(Icons.lock_outline, color: LoginTheme.bluePrimary, size: 22),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: LoginTheme.bluePrimary,
            size: 22,
          ),
          tooltip: _obscure ? 'Show password' : 'Hide password',
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LoginTheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LoginTheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LoginTheme.bluePrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          gradient: LinearGradient(
            colors: onPressed != null && !isLoading
                ? [LoginTheme.blueLight, LoginTheme.blueDark]
                : [LoginTheme.blueLight.withOpacity(0.7), LoginTheme.blueDark.withOpacity(0.7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
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
                  : const Text(
                      'Login to HRMS',
                      style: TextStyle(
                        color: Colors.white,
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

