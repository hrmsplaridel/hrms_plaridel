import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../api/client.dart';
import '../../api/config.dart';
import '../../data/recruitment_application.dart';
import '../../providers/recruitment_hire_prefill.dart';
import '../../widgets/structured_address_fields.dart';
import '../dtr_provider.dart';
import '../repositories/biometric_import_repository.dart';
import '../dtr_share.dart';
import '../../landingpage/constants/app_theme.dart';

/// Employee profile for Manage screen (full data from profiles).
class _EmployeeProfile {
  const _EmployeeProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.employeeNumber,
    this.email,
    this.isActive = true,
    this.avatarPath,
    this.middleName,
    this.suffix,
    this.sex,
    this.dateOfBirth,
    this.contactNumber,
    this.address,
    this.employmentType,
    this.salaryGrade,
    this.dateHired,
    this.employmentStatus,
    this.biometricUserId,
    this.departmentName,
    this.positionName,
  });
  final String id;
  final String fullName;
  final String role;

  /// Human-friendly number (1, 2, 3...) for display and ad-hoc queries.
  final int? employeeNumber;
  final String? email;
  final bool isActive;
  final String? avatarPath;
  final String? middleName;
  final String? suffix;
  final String? sex;
  final DateTime? dateOfBirth;
  final String? contactNumber;
  final String? address;
  final String? employmentType;
  final String? salaryGrade;
  final DateTime? dateHired;
  final String? employmentStatus;
  final String? biometricUserId;
  final String? departmentName;
  final String? positionName;

  String get roleDisplay => role == 'admin' ? 'Admin' : 'Employee';

  /// Current assignment from API (department · position), or em dash if none.
  String get assignmentDisplay {
    final d = departmentName?.trim();
    final p = positionName?.trim();
    final hasD = d != null && d.isNotEmpty;
    final hasP = p != null && p.isNotEmpty;
    if (!hasD && !hasP) return '—';
    if (d != null && d.isNotEmpty && p != null && p.isNotEmpty) {
      return '$d · $p';
    }
    if (d != null && d.isNotEmpty) return d;
    if (p != null && p.isNotEmpty) return p;
    return '—';
  }

  String get displayEmployeeNo {
    if (employeeNumber == null) return '—';
    return 'EMP-${employeeNumber!.toString().padLeft(3, '0')}';
  }
}

/// Create Account form. Use inline in Dashboard. Single place for adding employees.
class AddEmployeeForm extends StatefulWidget {
  const AddEmployeeForm({super.key, this.onAccountCreated});

  /// When set (e.g. opened from a dialog), invoked after a successful create instead of only a snackbar.
  final VoidCallback? onAccountCreated;

  @override
  State<AddEmployeeForm> createState() => _AddEmployeeFormState();
}

