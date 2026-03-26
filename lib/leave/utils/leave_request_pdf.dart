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
      'Dec'
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  static String _formatDateIso(DateTime value) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }

  static ({String last, String first, String middle}) _parseNameToLastFirstMiddle(
    String displayName,
  ) {
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
              child: pw.Text(
                'X',
                style: const pw.TextStyle(fontSize: 9),
              ),
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

  static pw.Widget _panel({
    required String title,
    required pw.Widget child,
  }) {
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
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: child,
          ),
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
    final effectiveBalances = balances ?? const [];
    final computedWorkingDays = _workingDaysToDisplay(request);
    final dateFiled = request.dateFiled ?? DateTime.now();
    final reviewerName =
        request.reviewerName?.trim().isNotEmpty == true ? request.reviewerName!.trim() : null;

    final ({String last, String first, String middle}) nameParts =
        _parseNameToLastFirstMiddle(
      request.employeeName?.trim().isNotEmpty == true
          ? request.employeeName!.trim()
          : request.userId,
    );

    final vlBal = effectiveBalances.firstWhere(
      (b) => b.leaveType == LeaveType.vacationLeave,
      orElse: () => const LeaveBalance(
        userId: '',
        leaveType: LeaveType.vacationLeave,
      ),
    );
    final slBal = effectiveBalances.firstWhere(
      (b) => b.leaveType == LeaveType.sickLeave,
      orElse: () => const LeaveBalance(
        userId: '',
        leaveType: LeaveType.sickLeave,
      ),
    );

    final leaveType = request.leaveType;
    final deductionDays =
        (leaveType == LeaveType.vacationLeave || leaveType == LeaveType.sickLeave)
            ? (computedWorkingDays ?? 0.0)
            : 0.0;
    final vlDeduction = leaveType == LeaveType.vacationLeave ? deductionDays : 0.0;
    final slDeduction = leaveType == LeaveType.sickLeave ? deductionDays : 0.0;

    String formatDays(double d) => d == 0 ? '—' : d.toStringAsFixed(3);

    final hasDateRange = _isValidDateRange(request.startDate, request.endDate);
    final startStr =
        request.startDate != null ? _formatDate(request.startDate!) : '—';
    final endStr = request.endDate != null ? _formatDate(request.endDate!) : '—';

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
            decoration:
                pw.BoxDecoration(border: pw.Border.all(color: _borderColor, width: 1)),
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
                                    nameParts.last.isEmpty ? '—' : nameParts.last,
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(
                                  child: _fieldLine(
                                    nameParts.first.isEmpty ? '—' : nameParts.first,
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(
                                  child: _fieldLine(
                                    nameParts.middle.isEmpty ? '—' : nameParts.middle,
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
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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
                              request.leaveType == LeaveType.others ? leaveTypeText : '—',
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
                              checked: request.locationOption ==
                                  LeaveLocationOption.withinPhilippines,
                            ),
                            _rowCheck(
                              'Abroad (Specify)',
                              checked: request.locationOption == LeaveLocationOption.abroad,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text('Location details',
                                style: const pw.TextStyle(fontSize: 10)),
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
                              checked: request.sickLeaveNature == SickLeaveNature.inHospital,
                            ),
                            _rowCheck(
                              'Out Patient (Specify Illness)',
                              checked: request.sickLeaveNature == SickLeaveNature.outPatient,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text('Specify illness', style: const pw.TextStyle(fontSize: 10)),
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
                              checked: request.studyPurpose ==
                                  StudyLeavePurpose.completionOfMastersDegree,
                            ),
                            _rowCheck(
                              'BAR/Board Examination Review',
                              checked: request.studyPurpose ==
                                  StudyLeavePurpose.barBoardExaminationReview,
                            ),
                            _rowCheck(
                              'Other purpose',
                              checked:
                                  request.studyPurpose == StudyLeavePurpose.otherPurpose,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text('Specify other study purpose',
                                style: const pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(height: 4),
                            _fieldLine(_s(request.studyPurposeDetails)),
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
                              checked: request.otherPurpose ==
                                  LeaveOtherPurpose.monetizationOfLeaveCredits,
                            ),
                            _rowCheck(
                              'Terminal Leave (HR process)',
                              checked: request.otherPurpose ==
                                  LeaveOtherPurpose.terminalLeave,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text('Additional details / reason',
                                style: const pw.TextStyle(fontSize: 10)),
                            pw.SizedBox(height: 4),
                            _fieldLine(_s(request.otherPurposeDetails)),
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
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text('Start Date',
                                          style: const pw.TextStyle(fontSize: 10)),
                                      pw.SizedBox(height: 4),
                                      _fieldLine(
                                        hasDateRange ? startStr : '—',
                                      ),
                                    ],
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text('End Date',
                                          style: const pw.TextStyle(fontSize: 10)),
                                      pw.SizedBox(height: 4),
                                      _fieldLine(
                                        hasDateRange ? endStr : '—',
                                      ),
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
                              checked: request.commutation ==
                                  LeaveCommutationOption.notRequested,
                            ),
                            _rowCheck(
                              'Requested',
                              checked: request.commutation == LeaveCommutationOption.requested,
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
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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
                              border: pw.TableBorder.all(color: _borderColor, width: 0.7),
                              columnWidths: const {
                                0: pw.FlexColumnWidth(1.0),
                                1: pw.FlexColumnWidth(1.0),
                                2: pw.FlexColumnWidth(1.0),
                              },
                              children: [
                                pw.TableRow(
                                  decoration: pw.BoxDecoration(color: _headerFill),
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text('', style: const pw.TextStyle(fontSize: 9)),
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
                                      child: pw.Text('Total Earned', style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(formatDays(vlBal.earnedDays + vlBal.adjustedDays),
                                          style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(formatDays(slBal.earnedDays + slBal.adjustedDays),
                                          style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                  ],
                                ),
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text('Less this application',
                                          style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child:
                                          pw.Text(formatDays(vlDeduction), style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child:
                                          pw.Text(formatDays(slDeduction), style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                  ],
                                ),
                                pw.TableRow(
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text('Balance', style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(formatDays(vlBal.remainingDays - vlDeduction),
                                          style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.all(4),
                                      child: pw.Text(formatDays(slBal.remainingDays - slDeduction),
                                          style: const pw.TextStyle(fontSize: 9)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 26),
                            pw.Divider(height: 1, thickness: 0.7, color: _borderColor),
                            pw.SizedBox(height: 8),
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
                                // TODO: Official form includes officer title/role details.
                                // Current backend model only provides `reviewerName`.
                                if (reviewerName != null) pw.SizedBox(height: 2),
                                if (reviewerName != null)
                                  pw.Text(
                                    reviewerName,
                                    style: pw.TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: pw.FontWeight.bold,
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
                        title: '7.B RECOMMENDATION',
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _rowCheck(
                              'For approval',
                              checked: request.status == LeaveRequestStatus.approved,
                            ),
                            pw.SizedBox(height: 6),
                            _rowCheck(
                              'For disapproval due to',
                              checked: request.status == LeaveRequestStatus.rejected,
                            ),
                            pw.SizedBox(height: 10),
                            pw.Text(
                              request.recommendationRemarks?.trim().isNotEmpty == true
                                  ? request.recommendationRemarks!.trim()
                                  : '____________________________________________________________',
                              style: const pw.TextStyle(fontSize: 10.2, height: 1.4),
                            ),
                            // TODO: The backend model also has `hrRemarks` and `reason`.
                            // The current UI maps only `recommendationRemarks` and
                            // `disapprovalReason` into the paper form. Update this once
                            // the official field mapping is confirmed.
                            pw.SizedBox(height: 20),
                            pw.Divider(height: 1, thickness: 0.7, color: _borderColor),
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
                                // TODO: Render officer title/role once available from backend.
                                if (reviewerName != null) pw.SizedBox(height: 2),
                                if (reviewerName != null)
                                  pw.Text(
                                    reviewerName,
                                    style: pw.TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
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
                                  right: pw.BorderSide(width: 1, color: _borderColor),
                                ),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                                children: [
                                  pw.Container(
                                    color: _headerFill,
                                    padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
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
                                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Text(
                                          request.approvedDaysWithPay != null
                                              ? '${request.approvedDaysWithPay!.toStringAsFixed(1)} days with pay'
                                              : '_______ days with pay',
                                          style: const pw.TextStyle(fontSize: 10.2),
                                        ),
                                        pw.SizedBox(height: 8),
                                        pw.Text(
                                          request.approvedDaysWithoutPay != null
                                              ? '${request.approvedDaysWithoutPay!.toStringAsFixed(1)} days without pay'
                                              : '_______ days without pay',
                                          style: const pw.TextStyle(fontSize: 10.2),
                                        ),
                                        pw.SizedBox(height: 8),
                                        pw.Text(
                                          request.approvedOtherDetails?.trim().isNotEmpty == true
                                              ? request.approvedOtherDetails!.trim()
                                              : '_______ others (Specify)',
                                          style: const pw.TextStyle(fontSize: 10.2),
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
                                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                                children: [
                                  pw.Container(
                                    color: _headerFill,
                                    padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
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
                                      request.disapprovalReason?.trim().isNotEmpty == true
                                          ? request.disapprovalReason!.trim()
                                          : '____________________________________________________________',
                                      style: const pw.TextStyle(fontSize: 10.2, height: 1.4),
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
                            pw.Divider(height: 1, thickness: 0.7, color: _borderColor),
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
                                // TODO: Approving authority title/role fields are not yet in the model.
                                if (reviewerName != null) pw.SizedBox(height: 2),
                                if (reviewerName != null)
                                  pw.Text(
                                    reviewerName,
                                    style: pw.TextStyle(
                                      fontSize: 10.2,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
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
                        style: pw.TextStyle(fontSize: 9.2, color: _textSecondary),
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

  /// Opens the platform print preview and allows direct printing or
  /// "Save as PDF" from the system dialog.
  static Future<void> printLeaveRequest({
    required LeaveRequest request,
    List<LeaveBalance>? balances,
    String? name,
  }) async {
    final doc = await buildPdf(request: request, balances: balances);
    final filename = name ?? 'Leave_Application_${request.id ?? request.userId}.pdf';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: filename,
    );
  }
}

