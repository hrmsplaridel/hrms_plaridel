part of '../pages/manage_employee.dart';

class AddEmployeeForm extends StatefulWidget {
  const AddEmployeeForm({super.key, this.onAccountCreated});

  /// When set (e.g. opened from a dialog), invoked after a successful create instead of only a snackbar.
  final VoidCallback? onAccountCreated;

  @override
  State<AddEmployeeForm> createState() => _AddEmployeeFormState();
}

class _AddEmployeeFormState extends State<AddEmployeeForm> {
  final _formKey = GlobalKey<FormState>();
  final _setupSectionKey = GlobalKey<EmployeeSetupSectionState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _streetController = TextEditingController();
  GlobalKey<StructuredAddressFormState> _addressFormKey =
      GlobalKey<StructuredAddressFormState>();
  final _salaryGradeController = TextEditingController();
  final _biometricIdController = TextEditingController();

  /// No role until HR picks one.
  String? _privilege;
  String? _suffix;
  String? _sex;
  DateTime? _dateOfBirth;
  String? _employmentType;
  String _employmentStatus = 'active';
  DateTime? _dateHired;
  bool _leaveCreditEligible = true;
  Uint8List? _selectedImageBytes;
  bool _saving = false;
  int? _lastAppliedPrefillStamp;

  void _ensureTemporaryPassword() {
    if (_passwordController.text.trim().isEmpty) {
      _passwordController.text = generateTemporaryAccountPassword();
    }
  }

  void _regenerateTemporaryPassword() {
    setState(() {
      _passwordController.text = generateTemporaryAccountPassword();
    });
  }

