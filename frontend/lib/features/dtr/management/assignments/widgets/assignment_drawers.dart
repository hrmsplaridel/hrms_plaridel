part of '../pages/manage_assignment.dart';

extension _ManageAssignmentDrawers on _ManageAssignmentState {
  Widget _buildAssignmentDrawer(BuildContext drawerContext) {
    final isEditing = _selectedAssignment != null;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing
                        ? 'Edit Primary Assignment'
                        : 'Add Primary Assignment',
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  icon: Icon(Icons.close_rounded, color: _mutedColor(context)),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _buildAssignmentForm(framed: false, showActions: false),
            ),
          ),
          _buildDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedAssignment != null;
    final canDeleteMistake =
        isEditing && _isFutureAssignment(_selectedAssignment!.effectiveFrom);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(drawerContext).pop(),
            child: const Text('Cancel'),
          ),
          if (isEditing)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivateAssignment();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          if (canDeleteMistake)
            IconButton(
              onPressed: () async {
                final ok = await _deleteMistakenAssignment();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.delete_forever_rounded),
              color: Colors.red,
              tooltip: 'Delete mistaken future assignment',
            ),
          FilledButton.icon(
            onPressed: _loadingLookups
                ? null
                : () async {
                    final ok = isEditing
                        ? await _updateAssignment()
                        : await _addAssignment();
                    if (ok && drawerContext.mounted) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Primary Assignment'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesignationDrawer(BuildContext drawerContext) {
    final isEditing = _selectedDesignation != null;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Edit Other Position' : 'Add Other Position',
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  icon: Icon(Icons.close_rounded, color: _mutedColor(context)),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _buildDesignationForm(framed: false),
            ),
          ),
          _buildDesignationDrawerFooter(drawerContext),
        ],
      ),
    );
  }

  Widget _buildPolicyPeriodDrawer(BuildContext drawerContext) {
    final isEditing = _selectedPolicyPeriod != null;
    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Change Policy Period' : 'Add Policy Period',
                    style: TextStyle(
                      color: _headingColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  icon: Icon(Icons.close_rounded, color: _mutedColor(context)),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(child: _buildPolicyPeriodForm()),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              border: Border(
                top: BorderSide(color: AppTheme.dashHairlineOf(context)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(drawerContext).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loadingLookups
                      ? null
                      : () async {
                          final ok = await _savePolicyPeriod();
                          if (ok && drawerContext.mounted) {
                            Navigator.of(drawerContext).pop();
                          }
                        },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(isEditing ? 'Apply Change' : 'Save Period'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE85D04),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesignationDrawerFooter(BuildContext drawerContext) {
    final isEditing = _selectedDesignation != null;
    final canDeactivate =
        isEditing && (_selectedDesignation?.isActive ?? false);
    final canDeleteMistake =
        isEditing && _isFutureAssignment(_selectedDesignation!.effectiveFrom);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        border: Border(
          top: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(drawerContext).pop(),
            child: const Text('Cancel'),
          ),
          if (canDeactivate)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _deactivateDesignation();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.person_off_rounded, size: 18),
              label: const Text('Deactivate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          if (canDeleteMistake)
            IconButton(
              onPressed: () async {
                final ok = await _deleteMistakenDesignation();
                if (ok && drawerContext.mounted) {
                  Navigator.of(drawerContext).pop();
                }
              },
              icon: const Icon(Icons.delete_forever_rounded),
              color: Colors.red,
              tooltip: 'Delete mistaken future other position',
            ),
          FilledButton.icon(
            onPressed: _loadingLookups
                ? null
                : () async {
                    final ok = isEditing
                        ? await _updateDesignation()
                        : await _addDesignation();
                    if (ok && drawerContext.mounted) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
            icon: Icon(
              isEditing ? Icons.edit_rounded : Icons.add_rounded,
              size: 18,
            ),
            label: Text(isEditing ? 'Update' : 'Add Other Position'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
