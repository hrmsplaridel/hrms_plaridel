import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import '../models/leave_type_definition.dart';
import '../../locator/models/locator_print_layout.dart';
import '../../locator/utils/locator_form_signatories.dart';
import '../../locator/utils/locator_layout_pdf.dart';

const leavePrintFields = <String, String>{
  'employee_name': 'Employee name',
  'date': 'Date filed',
  'request_type': 'Leave type',
  'office': 'Office / Department',
  'position': 'Employee position',
  'salary': 'Monthly salary',
  'start_date': 'Start date',
  'end_date': 'End date',
  'inclusive_dates': 'Inclusive dates',
  'working_days': 'Working days applied',
  'reason': 'Reason',
  'location_option': 'Leave location',
  'location_details': 'Location details',
  'sick_leave_nature': 'Sick leave nature',
  'sick_illness_details': 'Illness details',
  'maternity_delivery_type': 'Delivery type',
  'expected_delivery_date': 'Expected delivery date',
  'child_delivery_date': 'Child delivery date',
  'accident_date': 'Accident date',
  'calamity_date': 'Calamity date',
  'adoption_parent_role': 'Adoption parent role',
  'adoption_placement_date': 'Adoption placement date',
  'vawc_support_document_type': 'VAWC support document',
  'vawc_case_details': 'VAWC case details',
  'solo_parent_id_number': 'Solo parent ID',
  'solo_parent_id_expiry_date': 'Solo parent ID expiry',
  'women_illness_details': 'Special leave illness details',
  'study_purpose': 'Study purpose',
  'study_purpose_details': 'Study details',
  'other_purpose': 'Other purpose',
  'other_purpose_details': 'Other purpose details',
  'commutation': 'Commutation',
  'approved_days_with_pay': 'Approved days with pay',
  'approved_days_without_pay': 'Approved days without pay',
  'approved_other_details': 'Approval details',
  'recommendation_remarks': 'Recommendation remarks',
  'disapproval_reason': 'Disapproval reason',
  'hr_remarks': 'HR remarks',
};
const leavePrintSignatures = <String, String>{
  'applicant': 'Employee signature',
  'department_head': 'Department signature',
  'certification_officer': 'Certification signature',
  'hr_approver': 'Final signature',
};

Map<String, String> leaveLayoutFields(LeaveTypeDefinition type) => {
  ...leavePrintFields,
  for (final f in type.employeeDetailSchema) 'custom:${f.key}': f.label,
};
String _date(DateTime? d) => d?.toIso8601String().split('T').first ?? '';
Map<String, dynamic> leaveLayoutForm(LeaveRequest request) => {
  ...request.toJson(),
  'employee_name': request.employeeName ?? '',
  'slip_date': _date(request.dateFiled),
  'request_type_label': request.leaveTypeLabel,
  'office': request.officeDepartment ?? '',
  'position': request.positionTitle ?? '',
  'salary': request.salary?.toStringAsFixed(2) ?? '',
  'inclusive_dates': [
    _date(request.startDate),
    _date(request.endDate),
  ].where((v) => v.isNotEmpty).join(' - '),
  'working_days': request.workingDaysApplied,
  'location_option': request.locationOption?.displayName ?? '',
  'sick_leave_nature': request.sickLeaveNature?.displayName ?? '',
  'maternity_delivery_type': request.maternityDeliveryType?.displayName ?? '',
  'adoption_parent_role': request.adoptionParentRole?.displayName ?? '',
  'vawc_support_document_type':
      request.vawcSupportDocumentType?.displayName ?? '',
  'study_purpose': request.studyPurpose?.displayName ?? '',
  'other_purpose': request.otherPurpose?.displayName ?? '',
  'commutation': request.commutation.displayName,
  'additional_details': request.customDetails,
  'employee_detail_schema_snapshot': request.employeeDetailSchemaSnapshot
      .map((f) => f.toJson())
      .toList(),
};
LeaveRequest leaveLayoutSampleRequest(LeaveTypeDefinition type) => LeaveRequest(
  userId: 'sample',
  employeeName: 'Sample Employee',
  positionTitle: 'Sample employee position',
  officeDepartment: 'Human Resources',
  salary: 25000,
  dateFiled: DateTime(2026, 10, 13),
  startDate: DateTime(2026, 10, 14),
  endDate: DateTime(2026, 10, 15),
  workingDaysApplied: 2,
  leaveType: LeaveType.others,
  leaveTypeDisplayName: type.displayName.isEmpty
      ? 'Leave Application'
      : type.displayName,
  reason: 'Sample reason for leave',
  employeeDetailSchemaSnapshot: type.employeeDetailSchema,
  customDetails: {
    for (final f in type.employeeDetailSchema)
      f.key: switch (f.type) {
        LeaveCustomFieldType.date => '2026-10-13',
        LeaveCustomFieldType.number => 1,
        LeaveCustomFieldType.boolean => true,
        LeaveCustomFieldType.select => f.options.firstOrNull ?? 'Sample',
        _ => 'Sample ${f.label}',
      },
  },
);
LocatorPrintedSignatory leaveLayoutSampleSignatory(String source) =>
    LocatorPrintedSignatory(
      name: 'Sample signer',
      positionTitle: switch (source) {
        'applicant' => 'Sample employee position',
        'department_head' => 'Department Head',
        'certification_officer' => 'HR Officer',
        _ => 'Approving Authority',
      },
    );