  Future<void> _copyTemporaryPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: password));
    _showSnackBar('Temporary password copied.');
  }

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
    setState(() {
      _privilege = 'Employee';
      _ensureTemporaryPassword();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _streetController.dispose();
    _salaryGradeController.dispose();
    _biometricIdController.dispose();
    super.dispose();
  }

  bool _chromeDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _chromeHeadingColor(BuildContext context) => _chromeDark(context)
      ? AppTheme.dashTextPrimaryOf(context)
      : AppTheme.textPrimary;

  Color _chromeMutedColor(BuildContext context) => _chromeDark(context)
      ? AppTheme.dashTextSecondaryOf(context)
      : AppTheme.textSecondary;

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    final darkChrome = _chromeDark(context);
    final borderColor = AppTheme.dashInputBorderOf(context);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      labelStyle: TextStyle(
        color: _chromeMutedColor(context).withValues(alpha: 0.9),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: TextStyle(
        color: _chromeHeadingColor(context),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: _chromeMutedColor(context).withValues(alpha: 0.65),
        fontSize: 14,
      ),
      filled: true,
      fillColor: AppTheme.dashInputFillOf(context),
      isDense: false,
      contentPadding: EdgeInsets.fromLTRB(16, darkChrome ? 22 : 18, 16, 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
      ),
    );
  }

  Widget _paneHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _chromeHeadingColor(context),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: _chromeMutedColor(context),
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
    _firstNameController.clear();
    _middleNameController.clear();
    _lastNameController.clear();
    _contactController.clear();
    _streetController.clear();
    _salaryGradeController.clear();
    _biometricIdController.clear();
    setState(() {
      _addressFormKey = GlobalKey<StructuredAddressFormState>();
      _privilege = null;
      _suffix = null;
      _sex = null;
      _dateOfBirth = null;
      _employmentType = null;
      _employmentStatus = 'active';
      _dateHired = null;
      _leaveCreditEligible = true;
      _selectedImageBytes = null;
      _passwordController.clear();
    });
    _setupSectionKey.currentState?.clearSelection();
  }

  Future<void> _saveEmployee() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!(_setupSectionKey.currentState?.validateAssignmentSelection() ??
        true)) {
      return;
    }

    final email = _emailController.text.trim();
    _ensureTemporaryPassword();
    final password = _passwordController.text.trim();
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
        'first_name': firstName,
        'full_name': fullName,
        'last_name': lastName,
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
        if (_biometricIdController.text.trim().isNotEmpty)
          'biometric_user_id': _biometricIdController.text.trim(),
        'date_hired': _dateHired!.toIso8601String().split('T')[0],
        'employment_status': _employmentStatus,
        'leave_credit_eligible': _leaveCreditEligible,
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
      String? setupWarning;
      try {
        await _setupSectionKey.currentState?.createInitialSetupForEmployee(
          employeeId: userId,
          effectiveFrom: _dateHired ?? DateTime.now(),
        );
      } catch (e) {
        setupWarning = _apiErrorMessageFromDio(
          e,
          fallback: 'Initial assignment/policy was not saved.',
        );
      }

      if (!mounted) return;
      final hire = context.read<RecruitmentHirePrefill>();
      if (hire.hasPendingLink && hire.applicationId != null) {
        try {
          await RecruitmentRepo.instance.linkHiredUser(
            hire.applicationId!,
            userId,
          );
          hire.recordCreatedCredentials(
            applicationId: hire.applicationId!,
            loginEmail: email,
            password: data['temporary_password']?.toString() ?? password,
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
        dtr.loadDepartments(forceRefresh: true);
        dtr.loadEmployees(forceRefresh: true);
      } catch (_) {}
      final emailConfigured = data['account_email_configured'] == true;
      final emailSent = data['account_email_sent'] == true;
      final accountIsActive = data['is_active'] != false;
      final temporaryPassword = data['temporary_password']?.toString() ?? '';
      if (accountIsActive && !emailSent && temporaryPassword.isNotEmpty) {
        await _showTemporaryPasswordDialog(
          email: email,
          password: temporaryPassword,
          emailConfigured: emailConfigured,
          emailError: data['account_email_error']?.toString(),
        );
      }
      if (!mounted) return;
      _clearForm();
      if (setupWarning != null) {
        _showSnackBar(
          'Account created, but setup was not completed: $setupWarning',
        );
      }
      if (widget.onAccountCreated != null) {
        widget.onAccountCreated!();
      } else {
        final emailStatus = !accountIsActive
            ? ' Account is inactive; credentials were not sent.'
            : emailSent
            ? ' Credentials were emailed to the employee.'
            : emailConfigured
            ? ' Account email failed; please share the login details manually.'
            : ' Email is not configured; please share the login details manually.';
        final setupStatus = setupWarning == null ? '' : ' Setup needs review.';
        _showSnackBar('Account created as $privilege.$emailStatus$setupStatus');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 409) {
        final msg = e.response?.data is Map
            ? (e.response!.data as Map)['error']?.toString()
            : null;
        _showSnackBar(msg ?? 'Email already registered');
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

  Future<void> _showTemporaryPasswordDialog({
    required String email,
    required String password,
    required bool emailConfigured,
    String? emailError,
  }) async {
    if (!mounted) return;
    final reason = emailConfigured
        ? 'The account email could not be sent.'
        : 'SMTP email is not configured.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Temporary password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$reason Share these login details manually.'),
            if (emailError != null && emailError.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                emailError,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            SelectableText('Email: $email\nTemporary password: $password'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: 'Email: $email\nPassword: $password'),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy and close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.of(context).size.width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final isNarrow = width < 820;
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
                                  color: _chromeHeadingColor(context),
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
                decoration: BoxDecoration(
                  color: _chromeDark(context)
                      ? AppTheme.dashPanelOf(context)
                      : AppTheme.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
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
                                  _buildSectionCard(
                                    child: _buildPersonalSection(),
                                  ),
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
                  color: _chromeDark(context)
                      ? AppTheme.dashPanelOf(context)
                      : AppTheme.white,
                  border: Border(
                    top: BorderSide(color: AppTheme.dashHairlineOf(context)),
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
      },
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
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _privilege,
          isExpanded: true,
          decoration: _fieldDecoration('Role', hint: 'Select role first'),
          hint: Text(
            'Select role first',
            style: TextStyle(color: _chromeMutedColor(context)),
          ),
          items: const [
            DropdownMenuItem(value: 'Employee', child: Text('Employee')),
            DropdownMenuItem(value: 'Admin', child: Text('Administrator')),
          ],
          onChanged: (v) => setState(() {
            _privilege = v;
            _ensureTemporaryPassword();
          }),
          validator: (v) => v == null ? 'Select a role first' : null,
        ),
        if (_privilege != null) ...[
          const SizedBox(height: 18),
          TextFormField(
            controller: _passwordController,
            readOnly: true,
            decoration: _fieldDecoration('Temporary password').copyWith(
              helperText:
                  'Generated automatically. Copy it only if SMTP email fails.',
              helperMaxLines: 2,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Copy password',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: _copyTemporaryPassword,
                  ),
                  IconButton(
                    tooltip: 'Generate new password',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: _regenerateTemporaryPassword,
                  ),
                ],
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ],
        if (_privilege == 'Admin') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFEF6C00).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Color(0xFFEF6C00),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Administrator can access the full admin dashboard, DTR management, and all HR modules. Use Employee for hired staff.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: _chromeMutedColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        TextFormField(
          controller: _biometricIdController,
          decoration: _fieldDecoration('Biometric User ID (optional)').copyWith(
            helperText:
                'Set now if known, or leave blank and add it later from Edit employee.',
            helperMaxLines: 2,
          ),
          textInputAction: TextInputAction.next,
        ),
        SizedBox(height: narrow ? 14 : 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(
              alpha: _chromeDark(context) ? 0.14 : 0.06,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(
                alpha: _chromeDark(context) ? 0.28 : 0.1,
              ),
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
                  'Temporary passwords are emailed through SMTP and encrypted after creation. The user can change it from their profile.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: _chromeMutedColor(context),
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
    final dark = _chromeDark(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dashMutedSurfaceOf(context) : AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark
              ? AppTheme.dashHairlineOf(context)
              : Colors.black.withValues(alpha: 0.06),
        ),
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
            color: _chromeHeadingColor(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _firstNameController,
          decoration: _fieldDecoration('First name'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _middleNameController,
          decoration: _fieldDecoration('Middle name (optional)'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _lastNameController,
          decoration: _fieldDecoration('Last name'),
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 18),
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
            color: _chromeHeadingColor(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 14),
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
        const SizedBox(height: 18),
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
        const SizedBox(height: 18),
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
    final dark = _chromeDark(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dashMutedSurfaceOf(context) : AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark
              ? AppTheme.dashHairlineOf(context)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Employment',
            style: TextStyle(
              color: _chromeHeadingColor(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _employmentType,
            decoration: _fieldDecoration('Employment Type'),
            hint: Text(
              'Employment Type',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.85),
                fontSize: 14,
              ),
            ),
            items: [
              'regular',
              'contractual',
              'job_order',
              'casual',
            ].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => setState(() => _employmentType = v),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _salaryGradeController,
            decoration: _fieldDecoration('Salary Grade'),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 20),
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
                  decoration:
                      _fieldDecoration(
                        'Date hired',
                        hint: 'Tap calendar to choose',
                      ).copyWith(
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
                        : 'Tap calendar to choose',
                    style: TextStyle(
                      fontSize: 14,
                      color: _dateHired != null
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
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
            onChanged: (v) => setState(() {
              _employmentStatus = v ?? 'active';
              if (_employmentStatus != 'active') {
                _leaveCreditEligible = false;
              }
            }),
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _leaveCreditEligible,
            title: Text(
              'Earn monthly VL/SL credits',
              style: TextStyle(
                color: _chromeHeadingColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: _employmentStatus == 'active'
                ? null
                : const Text('Available only for active employees'),
            secondary: Icon(
              Icons.account_balance_wallet_outlined,
              color: AppTheme.primaryNavy,
            ),
            onChanged: _employmentStatus == 'active'
                ? (value) => setState(() => _leaveCreditEligible = value)
                : null,
          ),
          EmployeeSetupSection(
            key: _setupSectionKey,
            title: 'Initial assignment',
            subtitle: 'Optional setup created after the account is saved.',
            validationMessage:
                'For initial assignment, select Department, Position, and Shift; or leave all three blank.',
            showTopDivider: true,
          ),
        ],
      ),
    );
  }
}
