import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/approval_workflow_summary.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_shared_widgets.dart';

/// The same request information layout for employee and reviewer details.
class LeaveRequestInformation extends StatelessWidget {
  const LeaveRequestInformation({super.key, required this.request});
  final LeaveRequest request;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if(request.isPaperRecord) ...[
        const AdminLeaveSubsectionTitle(title:'Approved paper leave record'),
        AdminLeaveBodyCard(content:'Original approval: ${request.paperApprovalRecord!['approval_date']}\n'
          'Approved by: ${request.paperApprovalRecord!['final_approver']?['name'] ?? ''}\n'
          'Encoded by: ${request.paperApprovalRecord!['encoded_by_name'] ?? ''}\n'
          'Encoded at: ${request.paperApprovalRecord!['encoded_at'] ?? ''}\n'
          'The attachment is the signed original. Generated copies include the employee’s and selected officials’ saved signatures copied when this record was encoded, where available.'),
        const SizedBox(height:16),
      ],
      ApprovalWorkflowSummary(snapshot:request.workflowSnapshot),
      _AdminLeaveDetailGrid(request: request, employeeInformation: true),
      const SizedBox(height: 20),
      const AdminLeaveSubsectionTitle(title: 'Leave Details'),
      const SizedBox(height: 8),
      _RequestDetailsBox(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RequestDetailPill(
              label: 'Date Filed',
              value: request.dateFiled != null
                  ? formatAdminLeaveDate(request.dateFiled!)
                  : '—',
            ),
            _RequestDetailPill(
              label: 'Inclusive Dates',
              value: _formatRange(request),
            ),
            _RequestDetailPill(
              label: 'Total Working Days',
              value: request.workingDaysApplied?.toStringAsFixed(1) ?? '—',
            ),
            _RequestDetailPill(
              label: 'Leave Type',
              value: request.leaveTypeLabel,
            ),
            _RequestDetailPill(
              label: 'Commutation',
              value: request.commutation.displayName,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _AdminLeaveDetailGrid(request: request),
      if ((request.reason ?? '').trim().isNotEmpty) ...[
        AdminLeaveSubsectionTitle(title: 'Reason / Details'),
        AdminLeaveBodyCard(content: request.reason!.trim()),
        const SizedBox(height: 16),
      ],
    ],
  );

  String _formatRange(LeaveRequest request) {
    if (request.startDate == null || request.endDate == null) return '—';
    return '${formatAdminLeaveDate(request.startDate!)} to ${formatAdminLeaveDate(request.endDate!)}';
  }
}

