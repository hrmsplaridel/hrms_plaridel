// ignore_for_file: unused_element

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';

/// Dedicated PDF builder for the CSC-style "Application for Leave" form.
///
/// This is intentionally separated from the Flutter UI so the printed/exported
/// output comes from a true PDF layout (not a screenshot of widgets).
class LeaveRequestPdf {
  LeaveRequestPdf._();

  static const PdfColor _borderColor = PdfColors.black;
  static const PdfColor _headerFill = PdfColors.grey300;
  static const PdfColor _textSecondary = PdfColors.grey700;

  static String _s(String? v) =>
      (v == null || v.trim().isEmpty) ? '—' : v.trim();

  static String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  static String _formatDateIso(DateTime value) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }

  static String _prettifyRole(String role) {
    final parts = role.trim().replaceAll('_', ' ').split(RegExp(r'\s+'));
    return parts
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  static ({String last, String first, String middle})
  _parseNameToLastFirstMiddle(String displayName) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (last: '', first: '', middle: '');
    if (parts.length == 1) return (last: '', first: parts[0], middle: '');
    if (parts.length == 2) return (last: parts[1], first: parts[0], middle: '');
    return (
      last: parts.sublist(2).join(' '),
      first: parts[0],
      middle: parts[1],
    );
  }

  static bool _isValidDateRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return false;
    return !end.isBefore(start);
  }

  static double? _computeWorkingDaysApplied(LeaveRequest request) {
    if (!_isValidDateRange(request.startDate, request.endDate)) return null;
    final start = request.startDate!;
    final end = request.endDate!;

    var current = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    var count = 0;

    while (!current.isAfter(endDay)) {
      if (current.weekday != DateTime.saturday &&
          current.weekday != DateTime.sunday) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count.toDouble();
  }

  static double? _workingDaysToDisplay(LeaveRequest request) =>
      request.workingDaysApplied ?? _computeWorkingDaysApplied(request);

  static String _formatWorkingDays(double? days) =>
      days == null ? '—' : '${days.toStringAsFixed(1)} day(s)';

  static String _formatSalary(LeaveRequest request) =>
      request.salary == null ? '—' : request.salary!.toStringAsFixed(2);

  static pw.Widget _checkbox(bool checked) {
    return pw.Container(
      width: 12,
      height: 12,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.7, color: _borderColor),
      ),
      child: checked
          ? pw.Center(
              child: pw.Text('X', style: const pw.TextStyle(fontSize: 9)),
            )
          : null,
    );
  }

  static pw.Widget _rowCheck(String label, {required bool checked}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _checkbox(checked),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 10.5, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _fieldLine(String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(value, style: const pw.TextStyle(fontSize: 10.5)),
        pw.Divider(height: 1.0, thickness: 0.6, color: _borderColor),
      ],
    );
  }

  static pw.Widget _panel({required String title, required pw.Widget child}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderColor, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: _headerFill,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: pw.Text(
              title,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }

  static pw.Widget _signatureLine({required String label}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 18),
        pw.Container(height: 1, color: _borderColor),
        pw.SizedBox(height: 8),
        pw.Text(
          '($label)',
          style: pw.TextStyle(
            fontSize: 10.5,
            color: _textSecondary,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    );
  }

  static Future<pw.Document> buildPdf({
    required LeaveRequest request,
    List<LeaveBalance>? balances,
  }) async {
    return _LeaveRequestPdfFixedEngine.buildPdf(
      request: request,
      balances: balances,
    );
  }

  /// Opens the platform print preview and allows direct printing or
  /// "Save as PDF" from the system dialog.
  static Future<void> printLeaveRequest({
    required LeaveRequest request,
    List<LeaveBalance>? balances,
    String? name,
  }) async {
    return _LeaveRequestPdfFixedEngine.printLeaveRequest(
      request: request,
      balances: balances,
      name: name,
    );
  }

  static Future<pw.Document> _legacyBuildPdf({
    required LeaveRequest request,
    List<LeaveBalance>? balances,
  }) async {
    final effectiveBalances = balances ?? const [];
    final computedWorkingDays = _workingDaysToDisplay(request);
    final dateFiled = request.dateFiled ?? DateTime.now();
    final reviewedAt = request.reviewedAt;
    final reviewedAtText = reviewedAt != null ? _formatDate(reviewedAt) : null;
    final reviewerName = request.reviewerName?.trim().isNotEmpty == true
        ? request.reviewerName!.trim()
        : null;
    final reviewerRoleLabel = request.reviewerRole?.trim().isNotEmpty == true
        ? _prettifyRole(request.reviewerRole!)
        : null;
    final reviewerTitleLabel = request.reviewerTitle?.trim().isNotEmpty == true
        ? request.reviewerTitle!.trim()
        : reviewerRoleLabel;

    final ({String last, String first, String middle}) nameParts =
        _parseNameToLastFirstMiddle(
          request.employeeName?.trim().isNotEmpty == true
              ? request.employeeName!.trim()
              : request.userId,
        );

    final vlBal = effectiveBalances.firstWhere(
      (b) => b.leaveType == LeaveType.vacationLeave,
      orElse: () =>
          const LeaveBalance(userId: '', leaveType: LeaveType.vacationLeave),
    );
    final slBal = effectiveBalances.firstWhere(
      (b) => b.leaveType == LeaveType.sickLeave,
      orElse: () =>
          const LeaveBalance(userId: '', leaveType: LeaveType.sickLeave),
    );

    final leaveType = request.leaveType;
    final deductionDays =
        (leaveType == LeaveType.vacationLeave ||
            leaveType == LeaveType.sickLeave)
        ? (computedWorkingDays ?? 0.0)
        : 0.0;
    final vlDeduction = leaveType == LeaveType.vacationLeave
        ? deductionDays
        : 0.0;
    final slDeduction = leaveType == LeaveType.sickLeave ? deductionDays : 0.0;

    String formatDays(double d) => d == 0 ? '—' : d.toStringAsFixed(3);

    final hasDateRange = _isValidDateRange(request.startDate, request.endDate);
    final startStr = request.startDate != null
        ? _formatDate(request.startDate!)
        : '—';
    final endStr = request.endDate != null
        ? _formatDate(request.endDate!)
        : '—';
    final disapprovalDueToText =
        request.disapprovalReason?.trim().isNotEmpty == true
        ? request.disapprovalReason!.trim()
        : (request.hrRemarks?.trim().isNotEmpty == true
              ? request.hrRemarks!.trim()
              : '____________________________________________________________');

    final leaveTypeText = switch (request.leaveType) {
      LeaveType.others => _s(request.customLeaveTypeText),
      _ => request.leaveType.displayName,
    };

    final pageFormat = PdfPageFormat(612, 1008, marginAll: 18); // Legal-like.
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor, width: 1),
            ),
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.SizedBox(height: 8),
                pw.Text(
                  'APPLICATION FOR LEAVE',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                pw.SizedBox(height: 10),

                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.05),
                    1: pw.FlexColumnWidth(1.25),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '1. OFFICE/DEPARTMENT - DISTRICT/SCHOOL',
                                style: pw.TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              _fieldLine(_s(request.officeDepartment)),
                            ],
                          ),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              '2. NAME (Last) (First) (Middle)',
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Row(
                              children: [
                                pw.Expanded(
                                  child: _fieldLine(
                                    nameParts.last.isEmpty
                                        ? '—'
                                        : nameParts.last,
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(
                                  child: _fieldLine(
                                    nameParts.first.isEmpty
                                        ? '—'
                                        : nameParts.first,
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(
                                  child: _fieldLine(
                                    nameParts.middle.isEmpty
                                        ? '—'
                                        : nameParts.middle,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 8),
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.0),
                    1: pw.FlexColumnWidth(1.0),
                    2: pw.FlexColumnWidth(0.75),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '3. DATE OF FILING',
                                style: pw.TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              _fieldLine(_formatDate(dateFiled)),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                '4. POSITION',
                                style: pw.TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              _fieldLine(_s(request.positionTitle)),
                            ],
                          ),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              '5. SALARY P',
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            _fieldLine(_formatSalary(request)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Text(
                    '6. DETAILS OF APPLICATION',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),

                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _panel(
                        title: '6.A TYPE OF LEAVE TO BE AVAILED OF',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            ...LeaveType.values
                                .where((t) => t != LeaveType.others)
                                .map(
                                  (type) => _rowCheck(
                                    type.displayName,
                                    checked: request.leaveType == type,
                                  ),
                                ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              'Others:',
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            _rowCheck(
                              'Select "Others" and specify below',
                              checked: request.leaveType == LeaveType.others,
                            ),
                            pw.SizedBox(height: 6),
                            _fieldLine(
                              request.leaveType == LeaveType.others
                                  ? leaveTypeText
                                  : '—',
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: _panel(
                        title: '6.B DETAILS OF LEAVE',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'In case of Vacation/Special Privilege Leave:',
                              style: pw.TextStyle(
                                fontSize: 10.2,
                                fontWeight: pw.FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            _rowCheck(
                              'Within the Philippines',
                              checked:
                                  request.locationOption ==
                                  LeaveLocationOption.withinPhilippines,
                            ),
                            _rowCheck(
                              'Abroad (Specify)',
                              checked:
                                  request.locationOption ==
                                  LeaveLocationOption.abroad,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Location details',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                            pw.SizedBox(height: 4),
                            _fieldLine(_s(request.locationDetails)),
                            pw.SizedBox(height: 8),

                            pw.Text(
                              'In case of Sick Leave:',
                              style: pw.TextStyle(
                                fontSize: 10.2,
                                fontWeight: pw.FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            _rowCheck(
                              'In Hospital (Specify Illness)',
                              checked:
                                  request.sickLeaveNature ==
                                  SickLeaveNature.inHospital,
                            ),
                            _rowCheck(
                              'Out Patient (Specify Illness)',
                              checked:
                                  request.sickLeaveNature ==
                                  SickLeaveNature.outPatient,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Specify illness',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                            pw.SizedBox(height: 4),
                            _fieldLine(_s(request.sickIllnessDetails)),
                            pw.SizedBox(height: 8),

                            pw.Text(
                              'In case of Special Leave Benefits for Women:',
                              style: pw.TextStyle(
                                fontSize: 10.2,
                                fontWeight: pw.FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            _fieldLine(_s(request.womenIllnessDetails)),
                            pw.SizedBox(height: 8),

                            pw.Text(
                              'In case of Study Leave:',
                              style: pw.TextStyle(
                                fontSize: 10.2,
                                fontWeight: pw.FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            _rowCheck(
                              'Completion of Master\'s Degree',
                              checked:
                                  request.studyPurpose ==
                                  StudyLeavePurpose.completionOfMastersDegree,
                            ),
                            _rowCheck(
                              'BAR/Board Examination Review',
                              checked:
                                  request.studyPurpose ==
                                  StudyLeavePurpose.barBoardExaminationReview,
                            ),
                            pw.SizedBox(height: 4),
                            pw.SizedBox(height: 8),

                            pw.Text(
                              'Other purpose:',
                              style: pw.TextStyle(
                                fontSize: 10.2,
                                fontWeight: pw.FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            _rowCheck(
                              'Monetization of Leave Credits (HR process)',
                              checked:
                                  request.otherPurpose ==
                                  LeaveOtherPurpose.monetizationOfLeaveCredits,
                            ),
                            _rowCheck(
                              'Terminal Leave (HR process)',
                              checked:
                                  request.otherPurpose ==
                                  LeaveOtherPurpose.terminalLeave,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Additional details / reason',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                            pw.SizedBox(height: 4),
                            _fieldLine(_s(request.otherPurposeDetails)),
                            pw.SizedBox(height: 8),
                            pw.Text(
                              'General reason/details:',
                              style: pw.TextStyle(
                                fontSize: 10.2,
                                fontWeight: pw.FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            _fieldLine(_s(request.reason)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _panel(
                        title: '6.C NUMBER OF WORKING DAYS APPLIED FOR',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Working Days',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            _fieldLine(_formatWorkingDays(computedWorkingDays)),
                            pw.SizedBox(height: 8),
                            pw.Text(
                              'INCLUSIVE DATES',
                              style: pw.TextStyle(
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        'Start Date',
                                        style: const pw.TextStyle(fontSize: 10),
                                      ),
                                      pw.SizedBox(height: 4),
                                      _fieldLine(hasDateRange ? startStr : '—'),
                                    ],
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        'End Date',
                                        style: const pw.TextStyle(fontSize: 10),
                                      ),
                                      pw.SizedBox(height: 4),
                                      _fieldLine(hasDateRange ? endStr : '—'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: _panel(
                        title: '6.D COMMUTATION',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _rowCheck(
                              'Not Requested',
                              checked:
                                  request.commutation ==
                                  LeaveCommutationOption.notRequested,
                            ),
                            _rowCheck(
                              'Requested',
                              checked:
                                  request.commutation ==
                                  LeaveCommutationOption.requested,
                            ),
                            _signatureLine(label: 'Signature of Applicant'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Text(
                    '7. DETAILS OF ACTION ON APPLICATION',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),

                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: _panel(
                        title: '7.A CERTIFICATION OF LEAVE CREDITS',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'As of ${_formatDateIso(dateFiled)}',
                              style: const pw.TextStyle(fontSize: 10.2),
                            ),
                            pw.SizedBox(height: 10),
                            pw.Table(
                              border: pw.TableBorder.all(
                                color: _borderColor,
                                width: 0.7,
                              ),
                              columnWidths: const {
                                0: pw.FlexColumnWidth(1.0),
                                1: pw.FlexColumnWidth(1.0),
                                2: pw.FlexColumnWidth(1.0),
                              },
                              children: [
                                pw.TableRow(
                                  decoration: pw.BoxDecoration(
                                    color: _headerFill,
                                  ),
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        '',
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        'Vacation Leave',
                                        style: pw.TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: pw.FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        'Sick Leave',
                                        style: pw.TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: pw.FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        'Total Earned',
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        formatDays(
                                          vlBal.earnedDays + vlBal.adjustedDays,
                                        ),
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        formatDays(
                                          slBal.earnedDays + slBal.adjustedDays,
                                        ),
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                  ],
                                ),
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        'Less this application',
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        formatDays(vlDeduction),
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        formatDays(slDeduction),
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                  ],
                                ),
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        'Balance',
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        formatDays(
                                          vlBal.remainingDays - vlDeduction,
                                        ),
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(
                                        formatDays(
                                          slBal.remainingDays - slDeduction,
                                        ),
                                        style: const pw.TextStyle(fontSize: 9),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 26),
                            pw.Divider(
                              height: 1,
                              thickness: 0.7,
                              color: _borderColor,
                            ),
                            pw.SizedBox(height: 10),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  '(Authorized HR Officer)',
                                  style: pw.TextStyle(
                                    fontSize: 10.2,
                                    color: _textSecondary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                ),
                                if (reviewerTitleLabel != null)
                                  pw.SizedBox(height: 2),
                                if (reviewerTitleLabel != null)
                                  pw.Text(
                                    reviewerTitleLabel,
                                    style: const pw.TextStyle(fontSize: 9.8),
                                  ),
                                if (reviewerName != null)
                                  pw.SizedBox(height: 2),
                                if (reviewerName != null)
                                  pw.Text(
                                    reviewerName,
                                    style: pw.TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                if (reviewedAtText != null)
                                  pw.SizedBox(height: 2),
                                if (reviewedAtText != null)
                                  pw.Text(
                                    'Reviewed: $reviewedAtText',
                                    style: const pw.TextStyle(fontSize: 9.5),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: _panel(
                        title: '7.B RECOMMENDATION',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _rowCheck(
                              'For approval',
                              checked:
                                  request.status == LeaveRequestStatus.approved,
                            ),
                            pw.SizedBox(height: 6),
                            _rowCheck(
                              'For disapproval due to',
                              checked:
                                  request.status == LeaveRequestStatus.rejected,
                            ),
                            pw.SizedBox(height: 10),
                            pw.Text(
                              request.recommendationRemarks
                                          ?.trim()
                                          .isNotEmpty ==
                                      true
                                  ? request.recommendationRemarks!.trim()
                                  : '____________________________________________________________',
                              style: const pw.TextStyle(
                                fontSize: 10.2,
                                height: 1.4,
                              ),
                            ),
                            if (request.hrRemarks?.trim().isNotEmpty ==
                                true) ...[
                              pw.SizedBox(height: 8),
                              pw.Text(
                                'HR remarks:',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                request.hrRemarks!.trim(),
                                style: const pw.TextStyle(
                                  fontSize: 10.2,
                                  height: 1.35,
                                ),
                              ),
                            ],
                            pw.SizedBox(height: 20),
                            pw.Divider(
                              height: 1,
                              thickness: 0.7,
                              color: _borderColor,
                            ),
                            pw.SizedBox(height: 8),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  '(Authorized Officer)',
                                  style: pw.TextStyle(
                                    fontSize: 10.2,
                                    color: _textSecondary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                ),
                                if (reviewerTitleLabel != null)
                                  pw.SizedBox(height: 2),
                                if (reviewerTitleLabel != null)
                                  pw.Text(
                                    reviewerTitleLabel,
                                    style: const pw.TextStyle(fontSize: 9.8),
                                  ),
                                if (reviewerName != null)
                                  pw.SizedBox(height: 2),
                                if (reviewerName != null)
                                  pw.Text(
                                    reviewerName,
                                    style: pw.TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                if (reviewedAtText != null)
                                  pw.SizedBox(height: 2),
                                if (reviewedAtText != null)
                                  pw.Text(
                                    'Reviewed: $reviewedAtText',
                                    style: const pw.TextStyle(fontSize: 9.5),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor, width: 1),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Expanded(
                            child: pw.Container(
                              decoration: pw.BoxDecoration(
                                border: pw.Border(
                                  right: pw.BorderSide(
                                    width: 1,
                                    color: _borderColor,
                                  ),
                                ),
                              ),
                              child: pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.stretch,
                                children: [
                                  pw.Container(
                                    color: _headerFill,
                                    padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: pw.Text(
                                      '7.C APPROVED FOR',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(10),
                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Text(
                                          request.approvedDaysWithPay != null
                                              ? '${request.approvedDaysWithPay!.toStringAsFixed(1)} days with pay'
                                              : '_______ days with pay',
                                          style: const pw.TextStyle(
                                            fontSize: 10.2,
                                          ),
                                        ),
                                        pw.SizedBox(height: 8),
                                        pw.Text(
                                          request.approvedDaysWithoutPay != null
                                              ? '${request.approvedDaysWithoutPay!.toStringAsFixed(1)} days without pay'
                                              : '_______ days without pay',
                                          style: const pw.TextStyle(
                                            fontSize: 10.2,
                                          ),
                                        ),
                                        pw.SizedBox(height: 8),
                                        pw.Text(
                                          request.approvedOtherDetails
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? request.approvedOtherDetails!
                                                    .trim()
                                              : '_______ others (Specify)',
                                          style: const pw.TextStyle(
                                            fontSize: 10.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Container(
                              child: pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.stretch,
                                children: [
                                  pw.Container(
                                    color: _headerFill,
                                    padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: pw.Text(
                                      '7.D DISAPPROVED DUE TO',
                                      style: pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(10),
                                    child: pw.Text(
                                      disapprovalDueToText,
                                      style: const pw.TextStyle(
                                        fontSize: 10.2,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(12),
                        child: pw.Column(
                          children: [
                            pw.Divider(
                              height: 1,
                              thickness: 0.7,
                              color: _borderColor,
                            ),
                            pw.SizedBox(height: 8),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  '(Approving Authority)',
                                  style: pw.TextStyle(
                                    fontSize: 10.2,
                                    color: _textSecondary,
                                    fontStyle: pw.FontStyle.italic,
                                  ),
                                ),
                                if (reviewerTitleLabel != null)
                                  pw.SizedBox(height: 2),
                                if (reviewerTitleLabel != null)
                                  pw.Text(
                                    reviewerTitleLabel,
                                    style: const pw.TextStyle(fontSize: 9.8),
                                  ),
                                if (reviewerName != null)
                                  pw.SizedBox(height: 2),
                                if (reviewerName != null)
                                  pw.Text(
                                    reviewerName,
                                    style: pw.TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                if (reviewedAtText != null)
                                  pw.SizedBox(height: 2),
                                if (reviewedAtText != null)
                                  pw.Text(
                                    'Reviewed: $reviewedAtText',
                                    style: const pw.TextStyle(fontSize: 9.5),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      request.leaveType.requiresAttachment
                          ? 'This leave type typically requires supporting documents.'
                          : 'Supporting attachment: optional. PDF, JPG, PNG (max 10MB).',
                      style: pw.TextStyle(fontSize: 9.2, color: _textSecondary),
                    ),
                    if (request.attachmentName?.trim().isNotEmpty == true) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Attachment: ${request.attachmentName!.trim()}',
                        style: pw.TextStyle(
                          fontSize: 9.2,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc;
  }
}

class _LeaveRequestPdfFixedEngine {
  _LeaveRequestPdfFixedEngine._();

  static const _borderColor = PdfColors.black;
  static const _fontSize = 10.0;
  static const _small = 9.0;

  static String _s(String? v) =>
      (v == null || v.trim().isEmpty) ? '' : v.trim();

  static String _fmtDate(DateTime? d) {
    if (d == null) return '';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _fmtDateIso(DateTime? d) {
    if (d == null) return '';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static ({String last, String first, String middle}) _nameParts(String full) {
    final parts = full
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (last: '', first: '', middle: '');
    if (parts.length == 1) return (last: '', first: parts[0], middle: '');
    if (parts.length == 2) return (last: parts[1], first: parts[0], middle: '');
    return (
      last: parts.sublist(2).join(' '),
      first: parts[0],
      middle: parts[1],
    );
  }

  static double? _workDays(LeaveRequest r) {
    if (r.workingDaysApplied != null) return r.workingDaysApplied;
    final s = r.startDate;
    final e = r.endDate;
    if (s == null || e == null || e.isBefore(s)) return null;
    var c = DateTime(s.year, s.month, s.day);
    final end = DateTime(e.year, e.month, e.day);
    var count = 0;
    while (!c.isAfter(end)) {
      if (c.weekday != DateTime.saturday && c.weekday != DateTime.sunday)
        count++;
      c = c.add(const Duration(days: 1));
    }
    return count.toDouble();
  }

  static pw.Widget _box(bool checked) => pw.Container(
    width: 10,
    height: 10,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _borderColor, width: 0.8),
    ),
    alignment: pw.Alignment.center,
    child: checked
        ? pw.Text('X', style: const pw.TextStyle(fontSize: 8))
        : null,
  );

  static pw.Widget _checkLine(String label, bool checked) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _box(checked),
        pw.SizedBox(width: 5),
        pw.Expanded(
          child: pw.Text(label, style: const pw.TextStyle(fontSize: _fontSize)),
        ),
      ],
    ),
  );

  static pw.Widget _underlineValue(String value, {double h = 14}) =>
      pw.Container(
        height: h,
        alignment: pw.Alignment.bottomLeft,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _borderColor, width: 0.8),
          ),
        ),
        child: pw.Text(
          value.isEmpty ? ' ' : value,
          style: const pw.TextStyle(fontSize: _fontSize),
        ),
      );

  static pw.Widget _sectionHeader(String t) => pw.Container(
    // padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
    child: pw.Text(
      t,
      style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _cellLabel(String t) => pw.Text(
    t,
    style: pw.TextStyle(fontSize: _small, fontWeight: pw.FontWeight.bold),
  );

  static Future<pw.Document> buildPdf({
    required LeaveRequest request,
    List<LeaveBalance>? balances,
  }) async {
    final b = balances ?? const <LeaveBalance>[];
    final vl = b
        .where((e) => e.leaveType == LeaveType.vacationLeave)
        .cast<LeaveBalance?>()
        .firstWhere((e) => e != null, orElse: () => null);
    final sl = b
        .where((e) => e.leaveType == LeaveType.sickLeave)
        .cast<LeaveBalance?>()
        .firstWhere((e) => e != null, orElse: () => null);
    final wd = _workDays(request);
    final daysText = wd == null ? '' : '${wd.toStringAsFixed(1)} day/s';
    final fullName = _s(request.employeeName).isNotEmpty
        ? _s(request.employeeName)
        : request.userId;
    final n = _nameParts(fullName);
    final reviewerName = _s(request.reviewerName);
    final reviewerTitle = _s(request.reviewerTitle).isNotEmpty
        ? _s(request.reviewerTitle)
        : _s(request.reviewerRole);

    final vlDed = request.leaveType == LeaveType.vacationLeave
        ? (wd ?? 0.0)
        : 0.0;
    final slDed = request.leaveType == LeaveType.sickLeave ? (wd ?? 0.0) : 0.0;
    String d3(double v) => v == 0 ? '' : v.toStringAsFixed(3);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(612, 1008, marginAll: 16), // Legal size
        build: (_) {
          return pw.DefaultTextStyle(
            style: const pw.TextStyle(fontSize: _fontSize),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    'APPLICATION FOR LEAVE',
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 5),
                // Step 1: top header grid as one fixed table-like block.
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor, width: 0.8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Table(
                        border: const pw.TableBorder(
                          verticalInside: pw.BorderSide(
                            color: _borderColor,
                            width: 0.8,
                          ),
                        ),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.28),
                          1: pw.FlexColumnWidth(1.72),
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.fromLTRB(
                                  4,
                                  3,
                                  4,
                                  2,
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '1. OFFICE/DEPARTMENT - DISTRICT/SCHOOL',
                                      style: pw.TextStyle(
                                        fontSize: 8.3,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _underlineValue(
                                      _s(request.officeDepartment),
                                      h: 12,
                                    ),
                                  ],
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.fromLTRB(
                                  4,
                                  3,
                                  4,
                                  2,
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '2. NAME (Last) (First) (Middle)',
                                      style: pw.TextStyle(
                                        fontSize: 8.3,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    pw.Row(
                                      children: [
                                        pw.Expanded(
                                          child: _underlineValue(n.last, h: 12),
                                        ),
                                        pw.SizedBox(width: 4),
                                        pw.Expanded(
                                          child: _underlineValue(
                                            n.first,
                                            h: 12,
                                          ),
                                        ),
                                        pw.SizedBox(width: 4),
                                        pw.Expanded(
                                          child: _underlineValue(
                                            n.middle,
                                            h: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.Container(height: 0.8, color: _borderColor),
                      pw.Table(
                        border: const pw.TableBorder(
                          verticalInside: pw.BorderSide(
                            color: _borderColor,
                            width: 0.8,
                          ),
                        ),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1.0),
                          1: pw.FlexColumnWidth(1.0),
                          2: pw.FlexColumnWidth(0.72),
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.fromLTRB(
                                  4,
                                  3,
                                  4,
                                  2,
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '3. DATE OF FILING',
                                      style: pw.TextStyle(
                                        fontSize: 8.3,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _underlineValue(
                                      _fmtDate(request.dateFiled),
                                      h: 12,
                                    ),
                                  ],
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.fromLTRB(
                                  4,
                                  3,
                                  4,
                                  2,
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '4. POSITION',
                                      style: pw.TextStyle(
                                        fontSize: 8.3,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _underlineValue(
                                      _s(request.positionTitle),
                                      h: 12,
                                    ),
                                  ],
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.fromLTRB(
                                  4,
                                  3,
                                  4,
                                  2,
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '5. SALARY   P',
                                      style: pw.TextStyle(
                                        fontSize: 8.3,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _underlineValue(
                                      request.salary != null
                                          ? request.salary!.toStringAsFixed(2)
                                          : '',
                                      h: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor, width: 0.8),
                  ),
                  child: pw.Column(
                    children: [
                      _sectionHeader('6. DETAILS OF APPLICATION'),
                      pw.Table(
                        border: const pw.TableBorder(
                          top: pw.BorderSide(color: _borderColor, width: 0.8),
                          verticalInside: pw.BorderSide(
                            color: _borderColor,
                            width: 0.8,
                          ),
                        ),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1),
                          1: pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(
                                      '6.A TYPE OF LEAVE TO BE AVAILED OF',
                                    ),
                                    _checkLine(
                                      'Vacation Leave',
                                      request.leaveType ==
                                          LeaveType.vacationLeave,
                                    ),
                                    _checkLine(
                                      'Mandatory/Forced Leave',
                                      request.leaveType ==
                                          LeaveType.mandatoryForcedLeave,
                                    ),
                                    _checkLine(
                                      'Sick Leave',
                                      request.leaveType == LeaveType.sickLeave,
                                    ),
                                    _checkLine(
                                      'Maternity Leave',
                                      request.leaveType ==
                                          LeaveType.maternityLeave,
                                    ),
                                    _checkLine(
                                      'Paternity Leave',
                                      request.leaveType ==
                                          LeaveType.paternityLeave,
                                    ),
                                    _checkLine(
                                      'Special Privilege Leave',
                                      request.leaveType ==
                                          LeaveType.specialPrivilegeLeave,
                                    ),
                                    _checkLine(
                                      'Solo Parent Leave',
                                      request.leaveType ==
                                          LeaveType.soloParentLeave,
                                    ),
                                    _checkLine(
                                      'Study Leave',
                                      request.leaveType == LeaveType.studyLeave,
                                    ),
                                    _checkLine(
                                      '10-Day VAWC Leave',
                                      request.leaveType ==
                                          LeaveType.tenDayVawcLeave,
                                    ),
                                    _checkLine(
                                      'Rehabilitation Privilege',
                                      request.leaveType ==
                                          LeaveType.rehabilitationPrivilege,
                                    ),
                                    _checkLine(
                                      'Special Leave Benefits for Women',
                                      request.leaveType ==
                                          LeaveType
                                              .specialLeaveBenefitsForWomen,
                                    ),
                                    _checkLine(
                                      'Special Emergency (Calamity) Leave',
                                      request.leaveType ==
                                          LeaveType
                                              .specialEmergencyCalamityLeave,
                                    ),
                                    _checkLine(
                                      'Adoption Leave',
                                      request.leaveType ==
                                          LeaveType.adoptionLeave,
                                    ),
                                    pw.SizedBox(height: 4),
                                    pw.Text(
                                      'Others:',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _checkLine(
                                      'Select "Others" and specify below',
                                      request.leaveType == LeaveType.others,
                                    ),
                                    _underlineValue(
                                      request.leaveType == LeaveType.others
                                          ? _s(request.customLeaveTypeText)
                                          : '',
                                    ),
                                  ],
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader('6.B DETAILS OF LEAVE'),
                                    pw.Text(
                                      'In case of Vacation/Special Privilege Leave:',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                        fontStyle: pw.FontStyle.italic,
                                      ),
                                    ),
                                    _checkLine(
                                      'Within the Philippines',
                                      request.locationOption ==
                                          LeaveLocationOption.withinPhilippines,
                                    ),
                                    _checkLine(
                                      'Abroad (Specify)',
                                      request.locationOption ==
                                          LeaveLocationOption.abroad,
                                    ),
                                    _underlineValue(
                                      _s(request.locationDetails),
                                    ),
                                    pw.SizedBox(height: 3),
                                    pw.Text(
                                      'In case of Sick Leave:',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                        fontStyle: pw.FontStyle.italic,
                                      ),
                                    ),
                                    _checkLine(
                                      'In Hospital (Specify Illness)',
                                      request.sickLeaveNature ==
                                          SickLeaveNature.inHospital,
                                    ),
                                    _checkLine(
                                      'Out Patient (Specify Illness)',
                                      request.sickLeaveNature ==
                                          SickLeaveNature.outPatient,
                                    ),
                                    _underlineValue(
                                      _s(request.sickIllnessDetails),
                                    ),
                                    pw.SizedBox(height: 3),
                                    pw.Text(
                                      'In case of Special Leave Benefits for Women:',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                        fontStyle: pw.FontStyle.italic,
                                      ),
                                    ),
                                    _underlineValue(
                                      _s(request.womenIllnessDetails),
                                    ),
                                    pw.SizedBox(height: 3),
                                    pw.Text(
                                      'In case of Study Leave:',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                        fontStyle: pw.FontStyle.italic,
                                      ),
                                    ),
                                    _checkLine(
                                      "Completion of Master's Degree",
                                      request.studyPurpose ==
                                          StudyLeavePurpose
                                              .completionOfMastersDegree,
                                    ),
                                    _checkLine(
                                      'BAR/Board Examination Review',
                                      request.studyPurpose ==
                                          StudyLeavePurpose
                                              .barBoardExaminationReview,
                                    ),
                                    pw.SizedBox(height: 3),
                                    pw.Text(
                                      'Other purpose:',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _checkLine(
                                      'Monetization of Leave Credits',
                                      request.otherPurpose ==
                                          LeaveOtherPurpose
                                              .monetizationOfLeaveCredits,
                                    ),
                                    _checkLine(
                                      'Terminal Leave',
                                      request.otherPurpose ==
                                          LeaveOtherPurpose.terminalLeave,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.Table(
                        border: const pw.TableBorder(
                          top: pw.BorderSide(color: _borderColor, width: 0.8),
                          verticalInside: pw.BorderSide(
                            color: _borderColor,
                            width: 0.8,
                          ),
                        ),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1),
                          1: pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(
                                      '6.C NUMBER OF WORKING DAYS APPLIED FOR',
                                    ),
                                    pw.Text(
                                      'Working Days',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    _underlineValue(daysText),
                                    pw.SizedBox(height: 3),
                                    pw.Text(
                                      'INCLUSIVE DATES',
                                      style: pw.TextStyle(
                                        fontSize: _small,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    pw.Row(
                                      children: [
                                        pw.Expanded(
                                          child: pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              pw.Text(
                                                'Start Date',
                                                style: const pw.TextStyle(
                                                  fontSize: _small,
                                                ),
                                              ),
                                              _underlineValue(
                                                _fmtDate(request.startDate),
                                              ),
                                            ],
                                          ),
                                        ),
                                        pw.SizedBox(width: 6),
                                        pw.Expanded(
                                          child: pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              pw.Text(
                                                'End Date',
                                                style: const pw.TextStyle(
                                                  fontSize: _small,
                                                ),
                                              ),
                                              _underlineValue(
                                                _fmtDate(request.endDate),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader('6.D COMMUTATION'),
                                    _checkLine(
                                      'Not Requested',
                                      request.commutation ==
                                          LeaveCommutationOption.notRequested,
                                    ),
                                    _checkLine(
                                      'Requested',
                                      request.commutation ==
                                          LeaveCommutationOption.requested,
                                    ),
                                    pw.SizedBox(height: 12),
                                    pw.Container(
                                      height: 1,
                                      color: _borderColor,
                                    ),
                                    pw.SizedBox(height: 4),
                                    pw.Center(
                                      child: pw.Text(
                                        '(Signature of Applicant)',
                                        style: pw.TextStyle(
                                          fontSize: _small,
                                          fontStyle: pw.FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _borderColor, width: 0.8),
                  ),
                  child: pw.Column(
                    children: [
                      _sectionHeader('7. DETAILS OF ACTION ON APPLICATION'),
                      pw.Table(
                        border: const pw.TableBorder(
                          top: pw.BorderSide(color: _borderColor, width: 0.8),
                          verticalInside: pw.BorderSide(
                            color: _borderColor,
                            width: 0.8,
                          ),
                        ),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(1),
                          1: pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(
                                      '7.A CERTIFICATION OF LEAVE CREDITS',
                                    ),
                                    pw.Row(
                                      children: [
                                        pw.Text(
                                          'As c',
                                          style: const pw.TextStyle(
                                            fontSize: _small,
                                          ),
                                        ),
                                        pw.SizedBox(width: 6),
                                        pw.Expanded(
                                          child: pw.Container(
                                            height: 10,
                                            decoration: const pw.BoxDecoration(
                                              border: pw.Border(
                                                bottom: pw.BorderSide(
                                                  color: _borderColor,
                                                  width: 0.8,
                                                ),
                                              ),
                                            ),
                                            alignment: pw.Alignment.bottomLeft,
                                            child: pw.Text(
                                              _fmtDateIso(request.dateFiled),
                                              style: const pw.TextStyle(
                                                fontSize: _small,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    pw.SizedBox(height: 4),
                                    pw.Center(
                                      child: pw.Container(
                                        width: 250,
                                        child: pw.Table(
                                          border: pw.TableBorder.all(
                                            color: _borderColor,
                                            width: 0.8,
                                          ),
                                          columnWidths: const {
                                            0: pw.FlexColumnWidth(1.3),
                                            1: pw.FlexColumnWidth(1),
                                            2: pw.FlexColumnWidth(1),
                                          },
                                          children: [
                                            pw.TableRow(
                                              children: [
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    '',
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    'Vacation Leave',
                                                    style: pw.TextStyle(
                                                      fontSize: _small,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    'Sick Leave',
                                                    style: pw.TextStyle(
                                                      fontSize: _small,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            pw.TableRow(
                                              children: [
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    'Total Earned',
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    d3(
                                                      (vl?.earnedDays ?? 0) +
                                                          (vl?.adjustedDays ??
                                                              0),
                                                    ),
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    d3(
                                                      (sl?.earnedDays ?? 0) +
                                                          (sl?.adjustedDays ??
                                                              0),
                                                    ),
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            pw.TableRow(
                                              children: [
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    'Less this application',
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    d3(vlDed),
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    d3(slDed),
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            pw.TableRow(
                                              children: [
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    'Balance',
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    d3(
                                                      (vl?.remainingDays ?? 0) -
                                                          vlDed,
                                                    ),
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.all(
                                                        3,
                                                      ),
                                                  child: pw.Text(
                                                    d3(
                                                      (sl?.remainingDays ?? 0) -
                                                          slDed,
                                                    ),
                                                    style: const pw.TextStyle(
                                                      fontSize: _small,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(height: 14),
                                    pw.Container(
                                      height: 1,
                                      color: _borderColor,
                                    ),
                                    pw.SizedBox(height: 4),
                                    if (reviewerName.isNotEmpty)
                                      pw.Center(
                                        child: pw.Text(
                                          reviewerName,
                                          style: pw.TextStyle(
                                            fontSize: _small,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    if (reviewerTitle.isNotEmpty)
                                      pw.Center(
                                        child: pw.Text(
                                          reviewerTitle,
                                          style: const pw.TextStyle(
                                            fontSize: _small,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader('7.B RECOMMENDATION'),
                                    _checkLine(
                                      'For approval',
                                      request.status ==
                                          LeaveRequestStatus.approved,
                                    ),
                                    _checkLine(
                                      'For disapproval due to',
                                      request.status ==
                                          LeaveRequestStatus.rejected,
                                    ),
                                    pw.SizedBox(height: 2),
                                    pw.Container(
                                      height: 10,
                                      decoration: const pw.BoxDecoration(
                                        border: pw.Border(
                                          bottom: pw.BorderSide(
                                            color: _borderColor,
                                            width: 0.8,
                                          ),
                                        ),
                                      ),
                                      alignment: pw.Alignment.bottomLeft,
                                      child: pw.Text(
                                        _s(request.recommendationRemarks),
                                        style: const pw.TextStyle(
                                          fontSize: _small,
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(height: 8),
                                    pw.Container(
                                      height: 10,
                                      decoration: const pw.BoxDecoration(
                                        border: pw.Border(
                                          bottom: pw.BorderSide(
                                            color: _borderColor,
                                            width: 0.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(height: 8),
                                    pw.Container(
                                      height: 10,
                                      decoration: const pw.BoxDecoration(
                                        border: pw.Border(
                                          bottom: pw.BorderSide(
                                            color: _borderColor,
                                            width: 0.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(height: 19),
                                    pw.Container(
                                      height: 1,
                                      color: _borderColor,
                                    ),
                                    pw.SizedBox(height: 4),
                                    pw.Center(
                                      child: pw.Text(
                                        '(Authorized Officer)',
                                        style: pw.TextStyle(
                                          fontSize: _small,
                                          fontStyle: pw.FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: _borderColor,
                            width: 0.8,
                          ),
                        ),
                        child: pw.Table(
                          border: const pw.TableBorder(),
                          columnWidths: const {
                            0: pw.FlexColumnWidth(1),
                            1: pw.FlexColumnWidth(1),
                          },
                          children: [
                            pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      _sectionHeader('7.C APPROVED FOR'),
                                      pw.SizedBox(height: 2),
                                      pw.Text(
                                        request.approvedDaysWithPay != null
                                            ? '_____ ${request.approvedDaysWithPay!.toStringAsFixed(1)} days with pay'
                                            : '_____ days with pay',
                                        style: const pw.TextStyle(
                                          fontSize: _small,
                                        ),
                                      ),
                                      pw.SizedBox(height: 2),
                                      pw.Text(
                                        request.approvedDaysWithoutPay != null
                                            ? '_____ ${request.approvedDaysWithoutPay!.toStringAsFixed(1)} days without pay'
                                            : '_____ days without pay',
                                        style: const pw.TextStyle(
                                          fontSize: _small,
                                        ),
                                      ),
                                      pw.SizedBox(height: 2),
                                      pw.Text(
                                        _s(
                                              request.approvedOtherDetails,
                                            ).isNotEmpty
                                            ? '_____ ${_s(request.approvedOtherDetails)}'
                                            : '_____ others (Specify)',
                                        style: const pw.TextStyle(
                                          fontSize: _small,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      _sectionHeader('7.D DISAPPROVED DUE TO'),
                                      pw.SizedBox(height: 2),
                                      pw.Container(
                                        height: 10,
                                        decoration: const pw.BoxDecoration(
                                          border: pw.Border(
                                            bottom: pw.BorderSide(
                                              color: _borderColor,
                                              width: 0.8,
                                            ),
                                          ),
                                        ),
                                        alignment: pw.Alignment.bottomLeft,
                                        child: pw.Text(
                                          _s(request.disapprovalReason),
                                          style: const pw.TextStyle(
                                            fontSize: _small,
                                          ),
                                        ),
                                      ),
                                      pw.SizedBox(height: 6),
                                      pw.Container(
                                        height: 10,
                                        decoration: const pw.BoxDecoration(
                                          border: pw.Border(
                                            bottom: pw.BorderSide(
                                              color: _borderColor,
                                              width: 0.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      pw.SizedBox(height: 6),
                                      pw.Container(
                                        height: 10,
                                        decoration: const pw.BoxDecoration(
                                          border: pw.Border(
                                            bottom: pw.BorderSide(
                                              color: _borderColor,
                                              width: 0.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: pw.Column(
                          children: [
                            pw.Container(
                              height: 1,
                              color: _borderColor,
                              margin: const pw.EdgeInsets.symmetric(
                                horizontal: 180,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            if (reviewerName.isNotEmpty)
                              pw.Text(
                                reviewerName,
                                style: pw.TextStyle(
                                  fontSize: _small,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            if (reviewerTitle.isNotEmpty)
                              pw.Text(
                                reviewerTitle,
                                style: const pw.TextStyle(fontSize: _small),
                                textAlign: pw.TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return doc;
  }

  static Future<void> printLeaveRequest({
    required LeaveRequest request,
    List<LeaveBalance>? balances,
    String? name,
  }) async {
    final doc = await buildPdf(request: request, balances: balances);
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: name ?? 'Leave_Application_${request.id ?? request.userId}.pdf',
    );
  }
}
