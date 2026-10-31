import 'dart:convert';
import 'dart:typed_data';

import 'package:hrms_plaridel/core/api/client.dart';

class LocatorPrintedSignatory {
  const LocatorPrintedSignatory({
    this.name = '',
    this.positionTitle = '',
    this.signatureBytes,
  });

  final String name;
  final String positionTitle;
  final Uint8List? signatureBytes;

  factory LocatorPrintedSignatory.fromJson(dynamic value) {
    if (value is! Map) return const LocatorPrintedSignatory();
    // PostgreSQL base64 encoding inserts line breaks every 76 characters.
    final image = value['signature_image_base64']?.toString().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    return LocatorPrintedSignatory(
      name: value['name']?.toString() ?? '',
      positionTitle: value['position_title']?.toString() ?? '',
      signatureBytes: image == null || image.isEmpty
          ? null
          : base64Decode(image),
    );
  }
}

class LocatorFormSignatories {
  const LocatorFormSignatories({
    this.applicant = const LocatorPrintedSignatory(),
    this.departmentHead = const LocatorPrintedSignatory(),
    this.finalApprover = const LocatorPrintedSignatory(),
    this.form = const {},
    this.workflowApprovers = const {},
  });

  final LocatorPrintedSignatory applicant;
  final LocatorPrintedSignatory departmentHead;
  final LocatorPrintedSignatory finalApprover;
  final Map<String, dynamic> form;
  final Map<String, LocatorPrintedSignatory> workflowApprovers;

  LocatorPrintedSignatory forSource(String source) =>
      workflowApprovers[source] ??
      switch (source) {
        'applicant' => applicant,
        'department_head' => departmentHead,
        'hr_approver' => finalApprover,
        _ => const LocatorPrintedSignatory(),
      };

  factory LocatorFormSignatories.fromJson(Map<String, dynamic> json) {
    final roles = json['print_signatories'];
    if (roles is! Map) {
      throw const FormatException('Locator print signatories are unavailable');
    }
    return LocatorFormSignatories(
      applicant: LocatorPrintedSignatory.fromJson(roles['applicant']),
      departmentHead: LocatorPrintedSignatory.fromJson(
        roles['department_head'],
      ),
      finalApprover: LocatorPrintedSignatory.fromJson(roles['hr_approver']),
      form: Map<String, dynamic>.from(json['print_form'] as Map? ?? const {}),
      workflowApprovers: workflowPrintedSignatoriesFromJson(json),
    );
  }
}

/// Use completed, request-bound decisions only. Never substitute the final
/// approver's ink into a missing/future middle step.
Map<String, LocatorPrintedSignatory> workflowPrintedSignatoriesFromJson(
  Map<String, dynamic> json,
) {
  final snapshot = json['workflow_snapshot'];
  if (snapshot is! Map || snapshot['steps'] is! List) return const {};
  final steps = snapshot['steps'] as List;
  final decisions = (snapshot['decisions'] as List? ?? const [])
      .whereType<Map>();
  final signatures = (json['signatures'] as List? ?? const []).whereType<Map>();
  final active = const [
    'pending',
    'pending_hr',
    'pending_department_head',
    'pending_mayor',
    'approved',
  ].contains(json['source_status']);
  return {
    for (var i = 0; i < steps.length && i < 20; i++)
      'workflow_step_${i + 1}': (() {
        final step = steps[i];
        final label = step is Map
            ? step['label']?.toString() ?? ''
            : const {
                    'department': 'Department Review',
                    'hr': 'HR Review',
                    'mayor': 'Mayor Approval',
                    'manual_mayor': 'Manual Mayor Signing',
                  }[step] ??
                  '';
        final decision = decisions
            .where((d) => d['step'] == i && d['action'] == 'approve')
            .firstOrNull;
        final reviewer = decision?['reviewer'] is Map
            ? decision!['reviewer'] as Map
            : const {};
        final saved = decision?['signature'] is Map
            ? decision!['signature'] as Map
            : const {};
        final manual =
            step == 'manual_mayor' ||
            step is Map && step['assignee_source'] == 'manual_mayor';
        final confirmed = !active || manual || decision?['actor_id'] == null
            ? null
            : signatures
                  .where(
                    (s) =>
                        s['slot_key'] == 'workflow_step_${i + 1}' &&
                        s['signed_by'] == decision!['actor_id'] &&
                        s['signature_asset_id'] != null &&
                        s['signature_asset_id'] ==
                            saved['signature_asset_id'] &&
                        (json['source_revision'] == null ||
                            saved['revision'] == json['source_revision']),
                  )
                  .firstOrNull;
        return LocatorPrintedSignatory.fromJson({
          'name': decision == null
              ? ''
              : reviewer['name'] ?? saved['signer_name_snapshot'] ?? '',
          'position_title': reviewer['position_title'] ?? label,
          'signature_image_base64': confirmed?['signature_image_base64'],
        });
      })(),
  };
}

Future<LocatorFormSignatories> loadLocatorFormSignatories(String? id) async {
  if (id == null || id.isEmpty) return const LocatorFormSignatories();
  final response = await ApiClient.instance.get<Map<String, dynamic>>(
    '/api/docutracker/sources/dtr/locator_slips/$id/signatures',
  );
  // Fail visibly instead of silently printing an unsigned form after a network error.
  return LocatorFormSignatories.fromJson(response.data ?? const {});
}