class _RequestDetailsBox extends StatelessWidget {
  const _RequestDetailsBox({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

class _RequestDetailPill extends StatelessWidget {
  const _RequestDetailPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.dashIsDark(context)
          ? AppTheme.dashMutedSurfaceOf(context)
          : const Color(0xffe7eff6),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
    ),
    child: Text.rich(
      TextSpan(
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: 13,
          height: 1.35,
        ),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _AdminLeaveDetailGrid extends StatelessWidget {
  const _AdminLeaveDetailGrid({
    required this.request,
    this.employeeInformation = false,
  });

  final LeaveRequest request;
  final bool employeeInformation;

  @override
  Widget build(BuildContext context) {
    final allRows = _buildDetailRows(request);
    final rows = employeeInformation
        ? allRows.take(3).toList()
        : allRows.skip(3).toList();

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminLeaveSubsectionTitle(
          title: employeeInformation
              ? 'Employee Information'
              : 'Additional Context',
        ),
        const SizedBox(height: 8),
        if (rows.isNotEmpty)
          _RequestDetailsBox(
            padding: EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 600
                    ? 1
                    : (employeeInformation ? 3 : 2);
                return Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: AppTheme.dashHairlineOf(context)),
                  ),
                  children: [
                    for (var start = 0; start < rows.length; start += columns)
                      TableRow(
                        children: [
                          for (var col = 0; col < columns; col++)
                            if (start + col < rows.length)
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      rows[start + col].label,
                                      style: TextStyle(
                                        color: AppTheme.dashTextSecondaryOf(
                                          context,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      rows[start + col].value,
                                      style: TextStyle(
                                        color: AppTheme.dashTextPrimaryOf(
                                          context,
                                        ),
                                        fontSize: 15,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        if (!employeeInformation) const SizedBox(height: 20),
      ],
    );
  }

  List<({String label, String value})> _buildDetailRows(LeaveRequest request) {
    final rows = <({String label, String value})>[
      (
        label: 'Office / Department',
        value: _displayValue(request.officeDepartment),
      ),
      (label: 'Position Title', value: _displayValue(request.positionTitle)),
      (
        label: 'Salary',
        value: request.salary != null
            ? '₱${request.salary!.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\.)'), (match) => '${match[1]},')}'
            : '—',
      ),
    ];

    void addRelevant({
      required String label,
      required String? value,
      required bool applies,
    }) {
      if (!applies || !_hasValue(value)) return;
      rows.add((label: label, value: _displayValue(value)));
    }

    void addRelevantEnum({
      required String label,
      required String? value,
      required bool applies,
    }) {
      if (!applies || !_hasValue(value)) return;
      rows.add((label: label, value: value ?? '—'));
    }

    void addRelevantDate({
      required String label,
      required DateTime? value,
      required bool applies,
    }) {
      if (!applies || value == null) return;
      rows.add((
        label: label,
        value: formatAdminLeaveDate(value),
      ));
    }

    final leaveType = request.leaveType;
    final usesGenericOtherPurpose =
        leaveType == LeaveType.others &&
        request.effectiveLeaveTypeName.toLowerCase() == LeaveType.others.value;

    addRelevantEnum(
      label: 'Maternity Classification',
      value: request.maternityDeliveryType?.displayName,
      applies: leaveType == LeaveType.maternityLeave,
    );
    addRelevantDate(
      label: 'Expected Delivery Date',
      value: request.expectedDeliveryDate,
      applies: leaveType == LeaveType.maternityLeave,
    );
    addRelevantDate(
      label: 'Child Delivery Date',
      value: request.childDeliveryDate,
      applies: leaveType == LeaveType.paternityLeave,
    );
    addRelevantDate(
      label: 'Accident Date',
      value: request.accidentDate,
      applies: leaveType == LeaveType.rehabilitationPrivilege,
    );
    addRelevantDate(
      label: 'Calamity Occurrence Date',
      value: request.calamityDate,
      applies: leaveType == LeaveType.specialEmergencyCalamityLeave,
    );
    addRelevantEnum(
      label: 'Adoption Eligibility',
      value: request.adoptionParentRole?.displayName,
      applies: leaveType == LeaveType.adoptionLeave,
    );
    addRelevantDate(
      label: 'PAPA / Adoption Placement Date',
      value: request.adoptionPlacementDate,
      applies: leaveType == LeaveType.adoptionLeave,
    );
    addRelevantEnum(
      label: 'VAWC Supporting Document',
      value: request.vawcSupportDocumentType?.displayName,
      applies: leaveType == LeaveType.tenDayVawcLeave,
    );
    addRelevant(
      label: 'VAWC Case Details',
      value: request.vawcCaseDetails,
      applies: leaveType == LeaveType.tenDayVawcLeave,
    );
    addRelevant(
      label: 'Solo Parent ID Number',
      value: request.soloParentIdNumber,
      applies: leaveType == LeaveType.soloParentLeave,
    );
    addRelevantDate(
      label: 'Solo Parent ID Expiry Date',
      value: request.soloParentIdExpiryDate,
      applies: leaveType == LeaveType.soloParentLeave,
    );
    addRelevantEnum(
      label: 'Location',
      value: request.locationOption?.displayName,
      applies:
          leaveType == LeaveType.vacationLeave ||
          leaveType == LeaveType.specialPrivilegeLeave,
    );
    addRelevant(
      label: 'Location Details',
      value: request.locationDetails,
      applies:
          leaveType == LeaveType.vacationLeave ||
          leaveType == LeaveType.specialPrivilegeLeave,
    );
    addRelevantEnum(
      label: 'Sick Leave Nature',
      value: request.sickLeaveNature?.displayName,
      applies: leaveType == LeaveType.sickLeave,
    );
    addRelevant(
      label: 'Sick Illness Details',
      value: request.sickIllnessDetails,
      applies: leaveType == LeaveType.sickLeave,
    );
    addRelevant(
      label: 'Women Illness Details',
      value: request.womenIllnessDetails,
      applies: leaveType == LeaveType.specialLeaveBenefitsForWomen,
    );
    addRelevantEnum(
      label: 'Study Purpose',
      value: request.studyPurpose?.displayName,
      applies: leaveType == LeaveType.studyLeave,
    );
    addRelevant(
      label: 'Study Purpose Details',
      value: request.studyPurposeDetails,
      applies: leaveType == LeaveType.studyLeave,
    );
    addRelevantEnum(
      label: 'Other Purpose',
      value: request.otherPurpose?.displayName,
      applies: usesGenericOtherPurpose,
    );
    addRelevant(
      label: 'Other Purpose Details',
      value: request.otherPurposeDetails,
      applies: usesGenericOtherPurpose,
    );

    for (final field in request.employeeDetailSchemaSnapshot) {
      final value = request.customDetails[field.key];
      if (value == null || value.toString().trim().isEmpty) continue;
      rows.add((label: field.label, value: _displayCustomValue(field, value)));
    }

    return rows;
  }

  static String _displayCustomValue(
    LeaveCustomFieldDefinition field,
    dynamic value,
  ) {
    if (field.type == LeaveCustomFieldType.boolean) {
      return value == true ? 'Yes' : 'No';
    }
    if (field.type == LeaveCustomFieldType.date) {
      final date = DateTime.tryParse(value.toString());
      if (date != null) return formatAdminLeaveDate(date);
    }
    return value.toString();
  }

  static bool _hasValue(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String _displayValue(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? '—' : trimmed;
  }
}
