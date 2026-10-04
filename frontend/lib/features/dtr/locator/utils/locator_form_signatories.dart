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
  });

  final LocatorPrintedSignatory applicant;
  final LocatorPrintedSignatory departmentHead;
  final LocatorPrintedSignatory finalApprover;
  final Map<String, dynamic> form;

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
    );
  }
}

Future<LocatorFormSignatories> loadLocatorFormSignatories(String? id) async {
  if (id == null || id.isEmpty) return const LocatorFormSignatories();
  final response = await ApiClient.instance.get<Map<String, dynamic>>(
    '/api/docutracker/sources/dtr/locator_slips/$id/signatures',
  );
  // Fail visibly instead of silently printing an unsigned form after a network error.
  return LocatorFormSignatories.fromJson(response.data ?? const {});
}
