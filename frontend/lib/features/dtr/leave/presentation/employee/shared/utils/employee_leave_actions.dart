import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_overlay.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
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
    showLeaveFormSuccessSnackBar(context, result);
    if (userId != null && userId.isNotEmpty) {
      await provider.loadMyLeaveData(userId);
    }
  }

  Widget buildEditLeaveRequestForm({
    required LeaveProvider provider,
    required LeaveRequest request,
  }) {
    return EmployeeHrmsAssistantOverlay(
      initialBottom: 36,
      child: LeaveRequestFormScreen(
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
      ),
    );
  }

  /// Opens the leave form as an in-app preview (DTR-style side panel with
  /// print and share buttons) without going straight to the system dialog.
  Future<void> previewLeaveForm(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    if (!context.mounted || !isMounted()) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Loading preview...')));

    try {
      final (:target, :balances, :formSignatories) = await _loadLeaveFormData(
        provider,
        request,
      );
      if (!context.mounted || !isMounted()) return;

      final filename = 'Leave_Application_${target.id ?? target.userId}.pdf';
      final doc = await LeaveRequestPdf.buildPdf(
        request: target,
        balances: balances,
        certificationOfficerName: formSignatories.certificationOfficer?.name,
        certificationOfficerTitle: formSignatories.certificationOfficer?.title,
        recommendationOfficerName: formSignatories.recommendationOfficer?.name,
        recommendationOfficerTitle:
            formSignatories.recommendationOfficer?.title,
        approvingAuthorityName: formSignatories.approvingAuthority?.name,
        approvingAuthorityTitle: formSignatories.approvingAuthority?.title,
        applicantSignatureBytes:
            formSignatories.applicantSignature?.signatureImageBytes,
      );
      final bytes = await doc.save();
      if (!context.mounted || !isMounted()) return;

      ScaffoldMessenger.of(context).clearSnackBars();
      await showFormPdfPreview(
        context: context,
        bytes: bytes,
        title: 'Leave Form Preview',
        filename: filename,
      );
    } catch (e) {
      if (!context.mounted || !isMounted()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Preview failed — data could not be verified. '
            'Please retry when the server is reachable.\n($e)',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> printLeaveForm(LeaveRequest request) async {
    final provider = context.read<LeaveProvider>();
    if (!context.mounted || !isMounted()) return;

    // Show a loading indicator immediately so the user knows something is
    // happening — the data fetches below can take a couple of seconds.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Loading form data...')));

    try {
      final (:target, :balances, :formSignatories) = await _loadLeaveFormData(
        provider,
        request,
      );

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
        approvingAuthorityName: formSignatories.approvingAuthority?.name,
        approvingAuthorityTitle: formSignatories.approvingAuthority?.title,
        applicantSignatureBytes:
            formSignatories.applicantSignature?.signatureImageBytes,
        name: 'Leave_Application_${target.id ?? target.userId}.pdf',
      );
    } catch (e) {
      if (!context.mounted || !isMounted()) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Print failed — balance or request data could not be verified. '
            'Please retry when the server is reachable.\n($e)',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Shared data-fetch helper: refreshes the request then concurrently loads
  /// balances and signatories. Throws on any failure.
  Future<
    ({
      LeaveRequest target,
      List<LeaveBalance> balances,
      LeaveFormSignatories formSignatories,
    })
  >
  _loadLeaveFormData(LeaveProvider provider, LeaveRequest request) async {
    LeaveRequest target = request;
    final id = request.id;
    if (id != null && id.isNotEmpty) {
      final fresh = await provider.refreshRequestById(id);
      if (fresh == null) {
        throw Exception(
          'Could not load the latest request data. '
          'Please check your connection and try again.',
        );
      }
      target = fresh;
    }

    // Run the two independent lookups concurrently — they both depend on
    // `target` but not on each other, so there is no reason to wait for
    // one before starting the next.
    // Use the strict variant so any balance API failure throws rather than
    // returning an empty list that would silently produce zero credit figures
    // on the printed certification.
    final results = await Future.wait([
      provider.fetchBalancesForUserStrict(target.userId, forceRefresh: true),
      loadLeaveFormSignatories(request: target),
    ]);
    return (
      target: target,
      balances: results[0] as List<LeaveBalance>,
      formSignatories: results[1] as LeaveFormSignatories,
    );
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

  Future<void> discardDraft(LeaveRequest request) async {
    final userId = context.read<AuthProvider>().user?.id;
    final requestId = request.id;
    if (userId == null ||
        requestId == null ||
        request.status != LeaveRequestStatus.draft) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text('This draft will be removed from My Requests.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (!context.mounted || !isMounted() || confirmed != true) return;
    final provider = context.read<LeaveProvider>();
    final discarded = await provider.discardDraft(
      requestId: requestId,
      userId: userId,
    );
    if (!context.mounted || !isMounted()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          discarded
              ? 'Draft discarded.'
              : (provider.error ?? 'Could not discard draft.'),
        ),
      ),
    );
    if (discarded) {
      await provider.loadMyLeaveRequests(userId, forceRefresh: true);
    }
  }
}
