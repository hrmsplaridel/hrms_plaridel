import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_open_attachment.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_workflow_history.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/widgets/history_timeline.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/employee/mobile/widgets/employee_locator_mobile_details_widgets.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/shared/widgets/locator_custom_fields.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/widgets/workflow_request_signatures.dart';

String? pendingWorkflowStepLabel(Map<String, dynamic>? snapshot) {
  final steps = snapshot?['steps'];
  final current = snapshot?['current_step'];
  if (steps is! List ||
      current is! num ||
      current < 0 ||
      current >= steps.length) {
    return null;
  }
  final step = steps[current.toInt()];
  return step is Map ? step['label']?.toString() : null;
}

/// Assigned requests are merged into the source module's existing queue.
Future<Map<String, Map<String, dynamic>>> loadAssignedWorkflowRequests(
  String kind,
) async {
  final response = await ApiClient.instance.get<List<dynamic>>(
    '/api/approval-workflows/inbox',
    queryParameters: {'include_history': true},
  );
  return {
    for (final row in (response.data ?? []).whereType<Map>())
      if (row['kind'] == kind)
        row['id'].toString(): Map<String, dynamic>.from(row),
  };
}

Future<bool> reviewAssignedWorkflowRequest(
  BuildContext context,
  Map<String, dynamic> request, {
  Future<void> Function()? onPreview,
  Future<void> Function()? onPrint,
  VoidCallback? onRevoke,
  String? revokeDisabledReason,
}) async {
  final documents = DocuTrackerProvider();
  final messenger = ScaffoldMessenger.of(context);
  _WorkflowDecisionResult? result;
  try {
    if (request['kind'] == 'leave') {
      result = await openResponsiveRightSidePanel<_WorkflowDecisionResult>(
        context: context,
        barrierLabel: 'Close request details',
        minWidth: 400,
        initialWidthFraction: 0.46,
        builder: (_) => ChangeNotifierProvider.value(
          value: documents,
          child: _WorkflowDecisionDialog(
            request: request,
            onPreview: onPreview,
            onPrint: onPrint,
            onRevoke: onRevoke,
            revokeDisabledReason: revokeDisabledReason,
          ),
        ),
      );
    } else {
      result = await openResponsiveRightSidePanel<_WorkflowDecisionResult>(
        context: context,
        barrierLabel: 'Close locator approval details',
        breakpoint: 900,
        minWidth: 620,
        initialWidthFraction: 0.5,
        builder: (_) => ChangeNotifierProvider.value(
          value: documents,
          child: _WorkflowDecisionDialog(
            request: request,
            onPreview: onPreview,
            onPrint: onPrint,
            onRevoke: onRevoke,
            revokeDisabledReason: revokeDisabledReason,
          ),
        ),
      );
    }
    if (result != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
    return result != null;
  } finally {
    documents.dispose();
  }
}

class _WorkflowDecisionResult {
  const _WorkflowDecisionResult(this.message);
  final String message;
}

class _WorkflowDecisionDialog extends StatefulWidget {
  const _WorkflowDecisionDialog({
    required this.request,
    this.onPreview,
    this.onPrint,
    this.onRevoke,
    this.revokeDisabledReason,
  });
  final Map<String, dynamic> request;
  final Future<void> Function()? onPreview;
  final Future<void> Function()? onPrint;
  final VoidCallback? onRevoke;
  final String? revokeDisabledReason;
  @override
  State<_WorkflowDecisionDialog> createState() =>
      _WorkflowDecisionDialogState();
}

class _WorkflowDecisionDialogState extends State<_WorkflowDecisionDialog> {
  late Map<String, dynamic> _request = Map<String, dynamic>.from(
    widget.request,
  );
  StreamSubscription<AppRealtimeEvent>? _realtime;
  Timer? _refreshTimer;
  bool _listening = false, _refreshing = false;
  String? _refreshError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening || _request['kind'] != 'leave') return;
    _listening = true;
    try {
      _realtime = context.read<AppRealtimeProvider>().events.listen((event) {
        if (event.name != 'leave_updated' && event.name != 'connected') return;
        final id =
            event.payloadString('leaveRequestId') ??
            event.payloadString('requestId');
        if (id == null || id == _request['id']) {
          unawaited(_refreshCurrentRequest());
        }
      });
    } on ProviderNotFoundException {
      // Standalone review hosts still use the periodic fallback.
    }
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refreshCurrentRequest());
    });
  }

  Future<void> _refreshCurrentRequest() async {
    if (!mounted || _saving || _refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final assigned = await loadAssignedWorkflowRequests('leave');
      var current = assigned[_request['id']];
      if (current == null) {
        // Backups who did not act disappear from the assigned inbox after completion.
        // Load the authorized source record for the final status and complete history.
        final response = await ApiClient.instance.get<Map<String, dynamic>>(
          '/api/leave/${_request['id']}',
        );
        final data = response.data;
        if (data == null || data['id'] != _request['id']) {
          throw const FormatException('Request unavailable');
        }
        current = {
          ..._request,
          'can_review': false,
          'allowed_actions': <String>[],
          'request_data': data,
          'decisions': null,
          'status': data['status'],
          'current_step': (data['workflow_snapshot'] as Map?)?['current_step'],
        };
      }
      if (!mounted) return;
      setState(() {
        if (current!['current_step'] != _request['current_step'] ||
            current['signature_revision'] != _request['signature_revision']) {
          _signed = false;
        }
        _request = current;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _refreshError =
              'Could not verify this request. Refresh before reviewing.',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _locatorDateLabel(DateTime? date) {
    if (date == null) return '—';
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  final _remarks = TextEditingController();
  late final _paid = TextEditingController(
    text: widget.request['days']?.toString() ?? '0',
  );
  final _unpaid = TextEditingController(text: '0');
  bool _signed = false, _saving = false;
  String? _error;
  final _feedbackMessenger = GlobalKey<ScaffoldMessengerState>();
  bool get _canReview {
    final data = _request['request_data'] as Map?;
    final status = data?['status'] ?? _request['status'];
    return !_refreshing &&
        _refreshError == null &&
        _request['can_review'] != false &&
        (status == null || ['pending_hr', 'pending_mayor'].contains(status));
  }

  Future<void> _openForm(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _realtime?.cancel();
    _refreshTimer?.cancel();
    _remarks.dispose();
    _paid.dispose();
    _unpaid.dispose();
    super.dispose();
  }

  Future<void> _decide(String action) async {
    if (_saving || !_canReview) return;
    if (action == 'approve' && _request['kind'] == 'leave') {
      final paid = double.tryParse(_paid.text);
      final unpaid = double.tryParse(_unpaid.text);
      final requested = double.tryParse(_request['days'].toString());
      if (paid == null ||
          unpaid == null ||
          !paid.isFinite ||
          !unpaid.isFinite ||
          paid < 0 ||
          unpaid < 0 ||
          requested == null ||
          ((paid + unpaid) - requested).abs() > 0.001) {
        setState(
          () => _error =
              'Enter valid paid and unpaid days totaling the requested days.',
        );
        return;
      }
    }
    if (action != 'approve' && _remarks.text.trim().isEmpty) {
      setState(
        () => _error =
            'Enter the reason for returning or rejecting this request.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final request = _request;
    try {
      final response = await ApiClient.instance.post(
        '/api/approval-workflows/requests/${request['kind']}/${request['id']}/$action',
        data: {
          'expected_step': request['current_step'],
          'signature_revision': request['signature_revision'],
          'reviewer_remarks': _remarks.text.trim(),
          if (request['kind'] == 'leave') ...{
            'approved_days_with_pay': double.tryParse(_paid.text),
            'approved_days_without_pay': double.tryParse(_unpaid.text),
          },
        },
      );
      if (!mounted) return;
      final data = response.data;
      final nextLabel = data is Map && data['workflow_snapshot'] is Map
          ? pendingWorkflowStepLabel(
              Map<String, dynamic>.from(data['workflow_snapshot'] as Map),
            )
          : null;
      final message = action == 'approve'
          ? data is Map && data['status'] == 'approved'
                ? '${request['kind'] == 'leave' ? 'Leave' : 'Locator'} request approved successfully.'
                : '${request['step_label']} approved successfully.${nextLabel == null ? '' : ' Forwarded to $nextLabel.'}'
          : '${request['kind'] == 'leave' ? 'Leave' : 'Locator'} request ${action == 'return' ? 'returned' : 'rejected'} successfully.';
      setState(() => _saving = false);
      Navigator.pop(context, _WorkflowDecisionResult(message));
    } catch (error) {
      if (mounted) {
        final message = userFacingApiError(error);
        setState(() => _error = message);
        (_feedbackMessenger.currentState ?? ScaffoldMessenger.of(context))
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _attachment() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final request = _request;
      final response = await ApiClient.instance.dio.get<List<int>>(
        '/api/approval-workflows/requests/${request['kind']}/${request['id']}/attachment',
        options: Options(responseType: ResponseType.bytes),
      );
      if (!mounted) return;
      if (response.data?.isNotEmpty != true) {
        throw const FormatException('Attachment is empty.');
      }
      await openDocuTrackerAttachmentBytes(
        response.data!,
        request['attachment_name'] as String,
      );
    } catch (error) {
      if (mounted) setState(() => _error = userFacingApiError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final actions = (request['allowed_actions'] as List? ?? []).cast<String>();
    final isLeave = request['kind'] == 'leave';
    final reviewFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_refreshing) const LinearProgressIndicator(),
        if (_refreshError != null)
          Row(
            children: [
              Expanded(child: Text(_refreshError!)),
              IconButton(
                tooltip: 'Refresh request',
                onPressed: _refreshCurrentRequest,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        if (_canReview && request['kind'] == 'leave') ...[
          Text('Requested days: ${request['days']}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _paid,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days with pay'),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _unpaid,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days without pay',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        AbsorbPointer(
          absorbing: _saving,
          child: WorkflowRequestSignatures(
            sourceTable: request['kind'] == 'leave'
                ? 'leave_requests'
                : 'locator_slips',
            requestId: request['id'] as String,
            canReview: _canReview,
            stepLabel: request['step_label'] as String?,
            onChanged: (bundle) {
              final signature = bundle.signatureFor('hr_approver');
              final userId = context.read<AuthProvider>().user?.id;
              if (mounted) {
                setState(
                  () => _signed =
                      signature?.isSigned == true &&
                      signature?.signedBy == userId,
                );
              }
            },
          ),
        ),
        if (_canReview) ...[
          const SizedBox(height: 20),
          TextField(
            controller: _remarks,
            enabled: !_saving,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Review remarks'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: ScaffoldMessenger(
        key: _feedbackMessenger,
        child: Scaffold(
          backgroundColor: AppTheme.dashPanelOf(context),
          body: isLeave
              ? AdminLeaveDetailsFrame(
                  canClose: !_saving,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: _leaveDetails(reviewFields, actions),
                  ),
                )
              : _locatorDetails(reviewFields, actions),
        ),
      ),
    );
  }

  Widget _locatorDetails(Widget reviewFields, List<String> actions) {
    final request = _request;
    final data = Map<String, dynamic>.from(
      request['request_data'] as Map? ?? {},
    );
    final type = LocatorRequestType.fromJson({
      'code': data['request_type'],
      'label': data['request_type_label'],
      'location_label': data['request_type_location_label'],
    });
    final date = DateTime.tryParse(
      (data['slip_date'] ?? request['date'] ?? '').toString(),
    );
    final dateLabel = _locatorDateLabel(date);
    final status =
        data['status']?.toString() ??
        request['status']?.toString() ??
        'pending_hr';
    final pending = ['pending_hr', 'pending_mayor'].contains(status);
    final statusLabel =
        request['status_label']?.toString() ??
        (pending
            ? 'Pending ${request['step_label']}'
            : status == 'approved'
            ? 'Approved'
            : status == 'returned_for_correction'
            ? 'Needs Correction'
            : status.replaceAll('_', ' '));
    final statusColor = status == 'approved'
        ? Colors.green
        : pending
        ? Colors.blue
        : Colors.orange;
    final segments = [
      if (data['am_in'] == true) 'AM IN',
      if (data['am_out'] == true) 'AM OUT',
      if (data['pm_in'] == true) 'PM IN',
      if (data['pm_out'] == true) 'PM OUT',
    ];
    final events = <LeaveHistoryEvent>[
      LeaveHistoryEvent(
        label: 'Submitted',
        dateTime: DateTime.tryParse(request['created_at']?.toString() ?? ''),
        actor: request['employee_name']?.toString() ?? 'Applicant',
      ),
      for (final decision
          in (request['decisions'] as List? ?? []).whereType<Map>())
        LeaveHistoryEvent(
          label:
              '${decision['step_label']} · ${decision['action'] == 'approve' ? 'Approved' : decision['action']}',
          dateTime: DateTime.tryParse(decision['acted_at']?.toString() ?? ''),
          actor: decision['reviewer_name']?.toString() ?? 'Reviewer',
        ),
    ];
    return EmployeeLocatorMobileDetailsDialog(
      requestTypeLabel: type.label,
      dateLabel: dateLabel,
      requestTypeIcon: Icons.receipt_long_rounded,
      statusLabel: statusLabel,
      statusIcon: pending
          ? Icons.pending_actions_rounded
          : Icons.fact_check_outlined,
      statusBg: statusColor.shade50,
      statusBorder: statusColor.shade200,
      statusText: statusColor.shade900,
      onClose: () {
        if (!_saving) Navigator.pop(context);
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmployeeLocatorMobileDetailSection(
            title: 'Slip Information',
            icon: Icons.receipt_long_rounded,
            children: [
              EmployeeLocatorMobileDetailTile(
                icon: Icons.person_outline,
                label: 'Employee',
                value: request['employee_name']?.toString() ?? 'Employee',
              ),
              EmployeeLocatorMobileDetailTile(
                icon: Icons.business_outlined,
                label: 'Department',
                value: data['department_name']?.toString() ?? '—',
              ),
              EmployeeLocatorMobileDetailTile(
                icon: Icons.calendar_today_rounded,
                label: 'Date',
                value: dateLabel,
              ),
              EmployeeLocatorMobileDetailTile(
                icon: Icons.category_rounded,
                label: 'Type',
                value: type.label,
              ),
              EmployeeLocatorMobileDetailTile(
                icon: Icons.place_rounded,
                label: type.locationLabel,
                value: (data['office'] ?? request['office'] ?? '—').toString(),
              ),
              EmployeeLocatorMobileDetailTile(
                icon: Icons.schedule_rounded,
                label: 'Time Segments',
                value: segments.isEmpty ? 'Not specified' : segments.join(', '),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pending
                ? '${request['workflow_name']} · Step ${((request['current_step'] as num?) ?? 0) + 1} of ${request['step_count']}'
                : '${request['workflow_name']} · $statusLabel',
          ),
          const SizedBox(height: 12),
          EmployeeLocatorMobileReasonPanel(
            text: (data['reason'] ?? request['reason'] ?? 'No reason provided.')
                .toString(),
          ),
          LocatorCustomFieldDetails(
            fields: leaveCustomFieldDefinitionsFromJson(
              data['employee_detail_schema_snapshot'] ??
                  request['detail_schema'],
            ),
            values: Map<String, dynamic>.from(
              data['additional_details'] as Map? ??
                  request['additional_details'] as Map? ??
                  {},
            ),
          ),
          if (!_canReview &&
              [
                data['hr_remarks'],
                data['dept_head_remarks'],
                data['retroactive_correction_reason'],
              ].any(
                (value) => value?.toString().trim().isNotEmpty == true,
              )) ...[
            const SizedBox(height: 12),
            EmployeeLocatorMobileDetailSection(
              title: 'Review information',
              icon: Icons.fact_check_outlined,
              children: [
                for (final entry in {
                  'Department review remarks': data['dept_head_remarks'],
                  'Latest review remarks': data['hr_remarks'],
                  'HR Correction Reason': data['retroactive_correction_reason'],
                }.entries)
                  if (entry.value?.toString().trim().isNotEmpty == true)
                    EmployeeLocatorMobileDetailTile(
                      icon: Icons.rate_review_outlined,
                      label: entry.key,
                      value: entry.value.toString(),
                    ),
              ],
            ),
          ],
          if (data['revocation_reason']?.toString().trim().isNotEmpty ==
              true) ...[
            const SizedBox(height: 12),
            EmployeeLocatorMobileDetailSection(
              title: 'Approval Revoked',
              icon: Icons.undo_rounded,
              children: [
                if (data['revoked_by_name'] != null)
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Revoked By',
                    value: data['revoked_by_name'].toString(),
                  ),
                if (data['revoked_at'] != null)
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.schedule_rounded,
                    label: 'Revoked At',
                    value: _locatorDateLabel(
                      DateTime.tryParse(data['revoked_at'].toString()),
                    ),
                  ),
                EmployeeLocatorMobileDetailTile(
                  icon: Icons.rate_review_outlined,
                  label: 'Reason',
                  value: data['revocation_reason'].toString(),
                ),
                if (data['month_end_reconciliation_required'] == true)
                  EmployeeLocatorMobileDetailTile(
                    icon: Icons.sync_problem_rounded,
                    label: 'Month-End Reconciliation',
                    value:
                        'Re-run month-end processing for ${data['service_month']}.',
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Approval History',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              HistoryTimeline(events: events),
            ],
          ),
          const SizedBox(height: 20),
          reviewFields,
        ],
      ),
      actions: EmployeeLocatorMobileDetailActions(
        canCancel: false,
        canPrint: status == 'approved',
        canOpenAttachment: request['attachment_name'] != null,
        canReject: _canReview && actions.contains('reject'),
        canReturn: _canReview && actions.contains('return'),
        canApprove: _canReview && actions.contains('approve'),
        onCancel: () {},
        onPreview: () =>
            _openForm(widget.onPreview ?? () => _openLocatorForm(print: false)),
        onPrint: () =>
            _openForm(widget.onPrint ?? () => _openLocatorForm(print: true)),
        onOpenAttachment: () {
          if (!_saving) _attachment();
        },
        onReject: _saving ? null : () => _decide('reject'),
        onReturn: _saving ? null : () => _decide('return'),
        onApprove: _saving || !_signed ? null : () => _decide('approve'),
        additionalAction: status == 'approved' && widget.onRevoke != null
            ? Tooltip(
                message:
                    widget.revokeDisabledReason ??
                    'Revoke this locator approval',
                child: OutlinedButton.icon(
                  onPressed: _saving || widget.revokeDisabledReason != null
                      ? null
                      : () {
                          Navigator.pop(context);
                          widget.onRevoke!();
                        },
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Revoke Approval'),
                ),
              )
            : null,
      ),
    );
  }

  Future<void> _openLocatorForm({required bool print}) async {
    final request = _request;
    final data = Map<String, dynamic>.from(
      request['request_data'] as Map? ?? {},
    );
    final type = LocatorRequestType.fromJson({
      'code': data['request_type'],
      'label': data['request_type_label'],
      'location_label': data['request_type_location_label'],
    });
    final date = DateTime.tryParse(
      (data['slip_date'] ?? request['date'] ?? '').toString(),
    );
    final dateLabel = _locatorDateLabel(date);
    try {
      if (print) {
        await LocatorSlipPrint.printForm(
          context: context,
          id: request['id'] as String,
          employeeName: request['employee_name']?.toString() ?? 'Employee',
          dateText: dateLabel,
          requestTypeLabel: type.label,
          locationLabel: type.locationLabel,
          office: (data['office'] ?? request['office'] ?? '').toString(),
          remarks: (data['reason'] ?? request['reason'] ?? '').toString(),
          amIn: data['am_in'] == true,
          amOut: data['am_out'] == true,
          pmIn: data['pm_in'] == true,
          pmOut: data['pm_out'] == true,
        );
      } else {
        final bytes = await LocatorSlipPrint.loadPreview(
          context,
          () async => LocatorSlipPrint.buildPdf(
            signatories: await loadLocatorFormSignatories(
              request['id'] as String,
            ),
            id: request['id'] as String,
            employeeName: request['employee_name']?.toString() ?? 'Employee',
            dateText: dateLabel,
            requestTypeLabel: type.label,
            locationLabel: type.locationLabel,
            office: (data['office'] ?? request['office'] ?? '').toString(),
            remarks: (data['reason'] ?? request['reason'] ?? '').toString(),
            amIn: data['am_in'] == true,
            amOut: data['am_out'] == true,
            pmIn: data['pm_in'] == true,
            pmOut: data['pm_out'] == true,
          ),
        );
        if (!mounted) return;
        await showFormPdfPreview(
          context: context,
          bytes: bytes,
          title: 'Locator Form Preview',
          filename: 'Locator_Slip_${request['id']}.pdf',
        );
      }
    } catch (_) {
      if (mounted) {
        await LocatorSlipPrint.showFailure(
          context,
          print ? 'Print' : 'Preview',
        );
      }
    }
  }

  Widget _leaveDetails(Widget reviewFields, List<String> actions) {
    final request = _request;
    final data = Map<String, dynamic>.from(
      request['request_data'] as Map? ?? {},
    );
    final leave = LeaveRequest.fromJson({
      ...data,
      'id': request['id'],
      'user_id': data['user_id'] ?? '',
      'employee_name': data['employee_name'] ?? request['employee_name'],
      'status': data['status'] ?? 'pending_hr',
      'start_date': data['start_date'] ?? request['date'],
      'working_days_applied': data['working_days_applied'] ?? request['days'],
      'reason': data['reason'] ?? request['reason'],
      'attachment_name': data['attachment_name'] ?? request['attachment_name'],
    });
    final events = leaveWorkflowHistory(
      leave,
      decisions: request['decisions'] as List?,
    );
    final canRevoke = leave.status == LeaveRequestStatus.approved &&
        leave.canRevokeApproval == true && widget.onRevoke != null &&
        context.read<AuthProvider>().user?.id != leave.userId;
    final revokeReason = canRevoke
        ? widget.revokeDisabledReason ?? adminLeaveRevokeDisabledReason(leave)
        : null;
    return AdminLeaveRequestDetailsPanel(
      request: leave,
      isDepartmentHead: false,
      reviewing: _saving,
      statusLabel: leave.statusLabel,
      historyEvents: events,
      reviewFields: reviewFields,
      approvalEnabled: _signed,
      onApprove: _canReview && actions.contains('approve')
          ? () => _decide('approve')
          : null,
      onReturn: _canReview && actions.contains('return')
          ? () => _decide('return')
          : null,
      onReject: _canReview && actions.contains('reject')
          ? () => _decide('reject')
          : null,
      onPreview: widget.onPreview == null
          ? null
          : () => _openForm(widget.onPreview!),
      onPrint: widget.onPrint == null ? null : () => _openForm(widget.onPrint!),
      onRevoke: canRevoke && revokeReason == null && !_refreshing && _refreshError == null
          ? () {
              if (_saving) return;
              Navigator.of(context).pop();
              widget.onRevoke!();
            }
          : null,
      revokeDisabledReason: revokeReason,
      onOpenAttachment: () {
        if (!_saving) _attachment();
      },
    );
  }
}