class _AddEmployeeFormState extends State<AddEmployeeForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _streetController = TextEditingController();
  GlobalKey<StructuredAddressFormState> _addressFormKey =
      GlobalKey<StructuredAddressFormState>();
  final _salaryGradeController = TextEditingController();

  String? _privilege;
  String? _suffix;
  String? _sex;
  DateTime? _dateOfBirth;
  String? _employmentType;
  String _employmentStatus = 'active';
  DateTime? _dateHired;
  bool _obscurePassword = true;
  bool _obscureRepeatPassword = true;
  Uint8List? _selectedImageBytes;
  bool _saving = false;
  int? _lastAppliedPrefillStamp;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hire = context.read<RecruitmentHirePrefill>();
    if (!hire.hasPendingLink) {
      _lastAppliedPrefillStamp = null;
      return;
    }
    if (hire.prefillStamp == _lastAppliedPrefillStamp) return;
    _lastAppliedPrefillStamp = hire.prefillStamp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = context.read<RecruitmentHirePrefill>();
      if (!h.hasPendingLink) return;
      _applyRecruitmentPrefill(h);
    });
  }

  void _applyRecruitmentPrefill(RecruitmentHirePrefill hire) {
    final em = hire.applicantEmail;
    if (em != null && em.isNotEmpty) {
      _emailController.text = em;
    }
    final raw = hire.applicantFullName?.trim() ?? '';
    if (raw.isNotEmpty) {
      final sp = raw.indexOf(' ');
      if (sp < 0) {
        _firstNameController.text = raw;
        _lastNameController.text = raw;
      } else {
        _firstNameController.text = raw.substring(0, sp).trim();
        _lastNameController.text = raw.substring(sp + 1).trim();
        if (_lastNameController.text.isEmpty) {
          _lastNameController.text = _firstNameController.text;
        }
      }
    }
    final ph = hire.applicantPhone?.trim();
    if (ph != null && ph.isNotEmpty) {
      _contactController.text = ph;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _repeatPasswordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _streetController.dispose();
    _salaryGradeController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.9),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.65),
          fontSize: 14,
        ),
        filled: true,
        fillColor: AppTheme.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.lightGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.lightGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
        ),
      );

  Widget _paneHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.bytes != null) {
      setState(() {
        _selectedImageBytes = result.files.single.bytes;
      });
    }
  }

  void _clearForm() {
    _emailController.clear();
    _passwordController.clear();
    _repeatPasswordController.clear();
    _firstNameController.clear();
    _middleNameController.clear();
    _lastNameController.clear();
    _contactController.clear();
    _streetController.clear();
    _salaryGradeController.clear();
    setState(() {
      _addressFormKey = GlobalKey<StructuredAddressFormState>();
      _privilege = null;
      _suffix = null;
      _sex = null;
      _dateOfBirth = null;
      _employmentType = null;
      _employmentStatus = 'active';
      _dateHired = null;
      _selectedImageBytes = null;
    });
  }

  Future<void> _saveEmployee() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final suffixPart = (_suffix != null && _suffix != 'None')
        ? ' ${_suffix!}'
        : '';
    final fullName =
        '$firstName${middleName.isNotEmpty ? ' $middleName' : ''} $lastName$suffixPart'
            .trim();
    final privilege = _privilege ?? 'Employee';
    final role = privilege == 'Admin' ? 'admin' : 'employee';

    setState(() => _saving = true);
    try {
      final encodedAddress =
          _addressFormKey.currentState?.composeEncoded() ?? '';
      final body = <String, dynamic>{
        'email': email,
        'password': password,
        'full_name': fullName,
        'role': role,
        if (middleName.isNotEmpty) 'middle_name': middleName,
        if (_suffix != null && _suffix != 'None') 'suffix': _suffix,
        if (_sex != null) 'sex': _sex,
        if (_dateOfBirth != null)
          'date_of_birth': _dateOfBirth!.toIso8601String().split('T')[0],
        if (_contactController.text.trim().isNotEmpty)
          'contact_number': _contactController.text.trim(),
        if (encodedAddress.isNotEmpty) 'address': encodedAddress,
        if (_employmentType != null) 'employment_type': _employmentType,
        if (_salaryGradeController.text.trim().isNotEmpty)
          'salary_grade': _salaryGradeController.text.trim(),
        'date_hired': _dateHired!.toIso8601String().split('T')[0],
        'employment_status': _employmentStatus,
      };

      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/employees',
        data: body,
      );
      if (!mounted) return;
      final data = res.data;
      if (data == null || data['id'] == null) {
        _showSnackBar('Account creation failed');
        return;
      }

      final userId = data['id'] as String;

      final hire = context.read<RecruitmentHirePrefill>();
      if (hire.hasPendingLink && hire.applicationId != null) {
        try {
          await RecruitmentRepo.instance.linkHiredUser(
            hire.applicationId!,
            userId,
          );
          hire.clear();
          _lastAppliedPrefillStamp = null;
        } catch (e) {
          if (mounted) {
            _showSnackBar(
              'Account created, but linking to recruitment failed: $e',
            );
          }
        }
      }

      if (_selectedImageBytes != null && _selectedImageBytes!.isNotEmpty) {
        try {
          await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
            '/api/upload/avatar/for/$userId',
            bytes: _selectedImageBytes!,
            fileName: 'avatar.jpg',
          );
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      }

      if (!mounted) return;
      try {
        final dtr = context.read<DtrProvider>();
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      } catch (_) {}
      _clearForm();
      if (widget.onAccountCreated != null) {
        widget.onAccountCreated!();
      } else {
        _showSnackBar(
          'Account created successfully. They can sign in with their email and password.',
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        _showSnackBar('Email already registered');
      } else {
        final msg = e.response?.data is Map
            ? (e.response!.data as Map)['error']?.toString()
            : e.message ?? 'Failed';
        _showSnackBar(msg ?? 'Failed');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;
    final sectionGap = isNarrow ? 18.0 : 24.0;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Consumer<RecruitmentHirePrefill>(
            builder: (context, hire, _) {
              if (!hire.hasPendingLink) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Material(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.how_to_reg_rounded,
                          color: AppTheme.primaryNavy,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You opened this form from RSP (final interview passed). '
                            'Email and name are prefilled from the applicant. After you save, their recruitment record is linked automatically.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Padding(
              padding: EdgeInsets.all(isNarrow ? 16 : 24),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionCard(
                          child: _buildAccountSection(narrow: true),
                        ),
                        SizedBox(height: sectionGap),
                        _buildSectionCard(child: _buildPersonalSection()),
                        SizedBox(height: sectionGap),
                        _buildEmploymentSection(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSectionCard(
                                child: _buildAccountSection(narrow: false),
                              ),
                              SizedBox(height: sectionGap),
                              _buildEmploymentSection(),
                            ],
                          ),
                        ),
                        SizedBox(width: sectionGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSectionCard(child: _buildPersonalSection()),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: BoxDecoration(
              color: AppTheme.white,
              border: Border(
                top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: _saving ? null : _saveEmployee,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection({required bool narrow}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paneHeader(
          'Account',
          'Photo and sign-in credentials for the new user.',
        ),
        const SizedBox(height: 18),
        Center(
          child: _selectedImageBytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(48),
                  child: Image.memory(
                    _selectedImageBytes!,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                )
              : CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.lightGray,
                  child: Icon(
                    Icons.person_rounded,
                    size: 56,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: const Text('Select Image'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 22),
        TextFormField(
          controller: _emailController,
          decoration: _fieldDecoration('Email'),
          keyboardType: TextInputType.emailAddress,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _passwordController,
          decoration: _fieldDecoration('Password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          obscureText: _obscurePassword,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _repeatPasswordController,
          decoration: _fieldDecoration('Repeat password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscureRepeatPassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onPressed: () => setState(
                () => _obscureRepeatPassword = !_obscureRepeatPassword,
              ),
            ),
          ),
          obscureText: _obscureRepeatPassword,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (v != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _privilege,
          isExpanded: true,
          decoration: _fieldDecoration('Role', hint: 'Admin or Employee'),
          items: [
            'Admin',
            'Employee',
          ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _privilege = v),
          validator: (v) => v == null ? 'Required' : null,
        ),
        SizedBox(height: narrow ? 14 : 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppTheme.primaryNavy.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Passwords are encrypted. The new user signs in with email and password.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }

  Widget _buildPersonalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _paneHeader(
          'Personal details',
          'Legal name, demographics, contact, and structured address.',
        ),
        const SizedBox(height: 18),
        Text(
          'Name',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _firstNameController,
          decoration: _fieldDecoration('First name'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _middleNameController,
          decoration: _fieldDecoration('Middle name (optional)'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _lastNameController,
          decoration: _fieldDecoration('Last name'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _suffix ?? 'None',
          isExpanded: true,
          decoration: _fieldDecoration('Suffix', hint: 'None, Jr., Sr., …'),
          items: [
            'None',
            'Jr.',
            'Sr.',
            'II',
            'III',
            'IV',
          ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _suffix = (v == 'None') ? null : v),
        ),
        const SizedBox(height: 20),
        Text(
          'Demographics & contact',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _sex,
          isExpanded: true,
          decoration: _fieldDecoration('Sex', hint: 'Male or Female'),
          items: [
            'Male',
            'Female',
          ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _sex = v),
          validator: (v) => v == null ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _dateOfBirth ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (date != null) setState(() => _dateOfBirth = date);
          },
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration:
                _fieldDecoration(
                  'Date of birth',
                  hint: 'Tap to open calendar',
                ).copyWith(
                  suffixIcon: Icon(
                    Icons.calendar_today_rounded,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
            child: Text(
              _dateOfBirth != null
                  ? '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                  : 'Tap calendar to choose',
              style: TextStyle(
                fontSize: 14,
                color: _dateOfBirth != null
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _contactController,
          decoration: _fieldDecoration('Contact number'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 20),
        StructuredAddressForm(
          key: _addressFormKey,
          streetController: _streetController,
          initialRawAddress: null,
          inputDecoration: _fieldDecoration,
        ),
      ],
    );
  }

  Widget _buildEmploymentSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Employment',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _employmentType,
            decoration: _fieldDecoration('Employment Type'),
            hint: const Text('Employment Type'),
            items: [
              'regular',
              'contractual',
              'job_order',
              'casual',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _employmentType = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _salaryGradeController,
            decoration: _fieldDecoration('Salary Grade'),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 16),
          FormField<DateTime>(
            key: ValueKey(_dateHired?.toIso8601String() ?? 'hire_null'),
            validator: (_) =>
                _dateHired == null ? 'Date hired is required' : null,
            builder: (state) {
              return InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _dateHired ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now().add(
                      const Duration(days: 365 * 10),
                    ),
                  );
                  if (d != null) {
                    setState(() => _dateHired = d);
                    state.didChange(d);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _fieldDecoration('').copyWith(
                    errorText: state.errorText,
                    suffixIcon: Icon(
                      Icons.calendar_today_rounded,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  child: Text(
                    _dateHired != null
                        ? '${_dateHired!.year}-${_dateHired!.month.toString().padLeft(2, '0')}-${_dateHired!.day.toString().padLeft(2, '0')}'
                        : 'Date Hired (tap to select) *',
                    style: TextStyle(
                      fontSize: 14,
                      color: _dateHired != null
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _employmentStatus,
            decoration: _fieldDecoration('Employment Status'),
            items: [
              'active',
              'inactive',
              'resigned',
              'retired',
              'terminated',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _employmentStatus = v ?? 'active'),
          ),
        ],
      ),
    );
  }
}

/// Prefer JSON `error` from API responses (Dio), then Dio message.
String _apiErrorMessageFromDio(Object e, {required String fallback}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (e.message != null && e.message!.isNotEmpty) return e.message!;
  }
  return fallback;
}

String _messageForEmployeesLoadError(Object e) {
  if (e is DioException) {
    return _apiErrorMessageFromDio(
      e,
      fallback:
          'Could not load employees. Check your connection and try again.',
    );
  }
  return 'Could not load employees.';
}

String _titleCaseUnderscores(String raw) {
  return raw
      .split('_')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');
}

_EmployeeProfile _employeeProfileFromJson(Map<String, dynamic> m) {
  final dob = m['date_of_birth'];
  final empNum = m['employee_number'];
  final dateHiredRaw = m['date_hired'];
  return _EmployeeProfile(
    id: m['id'] as String,
    fullName: m['full_name'] as String? ?? 'Unknown',
    role: m['role'] as String? ?? 'employee',
    employeeNumber: empNum is int
        ? empNum
        : (empNum != null ? int.tryParse(empNum.toString()) : null),
    email: m['email'] as String?,
    isActive: m['is_active'] as bool? ?? true,
    avatarPath: m['avatar_path'] as String?,
    middleName: m['middle_name'] as String?,
    suffix: m['suffix'] as String?,
    sex: m['sex'] as String?,
    dateOfBirth: dob != null ? DateTime.tryParse(dob.toString()) : null,
    contactNumber: m['contact_number'] as String?,
    address: m['address'] as String?,
    employmentType: m['employment_type'] as String?,
    salaryGrade: m['salary_grade'] as String?,
    dateHired: dateHiredRaw != null
        ? DateTime.tryParse(dateHiredRaw.toString())
        : null,
    employmentStatus: m['employment_status'] as String?,
    biometricUserId: m['biometric_user_id'] as String?,
    departmentName: m['current_department_name'] as String?,
    positionName: m['current_position_name'] as String?,
  );
}

String _csvEscapeForExport(String? val) {
  if (val == null || val.isEmpty) return '';
  if (val.contains(',') ||
      val.contains('"') ||
      val.contains('\n') ||
      val.contains('\r')) {
    return '"${val.replaceAll('"', '""')}"';
  }
  return val;
}

/// Employees management screen: list with filters and detail panel.
/// Matches reference: search, Privilege/Status filters, ID/Name/Privilege columns,
/// right panel with avatar, Add/Edit/Deactivate buttons.
class ManageEmployee extends StatefulWidget {
  const ManageEmployee({super.key, this.onOpenAssignmentForEmployee});

  /// When set (e.g. from admin DTR hub), detail panel can jump to Assignment with this employee.
  final void Function(String employeeId)? onOpenAssignmentForEmployee;

  @override
  State<ManageEmployee> createState() => _ManageEmployeeState();
}

enum _EmployeeToolbarAction {
  importFromDevice,
  biometricRoster,
  exportAllCsv,
  exportPageCsv,
}

class _ManageEmployeeState extends State<ManageEmployee> {
  static const _kSearchDebounceMs = 350;
  static const _kPageSizes = [10, 25, 50, 100];

  final _searchController = TextEditingController();
  Timer? _searchDebounceTimer;

  /// Search text applied to the API (after debounce).
  String _searchQuery = '';

  String _privilegeFilter = 'All';
  String _statusFilter = 'Active';
  String? _departmentFilterId;

  /// When set, list only employees whose biometric ID exists on this ZKTeco (admin API).
  String? _biometricDeviceFilterId;
  List<dynamic> _biometricDevicesForFilter = [];
  String? _selectedEmployeeId;
  List<_EmployeeProfile> _employees = [];
  List<DepartmentOption> _departmentOptions = [];
  bool _loading = false;
  String? _loadError;

  int _pageIndex = 0;
  int _pageSize = 25;
  int _totalCount = 0;

  /// API `sort` param (whitelist on server).
  String _sortField = 'full_name';
  bool _sortAscending = true;
  bool _exportingCsv = false;

  final Set<String> _selectedBulkIds = {};
  final List<FocusNode> _rowFocusNodes = [];
  bool _bulkWorking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDepartmentOptions();
      _loadBiometricDevicesForFilter();
      _loadEmployees();
    });
  }

  Future<void> _loadDepartmentOptions() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final data = res.data ?? [];
      final list =
          data
              .map((e) {
                final m = e as Map;
                final id = m['id']?.toString();
                final name = m['name']?.toString() ?? '—';
                return id != null ? DepartmentOption(id: id, name: name) : null;
              })
              .whereType<DepartmentOption>()
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      if (mounted) {
        setState(() {
          _departmentOptions = list;
          final fid = _departmentFilterId;
          if (fid != null && !list.any((d) => d.id == fid)) {
            _departmentFilterId = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _departmentOptions = []);
    }
  }

  Future<void> _loadBiometricDevicesForFilter() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
        queryParameters: const {'status': 'Active'},
      );
      if (!mounted) return;
      final list = res.data ?? [];
      setState(() {
        _biometricDevicesForFilter = list;
        final fid = _biometricDeviceFilterId;
        if (fid != null &&
            !list.any((d) => (d as Map)['id']?.toString() == fid)) {
          _biometricDeviceFilterId = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _biometricDevicesForFilter = []);
    }
  }

  /// Query params shared by the paged list and CSV export (filters, search, sort).
  Map<String, dynamic> _employeeListQueryBase() {
    final q = <String, dynamic>{
      'status': _statusFilter,
      'role': _privilegeFilter,
      'sort': _sortField,
      'order': _sortAscending ? 'asc' : 'desc',
    };
    if (_departmentFilterId != null && _departmentFilterId!.isNotEmpty) {
      q['department_id'] = _departmentFilterId;
    }
    final bioDev = _biometricDeviceFilterId?.trim();
    if (bioDev != null && bioDev.isNotEmpty) {
      q['biometric_device_id'] = bioDev;
    }
    final sq = _searchQuery.trim();
    if (sq.isNotEmpty) {
      q['q'] = sq;
    }
    return q;
  }

  Future<void> _loadEmployees({bool clampPage = true}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final query = <String, dynamic>{
        ..._employeeListQueryBase(),
        'limit': _pageSize,
        'offset': _pageIndex * _pageSize,
      };

      final bioDev = _biometricDeviceFilterId?.trim();
      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: query,
        options: bioDev != null && bioDev.isNotEmpty
            ? Options(receiveTimeout: const Duration(seconds: 120))
            : null,
      );
      final data = res.data;
      List<_EmployeeProfile> next;
      int total;
      if (data is Map) {
        final list = data['employees'] as List<dynamic>? ?? [];
        total = (data['total'] as num?)?.toInt() ?? 0;
        next = list
            .map(
              (e) =>
                  _employeeProfileFromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      } else if (data is List) {
        next = data
            .map(
              (e) =>
                  _employeeProfileFromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        total = next.length;
      } else {
        next = [];
        total = 0;
      }

      var pageIdx = _pageIndex;
      if (clampPage && total > 0 && _pageSize > 0) {
        final maxPage = (total - 1) ~/ _pageSize;
        if (pageIdx > maxPage) {
          pageIdx = maxPage;
        }
      }

      if (clampPage && pageIdx != _pageIndex) {
        if (!mounted) return;
        setState(() {
          _pageIndex = pageIdx;
          _loading = false;
        });
        await _loadEmployees(clampPage: false);
        return;
      }

      if (!mounted) return;
      _syncRowFocusNodes(next.length);
      setState(() {
        _employees = next;
        _totalCount = total;
        _loading = false;
        _loadError = null;
        final id = _selectedEmployeeId;
        if (id != null && !_employees.any((e) => e.id == id)) {
          _selectedEmployeeId = null;
        }
        _selectedBulkIds.removeWhere(
          (id) => !_employees.any((e) => e.id == id),
        );
      });
    } catch (e) {
      debugPrint('Load employees failed: $e');
      if (!mounted) return;
      _syncRowFocusNodes(0);
      setState(() {
        _employees = [];
        _totalCount = 0;
        _loadError = _messageForEmployeesLoadError(e);
        _loading = false;
        _selectedEmployeeId = null;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(
      const Duration(milliseconds: _kSearchDebounceMs),
      () {
        if (!mounted) return;
        final next = _searchController.text.trim();
        if (next == _searchQuery) return;
        setState(() {
          _searchQuery = next;
          _pageIndex = 0;
        });
        _loadEmployees();
      },
    );
  }

  void _goToPage(int index) {
    if (index < 0) return;
    final maxPage = _totalCount > 0 ? (_totalCount - 1) ~/ _pageSize : 0;
    if (index > maxPage) return;
    setState(() => _pageIndex = index);
    _loadEmployees();
  }

  void _setPageSize(int size) {
    if (!_kPageSizes.contains(size)) return;
    setState(() {
      _pageSize = size;
      _pageIndex = 0;
    });
    _loadEmployees();
  }

  void _setSort(String sortKey) {
    setState(() {
      if (_sortField == sortKey) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = sortKey;
        _sortAscending = true;
      }
      _pageIndex = 0;
    });
    _loadEmployees();
  }

  Future<void> _exportCsv() async {
    if (!mounted || _exportingCsv) return;
    setState(() => _exportingCsv = true);
    try {
      final bioDev = _biometricDeviceFilterId?.trim();
      final res = await ApiClient.instance.dio.get<List<int>>(
        '/api/employees/export/csv',
        queryParameters: _employeeListQueryBase(),
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: Duration(
            seconds: bioDev != null && bioDev.isNotEmpty ? 120 : 90,
          ),
          headers: const {'Accept': 'text/csv'},
        ),
      );
      final raw = res.data;
      if (raw == null || raw.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export returned no data.')),
          );
        }
        return;
      }
      final bytes = Uint8List.fromList(raw);
      final day = DateTime.now().toIso8601String().split('T').first;
      await shareOrDownloadFile(bytes, 'employees_export_$day.csv', 'text/csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee export downloaded.')),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 413) {
        final body = e.response?.data;
        var msg =
            'Too many rows for one export. Narrow filters or search and try again.';
        if (body is Map && body['error'] != null) {
          msg = body['error'].toString();
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageForEmployeesLoadError(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _exportCsvPageOnly() async {
    if (!mounted) return;
    if (_employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rows on this page to export.')),
      );
      return;
    }
    const header = [
      'Employee No',
      'Full Name',
      'Email',
      'Department',
      'Position',
      'Privilege',
      'Account Active',
      'Employment Status',
      'Biometric ID',
    ];
    final lines = <String>[header.map(_csvEscapeForExport).join(',')];
    for (final e in _employees) {
      final empNo = e.employeeNumber != null
          ? 'EMP-${e.employeeNumber!.toString().padLeft(3, '0')}'
          : '';
      final priv = e.role == 'admin' ? 'Admin' : 'Employee';
      final acct = e.isActive ? 'Active' : 'Inactive';
      lines.add(
        [
          _csvEscapeForExport(empNo),
          _csvEscapeForExport(e.fullName),
          _csvEscapeForExport(e.email ?? ''),
          _csvEscapeForExport(e.departmentName ?? ''),
          _csvEscapeForExport(e.positionName ?? ''),
          _csvEscapeForExport(priv),
          _csvEscapeForExport(acct),
          _csvEscapeForExport(e.employmentStatus ?? ''),
          _csvEscapeForExport(e.biometricUserId ?? ''),
        ].join(','),
      );
    }
    final csv = '\uFEFF${lines.join('\n')}';
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final day = DateTime.now().toIso8601String().split('T').first;
    try {
      await shareOrDownloadFile(
        bytes,
        'employees_page${_pageIndex + 1}_$day.csv',
        'text/csv',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This page export downloaded.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _syncRowFocusNodes(int count) {
    while (_rowFocusNodes.length < count) {
      _rowFocusNodes.add(
        FocusNode(debugLabel: 'employee_row_${_rowFocusNodes.length}'),
      );
    }
    while (_rowFocusNodes.length > count) {
      _rowFocusNodes.removeLast().dispose();
    }
  }

  bool? _headerSelectAllValue() {
    if (_employees.isEmpty) return false;
    final onPage = _employees.map((e) => e.id).toSet();
    var n = 0;
    for (final id in onPage) {
      if (_selectedBulkIds.contains(id)) n++;
    }
    if (n == 0) return false;
    if (n == onPage.length) return true;
    return null;
  }

  void _onHeaderSelectAllChanged(bool? v) {
    setState(() {
      if (v == true) {
        for (final e in _employees) {
          _selectedBulkIds.add(e.id);
        }
      } else {
        for (final e in _employees) {
          _selectedBulkIds.remove(e.id);
        }
      }
    });
  }

  KeyEventResult _handleEmployeeRowKey(KeyEvent event, int index) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      final id = _employees[index].id;
      setState(() {
        if (_selectedBulkIds.contains(id)) {
          _selectedBulkIds.remove(id);
        } else {
          _selectedBulkIds.add(id);
        }
      });
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < _employees.length - 1) {
        _rowFocusNodes[index + 1].requestFocus();
        setState(() => _selectedEmployeeId = _employees[index + 1].id);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _rowFocusNodes[index - 1].requestFocus();
        setState(() => _selectedEmployeeId = _employees[index - 1].id);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirmBulkDeactivate() async {
    final targets = _employees
        .where((e) => _selectedBulkIds.contains(e.id) && e.isActive)
        .toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Deactivate ${targets.length} employees?'),
        content: Text(
          targets.length <= 3
              ? targets.map((e) => e.fullName).join(', ')
              : 'This will deactivate ${targets.length} selected accounts. They will no longer be able to sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final dtr = context.read<DtrProvider>();
    setState(() => _bulkWorking = true);
    try {
      await ApiClient.instance.post(
        '/api/employees/bulk-status',
        data: {
          'employee_ids': targets.map((e) => e.id).toList(),
          'is_active': false,
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${targets.length} employees deactivated.')),
      );
      setState(() {
        _bulkWorking = false;
        _selectedBulkIds.clear();
      });
      await _loadEmployees();
      if (mounted) {
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Bulk deactivate failed: $e')),
        );
        setState(() => _bulkWorking = false);
      }
    }
  }

  Future<void> _confirmBulkActivate() async {
    final targets = _employees
        .where((e) => _selectedBulkIds.contains(e.id) && !e.isActive)
        .toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Activate ${targets.length} employees?'),
        content: Text(
          targets.length <= 3
              ? targets.map((e) => e.fullName).join(', ')
              : 'This will reactivate ${targets.length} selected accounts. They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final dtr = context.read<DtrProvider>();
    setState(() => _bulkWorking = true);
    try {
      await ApiClient.instance.post(
        '/api/employees/bulk-status',
        data: {
          'employee_ids': targets.map((e) => e.id).toList(),
          'is_active': true,
        },
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${targets.length} employees activated.')),
      );
      setState(() {
        _bulkWorking = false;
        _selectedBulkIds.clear();
      });
      await _loadEmployees();
      if (mounted) {
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Bulk activate failed: $e')),
        );
        setState(() => _bulkWorking = false);
      }
    }
  }

  Widget _buildBulkSelectionBar() {
    final n = _selectedBulkIds.length;
    final canDeactivate = _employees.any(
      (e) => _selectedBulkIds.contains(e.id) && e.isActive,
    );
    final canActivate = _employees.any(
      (e) => _selectedBulkIds.contains(e.id) && !e.isActive,
    );
    return Material(
      color: AppTheme.primaryNavy.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$n selected',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: _bulkWorking
                  ? null
                  : () => setState(() => _selectedBulkIds.clear()),
              child: const Text('Clear'),
            ),
            FilledButton.icon(
              onPressed: _bulkWorking || !canDeactivate
                  ? null
                  : _confirmBulkDeactivate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
            ),
            FilledButton.icon(
              onPressed: _bulkWorking || !canActivate
                  ? null
                  : _confirmBulkActivate,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Activate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEmployeeDialog() {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        'Add employee',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AddEmployeeForm(
                      onAccountCreated: () {
                        Navigator.of(dialogContext).pop();
                        setState(() => _pageIndex = 0);
                        _loadEmployees();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Account created. The list has been refreshed.',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    for (final n in _rowFocusNodes) {
      n.dispose();
    }
    _rowFocusNodes.clear();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Employees',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        isNarrow ? _buildNarrowLayout() : _buildWideLayout(),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildLeftPanel()),
        const SizedBox(width: 24),
        SizedBox(width: 280, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLeftPanel(),
        const SizedBox(height: 24),
        _buildRightPanel(),
      ],
    );
  }

  Widget _buildEmployeesToolbar() {
    // Single horizontal strip: sharing one row with action buttons squeezed the Wrap
    // and forced each filter onto its own line. Scroll when the strip is wider than the panel.
    final filterStrip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 220, child: _buildSearchField()),
            const SizedBox(width: 12),
            _buildDropdown(_privilegeFilter, ['All', 'Admin', 'Employee'], (v) {
              setState(() {
                _privilegeFilter = v ?? 'All';
                _pageIndex = 0;
              });
              _loadEmployees();
            }),
            const SizedBox(width: 12),
            _buildDropdown(_statusFilter, ['Active', 'Inactive', 'All'], (v) {
              setState(() {
                _statusFilter = v ?? 'Active';
                _pageIndex = 0;
              });
              _loadEmployees();
            }),
            const SizedBox(width: 12),
            _buildDepartmentFilterDropdown(),
            const SizedBox(width: 12),
            _buildBiometricDeviceFilterDropdown(),
          ],
        ),
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<_EmployeeToolbarAction>(
          tooltip: 'More actions',
          offset: const Offset(0, 8),
          onSelected: (action) {
            switch (action) {
              case _EmployeeToolbarAction.importFromDevice:
                _showImportDialog(context);
              case _EmployeeToolbarAction.biometricRoster:
                _showBiometricRosterDialog(context);
              case _EmployeeToolbarAction.exportAllCsv:
                _exportCsv();
              case _EmployeeToolbarAction.exportPageCsv:
                _exportCsvPageOnly();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _EmployeeToolbarAction.importFromDevice,
              child: _toolbarMenuItem(
                icon: Icons.download_rounded,
                label: 'Import from Device',
              ),
            ),
            PopupMenuItem(
              value: _EmployeeToolbarAction.biometricRoster,
              child: _toolbarMenuItem(
                icon: Icons.badge_outlined,
                label: 'Biometric roster',
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _EmployeeToolbarAction.exportAllCsv,
              enabled: !_exportingCsv,
              child: _toolbarMenuItem(
                icon: Icons.file_download_outlined,
                label: _exportingCsv ? 'Exporting CSV...' : 'Export CSV',
              ),
            ),
            PopupMenuItem(
              value: _EmployeeToolbarAction.exportPageCsv,
              enabled: !_exportingCsv,
              child: _toolbarMenuItem(
                icon: Icons.download_for_offline_outlined,
                label: 'Export current page',
              ),
            ),
          ],
          child: Container(
            width: 46,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.45),
              ),
            ),
            child: Icon(Icons.more_vert_rounded, color: AppTheme.primaryNavy),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _showAddEmployeeDialog,
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: const Text('Add employee'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterStrip,
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: actions),
      ],
    );
  }

  Widget _toolbarMenuItem({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }

  Widget _buildDepartmentFilterDropdown() {
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String?>(
        value: _departmentFilterId,
        hint: Text(
          'All departments',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.85),
            fontSize: 14,
          ),
        ),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All departments'),
          ),
          ..._departmentOptions.map(
            (d) => DropdownMenuItem<String?>(
              value: d.id,
              child: Text(d.name, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ),
        ],
        onChanged: (v) {
          setState(() {
            _departmentFilterId = v;
            _pageIndex = 0;
          });
          _loadEmployees();
        },
      ),
    );
  }

  Widget _buildBiometricDeviceFilterDropdown() {
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String?>(
        value: _biometricDeviceFilterId,
        hint: Text(
          'All devices',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.85),
            fontSize: 14,
          ),
        ),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All devices'),
          ),
          ..._biometricDevicesForFilter.map((d) {
            final m = Map<String, dynamic>.from(d as Map);
            final id = m['id']?.toString() ?? '';
            final name = m['name']?.toString() ?? id;
            final loc = m['location']?.toString();
            final line = (loc != null && loc.isNotEmpty)
                ? '$name · $loc'
                : name;
            return DropdownMenuItem<String?>(
              value: id,
              child: Text(line, overflow: TextOverflow.ellipsis, maxLines: 1),
            );
          }),
        ],
        onChanged: (v) {
          setState(() {
            _biometricDeviceFilterId = v;
            _pageIndex = 0;
          });
          _loadEmployees();
        },
      ),
    );
  }

  Widget _buildLoadErrorBanner() {
    final err = _loadError;
    if (err == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFEBEE),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Colors.red.shade700,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                err,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(onPressed: _loadEmployees, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCellContent(_EmployeeProfile e) {
    final hrRaw = e.employmentStatus?.trim();
    final showHr =
        hrRaw != null && hrRaw.isNotEmpty && hrRaw.toLowerCase() != 'active';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          e.isActive ? 'Active' : 'Inactive',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: e.isActive
                ? const Color(0xFF2E7D32)
                : const Color(0xFFC62828),
          ),
        ),
        if (showHr)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _titleCaseUnderscores(hrRaw),
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary.withValues(alpha: 0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    String emptyMessage() {
      if (_totalCount == 0) {
        return _searchQuery.trim().isNotEmpty
            ? 'No results for your search.'
            : 'No employees match these filters yet.';
      }
      if (_employees.isEmpty) {
        return 'No rows on this page.';
      }
      return '';
    }

    const kTableMinWidth = 768.0;
    const columnWidths = <int, TableColumnWidth>{
      0: FixedColumnWidth(44),
      1: FixedColumnWidth(88),
      2: FlexColumnWidth(1.35),
      3: FlexColumnWidth(1.15),
      4: FixedColumnWidth(104),
      5: FixedColumnWidth(92),
    };

    Widget tableCore() {
      final headerRow = TableRow(
        decoration: BoxDecoration(
          color: AppTheme.lightGray.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        children: [
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: Semantics(
              label: 'Select all employees on this page',
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Checkbox(
                  tristate: true,
                  value: _headerSelectAllValue(),
                  onChanged: (_employees.isEmpty || _loading)
                      ? null
                      : _onHeaderSelectAllChanged,
                ),
              ),
            ),
          ),
          _sortableHeaderCell('No.', 'employee_number'),
          _sortableHeaderCell('Name', 'full_name'),
          _sortableHeaderCell('Assignment', 'department'),
          _sortableHeaderCell('Status', 'is_active'),
          _sortableHeaderCell('Privilege', 'role'),
        ],
      );

      if (_loading) {
        return Table(
          columnWidths: columnWidths,
          children: [headerRow, ..._employeeTableSkeletonRows()],
        );
      }

      if (_employees.isEmpty) {
        final msg = emptyMessage();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Table(columnWidths: columnWidths, children: [headerRow]),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppTheme.lightGray.withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: Semantics(
                label: msg,
                child: Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.88),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      return Table(
        columnWidths: columnWidths,
        children: [
          headerRow,
          ..._employees.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final isSelected = _selectedEmployeeId == e.id;
            return TableRow(
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryNavy.withValues(alpha: 0.08)
                    : null,
              ),
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Checkbox(
                      value: _selectedBulkIds.contains(e.id),
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedBulkIds.add(e.id);
                          } else {
                            _selectedBulkIds.remove(e.id);
                          }
                          _selectedEmployeeId = e.id;
                        });
                        if (i >= 0 && i < _rowFocusNodes.length) {
                          _rowFocusNodes[i].requestFocus();
                        }
                      },
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        e.displayEmployeeNo,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Focus(
                    focusNode: _rowFocusNodes[i],
                    onKeyEvent: (node, event) =>
                        _handleEmployeeRowKey(event, i),
                    child: _employeeRowInkWell(
                      e: e,
                      isSelected: isSelected,
                      primarySemanticForRow: true,
                      rowIndex: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.fullName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (!e.isActive)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  e.biometricUserId != null
                                      ? 'Imported (Inactive)'
                                      : 'Inactive',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        e.assignmentDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: _buildStatusCellContent(e),
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: _employeeRowInkWell(
                    e: e,
                    isSelected: isSelected,
                    primarySemanticForRow: false,
                    rowIndex: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        e.roleDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEmployeesToolbar(),
          const SizedBox(height: 16),
          if (_selectedBulkIds.isNotEmpty) ...[
            _buildBulkSelectionBar(),
            const SizedBox(height: 12),
          ],
          if (_loadError != null) ...[
            _buildLoadErrorBanner(),
            const SizedBox(height: 16),
          ],
          if (_loadError == null) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final useHScroll = constraints.maxWidth < kTableMinWidth;
                if (!useHScroll) return tableCore();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: kTableMinWidth, child: tableCore()),
                );
              },
            ),
            _buildPaginationBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildPaginationBar() {
    if (_loading && _employees.isEmpty) return const SizedBox.shrink();
    final total = _totalCount;
    final maxPage = total <= 0 ? 0 : (total - 1) ~/ _pageSize;
    final start = total == 0 ? 0 : _pageIndex * _pageSize + 1;
    final end = total == 0
        ? 0
        : (_pageIndex * _pageSize + _employees.length).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            total == 0 ? 'No results' : 'Showing $start–$end of $total',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rows',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _pageSize,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: _kPageSizes
                    .map(
                      (s) =>
                          DropdownMenuItem(value: s, child: Text('$s / page')),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _setPageSize(v);
                },
              ),
            ],
          ),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _pageIndex > 0 ? () => _goToPage(_pageIndex - 1) : null,
          ),
          Text(
            'Page ${_pageIndex + 1} / ${maxPage + 1}',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _pageIndex < maxPage
                ? () => _goToPage(_pageIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _employeeRowInkWell({
    required _EmployeeProfile e,
    required bool isSelected,
    required bool primarySemanticForRow,
    required Widget child,
    int? rowIndex,
  }) {
    final ink = InkWell(
      onTap: () {
        if (rowIndex != null &&
            rowIndex >= 0 &&
            rowIndex < _rowFocusNodes.length) {
          _rowFocusNodes[rowIndex].requestFocus();
        }
        setState(() => _selectedEmployeeId = e.id);
      },
      focusColor: AppTheme.primaryNavy.withValues(alpha: 0.08),
      canRequestFocus: false,
      child: child,
    );
    if (primarySemanticForRow) {
      return Semantics(
        button: true,
        selected: isSelected,
        label:
            '${e.fullName}, employee number ${e.displayEmployeeNo}, '
            '${e.assignmentDisplay}, '
            '${e.isActive ? "active account" : "inactive account"}, '
            '${e.roleDisplay}. Activate to select. '
            'Arrow up and down to move between rows. Space toggles bulk selection.',
        child: ink,
      );
    }
    return ExcludeSemantics(child: ink);
  }

  List<TableRow> _employeeTableSkeletonRows() {
    Widget skelBox(double width) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Shimmer.fromColors(
            baseColor: AppTheme.lightGray.withValues(alpha: 0.55),
            highlightColor: AppTheme.white,
            period: const Duration(milliseconds: 1200),
            child: SizedBox(
              width: width,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.lightGray.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return List<TableRow>.generate(
      6,
      (_) => TableRow(
        children: [
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(22),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(52),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(160),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(120),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(64),
          ),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: skelBox(72),
          ),
        ],
      ),
    );
  }

  Widget _sortableHeaderCell(String label, String sortKey) {
    final active = _sortField == sortKey;
    final orderHint = active
        ? (_sortAscending ? ', ascending' : ', descending')
        : '';
    return Semantics(
      button: true,
      label: 'Sort by $label$orderHint',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _setSort(sortKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (active)
                  Icon(
                    _sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                    color: AppTheme.primaryNavy,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Search name, ID, or email',
        hintStyle: TextStyle(
          color: AppTheme.textSecondary.withValues(alpha: 0.8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.textSecondary.withValues(alpha: 0.7),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: AppTheme.lightGray.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.transparent),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildRightPanel() {
    _EmployeeProfile? selected;
    if (_selectedEmployeeId != null) {
      try {
        selected = _employees.firstWhere((e) => e.id == _selectedEmployeeId);
      } catch (_) {}
    }
    final sel = selected;
    final hasSelection = sel != null;
    final emailTrim = sel?.email?.trim();
    final bioTrim = sel?.biometricUserId?.trim();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          hasSelection && (sel.avatarPath ?? '').isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    '${ApiConfig.baseUrl}/api/files/avatar/${sel.id}',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 96,
                      height: 96,
                      color: AppTheme.lightGray,
                      child: Icon(
                        Icons.person_rounded,
                        size: 56,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                )
              : CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.lightGray,
                  child: Icon(
                    Icons.person_rounded,
                    size: 56,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
          const SizedBox(height: 16),
          Text(
            hasSelection ? sel.fullName : 'Select an employee',
            style: TextStyle(
              color: hasSelection
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (emailTrim != null && emailTrim.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              emailTrim,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.9),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (hasSelection && sel.assignmentDisplay != '—') ...[
            const SizedBox(height: 10),
            Text(
              sel.assignmentDisplay,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.85),
                fontSize: 12,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (bioTrim != null && bioTrim.isNotEmpty) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label:
                  'Linked to time clock device. Biometric user identifier $bioTrim',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Linked to device',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fingerprint_rounded,
                          size: 14,
                          color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            bioTrim,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textPrimary.withValues(
                                alpha: 0.85,
                              ),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (hasSelection && widget.onOpenAssignmentForEmployee != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => widget.onOpenAssignmentForEmployee!(sel.id),
              icon: Icon(
                Icons.assignment_turned_in_outlined,
                size: 18,
                color: AppTheme.primaryNavy,
              ),
              label: Text(
                'View assignment & shift',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hasSelection
                  ? () => _showEditEmployeeDialog(sel)
                  : null,
              icon: Icon(
                Icons.edit_rounded,
                size: 20,
                color: hasSelection
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary.withValues(alpha: 0.5),
              ),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(
                  color: hasSelection
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.6)
                      : AppTheme.lightGray,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasSelection
                  ? () {
                      final p = sel;
                      p.isActive ? _confirmDeactivate(p) : _confirmActivate(p);
                    }
                  : null,
              icon: Icon(
                (hasSelection && !sel.isActive)
                    ? Icons.person_add_rounded
                    : Icons.person_off_rounded,
                size: 20,
                color: hasSelection
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.5),
              ),
              label: Text(
                hasSelection && !sel.isActive ? 'Activate' : 'Deactivate',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: (hasSelection && !sel.isActive)
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFE53935),
                disabledBackgroundColor: Colors.red.shade200.withValues(
                  alpha: 0.5,
                ),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmActivate(_EmployeeProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activate employee?'),
        content: Text(
          'This will reactivate the account of ${profile.fullName}. They will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Activate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.put(
        '/api/employees/${profile.id}',
        data: {'is_active': true},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profile.fullName} has been activated.')),
      );
      await _loadEmployees();
      if (!mounted) return;
      final dtr = context.read<DtrProvider>();
      dtr.invalidateCachedDtrData(includeReferenceData: true);
      dtr.loadEmployees(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to activate: $e')));
    }
  }

  Future<void> _showEditEmployeeDialog(_EmployeeProfile profile) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _EditEmployeeDialog(profile: profile),
    );
    if (updated != true || !mounted) return;
    await _loadEmployees();
    if (!mounted) return;
    final dtr = context.read<DtrProvider>();
    dtr.invalidateCachedDtrData(includeReferenceData: true);
    dtr.loadEmployees(forceRefresh: true);
  }

  void _showImportDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _BiometricImportDialog(
        onImportSuccess: () {
          setState(() => _pageIndex = 0);
          _loadEmployees();
          final dtr = dialogContext.read<DtrProvider>();
          dtr.invalidateCachedDtrData(includeReferenceData: true);
          dtr.loadEmployees(forceRefresh: true);
        },
      ),
    );
  }

  void _showBiometricRosterDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _BiometricRosterDialog(),
    );
  }

  Future<void> _confirmDeactivate(_EmployeeProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate employee?'),
        content: Text(
          'This will deactivate the account of ${profile.fullName}. They will no longer be able to sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.delete('/api/employees/${profile.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profile.fullName} has been deactivated.')),
      );
      await _loadEmployees();
      if (!mounted) return;
      final dtr = context.read<DtrProvider>();
      dtr.invalidateCachedDtrData(includeReferenceData: true);
      dtr.loadEmployees(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
    }
  }
}

/// Parses full_name into first, middle, last.
void _parseFullName(
  String fullName,
  TextEditingController first,
  TextEditingController middle,
  TextEditingController last,
) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    first.text = '';
    middle.text = '';
    last.text = '';
    return;
  }
  if (parts.length == 1) {
    first.text = parts[0];
    middle.text = '';
    last.text = '';
    return;
  }
  if (parts.length == 2) {
    first.text = parts[0];
    middle.text = '';
    last.text = parts[1];
    return;
  }
  first.text = parts.first;
  last.text = parts.last;
  middle.text = parts.sublist(1, parts.length - 1).join(' ');
}

class _EditEmployeeDialog extends StatefulWidget {
  const _EditEmployeeDialog({required this.profile});
  final _EmployeeProfile profile;

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  late final _EmployeeProfile _profile;
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _streetController = TextEditingController();
  final GlobalKey<StructuredAddressFormState> _addressFormKey =
      GlobalKey<StructuredAddressFormState>();
  final _salaryGradeController = TextEditingController();
  final _biometricIdController = TextEditingController();

  String? _privilege;
  String? _suffix;
  String? _sex;
  DateTime? _dateOfBirth;
  String? _employmentType;
  DateTime? _dateHired;
  String? _employmentStatus;
  Uint8List? _selectedImageBytes;
  bool _saving = false;

  List<dynamic> _bioDevices = [];
  String? _selectedPushDeviceId;
  bool _loadingBioDevices = true;
  bool _pushingToDevice = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _parseFullName(
      _profile.fullName,
      _firstNameController,
      _middleNameController,
      _lastNameController,
    );
    if (_profile.middleName != null && _profile.middleName!.isNotEmpty) {
      _middleNameController.text = _profile.middleName!;
    }
    _contactController.text = _profile.contactNumber ?? '';
    _salaryGradeController.text = _profile.salaryGrade ?? '';
    _privilege = _profile.role == 'admin' ? 'Admin' : 'Employee';
    _suffix = _profile.suffix;
    _sex = _profile.sex;
    _dateOfBirth = _profile.dateOfBirth;
    _employmentType = _profile.employmentType;
    _dateHired = _profile.dateHired;
    _employmentStatus = _profile.employmentStatus ?? 'active';
    _biometricIdController.text = _profile.biometricUserId ?? '';
    _loadBioDevicesForPush();
  }

  Future<void> _loadBioDevicesForPush() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
      );
      if (!mounted) return;
      final list = res.data ?? [];
      setState(() {
        _bioDevices = list;
        _selectedPushDeviceId = list.isNotEmpty
            ? list.first['id']?.toString()
            : null;
        _loadingBioDevices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBioDevices = false);
    }
  }

  Future<void> _pushEmployeeToDevice() async {
    final deviceId = _selectedPushDeviceId;
    if (deviceId == null) return;
    final bio = _biometricIdController.text.trim();
    if (bio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set a Biometric User ID first (employee number on the clock).',
          ),
        ),
      );
      return;
    }
    setState(() => _pushingToDevice = true);
    try {
      await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/biometric-devices/$deviceId/push-user',
        data: <String, dynamic>{'employee_id': _profile.id},
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'User sent to device. Enroll fingerprint or face on the clock if required.',
          ),
        ),
      );
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _apiErrorMessageFromDio(
                e,
                fallback: 'Push to device failed. Check network and device IP.',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Push to device failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _pushingToDevice = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _streetController.dispose();
    _salaryGradeController.dispose();
    _biometricIdController.dispose();
    super.dispose();
  }

  /// Once saved, the ID must match the device (ZKTeco user ID is fixed on the clock).
  bool get _biometricUserIdLocked =>
      (_profile.biometricUserId?.trim().isNotEmpty ?? false);

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppTheme.textSecondary.withValues(alpha: 0.7),
      fontSize: 14,
    ),
    filled: true,
    fillColor: AppTheme.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppTheme.lightGray),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
    ),
  );

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.bytes != null) {
      setState(() {
        _selectedImageBytes = result.files.single.bytes;
      });
    }
  }

  Future<void> _saveEmployee() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final suffixPart = (_suffix != null && _suffix != 'None')
        ? ' ${_suffix!}'
        : '';
    final fullName =
        '$firstName${middleName.isNotEmpty ? ' $middleName' : ''} $lastName$suffixPart'
            .trim();
    final privilege = _privilege ?? 'Employee';
    final role = privilege == 'Admin' ? 'admin' : 'employee';

    setState(() => _saving = true);
    try {
      final encodedAddress =
          _addressFormKey.currentState?.composeEncoded() ?? '';
      final body = <String, dynamic>{
        'full_name': fullName,
        'role': role,
        if (middleName.isNotEmpty) 'middle_name': middleName,
        if (_suffix != null && _suffix != 'None') 'suffix': _suffix,
        if (_sex != null) 'sex': _sex,
        if (_dateOfBirth != null)
          'date_of_birth': _dateOfBirth!.toIso8601String().split('T')[0],
        if (_contactController.text.trim().isNotEmpty)
          'contact_number': _contactController.text.trim(),
        if (encodedAddress.isNotEmpty) 'address': encodedAddress,
        if (_employmentType != null) 'employment_type': _employmentType,
        if (_salaryGradeController.text.trim().isNotEmpty)
          'salary_grade': _salaryGradeController.text.trim(),
        if (_dateHired != null)
          'date_hired': _dateHired!.toIso8601String().split('T')[0],
        if (_employmentStatus != null) 'employment_status': _employmentStatus,
        if (!_biometricUserIdLocked &&
            _biometricIdController.text.trim().isNotEmpty)
          'biometric_user_id': _biometricIdController.text.trim(),
      };

      if (_selectedImageBytes != null && _selectedImageBytes!.isNotEmpty) {
        try {
          await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
            '/api/upload/avatar/for/${_profile.id}',
            bytes: _selectedImageBytes!,
            fileName: 'avatar.jpg',
          );
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      }

      if (!mounted) return;
      await ApiClient.instance.put('/api/employees/${_profile.id}', data: body);

      if (!mounted) return;
      try {
        final dtr = context.read<DtrProvider>();
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee updated successfully.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isNarrow = w < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height - 48,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAccountSection(),
                            const SizedBox(height: 24),
                            _buildPersonalSection(),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildAccountSection()),
                            const SizedBox(width: 28),
                            Expanded(child: _buildPersonalSection()),
                          ],
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _saveEmployee,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: _selectedImageBytes != null
                ? CircleAvatar(
                    radius: 48,
                    backgroundImage: MemoryImage(_selectedImageBytes!),
                  )
                : _profile.avatarPath != null && _profile.avatarPath!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      '${ApiConfig.baseUrl}/api/files/avatar/${_profile.id}',
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => CircleAvatar(
                        radius: 48,
                        backgroundColor: AppTheme.lightGray,
                        child: Icon(
                          Icons.person_rounded,
                          size: 56,
                          color: AppTheme.textSecondary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  )
                : CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.lightGray,
                    child: Icon(
                      Icons.person_rounded,
                      size: 56,
                      color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Select Image'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 24),
          InputDecorator(
            decoration: _inputDecoration('Email'),
            child: Text(
              _profile.email ?? 'â€”',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _privilege,
            decoration: _inputDecoration('Select role'),
            hint: const Text(
              'Select role',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'Admin',
              'Employee',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _privilege = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          if (_biometricUserIdLocked)
            InputDecorator(
              decoration: _inputDecoration('Biometric User ID').copyWith(
                helperText:
                    'Locked: must match the time clock. IDs cannot be edited here after they are set.',
                helperMaxLines: 2,
              ),
              child: Text(
                _profile.biometricUserId ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            )
          else
            TextFormField(
              controller: _biometricIdController,
              decoration: _inputDecoration('Biometric User ID (optional)').copyWith(
                helperText:
                    'Set once to match the user ID on the ZKTeco; then it becomes locked.',
                helperMaxLines: 2,
              ),
            ),
          const SizedBox(height: 12),
          if (_loadingBioDevices)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (_bioDevices.isEmpty)
            Text(
              'No biometric devices registered. Add one under DTR / devices to push users to the clock.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedPushDeviceId,
                  decoration: _inputDecoration('Push to device'),
                  items: _bioDevices
                      .where((d) => d['id'] != null && '${d['id']}'.isNotEmpty)
                      .map(
                        (d) => DropdownMenuItem<String>(
                          value: d['id'].toString(),
                          child: Text(
                            '${d['name'] ?? 'Device'}${d['ip_address'] != null ? ' (${d['ip_address']})' : ''}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedPushDeviceId = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _pushingToDevice ? null : _pushEmployeeToDevice,
                  icon: _pushingToDevice
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_rounded, size: 18),
                  label: Text(
                    _pushingToDevice ? 'Pushing…' : 'Push to Biometric Device',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    alignment: Alignment.center,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPersonalSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _firstNameController,
            decoration: _inputDecoration('First Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _middleNameController,
            decoration: _inputDecoration('Middle Name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _lastNameController,
            decoration: _inputDecoration('Last Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _suffix ?? 'None',
            decoration: _inputDecoration('Suffix (e.g. Jr., Sr., or None)'),
            hint: const Text(
              'Suffix (e.g. Jr., Sr., or None)',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'None',
              'Jr.',
              'Sr.',
              'II',
              'III',
              'IV',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) =>
                setState(() => _suffix = (v == 'None') ? null : v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: _inputDecoration('Sex (Male / Female)'),
            hint: const Text(
              'Sex (Male / Female)',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            items: [
              'Male',
              'Female',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _sex = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _dateOfBirth ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) setState(() => _dateOfBirth = date);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('').copyWith(
                suffixIcon: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              child: Text(
                _dateOfBirth != null
                    ? '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                    : 'Date of Birth (tap to select)',
                style: TextStyle(
                  fontSize: 14,
                  color: _dateOfBirth != null
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contactController,
            decoration: _inputDecoration('Contact Number'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          StructuredAddressForm(
            key: _addressFormKey,
            streetController: _streetController,
            initialRawAddress: _profile.address,
            inputDecoration: _inputDecoration,
          ),
          const SizedBox(height: 24),
          Text(
            'Employment',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _employmentType,
            decoration: _inputDecoration('Employment Type'),
            hint: const Text('Employment Type'),
            items: [
              'regular',
              'contractual',
              'job_order',
              'casual',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _employmentType = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _salaryGradeController,
            decoration: _inputDecoration('Salary Grade'),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _dateHired ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (date != null) setState(() => _dateHired = date);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('').copyWith(
                suffixIcon: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
              ),
              child: Text(
                _dateHired != null
                    ? '${_dateHired!.year}-${_dateHired!.month.toString().padLeft(2, '0')}-${_dateHired!.day.toString().padLeft(2, '0')}'
                    : 'Date Hired (tap to select)',
                style: TextStyle(
                  fontSize: 14,
                  color: _dateHired != null
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Changing date hired may affect leave accrual and first-month proration.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.textSecondary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _employmentStatus,
            decoration: _inputDecoration('Employment Status'),
            items: [
              'active',
              'inactive',
              'resigned',
              'retired',
              'terminated',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _employmentStatus = v ?? 'active'),
          ),
        ],
      ),
    );
  }
}

class _RosterStatusPill extends StatelessWidget {
  const _RosterStatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2E7D32) : Colors.red.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BiometricImportDialog extends StatefulWidget {
  const _BiometricImportDialog({required this.onImportSuccess});

  final VoidCallback onImportSuccess;

  @override
  State<_BiometricImportDialog> createState() => _BiometricImportDialogState();
}

class _BiometricImportDialogState extends State<_BiometricImportDialog> {
  bool _loadingDevices = true;
  List<dynamic> _devices = [];
  String? _selectedDeviceId;

  bool _loadingUsers = false;
  List<dynamic> _fetchedUsers = [];

  /// Biometric user IDs already linked in HRMS (from API; not the paged table).
  Set<String> _duplicateBioIds = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final res = await ApiClient.instance.get('/api/biometric-devices');
      if (mounted) {
        setState(() {
          _devices = res.data ?? [];
          if (_devices.isNotEmpty) {
            _selectedDeviceId = _devices.first['id'];
          }
          _loadingDevices = false;
        });
        if (_selectedDeviceId != null) {
          _fetchUsers();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _fetchUsers() async {
    if (_selectedDeviceId == null) return;
    setState(() {
      _loadingUsers = true;
      _fetchedUsers = [];
      _duplicateBioIds = {};
    });
    try {
      final res = await ApiClient.instance.get(
        '/api/biometric-devices/$_selectedDeviceId/users',
      );
      if (mounted) {
        setState(() {
          _fetchedUsers = res.data ?? [];
          _loadingUsers = false;
        });
        await _refreshDuplicateBioIds();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch users: $e')));
        setState(() => _loadingUsers = false);
      }
    }
  }

  Future<void> _refreshDuplicateBioIds() async {
    final ids = _fetchedUsers
        .map((u) => u['biometric_user_id']?.toString().trim())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    if (!mounted) return;
    if (ids.isEmpty) {
      setState(() => _duplicateBioIds = {});
      return;
    }
    const chunk = 40;
    final found = <String>{};
    try {
      const repo = BiometricImportRepository();
      for (var i = 0; i < ids.length; i += chunk) {
        final end = i + chunk > ids.length ? ids.length : i + chunk;
        final slice = ids.sublist(i, end);
        final matches = await repo.findEmployeesByBiometricIds(slice);
        found.addAll(matches.map((e) => e.biometricUserId));
      }
    } catch (_) {
      if (mounted) setState(() => _duplicateBioIds = {});
      return;
    }
    if (mounted) setState(() => _duplicateBioIds = found);
  }

  void _openUserImportModal(Map<String, dynamic> user, bool isDuplicate) async {
    if (isDuplicate) return;
    final success = await showDialog<bool>(
      context: context,
      builder: (_) => _SingleUserImportModal(user, _selectedDeviceId!),
    );
    if (success == true) {
      widget.onImportSuccess();
      final bid = user['biometric_user_id']?.toString().trim();
      if (bid != null && bid.isNotEmpty && mounted) {
        setState(() => _duplicateBioIds = {..._duplicateBioIds, bid});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import from Biometric Device',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_loadingDevices)
              const CircularProgressIndicator()
            else if (_devices.isEmpty)
              const Text('No devices found.')
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedDeviceId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Select Device',
                        isDense: true,
                      ),
                      items: _devices
                          .map(
                            (d) => DropdownMenuItem<String>(
                              value: d['id'],
                              child: Text(d['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedDeviceId = v;
                        _fetchUsers();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loadingUsers ? null : _fetchUsers,
                    icon: const Icon(Icons.sync),
                    label: const Text('Fetch Users'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (_loadingUsers)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: _fetchedUsers.isEmpty
                    ? const Center(child: Text('No users fetched yet.'))
                    : ListView.builder(
                        itemCount: _fetchedUsers.length,
                        itemBuilder: (context, index) {
                          final u = _fetchedUsers[index];
                          final bioId = u['biometric_user_id']?.toString();
                          if (bioId == null) return const SizedBox.shrink();

                          final isDuplicate = _duplicateBioIds.contains(bioId);
                          final name = u['full_name']?.toString() ?? 'Unknown';

                          return ListTile(
                            title: Text(name),
                            subtitle: Text('Bio ID: $bioId'),
                            trailing: isDuplicate
                                ? const Chip(
                                    label: Text(
                                      'Duplicate',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                    backgroundColor: Colors.orange,
                                  )
                                : FilledButton.icon(
                                    onPressed: () =>
                                        _openUserImportModal(u, isDuplicate),
                                    icon: const Icon(
                                      Icons.person_add_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Import'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF4CAF50),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleUserImportModal extends StatefulWidget {
  final Map<String, dynamic> user;
  final String deviceId;
  const _SingleUserImportModal(this.user, this.deviceId);

  @override
  State<_SingleUserImportModal> createState() => _SingleUserImportModalState();
}

class _SingleUserImportModalState extends State<_SingleUserImportModal> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();

  String _role = 'employee';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _nameController.text =
        widget.user['full_name']?.toString() ?? 'Imported User';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _importing = true);
    try {
      await ApiClient.instance.post(
        '/api/biometric-devices/${widget.deviceId}/import-user',
        data: {
          'biometric_user_id': widget.user['biometric_user_id'].toString(),
          'full_name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User imported securely and marked inactive.'),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        String errMsg = 'Import failed: $e';
        if (e is DioException) {
          errMsg = (e.response?.data is Map)
              ? e.response?.data['error']?.toString() ?? 'Network Error'
              : e.message ?? 'Unknown error';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import Biometric User',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Biometric ID: ${widget.user['biometric_user_id']}',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Admin Email for User',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Initial Password',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: ['employee', 'admin']
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _role = v ?? 'employee'),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _importing ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                    ),
                    child: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Import as Inactive'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog: all employees with biometric user ID visibility (paged, search, filters).
class _BiometricRosterDialog extends StatefulWidget {
  const _BiometricRosterDialog();

  @override
  State<_BiometricRosterDialog> createState() => _BiometricRosterDialogState();
}

class _BiometricRosterDialogState extends State<_BiometricRosterDialog> {
  static const int _pageSize = 50;

  int _pageIndex = 0;
  String _filter = 'all';
  String? _selectedDeviceId;
  List<dynamic> _devices = [];
  bool _loadingDevices = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableHorizontalScrollController = ScrollController();
  Timer? _searchDebounce;
  bool _loading = true;
  String? _error;
  List<_EmployeeProfile> _rows = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _tableHorizontalScrollController.dispose();
    super.dispose();
  }

  int get _totalPages {
    if (_total <= 0) return 1;
    return ((_total - 1) ~/ _pageSize) + 1;
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
        queryParameters: const {'status': 'Active'},
      );
      if (!mounted) return;
      setState(() {
        _devices = res.data ?? [];
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _devices = [];
          _loadingDevices = false;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'status': 'All',
        'role': 'All',
        'sort': 'full_name',
        'order': 'asc',
        'limit': _pageSize,
        'offset': _pageIndex * _pageSize,
      };
      if (_filter != 'all') {
        query['biometric_filter'] = _filter;
      }
      final dev = _selectedDeviceId?.trim();
      if (dev != null && dev.isNotEmpty) {
        query['biometric_device_id'] = dev;
      }
      final sq = _searchController.text.trim();
      if (sq.isNotEmpty) {
        query['q'] = sq;
      }

      final res = await ApiClient.instance.get<dynamic>(
        '/api/employees',
        queryParameters: query,
        options: dev != null && dev.isNotEmpty
            ? Options(receiveTimeout: const Duration(seconds: 120))
            : null,
      );
      if (!mounted) return;
      final data = res.data;
      List<_EmployeeProfile> next = [];
      var total = 0;
      if (data is Map) {
        final list = data['employees'] as List<dynamic>? ?? [];
        total = (data['total'] as num?)?.toInt() ?? 0;
        next = list
            .map(
              (e) =>
                  _employeeProfileFromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
      setState(() {
        _rows = next;
        _total = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _rows = [];
        _total = 0;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _pageIndex = 0;
      _load();
    });
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _pageIndex = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppTheme.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Biometric roster',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedDeviceId == null ||
                                  _selectedDeviceId!.trim().isEmpty
                              ? 'Biometric user IDs stored in HRMS. Use this list to pick a free ID before enrolling someone on the ZKTeco.'
                              : 'Only employees whose Biometric User ID exists on the selected device. The server reads the device user list and may take a few seconds the first time.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _selectedDeviceId,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.offWhite,
                      labelText: 'Device',
                      prefixIcon: const Icon(Icons.devices_other_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    hint: const Text('All devices (HRMS only)'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All devices (HRMS only)'),
                      ),
                      ..._devices.map((d) {
                        final map = Map<String, dynamic>.from(d as Map);
                        final id = map['id']?.toString() ?? '';
                        final name = map['name']?.toString() ?? id;
                        final loc = map['location']?.toString();
                        final label = (loc != null && loc.isNotEmpty)
                            ? '$name · $loc'
                            : name;
                        return DropdownMenuItem<String?>(
                          value: id,
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: _loadingDevices
                        ? null
                        : (v) {
                            setState(() {
                              _selectedDeviceId = v;
                              _pageIndex = 0;
                            });
                            _load();
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == 'all',
                    selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
                    showCheckmark: false,
                    onSelected: (sel) {
                      if (sel) _setFilter('all');
                    },
                  ),
                  ChoiceChip(
                    avatar: _filter == 'set'
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                    label: const Text('Has ID'),
                    selected: _filter == 'set',
                    selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
                    showCheckmark: false,
                    onSelected: (sel) {
                      if (sel) _setFilter('set');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Missing ID'),
                    selected: _filter == 'missing',
                    selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
                    showCheckmark: false,
                    onSelected: (sel) {
                      if (sel) _setFilter('missing');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search name, email, employee no., biometric ID…',
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.offWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red.shade800),
                            ),
                          ),
                        )
                      : _rows.isEmpty
                      ? Center(
                          child: Text(
                            'No employees match.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final tableMinWidth = constraints.hasBoundedWidth
                                ? constraints.maxWidth
                                : 0.0;
                            return Scrollbar(
                              controller: _tableHorizontalScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _tableHorizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: tableMinWidth,
                                  ),
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      columnSpacing: 28,
                                      headingRowHeight: 42,
                                      dataRowMinHeight: 44,
                                      headingRowColor: WidgetStateProperty.all(
                                        AppTheme.offWhite,
                                      ),
                                      columns: const [
                                        DataColumn(label: Text('No.')),
                                        DataColumn(label: Text('Name')),
                                        DataColumn(label: Text('Biometric ID')),
                                        DataColumn(label: Text('Active')),
                                      ],
                                      rows: _rows.map((e) {
                                        final bio =
                                            e.biometricUserId?.trim() ?? '';
                                        return DataRow(
                                          cells: [
                                            DataCell(Text(e.displayEmployeeNo)),
                                            DataCell(
                                              SizedBox(
                                                width: 260,
                                                child: Text(
                                                  e.fullName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 2,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                bio.isNotEmpty ? bio : '—',
                                                style: TextStyle(
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                  fontWeight: bio.isNotEmpty
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              _RosterStatusPill(
                                                label: e.isActive
                                                    ? 'Yes'
                                                    : 'No',
                                                active: e.isActive,
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.offWhite,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _total == 0
                            ? '0 employees'
                            : 'Page ${_pageIndex + 1} of $_totalPages · $_total total',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _pageIndex <= 0 || _loading
                            ? null
                            : () {
                                setState(() => _pageIndex--);
                                _load();
                              },
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Previous'),
                      ),
                      TextButton.icon(
                        onPressed: _pageIndex >= _totalPages - 1 || _loading
                            ? null
                            : () {
                                setState(() => _pageIndex++);
                                _load();
                              },
                        label: const Text('Next'),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
