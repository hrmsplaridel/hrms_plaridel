import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/core/api/client.dart';
import '../models/leave_request.dart';

Future<Uint8List> saveConfiguredLeavePdf({
  required LeaveRequest request,
  required pw.Document document,
  String? departmentReviewer,
  Uint8List? applicantSignature,
  Uint8List? departmentSignature,
  Uint8List? finalSignature,
}) async {
  if (request.id == null) return document.save();
  final response = await ApiClient.instance.get<Map<String, dynamic>>(
    '/api/leave/print/requests/${request.id}',
  );
  final config = response.data!;
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
  final bytes = await doc.save();
  if (config['has_background'] != true) return bytes;
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
  pw.Widget field(String label, String value) => pw.Row(
    children: [
      text(label, strong: true),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide()),
          ),
          child: text(value),
        ),
      ),
    ],
  );
  pw.Widget signature(String label, String name, Uint8List? bytes) => pw.Column(
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
  );
  final reason = request.reason ?? '';
  final continued = reason.length > 500;
  final shown = continued
      ? '${reason.substring(0, 500)} … (continued on next page)'
      : reason;
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(52, 110, 52, 120),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: text('WELLNESS LEAVE REQUEST FORM', strong: true, size: 14),
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
          pw.Container(
            height: 95,
            width: double.infinity,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide()),
            ),
            child: text(shown, size: 9),
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
                  text('APPROVED BY:', strong: true),
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
          ),
        ],
      ),
    ),
  );
  if (continued) {
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
