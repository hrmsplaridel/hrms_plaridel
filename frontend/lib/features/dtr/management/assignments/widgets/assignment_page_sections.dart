part of '../pages/manage_assignment.dart';

extension _ManageAssignmentPageSections on _ManageAssignmentState {
  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 1, child: _buildLeftPanel()),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _buildRightPanel()),
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

  Widget _buildLeftPanel() {
    final dark = _isDark(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(width: 180, child: _buildSearchField()),
              _buildDepartmentFilterDropdown(),
              _buildEmployeeStatusDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    'EMP ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Name',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _headingColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingEmployees)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_employees.isEmpty)
            Container(
              constraints: const BoxConstraints(minHeight: 120),
              alignment: Alignment.center,
              child: Text(
                'No employees',
                style: TextStyle(
                  color: _mutedColor(context).withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
            )
          else
            ..._employees.map((e) {
              final isSelected = _selectedEmployeeId == e.id;
              return Material(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _updateAssignmentFormState(() {
                      _selectedEmployeeId = e.id;
                      _selectedEmployeeName = e.fullName;
                      _selectedAssignment = null;
                      _selectedDeptId = null;
                      _selectedPositionId = null;
                      _selectedShiftId = null;
                      _selectedPolicyId = null;
                      _effectiveFrom = null;
                      _effectiveTo = null;
                      _selectedDesignation = null;
                      _designationDeptId = null;
                      _designationPositionId = null;
                      _designationEffectiveFrom = null;
                      _designationEffectiveTo = null;
                      _designationIsActive = true;
                      _remarksController.clear();
                      _designationRemarksController.clear();
                    });
                    _loadAssignments();
                    _loadDesignations();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: Tooltip(
                            message: e.displayEmployeeNo,
                            child: Text(
                              e.compactEmployeeNo,
                              style: TextStyle(
                                fontSize: 12,
                                color: _mutedColor(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.fullName,
                            style: TextStyle(
                              fontSize: 13,
                              color: _headingColor(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          if (!_loadingEmployees && _totalEmployeeCount > 0)
            _buildEmployeePaginationBar(),
        ],
      ),
    );
  }

  Widget _buildEmployeePaginationBar() {
    final total = _totalEmployeeCount;
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
              fontSize: 12,
              color: _mutedColor(context).withValues(alpha: 0.9),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rows',
                style: TextStyle(
                  fontSize: 12,
                  color: _mutedColor(context).withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _pageSize,
                dropdownColor: AppTheme.dashPanelOf(context),
                style: AppTheme.dashFieldTextStyle(context),
                underline: const SizedBox.shrink(),
                isDense: true,
                items: _ManageAssignmentState._kPageSizes
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          '$s / page',
                          style: AppTheme.dashFieldTextStyle(context),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) _setEmployeePageSize(v);
                },
              ),
            ],
          ),
          if (maxPage > 0)
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _pageIndex > 0
                  ? () => _goToEmployeePage(_pageIndex - 1)
                  : null,
            ),
          Text(
            'Page ${_pageIndex + 1} / ${maxPage + 1}',
            style: TextStyle(
              fontSize: 12,
              color: _headingColor(context),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (maxPage > 0)
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _pageIndex < maxPage
                  ? () => _goToEmployeePage(_pageIndex + 1)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => _onSearchChanged(),
      style: AppTheme.dashFieldTextStyle(context),
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'Search',
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: _mutedColor(context).withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        radius: 10,
      ),
    );
  }

  Widget _buildDepartmentFilterDropdown() {
    final safeValue =
        _employeeDepartmentFilterId != null &&
            _departments.any(
              (d) => d['id']?.toString() == _employeeDepartmentFilterId,
            )
        ? _employeeDepartmentFilterId
        : null;

    return SizedBox(
      width: 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: _filterDecoration(context),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: safeValue,
            dropdownColor: AppTheme.dashPanelOf(context),
            style: AppTheme.dashFieldTextStyle(context),
            icon: Icon(
              Icons.arrow_drop_down_rounded,
              color: _mutedColor(context),
            ),
            hint: Text(
              'All departments',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppTheme.dashFieldHintStyle(context),
            ),
            isExpanded: true,
            isDense: true,
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All departments',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTheme.dashFieldTextStyle(context),
                ),
              ),
              ..._departments.map(
                (d) => DropdownMenuItem<String?>(
                  value: d['id']?.toString(),
                  child: Text(
                    d['name']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: AppTheme.dashFieldTextStyle(context),
                  ),
                ),
              ),
            ],
            onChanged: (v) {
              _resetEmployeeFiltersAndReload(() {
                _employeeDepartmentFilterId = v;
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String>(
        value: _employeeStatusFilter,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['All', 'Active', 'Inactive']
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: (v) {
          _resetEmployeeFiltersAndReload(() {
            _employeeStatusFilter = v ?? 'All';
          });
        },
      ),
    );
  }

  Widget _buildRightPanel() {
    final hasSelection = _selectedEmployeeId != null;
    final employeeLabel = _selectedEmployeeName ?? 'Select an employee';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.dashMutedSurfaceOf(context),
                  child: Icon(
                    Icons.person_rounded,
                    size: 28,
                    color: _mutedColor(context).withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Assignments for ${hasSelection ? employeeLabel : 'Select an employee'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 16,
                      fontWeight: hasSelection
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (hasSelection) ...[
                  FilledButton.icon(
                    onPressed: _loadingLookups
                        ? null
                        : () => _openAssignmentDrawer(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Primary'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE85D04),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                _buildStatusDropdown(),
              ],
            ),
            const SizedBox(height: 24),
            _buildAssignmentsTable(hasSelection),
            if (hasSelection) ...[
              const SizedBox(height: 24),
              _buildDesignationsSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _filterDecoration(context),
      child: DropdownButton<String>(
        value: _assignmentStatusFilter,
        dropdownColor: AppTheme.dashPanelOf(context),
        style: AppTheme.dashFieldTextStyle(context),
        underline: const SizedBox.shrink(),
        isDense: true,
        items: ['Active', 'Inactive', 'All']
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: AppTheme.dashFieldTextStyle(context)),
              ),
            )
            .toList(),
        onChanged: _setAssignmentStatusFilter,
      ),
    );
  }

  Widget _buildAssignmentsTable(bool hasSelection) {
    if (!hasSelection) return const SizedBox.shrink();
    final dark = _isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.65)
            : AppTheme.lightGray.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.assignment_ind_rounded,
                  size: 18,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Primary Assignment',
                    style: _tableHeaderStyle(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Department', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Position', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Shift', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Policy', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('Time', style: _tableHeaderStyle(context)),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Effective period',
                    style: _tableHeaderStyle(context),
                  ),
                ),
              ],
            ),
          ),
          if (_loadingAssignments)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_assignments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No primary assignment yet',
                  style: TextStyle(color: _mutedColor(context)),
                ),
              ),
            )
          else
            ..._assignments.map((a) {
              final isSelected = _selectedAssignment?.id == a.id;
              return Material(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _openAssignmentDrawer(assignment: a),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            a.departmentName,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            a.positionName,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            a.shiftName,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            (a.policyName != null &&
                                    a.policyName!.trim().isNotEmpty)
                                ? a.policyName!
                                : 'Default policy',
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${_timeStr(a.startTime)} - ${_timeStr(a.endTime)}',
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            _effectivePeriodStr(a),
                            style: _tableCellStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDesignationsSection() {
    final dark = _isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.65)
            : AppTheme.lightGray.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.badge_rounded,
                  size: 18,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Other Positions',
                    style: _tableHeaderStyle(context),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loadingLookups
                      ? null
                      : () => _openDesignationDrawer(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Other'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE85D04),
                  ),
                ),
              ],
            ),
          ),
          if (_loadingDesignations)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_designations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No other positions yet',
                  style: TextStyle(color: _mutedColor(context)),
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Department',
                      style: _tableHeaderStyle(context),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('Position', style: _tableHeaderStyle(context)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Effective period',
                      style: _tableHeaderStyle(context),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text('Status', style: _tableHeaderStyle(context)),
                  ),
                ],
              ),
            ),
            ..._designations.map((designation) {
              final isSelected = _selectedDesignation?.id == designation.id;
              final status = _designationStatus(designation);
              return Material(
                color: isSelected
                    ? (dark
                          ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                          : AppTheme.primaryNavy.withValues(alpha: 0.08))
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => _openDesignationDrawer(designation: designation),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.dashHairlineOf(
                            context,
                          ).withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            designation.departmentName ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _designationTitle(designation),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _designationEffectivePeriodStr(designation),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _tableCellStyle(context),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: _buildDesignationStatusBadge(status),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignationStatusBadge(String status) {
    final Color color = switch (status) {
      'Active' => const Color(0xFF2E7D32),
      'Upcoming' => const Color(0xFF1565C0),
      'Expired' => const Color(0xFF6B7280),
      _ => const Color(0xFFC62828),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _isDark(context) ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _isDark(context) ? color.withValues(alpha: 0.9) : color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  TextStyle _tableHeaderStyle(BuildContext context) => TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 13,
    color: _headingColor(context),
  );

  TextStyle _tableCellStyle(BuildContext context) =>
      TextStyle(fontSize: 13, color: _headingColor(context));
}
