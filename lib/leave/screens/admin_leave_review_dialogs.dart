import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../leave_repository.dart';
import '../models/leave_balance.dart';
import '../models/leave_request.dart';
import '../models/leave_type.dart';
import 'admin_leave_screen_utils.dart';

class AdminLeaveApproveDialog extends StatefulWidget {
  const AdminLeaveApproveDialog({
    super.key,
    required this.request,
    this.leaveBalance,
  });

  final LeaveRequest request;
  final LeaveBalance? leaveBalance;

  @override
  State<AdminLeaveApproveDialog> createState() => _AdminLeaveApproveDialogState();
}

class _AdminLeaveApproveDialogState extends State<AdminLeaveApproveDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _withPayController;
  late final TextEditingController _withoutPayController;
  late final TextEditingController _remarksController;

  double get _totalRequested => widget.request.workingDaysApplied ?? 0.0;

  @override
  void initState() {
    super.initState();
    _withPayController = TextEditingController(
      text: _totalRequested.toStringAsFixed(1),
    );
    _withoutPayController = TextEditingController(text: '0.0');
    _remarksController = TextEditingController();
  }

  @override
  void dispose() {
    _withPayController.dispose();
    _withoutPayController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String? _validateApprovedDays(String? value) {
    final withPay = parseAdminLeaveDouble(_withPayController.text) ?? 0;
    final withoutPay = parseAdminLeaveDouble(_withoutPayController.text) ?? 0;
    if (withPay < 0 || withoutPay < 0) {
      return 'Days cannot be negative.';
    }
    final sum = withPay + withoutPay;
    if (sum > _totalRequested) {
      return 'Approved with pay + without pay must not exceed total requested ($_totalRequested days).';
    }
    if (sum != _totalRequested) {
      return 'Approved days must equal total requested ($_totalRequested days).';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final balanceLabel = widget.leaveBalance != null
        ? '${widget.leaveBalance!.leaveType.displayName}: '
              '${widget.leaveBalance!.availableDays.toStringAsFixed(1)} available '
              '(${widget.leaveBalance!.remainingDays.toStringAsFixed(1)} remaining excl. pending)'
        : 'No balance record for this leave type';

    return AlertDialog(
      title: const Text('Approve Leave Request'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Requested: ${_totalRequested.toStringAsFixed(1)} days',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 20),
                _AdminLeaveDialogField(
                  controller: _withPayController,
                  label: 'Approved Days With Pay',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (_) => _validateApprovedDays(null),
                ),
                const SizedBox(height: 12),
                _AdminLeaveDialogField(
                  controller: _withoutPayController,
                  label: 'Approved Days Without Pay',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (_) => _validateApprovedDays(null),
                ),
                const SizedBox(height: 12),
                _AdminLeaveDialogField(
                  controller: _remarksController,
                  label: 'Remarks',
                  maxLines: null,
                  minLines: 2,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dashMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Leave Balance:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        balanceLabel,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              LeaveApprovalInput(
                requestId: widget.request.id ?? '',
                reviewerId: '',
                approvedDaysWithPay: parseAdminLeaveDouble(_withPayController.text),
                approvedDaysWithoutPay: parseAdminLeaveDouble(
                  _withoutPayController.text,
                ),
                hrRemarks: trimAdminLeaveOrNull(_remarksController.text),
              ),
            );
          },
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class AdminLeaveDecisionDialog extends StatefulWidget {
  const AdminLeaveDecisionDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.requireReason,
    required this.request,
  });

  final String title;
  final String subtitle;
  final String confirmLabel;
  final bool requireReason;
  final LeaveRequest request;

  @override
  State<AdminLeaveDecisionDialog> createState() => _AdminLeaveDecisionDialogState();
}

class _AdminLeaveDecisionDialogState extends State<AdminLeaveDecisionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reasonController;
  late final TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _remarksController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _AdminLeaveDialogField(
                  controller: _reasonController,
                  label: 'Reason',
                  maxLines: null,
                  minLines: 3,
                  validator: widget.requireReason
                      ? (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Reason is required.';
                          }
                          return null;
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                _AdminLeaveDialogField(
                  controller: _remarksController,
                  label: 'HR Remarks',
                  maxLines: null,
                  minLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              LeaveReviewDecisionInput(
                requestId: widget.request.id ?? '',
                reviewerId: '',
                reason: trimAdminLeaveOrNull(_reasonController.text),
                hrRemarks: trimAdminLeaveOrNull(_remarksController.text),
              ),
            );
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _AdminLeaveDialogField extends StatelessWidget {
  const _AdminLeaveDialogField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      validator: validator,
      style: AppTheme.dashFieldTextStyle(context),
      decoration: adminLeaveInputDecoration(context, label),
    );
  }
}
