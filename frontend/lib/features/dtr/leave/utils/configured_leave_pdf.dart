import '../models/leave_balance.dart';
import 'leave_design_capture.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/core/api/client.dart';
import '../models/leave_request.dart';
import 'leave_layout_pdf.dart';
import '../../locator/models/locator_print_layout.dart';
import '../../locator/utils/locator_form_signatories.dart';

Future<Uint8List> saveConfiguredLeavePdf({
  required LeaveRequest request,
  required pw.Document document,
  List<LeaveBalance>? balances,
  String? departmentReviewer,
  String? departmentReviewerTitle,
  String? approvingAuthorityName,
  String? approvingAuthorityTitle,
  String? certificationOfficerName,
  String? certificationOfficerTitle,
  Uint8List? certificationSignature,
  Uint8List? applicantSignature,
  Uint8List? departmentSignature,
  Uint8List? finalSignature,
}) async {
  if (request.id == null) return document.save();
  final response = await ApiClient.instance.get<Map<String, dynamic>>(
    '/api/leave/print/requests/${request.id}',
  );
  final config = response.data!;
  Uint8List? customBytes;
  if (config['layout'] == 'custom') {
    if (config['print_layout'] is! Map) {
      throw const FormatException('Saved custom leave layout is missing.');
    }
    final nativeLayout = LocatorPrintLayout.fromJson(
      Map<String, dynamic>.from(config['print_layout'] as Map),
    );
    final manualMayor =
        request.finalReviewRoute == 'mayor' ||
        nativeLayout.baseForm == 'wellness';
    Map<String, LocatorPrintedSignatory> workflowApprovers = const {};
    if (nativeLayout.elements.any((item) => item.kind == 'signature' && item.source.startsWith('workflow_step_')) && !request.isPaperRecord) {
      final signatures = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/docutracker/sources/dtr/leave_requests/${request.id}/signatures',
      );
      workflowApprovers = workflowPrintedSignatoriesFromJson(signatures.data ?? const {});
    }
    customBytes = await buildLeaveLayoutPdf(
      layout: nativeLayout,
      balances: balances,
      request: request,
      signatories: LocatorFormSignatories(
        workflowApprovers: workflowApprovers,
        applicant: LocatorPrintedSignatory(
          name: request.employeeName ?? '',
          positionTitle: request.positionTitle ?? '',
          signatureBytes: applicantSignature,
        ),
        departmentHead: LocatorPrintedSignatory(
          name: departmentReviewer ?? request.departmentHeadReviewerName ?? '',
          positionTitle: departmentReviewerTitle ?? '',
          signatureBytes: departmentSignature,
        ),
        finalApprover: LocatorPrintedSignatory(
          name: manualMayor
              ? config['mayor_name']?.toString() ?? ''
              : approvingAuthorityName ?? '',
          positionTitle: manualMayor
              ? config['mayor_title']?.toString() ?? 'Municipal Mayor'
              : approvingAuthorityTitle ?? '',
          signatureBytes: manualMayor ? null : finalSignature,
        ),
      ),
      certificationOfficer: LocatorPrintedSignatory(
        name: certificationOfficerName ?? '',
        positionTitle: certificationOfficerTitle ?? '',
        signatureBytes: certificationSignature,
      ),
    );
  }
  final doc = config['layout'] == 'wellness'
      ? await buildWellnessLeavePdf(
          request: request,
          department:
              request.officeDepartment ??
              config['department_name']?.toString() ??
              '',
          mayorName: config['mayor_name']?.toString() ?? '',
          departmentReviewer: departmentReviewer,
          applicantSignature: applicantSignature,
          departmentSignature: departmentSignature,
          // Mayor signing is performed on the printed form.
          mayorSignature: null,
        )
      : document;
  final bytes = customBytes ?? await doc.save();
  if (config['has_background'] != true && config['layout'] != 'custom') {
    return bytes;
  }
  final result = await ApiClient.instance.post<List<int>>(
    '/api/leave/print/requests/${request.id}/render',
    data: FormData.fromMap({
      'version_id': config['id'],
      'file': MultipartFile.fromBytes(bytes, filename: 'form.pdf'),
    }),
    options: Options(responseType: ResponseType.bytes),
  );
  return Uint8List.fromList(result.data!);
}

