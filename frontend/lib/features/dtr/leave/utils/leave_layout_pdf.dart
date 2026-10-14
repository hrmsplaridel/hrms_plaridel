import 'dart:math' as math;
import 'leave_design_capture.dart';
import 'leave_request_pdf.dart';
import 'configured_leave_pdf.dart' show buildWellnessLeavePdf;
import '../models/leave_balance.dart';
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
  'employee_first_name': 'First name',
  'employee_middle_name': 'Middle name',
  'employee_last_name': 'Last name',
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

const _typeDetails = <String, Set<String>>{
  'vacationLeave': {'location_option', 'location_details'},
  'mandatoryForcedLeave': {'location_option', 'location_details'},
  'specialPrivilegeLeave': {'location_option', 'location_details'},
  'sickLeave': {'sick_leave_nature', 'sick_illness_details'},
  'maternityLeave': {'maternity_delivery_type', 'expected_delivery_date'},
  'paternityLeave': {'child_delivery_date'},
  'rehabilitationPrivilege': {'accident_date'},
  'specialEmergencyCalamityLeave': {'calamity_date'},
  'adoptionLeave': {'adoption_parent_role', 'adoption_placement_date'},
  'tenDayVawcLeave': {'vawc_support_document_type', 'vawc_case_details'},
  'soloParentLeave': {'solo_parent_id_number', 'solo_parent_id_expiry_date'},
  'specialLeaveBenefitsForWomen': {'women_illness_details'},
  'studyLeave': {'study_purpose', 'study_purpose_details'},
  'others': {'other_purpose', 'other_purpose_details'},
};
Map<String, String> leaveLayoutFields(LeaveTypeDefinition type) {
  final specialized = _typeDetails.values.expand((e) => e).toSet();
  final allowed = _typeDetails[type.name] ?? const <String>{};
  return {
    for (final e in leavePrintFields.entries)
      if (!specialized.contains(e.key) || allowed.contains(e.key))
        e.key: e.value,
    for (final f in type.employeeDetailSchema) 'custom:${f.key}': f.label,
  };
}

(String, String) _nameParts(String? name) {
  final p = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  return (
    p.length > 2 ? p[1] : '',
    p.length > 2
        ? p.skip(2).join(' ')
        : p.length == 2
        ? p[1]
        : '',
  );
}

String _date(DateTime? d) => d?.toIso8601String().split('T').first ?? '';
Map<String, dynamic> leaveLayoutForm(LeaveRequest request) => {
  ...request.toJson(),
  'employee_name': request.employeeName ?? '',
  'employee_first_name':
      (request.employeeName ?? '').trim().split(RegExp(r'\s+')).firstOrNull ??
      '',
  'employee_middle_name': _nameParts(request.employeeName).$1,
  'employee_last_name': _nameParts(request.employeeName).$2,
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
  leaveType: LeaveType.values.firstWhere(
    (e) => e.name == type.name,
    orElse: () => LeaveType.others,
  ),
  customLeaveTypeText: LeaveType.values.any((e) => e.name == type.name)
      ? null
      : type.displayName,
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

Map<String, String> leaveLayoutSignatures(String? form) => form == 'wellness'
    ? {
        'applicant': 'Employee signature',
        'department_head': 'Department signature',
        'hr_approver': 'Mayor signature',
      }
    : leavePrintSignatures;

Future<({LocatorPrintLayout layout, Uint8List background})>
importLeaveNativeLayout(
  LeaveTypeDefinition type,
  String form, {
  bool letterhead = false,
}) async {
  final capture = LeaveDesignCapture(
    fields: leaveLayoutFields(type),
    signatureStyle: form == 'wellness' ? 'standard' : 'csc',
  );
  final request = leaveLayoutSampleRequest(type);
  final doc = form == 'wellness'
      ? await buildWellnessLeavePdf(
          request: request,
          department: 'Human Resources',
          designCapture: capture,
        )
      : await LeaveRequestPdf.buildPdf(
          request: request,
          designCapture: capture,
        );
  final bytes = await doc.save();
  final nativeWidth = form == 'wellness' ? 595.28 : 612.0,
      nativeHeight = form == 'wellness' ? 841.89 : 1008.0;
  final scale = form == 'csc' && letterhead
      ? math.min(491.28 / nativeWidth, 611.89 / nativeHeight)
      : 1.0;
  final x = form == 'csc' && letterhead
      ? (595.28 - nativeWidth * scale) / 2
      : 0.0;
  final bottom = form == 'csc' && letterhead ? 120.0 : 0.0;
  final pageHeight = form == 'csc' && letterhead ? 841.89 : nativeHeight;
  final top = pageHeight - bottom - nativeHeight * scale;
  final nativeBox = form == 'wellness'
      ? {'x': 52.0, 'y': 110.0, 'width': 491.28, 'height': 611.89}
      : {'x': 16.0, 'y': 16.0, 'width': 580.0, 'height': 976.0};
  final layout = LocatorPrintLayout(
    paperSize: form == 'csc' && !letterhead ? 'legal' : 'a4',
    baseForm: form,
    baseFormBox: {
      'x': x + nativeBox['x']! * scale,
      'y': top + nativeBox['y']! * scale,
      'width': nativeBox['width']! * scale,
      'height': nativeBox['height']! * scale,
    },
    elements: [
      for (final item in capture.elements.values)
        item.copyWith(
          x: x + item.x * scale,
          y: top + item.y * scale,
          width: math.max(
            item.kind == 'signature' ? 100.0 : 20.0,
            item.width * scale,
          ),
          height: math.max(
            item.kind == 'signature'
                ? (item.signatureStyle == 'csc'
                      ? (item.source == 'applicant' ? 18.0 : 32.0)
                      : 60.0)
                : 20.0,
            item.height * scale,
          ),
          fontSize: math.max(6.0, item.fontSize * scale),
        ),
    ],
  );
  final error = layout.validate();
  if (error != null) throw FormatException(error);
  return (layout: layout, background: bytes);
}

Future<Uint8List> buildLeaveLayoutPdf({
  required LocatorPrintLayout layout,
  required LeaveRequest request,
  LocatorFormSignatories signatories = const LocatorFormSignatories(),
  List<LeaveBalance>? balances,
  LocatorPrintedSignatory certificationOfficer =
      const LocatorPrintedSignatory(),
}) async {
  pw.Document? nativeDocument;
  LeaveDesignCapture? capture;
  if (layout.baseForm != null) {
    capture = LeaveDesignCapture(
      fields: leavePrintFields,
      renderingLayout: layout,
      signatureStyle: layout.baseForm == 'wellness' ? 'standard' : 'csc',
    );
    nativeDocument = layout.baseForm == 'wellness'
        ? await buildWellnessLeavePdf(
            request: request,
            department: request.officeDepartment ?? '',
            designCapture: capture,
          )
        : await LeaveRequestPdf.buildPdf(
            request: request,
            balances: balances,
            designCapture: capture,
          );
  }
  return buildLocatorLayoutPdf(
    document: nativeDocument,
    onMainPageWidgets: capture == null
        ? null
        : (widgets) => capture!.overlays = widgets,
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
}
