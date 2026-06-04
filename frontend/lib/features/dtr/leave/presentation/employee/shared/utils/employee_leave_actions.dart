import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_form_signatories.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_request_pdf.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';

class EmployeeLeaveActions {
  const EmployeeLeaveActions({required this.context, required this.isMounted});

  final BuildContext context;
  final bool Function() isMounted;

  Future<void> editRequest(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    final userId = context.read<AuthProvider>().user?.id;
    final result = await openResponsiveLeaveFormHost<String?>(
      context: context,
      builder: (_) =>
          buildEditLeaveRequestForm(provider: provider, request: request),
    );
    if (!context.mounted || !isMounted() || result == null) return;
    if (result != kLeaveFormResultDraftSaved &&
        result != kLeaveFormResultSubmitted) {
      return;
    }
    if (userId != null && userId.isNotEmpty) {
      await provider.loadMyLeaveData(userId);
    }
    if (!context.mounted || !isMounted()) return;
    showLeaveFormSuccessSnackBar(context, result);
  }

  Widget buildEditLeaveRequestForm({
    required LeaveProvider provider,
    required LeaveRequest request,
  }) {
    return LeaveRequestFormScreen(
      initialRequest: request,
      onSaveDraft: (updated) async {
        final saved = updated.id == null || updated.id!.isEmpty
            ? await provider.saveDraft(updated)
            : await provider.updateRequest(
                updated.copyWith(
                  status: request.status == LeaveRequestStatus.returned
                      ? LeaveRequestStatus.returned
                      : LeaveRequestStatus.draft,
                ),
              );
        return saved != null;
      },
      onSubmitRequest: (updated) async {
        final saved = updated.id == null || updated.id!.isEmpty
            ? await provider.submitRequest(updated)
            : await provider.updateRequest(
                updated.copyWith(status: LeaveRequestStatus.pending),
              );
        return saved != null;
      },
      onSubmitRequestWithAttachment: (updated, fileBytes, fileName) async {
        final saved = updated.id == null || updated.id!.isEmpty
            ? await provider.submitRequestWithAttachment(
                request: updated,
                fileBytes: fileBytes,
                fileName: fileName,
              )
            : await provider.updateRequest(
                updated.copyWith(status: LeaveRequestStatus.pending),
              );
        return saved != null;
      },
    );
  }

  Future<void> printLeaveForm(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    if (!context.mounted || !isMounted()) return;
    try {
      LeaveRequest target = request;
      final id = request.id;
      if (id != null && id.isNotEmpty) {
        final fresh = await provider.refreshRequestById(id);
        if (fresh != null) target = fresh;
      }

      final balances = await provider.fetchBalancesForUser(
        target.userId,
        forceRefresh: true,
      );
      final formSignatories = await loadLeaveFormSignatories(request: target);

      if (!context.mounted || !isMounted()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preparing print...')));

      await LeaveRequestPdf.printLeaveRequest(
        request: target,
        balances: balances,
        certificationOfficerName: formSignatories.certificationOfficer?.name,
        certificationOfficerTitle: formSignatories.certificationOfficer?.title,
        recommendationOfficerName: formSignatories.recommendationOfficer?.name,
        recommendationOfficerTitle:
            formSignatories.recommendationOfficer?.title,
        name: 'Leave_Application_${target.id ?? target.userId}.pdf',
      );
    } catch (e) {
      if (!context.mounted || !isMounted()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<void> cancelRequest(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) return;
    final requestId = request.id;
    if (requestId == null || requestId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel leave request?'),
        content: const Text(
          'This will cancel the request. You can file a new request anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (!context.mounted || !isMounted() || ok != true) return;

    final updated = await provider.cancelRequest(
      requestId: requestId,
      userId: userId,
    );
    if (!context.mounted || !isMounted()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated != null
              ? 'Leave request cancelled.'
              : (provider.error ?? 'Cancel failed.'),
        ),
      ),
    );
    await provider.loadMyLeaveData(userId);
  }
}