Future<pw.Document> buildWellnessLeavePdf({
  required LeaveRequest request,
  String department = '',
  String mayorName = '',
  String? departmentReviewer,
  Uint8List? applicantSignature,
  Uint8List? departmentSignature,
  Uint8List? mayorSignature,
  LeaveDesignCapture? designCapture,
}) async {
  final base = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
  String date(DateTime? d) => d == null
      ? ''
      : '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  pw.Widget text(String value, {bool strong = false, double size = 10}) =>
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );
  pw.Widget slot(String label, pw.Widget child) {
    final source = switch (label) {
      'Date:' => 'date',
      'Employee Name:' => 'employee_name',
      'Department:' => 'office',
      'Dates Requested: From:' => 'inclusive_dates',
      'Total No. of Days:' => 'working_days',
      _ => '',
    };
    return designCapture?.field(source, child, underline: true) ?? child;
  }

  pw.Widget field(String label, String value) => pw.Row(
    children: [
      text(label, strong: true),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: slot(
          label,
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide()),
            ),
            child: text(value),
          ),
        ),
      ),
    ],
  );
  pw.Widget signatureSlot(String label, pw.Widget child) {
    final source = label == 'Signature of Employee'
        ? 'applicant'
        : 'department_head';
    return designCapture?.signature(source, child, caption: label) ?? child;
  }

  pw.Widget signature(String label, String name, Uint8List? bytes) =>
      signatureSlot(
        label,
        pw.Column(
          children: [
            pw.SizedBox(
              height: 32,
              child: bytes == null
                  ? pw.SizedBox()
                  : pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
            ),
            text(name, strong: true),
            pw.Divider(height: 4),
            text(label, strong: true, size: 9),
          ],
        ),
      );
  pw.Widget reasonSlot(pw.Widget child) =>
      designCapture?.field('reason', child) ?? child;
  pw.Widget finalSlot(pw.Widget child) =>
      designCapture?.signature(
        'hr_approver',
        child,
        caption: 'Municipal Mayor',
      ) ??
      child;
  final reason = request.reason ?? '';
  final continued = reason.length > 500;
  final shown = continued
      ? '${reason.substring(0, 500)} … (continued on next page)'
      : reason;
  doc.addPage(
    pw.Page(
      pageFormat: designCapture?.renderingLayout == null
          ? PdfPageFormat.a4
          : PdfPageFormat(
              designCapture!.renderingLayout!.pageWidth,
              designCapture.renderingLayout!.pageHeight,
            ),
      margin: designCapture?.renderingLayout == null
          ? const pw.EdgeInsets.fromLTRB(52, 110, 52, 120)
          : pw.EdgeInsets.zero,
      build: (_) {
        final native = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: text(
                'WELLNESS LEAVE REQUEST FORM',
                strong: true,
                size: 14,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Center(
              child: text(
                'For Job Orders and Contract of Service Employees Only',
                size: 10,
              ),
            ),
            pw.SizedBox(height: 24),
            pw.SizedBox(
              width: 205,
              child: field('Date:', date(request.dateFiled)),
            ),
            pw.SizedBox(height: 25),
            pw.Row(
              children: [
                pw.Expanded(
                  child: field('Employee Name:', request.employeeName ?? ''),
                ),
                pw.SizedBox(width: 15),
                pw.Expanded(child: field('Department:', department)),
              ],
            ),
            pw.SizedBox(height: 25),
            text('Reason for requested leave:', strong: true),
            pw.SizedBox(height: 8),
            reasonSlot(
              pw.Container(
                height: 95,
                width: double.infinity,
                child: pw.Text(
                  shown,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            field(
              'Dates Requested: From:',
              '${date(request.startDate)}   to   ${date(request.endDate)}',
            ),
            pw.SizedBox(height: 12),
            pw.SizedBox(
              width: 230,
              child: field(
                'Total No. of Days:',
                request.workingDaysApplied?.toString() ?? '',
              ),
            ),
            pw.SizedBox(height: 15),
            pw.SizedBox(
              width: 230,
              child: signature('Signature of Employee', '', applicantSignature),
            ),
            pw.SizedBox(height: 22),
            text('RECOMMENDED BY:', strong: true),
            pw.SizedBox(
              width: 270,
              child: signature(
                'Name & Signature of Department Head',
                departmentReviewer ?? '',
                departmentSignature,
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 330,
                child: pw.Column(
                  children: [
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: text('APPROVED BY:', strong: true),
                    ),
                    finalSlot(
                      pw.Column(
                        children: [
                          pw.SizedBox(
                            height: 22,
                            child: mayorSignature == null
                                ? pw.SizedBox()
                                : pw.Image(
                                    pw.MemoryImage(mayorSignature),
                                    fit: pw.BoxFit.contain,
                                  ),
                          ),
                          text(mayorName, strong: true),
                          pw.Divider(height: 4),
                          text('Municipal Mayor', strong: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        return designCapture?.page(
              native,
              width: 595.28,
              height: 841.89,
              margin: 0,
              wellness: true,
            ) ??
            native;
      },
    ),
  );
  if (continued && designCapture == null) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(52, 110, 52, 120),
        build: (_) => [
          text('WELLNESS LEAVE — REASON CONTINUATION', strong: true, size: 12),
          pw.SizedBox(height: 12),
          text(request.employeeName ?? '', strong: true),
          pw.SizedBox(height: 12),
          text(reason),
        ],
      ),
    );
  }
  return doc;
}
