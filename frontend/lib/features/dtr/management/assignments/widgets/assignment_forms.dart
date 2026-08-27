part of '../pages/manage_assignment.dart';

extension _ManageAssignmentForms on _ManageAssignmentState {
  Widget _buildAssignmentForm({bool framed = true, bool showActions = true}) {
    String? safeValue(String? value, List<Map<String, dynamic>> items) {
      if (value == null) return null;
      return items.any((item) => item['id']?.toString() == value)
          ? value
          : null;
    }

    final selectedDeptValue = safeValue(_selectedDeptId, _departments);
    final selectedShiftValue = safeValue(_selectedShiftId, _shifts);
    final selectedPolicyValue = safeValue(
      _selectedPolicyId,
      _attendancePolicies,
    );
    final isEditing = _selectedAssignment != null;
    final filteredPositions = _positionsForSelectedDepartment;
    final hasDepartment = selectedDeptValue != null;
    final canSelectPosition = hasDepartment && filteredPositions.isNotEmpty;
    final positionSelectLabel = !hasDepartment
        ? 'Select department first'
        : filteredPositions.isEmpty
        ? 'No positions'
        : 'Select';
    final selectedPositionValue =
        filteredPositions.any(
          (position) => position['id']?.toString() == _selectedPositionId,
        )
        ? _selectedPositionId
        : null;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth >= 600;
            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildFormDropdown(
                      'Department',
                      selectedDeptValue,
                      _departments,
                      _setDepartment,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildFormDropdown(
                      'Position',
                      selectedPositionValue,
                      filteredPositions,
                      (v) => _updateAssignmentFormState(
                        () => _selectedPositionId = v,
                      ),
                      enabled: canSelectPosition,
                      selectLabel: positionSelectLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildFormDropdown(
                      'Shift',
                      selectedShiftValue,
                      _shifts,
                      (v) => _updateAssignmentFormState(
                        () => _selectedShiftId = v,
                      ),
                    ),
                  ),
                  if (!isEditing) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildFormDropdown(
                        'Initial Attendance Policy (opt)',
                        selectedPolicyValue,
                        _attendancePolicies,
                        (v) => _updateAssignmentFormState(
                          () => _selectedPolicyId = v,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildFormDropdown(
                  'Department',
                  selectedDeptValue,
                  _departments,
                  _setDepartment,
                ),
                _buildFormDropdown(
                  'Position',
                  selectedPositionValue,
                  filteredPositions,
                  (v) =>
                      _updateAssignmentFormState(() => _selectedPositionId = v),
                  enabled: canSelectPosition,
                  selectLabel: positionSelectLabel,
                ),
                _buildFormDropdown(
                  'Shift',
                  selectedShiftValue,
                  _shifts,
                  (v) => _updateAssignmentFormState(() => _selectedShiftId = v),
                ),
                if (!isEditing)
                  _buildFormDropdown(
                    'Initial Attendance Policy (opt)',
                    selectedPolicyValue,
                    _attendancePolicies,
                    (v) =>
                        _updateAssignmentFormState(() => _selectedPolicyId = v),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth >= 520;
            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildDatePicker(
                      'Effective from',
                      _effectiveFrom,
                      (d) =>
                          _updateAssignmentFormState(() => _effectiveFrom = d),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDatePicker(
                      'Effective to (opt)',
                      _effectiveTo,
                      (d) => _updateAssignmentFormState(() => _effectiveTo = d),
                    ),
                  ),
                ],
              );
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildDatePicker(
                  'Effective from',
                  _effectiveFrom,
                  (d) => _updateAssignmentFormState(() => _effectiveFrom = d),
                ),
                _buildDatePicker(
                  'Effective to (opt)',
                  _effectiveTo,
                  (d) => _updateAssignmentFormState(() => _effectiveTo = d),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Remarks (optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _remarksController,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: AppTheme.dashInputDecoration(
            context,
            hintText: 'Notes about this assignment',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            radius: 8,
          ),
          maxLines: 2,
        ),
        if (showActions) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loadingLookups ? null : () => _addAssignment(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Primary Assignment'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _selectedAssignment != null
                    ? () => _updateAssignment()
                    : null,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Update'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  side: const BorderSide(color: Color(0xFF4CAF50)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _selectedAssignment != null
                    ? () => _deactivateAssignment()
                    : null,
                icon: const Icon(Icons.person_off_rounded, size: 18),
                label: const Text('Deactivate'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (!framed) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark(context)
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.lightGray.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: content,
    );
  }

  Widget _buildPolicyPeriodForm() {
    final policyItems = [..._attendancePolicies];
    final selectedPeriod = _selectedPolicyPeriod;
    if (selectedPeriod != null &&
        !policyItems.any(
          (item) => item['id']?.toString() == selectedPeriod.policyId,
        )) {
      policyItems.add({
        'id': selectedPeriod.policyId,
        'name': '${selectedPeriod.policyName} (inactive)',
      });
    }
    final selectedPolicyValue =
        policyItems.any(
          (item) => item['id']?.toString() == _policyPeriodPolicyId,
        )
        ? _policyPeriodPolicyId
        : null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFormDropdown(
            'Employee attendance policy',
            selectedPolicyValue,
            policyItems,
            (value) =>
                _updatePolicyFormState(() => _policyPeriodPolicyId = value),
            selectLabel: 'Use fallback policy',
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final useRow = constraints.maxWidth >= 420;
              final from = _buildDatePicker(
                'Effective from',
                _policyPeriodEffectiveFrom,
                (date) => _updatePolicyFormState(
                  () => _policyPeriodEffectiveFrom = date,
                ),
              );
              final to = _buildDatePicker(
                'Effective to (optional)',
                _policyPeriodEffectiveTo,
                (date) => _updatePolicyFormState(
                  () => _policyPeriodEffectiveTo = date,
                ),
              );
              if (!useRow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [from, const SizedBox(height: 16), to],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: from),
                  const SizedBox(width: 16),
                  Expanded(child: to),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selectedPolicyValue == null
                        ? 'The employee-level policy is removed only for this period. Shift, department, or default policy can then apply.'
                        : 'Existing policy periods before and after these dates are preserved automatically.',
                    style: TextStyle(
                      color: _mutedColor(context),
                      fontSize: 13,
                      height: 1.35,
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

  Widget _buildDesignationForm({bool framed = true}) {
    String? safeValue(String? value, List<Map<String, dynamic>> items) {
      if (value == null) return null;
      return items.any((item) => item['id']?.toString() == value)
          ? value
          : null;
    }

    final selectedDeptValue = safeValue(_designationDeptId, _departments);
    final filteredPositions = _positionsForDesignationDepartment;
    final hasDepartment = selectedDeptValue != null;
    final canSelectPosition = hasDepartment && filteredPositions.isNotEmpty;
    final positionSelectLabel = !hasDepartment
        ? 'Select department first'
        : filteredPositions.isEmpty
        ? 'No positions'
        : 'Select';
    final selectedPositionValue =
        filteredPositions.any(
          (position) => position['id']?.toString() == _designationPositionId,
        )
        ? _designationPositionId
        : null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth >= 560;
            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildFormDropdown(
                      'Department',
                      selectedDeptValue,
                      _departments,
                      _setDesignationDepartment,
                      selectLabel: 'Select department',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFormDropdown(
                      'Position',
                      selectedPositionValue,
                      filteredPositions,
                      (v) => _updateDesignationFormState(
                        () => _designationPositionId = v,
                      ),
                      enabled: canSelectPosition,
                      selectLabel: positionSelectLabel,
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFormDropdown(
                  'Department',
                  selectedDeptValue,
                  _departments,
                  _setDesignationDepartment,
                  selectLabel: 'Select department',
                ),
                const SizedBox(height: 16),
                _buildFormDropdown(
                  'Position',
                  selectedPositionValue,
                  filteredPositions,
                  (v) => _updateDesignationFormState(
                    () => _designationPositionId = v,
                  ),
                  enabled: canSelectPosition,
                  selectLabel: positionSelectLabel,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final useRow = constraints.maxWidth >= 520;
            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildDatePicker(
                      'Effective from',
                      _designationEffectiveFrom,
                      (d) => _updateDesignationFormState(
                        () => _designationEffectiveFrom = d,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDatePicker(
                      'Effective to (opt)',
                      _designationEffectiveTo,
                      (d) => _updateDesignationFormState(
                        () => _designationEffectiveTo = d,
                      ),
                    ),
                  ),
                ],
              );
            }
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildDatePicker(
                  'Effective from',
                  _designationEffectiveFrom,
                  (d) => _updateDesignationFormState(
                    () => _designationEffectiveFrom = d,
                  ),
                ),
                _buildDatePicker(
                  'Effective to (opt)',
                  _designationEffectiveTo,
                  (d) => _updateDesignationFormState(
                    () => _designationEffectiveTo = d,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _isDark(context)
                ? AppTheme.dashMutedSurfaceOf(context)
                : AppTheme.lightGray.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: SwitchListTile(
            value: _designationIsActive,
            onChanged: (value) =>
                _updateDesignationFormState(() => _designationIsActive = value),
            title: Text(
              'Active other position',
              style: TextStyle(
                color: _headingColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            activeThumbColor: const Color(0xFFE85D04),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          label: 'Remarks (optional)',
          controller: _designationRemarksController,
          hintText: 'Notes about this other position',
          maxLines: 2,
        ),
      ],
    );

    if (!framed) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark(context)
            ? AppTheme.dashMutedSurfaceOf(context)
            : AppTheme.lightGray.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: content,
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: AppTheme.dashFieldTextStyle(context),
          decoration: AppTheme.dashInputDecoration(
            context,
            hintText: hintText,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            radius: 8,
          ),
          maxLines: maxLines,
        ),
      ],
    );
  }

  Widget _buildFormDropdown(
    String label,
    String? value,
    List<Map<String, dynamic>> items,
    ValueChanged<String?> onChanged, {
    bool enabled = true,
    String selectLabel = 'Select',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _mutedColor(context),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('$label-${value ?? ''}-${items.length}-$enabled'),
          initialValue: value,
          dropdownColor: AppTheme.dashPanelOf(context),
          style: AppTheme.dashFieldTextStyle(context),
          decoration: _inputDecoration(selectLabel),
          hint: Text(
            selectLabel,
            style: TextStyle(color: _mutedColor(context)),
            overflow: TextOverflow.ellipsis,
          ),
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(
                selectLabel,
                style: AppTheme.dashFieldTextStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...items.map(
              (e) => DropdownMenuItem(
                value: e['id'] as String?,
                child: Text(
                  e['name'] as String? ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
            ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onChanged,
  ) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _mutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (d != null) onChanged(d);
            },
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDecoration('Select date').copyWith(
                suffixIcon: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: _mutedColor(context),
                ),
              ),
              child: Text(
                value != null
                    ? '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'
                    : '',
                style: TextStyle(
                  fontSize: 14,
                  color: value != null
                      ? _headingColor(context)
                      : _mutedColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => AppTheme.dashInputDecoration(
    context,
    hintText: hint,
    radius: 8,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}