LocatorPrintLayout leavePrintLayoutDefaults(
  LeaveTypeDefinition type, {
  String orientation = 'portrait',
}) {
  final portrait = orientation == 'portrait',
      pageWidth = portrait ? 595.28 : 841.89,
      pageHeight = portrait ? 841.89 : 595.28;
  final fields = {
    'employee_name': 'Employee name',
    'date': 'Date filed',
    'office': 'Office / Department',
    'position': 'Employee position',
    'request_type': 'Leave type',
    'inclusive_dates': 'Inclusive dates',
    'working_days': 'Working days applied',
    'reason': 'Reason',
    for (final f in type.employeeDetailSchema.take(20))
      'custom:${f.key}': f.label,
  };
  final rowHeight = portrait ? 35.0 : 24.0,
      width = (pageWidth - 94) / 2,
      start = portrait ? 180.0 : 120.0;
  final elements = <LocatorPrintElement>[
    LocatorPrintElement(
      id: 'title',
      kind: 'text',
      text: type.displayName.isEmpty
          ? 'APPLICATION FOR LEAVE'
          : type.displayName.toUpperCase(),
      x: 40,
      y: portrait ? 130 : 80,
      width: pageWidth - 80,
      height: 32,
      fontSize: 20,
      bold: true,
      align: 'center',
    ),
  ];
  var i = 0;
  for (final e in fields.entries) {
    elements.add(
      LocatorPrintElement(
        id: 'field_$i',
        kind: 'field',
        source: e.key,
        label: e.value,
        x: 40 + (i % 2) * (width + 14),
        y: start + (i ~/ 2) * rowHeight,
        width: width,
        height: rowHeight - 2,
        fontSize: portrait ? 10 : 8,
      ),
    );
    i++;
  }
  final sigWidth = (pageWidth - 122) / 4;
  final sigY = (start + ((i + 1) ~/ 2) * rowHeight + 20).clamp(
    0.0,
    pageHeight - 90,
  );
  i = 0;
  for (final source in leavePrintSignatures.keys) {
    elements.add(
      LocatorPrintElement(
        id: 'signature_$source',
        kind: 'signature',
        source: source,
        x: 40 + i * (sigWidth + 14),
        y: sigY,
        width: sigWidth,
        height: 75,
        fontSize: 10,
        align: 'center',
      ),
    );
    i++;
  }
  return LocatorPrintLayout(orientation: orientation, elements: elements);
}

Future<Uint8List> buildLeaveLayoutPdf({
  required LocatorPrintLayout layout,
  required LeaveRequest request,
  LocatorFormSignatories signatories = const LocatorFormSignatories(),
  LocatorPrintedSignatory certificationOfficer =
      const LocatorPrintedSignatory(),
}) async => buildLocatorLayoutPdf(
  layout: layout,
  form: leaveLayoutForm(request),
  signatories: signatories,
  extraSignatories: {'certification_officer': certificationOfficer},
  regularFont: pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  ),
  strongFont: pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  ),
);
