part of '../pages/manage_employee.dart';

class _EditEmployeeDialog extends StatefulWidget {
  const _EditEmployeeDialog({required this.profile});
  final _EmployeeProfile profile;

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  late final _EmployeeProfile _profile;
  final _formKey = GlobalKey<FormState>();
  final _setupSectionKey = GlobalKey<EmployeeSetupSectionState>();
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
  DateTime? _separationDate;
  String? _employmentStatus;
  bool _leaveCreditEligible = true;
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
    if ((_profile.firstName ?? '').trim().isNotEmpty) {
      _firstNameController.text = _profile.firstName!.trim();
    }
    if (_profile.middleName != null && _profile.middleName!.isNotEmpty) {
      _middleNameController.text = _profile.middleName!;
    }
    if ((_profile.lastName ?? '').trim().isNotEmpty) {
      _lastNameController.text = _profile.lastName!.trim();
    }
    _contactController.text = _profile.contactNumber ?? '';
    _salaryGradeController.text = _profile.salaryGrade ?? '';
    _privilege = _profile.role == 'admin' ? 'Admin' : 'Employee';
    _suffix = _profile.suffix;
    _sex = _profile.sex;
    _dateOfBirth = _profile.dateOfBirth;
    _employmentType = _profile.employmentType;
    _dateHired = _profile.dateHired;
    _separationDate = _profile.separationDate;
    _employmentStatus = _profile.employmentStatus ?? 'active';
    _leaveCreditEligible =
        _profile.leaveCreditEligible ||
        _profile.leaveCreditEligibleUntil != null;
    _biometricIdController.text = _profile.biometricUserId ?? '';
    _loadBioDevicesForPush();
  }

  Future<void> _loadBioDevicesForPush() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/biometric-devices',
        queryParameters: const {'status': 'Active', 'probe_online': '0'},
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

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    if (!(_setupSectionKey.currentState?.validateAssignmentSelection() ??
        true)) {
      return;
    }

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
        'first_name': firstName,
        'full_name': fullName,
        'last_name': lastName,
        'role': role,
        ...buildClearableEmployeeProfileUpdateFields(
          middleName: middleName,
          suffix: _suffix,
          sex: _sex,
          dateOfBirth: _dateOfBirth,
          contactNumber: _contactController.text,
          address: encodedAddress,
          employmentType: _employmentType,
          salaryGrade: _salaryGradeController.text,
        ),
        if (_dateHired != null)
          'date_hired': _dateHired!.toIso8601String().split('T')[0],
        'separation_date': _requiresSeparationDate(_employmentStatus)
            ? _employeeDateText(_separationDate!)
            : null,
        if (_employmentStatus != null) 'employment_status': _employmentStatus,
        'leave_credit_eligible': _leaveCreditEligible,
        if (!_biometricUserIdLocked &&
            _biometricIdController.text.trim().isNotEmpty)
          'biometric_user_id': _biometricIdController.text.trim(),
      };
      if (!_requiresSeparationDate(_employmentStatus)) {
        final setupChanges = _setupSectionKey.currentState
            ?.buildAtomicSetupPayload(
              effectiveFrom: DateTime.now(),
              changedOnly: true,
            );
        if (setupChanges != null) body['setup'] = setupChanges;
      }

      await ApiClient.instance.put('/api/employees/${_profile.id}', data: body);

      var avatarUploadFailed = false;
      if (_selectedImageBytes != null && _selectedImageBytes!.isNotEmpty) {
        try {
          await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
            '/api/upload/avatar/for/${_profile.id}',
            bytes: _selectedImageBytes!,
            fileName: 'avatar.jpg',
          );
        } catch (e) {
          avatarUploadFailed = true;
          debugPrint('Avatar upload failed: $e');
        }
      }

      if (!mounted) return;
      try {
        final dtr = context.read<DtrProvider>();
        dtr.invalidateCachedDtrData(includeReferenceData: true);
        dtr.loadEmployees(forceRefresh: true);
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            avatarUploadFailed
                ? 'Employee setup was updated, but the photo upload failed. Reopen the employee to retry the photo.'
                : 'Employee updated successfully.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _apiErrorMessageFromDio(e, fallback: 'Failed to update employee.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.dashPanelOf(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit employee',
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _profile.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                    tooltip: 'Close',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.of(context).size.width;
                  final isNarrow = width < 820;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
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
                                const SizedBox(width: 24),
                                Expanded(child: _buildPersonalSection()),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                border: Border(
                  top: BorderSide(color: AppTheme.dashHairlineOf(context)),
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
                        color: AppTheme.dashTextSecondaryOf(context),
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
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Information',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
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
                      userAvatarImageUrl(
                        _profile.id,
                        avatarPath: _profile.avatarPath,
                      ),
                      key: ValueKey(_profile.avatarPath),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => CircleAvatar(
                        radius: 48,
                        backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                        child: Icon(
                          Icons.person_rounded,
                          size: 56,
                          color: AppTheme.dashTextSecondaryOf(
                            context,
                          ).withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  )
                : CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                    child: Icon(
                      Icons.person_rounded,
                      size: 56,
                      color: AppTheme.dashTextSecondaryOf(
                        context,
                      ).withValues(alpha: 0.5),
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
              _profile.email ?? '—',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _privilege,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            decoration: _inputDecoration('Select role'),
            hint: Text(
              'Select role',
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
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
          const SizedBox(height: 16),
          if (!_requiresSeparationDate(_employmentStatus))
            EmployeeSetupSection(
              key: _setupSectionKey,
              title: 'Current assignment',
              subtitle:
                  'Change these only if this employee needs a new current department, position, shift, or policy. Assignment changes start today and keep old history.',
              validationMessage:
                  'For assignment, select Department, Position, and Shift; or leave all three blank.',
              employeeId: _profile.id,
              loadCurrentSetup: true,
              boxed: true,
            ),
        ],
      ),
    );
  }

  Widget _buildPersonalSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _firstNameController,
            style: AppTheme.dashFieldTextStyle(context),
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
                suffixIcon: _dateOfBirth == null
                    ? const Icon(
                        Icons.calendar_today_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      )
                    : IconButton(
                        onPressed: () => setState(() => _dateOfBirth = null),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Clear date of birth',
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
            initialValue: _employmentType ?? '',
            decoration: _inputDecoration('Employment Type'),
            hint: const Text('Employment Type'),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('Not specified'),
              ),
              ...[
                'regular',
                'contractual',
                'job_order',
                'casual',
              ].map((o) => DropdownMenuItem(value: o, child: Text(o))),
            ],
            onChanged: (v) => setState(
              () => _employmentType = v == null || v.isEmpty ? null : v,
            ),
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
            onChanged: (v) => setState(() {
              _employmentStatus = v ?? 'active';
              if (_employmentStatus == 'inactive') {
                _leaveCreditEligible = false;
              }
              if (!_requiresSeparationDate(_employmentStatus)) {
                _separationDate = null;
              }
            }),
          ),
          if (_requiresSeparationDate(_employmentStatus)) ...[
            const SizedBox(height: 16),
            FormField<DateTime>(
              key: ValueKey(
                '${_employmentStatus}_${_separationDate?.toIso8601String() ?? 'separation_null'}',
              ),
              validator: (_) {
                if (_separationDate == null) {
                  return 'Last day of service is required';
                }
                if (_dateHired != null &&
                    _separationDate!.isBefore(_dateHired!)) {
                  return 'Last day of service cannot be before date hired';
                }
                if (_separationDate!.isAfter(DateTime.now())) {
                  return 'Last day of service cannot be in the future';
                }
                return null;
              },
              builder: (state) => InkWell(
                onTap: () async {
                  final today = DateTime.now();
                  final initial = _separationDate ?? today;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial.isAfter(today) ? today : initial,
                    firstDate: DateTime(1900),
                    lastDate: today,
                  );
                  if (picked != null) {
                    setState(() => _separationDate = picked);
                    state.didChange(picked);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _inputDecoration('Last day of service').copyWith(
                    errorText: state.errorText,
                    suffixIcon: Icon(
                      Icons.event_busy_outlined,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  child: Text(
                    _separationDate != null
                        ? _employeeDateText(_separationDate!)
                        : 'Tap calendar to choose',
                    style: TextStyle(
                      fontSize: 14,
                      color: _separationDate != null
                          ? AppTheme.dashTextPrimaryOf(context)
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _leaveCreditEligible,
            title: Text(
              _requiresSeparationDate(_employmentStatus)
                  ? 'Eligible for VL/SL through separation'
                  : 'Earn monthly VL/SL credits',
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: _requiresSeparationDate(_employmentStatus)
                ? const Text(
                    'Used to calculate the prorated final-month credit.',
                  )
                : (_employmentStatus == 'active'
                      ? null
                      : const Text('Available only for active employees')),
            secondary: Icon(
              Icons.account_balance_wallet_outlined,
              color: AppTheme.primaryNavy,
            ),
            onChanged:
                _employmentStatus == 'active' ||
                    _requiresSeparationDate(_employmentStatus)
                ? (value) => setState(() => _leaveCreditEligible = value)
                : null,
          ),
        ],
      ),
    );
  }
}
