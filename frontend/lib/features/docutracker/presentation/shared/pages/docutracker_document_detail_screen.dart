import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_action.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_record.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permission_service.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_open_attachment.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_permission_reason_label.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_document_attachment_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_document_detail_ui.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_status_badge.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
import 'package:hrms_plaridel/core/utils/responsive_right_side_panel.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_linked_source_document_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_details_side_sheet.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/shared/utils/employee_leave_actions.dart';

/// Step 9: Document detail with audit trail timeline.
/// Step 8: Document actions - Review, Approve, Reject, Return, Forward, Add remarks.
class DocuTrackerDocumentDetailScreen extends StatefulWidget {
  const DocuTrackerDocumentDetailScreen({
    super.key,
    required this.document,
    this.isAdmin = false,
  });

  final DocuTrackerDocument document;
  final bool isAdmin;

  @override
  State<DocuTrackerDocumentDetailScreen> createState() =>
      _DocuTrackerDocumentDetailScreenState();
}

class _DocuTrackerDocumentDetailScreenState
    extends State<DocuTrackerDocumentDetailScreen> {
  final _remarkController = TextEditingController();
  final _noteController = TextEditingController();
  bool _postingNote = false;

  Timer? _pollTimer;
  List<DocumentRoutingRecord> _routingRecords = const [];
  bool _routingLoading = true;

  DocuTrackerDocument _resolveDocForView(DocuTrackerProvider provider) {
    final docId = widget.document.id;
    if (docId == null) return widget.document;
    for (final d in provider.documents) {
      if (d.id == docId) return d;
    }
    return widget.document;
  }

  bool _permissionsLoading = true;
  String? _workflowConfigIssue;
  bool _canViewAuditTrail = false;
  bool _canEdit = false; // Candidate documents / remark ability
  bool _canSubmitAction = false;
  bool _canApproveAction = false;
  bool _canForwardAction = false;
  bool _canRejectAction = false;
  bool _canReturnAction = false;
  bool _canDownloadAttachment = false;
  bool _canModifyAttachment = false;
  Map<String, DocuTrackerPermissionExplanation> _permissionExplanations = {};

  bool _isLinkedLeave(DocuTrackerDocument doc) =>
      doc.sourceModule == 'dtr' &&
      doc.sourceTable == 'leave_requests' &&
      (doc.sourceRecordId ?? '').isNotEmpty;

  bool _isSupportedLinkedSource(DocuTrackerDocument doc) {
    final module = doc.sourceModule;
    final table = doc.sourceTable;
    return (module == 'ld' && table == 'training_daily_reports') ||
        (module == 'rsp' && table == 'recruitment_applications');
  }

  Future<void> _openPrimaryDocument(DocuTrackerDocument doc) async {
    if (_isLinkedLeave(doc)) {
      await _openLinkedLeaveForm(doc);
      return;
    }
    if (doc.sourceOnly) {
      if (!_isSupportedLinkedSource(doc)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This source document cannot be opened here yet.'),
          ),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DocuTrackerLinkedSourceDocumentScreen(document: doc),
        ),
      );
      return;
    }
    final provider = context.read<DocuTrackerProvider>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DocuTrackerDocumentBuilderScreen(document: doc),
      ),
    );
    if (mounted && doc.id != null) {
      provider.refreshDocument(doc.id!);
    }
  }

  Future<void> _openLinkedLeaveForm(DocuTrackerDocument doc) async {
    final sourceRecordId = doc.sourceRecordId;
    if (sourceRecordId == null || sourceRecordId.isEmpty) return;
    final leaveProvider = context.read<LeaveProvider>();
    final request = await leaveProvider.loadRequestById(sourceRecordId);
    if (!mounted) return;
    if (request == null) {
      final error =
          leaveProvider.error?.replaceFirst('Exception: ', '') ??
          'The linked leave request could not be opened.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final currentUserId = context.read<AuthProvider>().user?.id;
    final isApplicant =
        currentUserId != null &&
        currentUserId.isNotEmpty &&
        request.userId == currentUserId;
    if (isApplicant && request.status.canEmployeeEdit) {
      await EmployeeLeaveActions(
        context: context,
        isMounted: () => mounted,
      ).editRequest(request);
      return;
    }
    final leaveActions = EmployeeLeaveActions(
      context: context,
      isMounted: () => mounted,
    );
    Future<void> readOnly(LeaveRequest _) async {}
    await openResponsiveRightSidePanel<void>(
      context: context,
      barrierLabel: 'Close request details',
      minWidth: 400,
      initialWidthFraction: 0.46,
      builder: (_) => AdminLeaveDetailsSideSheet(
        initial: request,
        isDepartmentHead: false,
        canReviewPending: false,
        currentReviewerId: currentUserId,
        onApprove: readOnly,
        onReturn: readOnly,
        onReject: readOnly,
        onPreview: leaveActions.previewLeaveForm,
        onPrint: leaveActions.printLeaveForm,
      ),
    );
  }

  Widget _buildLinkedLeaveSection(
    DocuTrackerDocument doc,
    String currentUserId,
  ) {
    final sourceRecordId = doc.sourceRecordId!;
    final isApplicant = doc.createdBy == currentUserId;
    return DocuTrackerDetailSectionCard(
      icon: Icons.event_note_rounded,
      title: 'Linked Leave Form',
      subtitle: 'One DTR request, tracked and signed through DocuTracker',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DocuTrackerSourceSignatureCard(
            sourceModule: 'dtr',
            sourceTable: 'leave_requests',
            sourceRecordId: sourceRecordId,
          ),
          const SizedBox(height: 12),
          DocuTrackerSourceSignatureCard(
            sourceModule: 'dtr',
            sourceTable: 'leave_requests',
            sourceRecordId: sourceRecordId,
            slotKey: 'department_head',
            title: 'Department Head E-Signature',
            unsignedMessage: 'No department head signature yet',
            waitingMessage: 'Waiting for the assigned department head to sign.',
            savedMessage: 'Department head signature saved.',
          ),
          const SizedBox(height: 12),
          DocuTrackerSourceSignatureCard(
            sourceModule: 'dtr',
            sourceTable: 'leave_requests',
            sourceRecordId: sourceRecordId,
            slotKey: 'hr_approver',
            title: 'HR/Admin E-Signature',
            unsignedMessage: 'No final approver signature yet',
            waitingMessage: 'Waiting for an authorized HR reviewer to sign.',
            savedMessage: 'Final approver signature saved.',
          ),
          const SizedBox(height: 12),
          if (isApplicant)
            FilledButton.icon(
              onPressed: () => _openLinkedLeaveForm(doc),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open, Edit, or Submit Leave Form'),
            )
          else
            const Text(
              'The leave details and approval decision remain controlled by '
              'the DTR Leave workflow.',
              style: TextStyle(
                color: DocuTrackerTokens.textMuted,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshEffectivePermissions({
    required DocuTrackerDocument doc,
    required AuthProvider auth,
    required bool isAdmin,
  }) async {
    final repo = DocuTrackerRepository.instance;
    final userId = auth.user?.id ?? '';
    final roleId = auth.user?.role;
    final documentId = doc.id;
    if (doc.sourceOnly || documentId == null || documentId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _canViewAuditTrail = false;
        _canEdit = false;
        _canSubmitAction = false;
        _canApproveAction = false;
        _canForwardAction = false;
        _canRejectAction = false;
        _canReturnAction = false;
        _canDownloadAttachment = false;
        _canModifyAttachment = false;
        _permissionsLoading = false;
      });
      return;
    }

    final actions = <String>[
      DocumentAction.view.value,
      DocumentAction.download.value,
      DocumentAction.edit.value,
      DocumentAction.submit.value,
      DocumentAction.approve.value,
      DocumentAction.forward.value,
      DocumentAction.reject.value,
      DocumentAction.returnDoc.value,
    ];
    final explanationEntries = await Future.wait(
      actions.map((action) async {
        final explanation = await repo.explainPermission(
          userId: userId,
          roleId: roleId,
          documentType: doc.documentType,
          action: action,
          documentId: documentId,
          isAdmin: isAdmin,
        );
        return MapEntry(action, explanation);
      }),
    );
    final explanationDetails =
        Map<String, DocuTrackerPermissionExplanation>.fromEntries(
          explanationEntries,
        );
    bool granted(String action) => explanationDetails[action]?.granted == true;
    if (!mounted) return;
    setState(() {
      _permissionExplanations = explanationDetails;
      _canViewAuditTrail = granted(DocumentAction.view.value);
      _canEdit = isAdmin || granted(DocumentAction.edit.value);
      _canSubmitAction =
          granted(DocumentAction.submit.value) &&
          doc.createdBy == userId &&
          DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
      _canApproveAction = granted(DocumentAction.approve.value);
      _canForwardAction = granted(DocumentAction.forward.value);
      _canRejectAction = granted(DocumentAction.reject.value);
      _canReturnAction = granted(DocumentAction.returnDoc.value);
      _canDownloadAttachment =
          granted(DocumentAction.download.value) ||
          granted(DocumentAction.view.value);
      _canModifyAttachment =
          isAdmin ||
          (DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc) &&
              doc.createdBy == userId) ||
          granted(DocumentAction.edit.value);
      _permissionsLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<DocuTrackerProvider>();
      final auth = context.read<AuthProvider>();
      final repo = DocuTrackerRepository.instance;
      final userId = auth.user?.id ?? '';
      final docId = widget.document.id!;

      if (widget.document.sourceOnly) {
        if (mounted) {
          setState(() {
            _routingLoading = false;
            _workflowConfigIssue = null;
          });
        }
        await _refreshEffectivePermissions(
          doc: widget.document,
          auth: auth,
          isAdmin: widget.isAdmin,
        );
        return;
      }

      _routingRecords = await repo.getDocumentRoutingRecords(docId);
      if (mounted) setState(() => _routingLoading = false);

      if (!widget.isAdmin &&
          !DocuTrackerDocumentVisibility.isVisible(
            doc: widget.document,
            userId: userId,
            routingForDocument: _routingRecords,
          )) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You do not have access to this document. '
              'Only the creator, current assignee, or step reviewers can open it.',
            ),
          ),
        );
        Navigator.of(context).pop();
        return;
      }

      // Load audit trail eagerly; we'll still hide it if permissions deny access.
      provider.loadDocumentHistory(docId);
      await provider.loadRoutingConfigs();
      // Keep shared notification badges in sync while this screen is open.
      await provider.loadNotifications();
      final effectiveDoc = _resolveDocForView(provider);
      final docType = documentTypeFromString(effectiveDoc.documentType);
      final workflowIssue = provider.workflowConfigIssueForType(docType);
      if (mounted) setState(() => _workflowConfigIssue = workflowIssue);
      await _refreshEffectivePermissions(
        doc: effectiveDoc,
        auth: auth,
        isAdmin: widget.isAdmin,
      );

      // Poll for server-side workflow changes (escalation, overdue transitions).
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
        if (!mounted) return;
        final provider = context.read<DocuTrackerProvider>();
        final auth = context.read<AuthProvider>();
        final docId = widget.document.id!;

        await provider.refreshDocument(docId, reloadHistory: true);
        _routingRecords = await repo.getDocumentRoutingRecords(docId);
        if (!mounted) return;
        DocuTrackerDocument? updatedDoc;
        for (final d in provider.documents) {
          if (d.id == docId) {
            updatedDoc = d;
            break;
          }
        }
        if (!mounted) return;
        if (updatedDoc == null) return;

        await _refreshEffectivePermissions(
          doc: updatedDoc,
          auth: auth,
          isAdmin: widget.isAdmin,
        );
      });
    });
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _noteController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _showActionError(
    DocuTrackerProvider provider, {
    required String fallback,
  }) {
    showDocuTrackerProviderError(context, provider, fallback: fallback);
  }

  void _onWorkflowActionSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  DocuTrackerWorkflowPhase _workflowPhaseFor(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
  ) {
    final cfg = _routingConfigFor(provider, doc);
    final steps = (cfg?.steps ?? const <WorkflowStep>[])
        .where((s) => s.enabled)
        .toList();
    final current = doc.currentStep ?? 1;
    String? stepLabel;
    for (final s in steps) {
      if (s.stepOrder == current) {
        stepLabel = s.label;
        break;
      }
    }
    return DocuTrackerWorkflowPhase.forDocument(
      doc: doc,
      totalEnabledSteps: steps.isEmpty ? null : steps.length,
      currentStepLabel: stepLabel,
    );
  }

  Widget _buildWorkflowConfigBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.overduePink,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(
          color: DocuTrackerTokens.overdueAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.account_tree_outlined,
            color: DocuTrackerTokens.terracotta,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: DocuTrackerTokens.subtitleStyle(context).copyWith(
                color: DocuTrackerTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildWorkflowGuidance({
    required DocuTrackerDocument doc,
    required String userId,
    required bool showYourTurn,
    required bool isAssignedReviewer,
    List<String> assigneeNames = const [],
  }) {
    final terminal =
        doc.status == DocumentStatus.approved ||
        doc.status == DocumentStatus.rejected ||
        doc.status == DocumentStatus.cancelled;
    if (terminal || _permissionsLoading) return null;

    final phase = _workflowPhaseFor(doc, context.read<DocuTrackerProvider>());
    final isWip = DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
    final isCreator = doc.createdBy == userId;
    final messages = <String>[];

    if (isWip && isCreator) {
      if (_canSubmitAction) {
        messages.add('Submit this draft to start the approval workflow.');
      } else {
        final exp = _permissionExplanations[DocumentAction.submit.value];
        if (exp != null) {
          messages.add(
            docuTrackerPermissionReasonLabel(
              exp,
              action: DocumentAction.submit,
            ),
          );
        }
      }
    } else if (!showYourTurn) {
      if (assigneeNames.isNotEmpty) {
        messages.add('Waiting on: ${assigneeNames.join(', ')}.');
      } else if (doc.creatorName != null && doc.creatorName!.isNotEmpty) {
        messages.add('With ${doc.creatorName} or the assigned reviewer.');
      } else {
        messages.add('Waiting for the assigned reviewer on this step.');
      }
    }

    if (isAssignedReviewer && !showYourTurn && !_canApproveAction) {
      final exp = _permissionExplanations[DocumentAction.approve.value];
      if (exp != null && !exp.granted) {
        messages.add(
          docuTrackerPermissionReasonLabel(exp, action: DocumentAction.approve),
        );
      }
    }

    if (messages.isEmpty && phase.detail == null) return null;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DocuTrackerDetailActionBanner(
        title: phase.label,
        subtitle: [
          if (phase.detail != null) phase.detail!,
          ...messages,
        ].join('\n'),
        icon: Icons.route_rounded,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();
    final docId = widget.document.id;
    final doc = docId != null ? _resolveDocForView(provider) : widget.document;
    final userId = auth.user?.id ?? '';
    final isPending = doc.status == DocumentStatus.pending;
    final isCreator = doc.createdBy == userId;
    final isWip = DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
    final canAct =
        doc.status != DocumentStatus.approved &&
        doc.status != DocumentStatus.rejected &&
        doc.status != DocumentStatus.cancelled;

    final currentStep = doc.currentStep ?? 1;
    final currentRouting = _routingRecords
        .where((r) => r.stepOrder == currentStep)
        .cast<DocumentRoutingRecord?>()
        .firstWhere((_) => true, orElse: () => null);

    // isAssignedReviewer is true when:
    // 1. current_holder matches this user (legacy single-holder), OR
    // 2. user appears in routing_record_assignees snapshot (primary + backup)
    // We gate on !_routingLoading so buttons don't flash-hide before data loads.
    final isAssignedReviewer =
        !_routingLoading &&
        userId.isNotEmpty &&
        (doc.currentHolderId == userId ||
            (currentRouting?.assigneeIds.contains(userId) ?? false) ||
            // Fallback for legacy docs where snapshot table may be empty but holder is set.
            (currentRouting == null && doc.currentHolderId == userId));

    final workflowReady = _workflowConfigIssue == null;
    final canSubmit =
        workflowReady && canAct && _canSubmitAction && isCreator && isWip;

    // Review actions only valid if NOT pending and workflow is configured.
    final canApprove =
        workflowReady && !isPending && canAct && _canApproveAction;
    final canForward =
        workflowReady && !isPending && canAct && _canForwardAction;
    final canReject = workflowReady && !isPending && canAct && _canRejectAction;
    final canReturn = workflowReady && !isPending && canAct && _canReturnAction;

    final showYourTurn =
        canAct &&
        !_permissionsLoading &&
        userId.isNotEmpty &&
        (isAssignedReviewer || canSubmit);

    final showActions =
        _shouldShowActionsPanel(
          doc,
          canApprove: canApprove,
          canForward: canForward,
          canReject: canReject,
          canReturn: canReturn,
        ) ||
        canSubmit;

    return Scaffold(
      backgroundColor: DocuTrackerTokens.canvasOf(context),
      body: SingleChildScrollView(
        child: DocuTrackerResponsiveBody(
          maxWidth: DocuTrackerTokens.maxContentWidth,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroHeader(
                doc,
                showYourTurn,
                userId: userId,
                isAssignedReviewer: isAssignedReviewer,
                assigneeNames: currentRouting?.assigneeNames ?? const [],
              ),
              if (_workflowConfigIssue != null) ...[
                const SizedBox(height: 16),
                _buildWorkflowConfigBanner(_workflowConfigIssue!),
              ],
              if (provider.error != null) ...[
                const SizedBox(height: 16),
                DocuTrackerErrorBanner(
                  message: provider.error!,
                  onDismiss: () => provider.clearError(),
                ),
              ],
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 720;
                  final actionsCard = showActions
                      ? _buildActionsCard(
                          doc,
                          provider,
                          userId,
                          canAct,
                          canSubmit,
                          canApprove: canApprove,
                          canForward: canForward,
                          canReject: canReject,
                          canReturn: canReturn,
                        )
                      : null;

                  final leftColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWorkflowSection(doc, provider, userId),
                      const SizedBox(height: 24),
                      _buildHistorySection(provider, doc, userId),
                    ],
                  );

                  final rightColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (actionsCard != null) ...[
                        actionsCard,
                        const SizedBox(height: 24),
                      ],
                      if (_isLinkedLeave(doc)) ...[
                        _buildLinkedLeaveSection(doc, userId),
                        const SizedBox(height: 24),
                      ],
                      _buildAttachmentSection(doc),
                      const SizedBox(height: 24),
                      _buildDocumentInfoSection(doc),
                    ],
                  );

                  if (isDesktop) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: leftColumn),
                        const SizedBox(width: 32),
                        Expanded(flex: 4, child: rightColumn),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (actionsCard != null) ...[
                        actionsCard,
                        const SizedBox(height: 24),
                      ],
                      _buildWorkflowSection(doc, provider, userId),
                      const SizedBox(height: 24),
                      if (_isLinkedLeave(doc)) ...[
                        _buildLinkedLeaveSection(doc, userId),
                        const SizedBox(height: 24),
                      ],
                      _buildAttachmentSection(doc),
                      const SizedBox(height: 24),
                      _buildDocumentInfoSection(doc),
                      const SizedBox(height: 24),
                      _buildHistorySection(provider, doc, userId),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(
    DocuTrackerDocument doc,
    bool showYourTurn, {
    required String userId,
    required bool isAssignedReviewer,
    List<String> assigneeNames = const [],
  }) {
    final typeName = documentTypeFromString(doc.documentType).displayName;
    final isDraft = DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
    final isTerminal =
        doc.status == DocumentStatus.approved ||
        doc.status == DocumentStatus.rejected ||
        doc.status == DocumentStatus.cancelled;
    final currentStepValue = switch (doc.status) {
      DocumentStatus.approved => 'Completed at Step ${doc.currentStep ?? 1}',
      DocumentStatus.rejected => 'Stopped at Step ${doc.currentStep ?? 1}',
      DocumentStatus.cancelled => 'Cancelled',
      DocumentStatus.returned => 'Returned to Step ${doc.currentStep ?? 1}',
      _ => isDraft ? 'Not submitted' : 'Step ${doc.currentStep ?? 1}',
    };
    final currentAssigneeValue = isTerminal
        ? 'No active assignee'
        : doc.assigneeName?.trim().isNotEmpty == true
        ? doc.assigneeName!.trim()
        : (isDraft ? 'Not submitted' : 'Unassigned');
    final backupNames = isTerminal
        ? const <String>[]
        : assigneeNames
              .where(
                (name) => name.trim().isNotEmpty && name != doc.assigneeName,
              )
              .toList();
    final phase = _workflowPhaseFor(doc, context.read<DocuTrackerProvider>());
    final guidance = _buildWorkflowGuidance(
      doc: doc,
      userId: userId,
      showYourTurn: showYourTurn,
      isAssignedReviewer: isAssignedReviewer,
      assigneeNames: assigneeNames,
    );

    String deadlineLabel = '';
    Color deadlineColor = const Color(0xFF6B7280);
    IconData deadlineIcon = Icons.schedule_rounded;
    if (doc.deadlineTime == null && doc.status == DocumentStatus.pending) {
      deadlineLabel = 'Awaiting submission';
      deadlineColor = const Color(0xFF9CA3AF);
      deadlineIcon = Icons.edit_note_rounded;
    } else if (doc.deadlineTime != null &&
        doc.status != DocumentStatus.approved &&
        doc.status != DocumentStatus.rejected) {
      final diff = doc.deadlineTime!.difference(DateTime.now());
      if (diff.isNegative) {
        deadlineLabel = 'Overdue';
        deadlineColor = const Color(0xFFDC2626);
        deadlineIcon = Icons.warning_amber_rounded;
      } else {
        final d = diff.inDays;
        final h = diff.inHours % 24;
        deadlineLabel = d > 0
            ? '$d days left'
            : (h > 0
                  ? '${diff.inHours}h left'
                  : '${diff.inMinutes % 60}m left');
        if (diff.inHours < 24) {
          deadlineColor = const Color(0xFFEA580C);
        }
      }
    }

    final provider = context.read<DocuTrackerProvider>();
    final currentStep = doc.currentStep ?? 1;
    final currentStepLabel =
        (_routingConfigFor(provider, doc)?.steps ?? const <WorkflowStep>[])
            .where((s) => s.enabled && s.stepOrder == currentStep)
            .map((s) => s.label?.trim() ?? '')
            .firstWhere((label) => label.isNotEmpty, orElse: () => '');
    final stepValue = !isDraft && !isTerminal && currentStepLabel.isNotEmpty
        ? '$currentStep. $currentStepLabel'
        : currentStepValue;
    final stepSub = isDraft
        ? 'Draft stage'
        : isTerminal
        ? doc.status.displayName
        : phase.label;
    final creatorName = doc.creatorName?.trim().isNotEmpty == true
        ? doc.creatorName!.trim()
        : null;
    final assigneeValue = isDraft
        ? (creatorName ?? currentAssigneeValue)
        : currentAssigneeValue;
    final assigneeSub = isDraft
        ? 'Document owner'
        : backupNames.isNotEmpty
        ? 'Backup: ${backupNames.join(', ')}'
        : (isTerminal ? 'Workflow finished' : 'Current reviewer');
    final lastSaved = doc.updatedAt ?? doc.createdAt;
    final versionSub = doc.workflowVersion == null
        ? ''
        : 'Workflow version ${doc.workflowVersion}${isDraft ? ' (Draft)' : ''}';
    final busy = provider.loading;

    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!doc.sourceOnly)
          OutlinedButton.icon(
            key: const ValueKey('docutracker-detail-preview'),
            onPressed: busy ? null : () => _openPrimaryDocument(doc),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Preview'),
            style: DocuTrackerStyles.outlinedButtonStyle(),
          ),
        FilledButton.icon(
          onPressed: busy ? null : () => _openPrimaryDocument(doc),
          icon: const Icon(Icons.article_outlined, size: 18),
          label: Text(
            doc.sourceOnly ? 'Open Source Document' : 'Open Document',
          ),
          style: DocuTrackerStyles.primaryBrandButtonStyle(),
        ),
      ],
    );

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DocuTrackerDetailTag(label: typeName.toUpperCase()),
            if (doc.documentNumber != null)
              DocuTrackerDetailTag(label: doc.documentNumber!),
            DocuTrackerStatusBadge(
              status: doc.status,
              compact: true,
              dotStyle: true,
              label: doc.status == DocumentStatus.pending && isDraft
                  ? 'Draft'
                  : null,
            ),
            if (deadlineLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: deadlineColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: deadlineColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(deadlineIcon, size: 12, color: deadlineColor),
                    const SizedBox(width: 4),
                    Text(
                      deadlineLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: deadlineColor,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          doc.title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.textPrimaryOf(context),
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        if (creatorName != null) ...[
          const SizedBox(height: 6),
          Text(
            'Initiated by $creatorName',
            style: DocuTrackerTokens.subtitleStyle(context),
          ),
        ],
      ],
    );

    final summaryCells = <Widget>[
      _HeroSummaryCell(
        label: 'CURRENT STEP',
        value: stepValue,
        sub: stepSub,
        leading: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: DocuTrackerTokens.brand,
            shape: BoxShape.circle,
          ),
        ),
      ),
      _HeroSummaryCell(
        label: 'PRIMARY ASSIGNEE',
        value: assigneeValue,
        sub: assigneeSub,
        leading: CircleAvatar(
          radius: 11,
          backgroundColor: DocuTrackerTokens.brandSoft,
          child: Text(
            _getInitials(assigneeValue),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: DocuTrackerTokens.brand,
            ),
          ),
        ),
      ),
      _HeroSummaryCell(
        label: 'TARGET DEADLINE',
        value: doc.deadlineTime == null
            ? 'No deadline'
            : _formatDateTime(doc.deadlineTime!),
        sub: deadlineLabel,
        subColor: deadlineLabel.isEmpty ? null : deadlineColor,
      ),
      _HeroSummaryCell(
        label: 'LAST SAVED',
        value: lastSaved == null ? 'Not available' : _formatDateTime(lastSaved),
        sub: versionSub,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: const ValueKey('docutracker-detail-breadcrumbs'),
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 16,
                      color: DocuTrackerTokens.textMuted,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Back to documents',
                      style: TextStyle(
                        color: DocuTrackerTokens.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Text('/', style: TextStyle(color: Color(0xFFD1D5DB))),
            Text(
              typeName,
              style: const TextStyle(
                color: DocuTrackerTokens.textMuted,
                fontSize: 13,
              ),
            ),
            if (doc.documentNumber != null) ...[
              const Text('/', style: TextStyle(color: Color(0xFFD1D5DB))),
              DocuTrackerDetailTag(label: doc.documentNumber!),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: DocuTrackerTokens.cardDecoration(context: context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: titleBlock),
                        const SizedBox(width: 16),
                        actionButtons,
                      ],
                    )
                  else ...[
                    titleBlock,
                    const SizedBox(height: 14),
                    actionButtons,
                  ],
                  const SizedBox(height: 20),
                  if (constraints.maxWidth >= 900)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < summaryCells.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(child: summaryCells[i]),
                          ],
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final cell in summaryCells)
                          SizedBox(
                            width: wide
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth,
                            child: cell,
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
        if (doc.status == DocumentStatus.approved ||
            doc.status == DocumentStatus.rejected) ...[
          const SizedBox(height: 16),
          DocuTrackerStyles.stateMessage(
            icon: doc.status == DocumentStatus.approved
                ? Icons.verified_rounded
                : Icons.gpp_bad_rounded,
            color: doc.status == DocumentStatus.approved
                ? const Color(0xFF047857)
                : const Color(0xFFB91C1C),
            message: doc.status == DocumentStatus.approved
                ? 'This workflow is complete.'
                : 'This document was rejected and cannot move forward.',
          ),
        ],
        if (showYourTurn) ...[
          const SizedBox(height: 20),
          DocuTrackerDetailActionBanner(
            title: 'Action required: Your turn',
            subtitle: phase.detail != null
                ? 'You are the assigned reviewer for this step. ${phase.detail}'
                : 'You are the assigned reviewer — submit your decision or add a remark.',
          ),
        ] else if (guidance != null)
          guidance,
      ],
    );
  }

  DocumentRoutingConfig? _routingConfigFor(
    DocuTrackerProvider provider,
    DocuTrackerDocument doc,
  ) {
    final dt = documentTypeFromString(doc.documentType);
    final fromProvider = provider.getRoutingConfigForType(dt);
    if (fromProvider != null) return fromProvider;
    for (final c in DocumentRoutingConfig.defaults) {
      if (c.documentType == dt) return c;
    }
    return null;
  }

  bool _shouldShowActionsPanel(
    DocuTrackerDocument doc, {
    required bool canApprove,
    required bool canForward,
    required bool canReject,
    required bool canReturn,
  }) {
    if (_permissionsLoading) return false;
    final quickAccess =
        (_canEdit &&
            DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc)) ||
        _canDownloadAttachment;
    final terminal =
        doc.status == DocumentStatus.approved ||
        doc.status == DocumentStatus.rejected;
    if (terminal) return _canDownloadAttachment;
    return canApprove || canReject || canReturn || canForward || quickAccess;
  }

  Widget _buildAttachmentSection(DocuTrackerDocument doc) {
    if (_permissionsLoading) return const SizedBox.shrink();
    return DocuTrackerDocumentAttachmentPanel(
      document: doc,
      canDownload: _canDownloadAttachment,
      canModify: _canModifyAttachment,
    );
  }

  Widget _buildDocumentInfoSection(DocuTrackerDocument doc) {
    return DocuTrackerDetailSectionCard(
      icon: Icons.description_outlined,
      title: 'Document Details',
      subtitle: 'Reference and audit metadata',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Reference', value: doc.documentNumber ?? '—'),
          _InfoRow(
            label: 'Type',
            value: documentTypeFromString(doc.documentType).displayName,
          ),
          _InfoRow(
            label: 'Sender',
            value: doc.creatorName ?? doc.createdBy ?? '—',
          ),
          _InfoRow(
            label: 'Created',
            value: doc.createdAt != null
                ? _formatDateTime(doc.createdAt!)
                : '—',
          ),
          if (doc.workflowVersion != null)
            _InfoRow(label: 'Version', value: '${doc.workflowVersion}'),
          if (doc.description != null && doc.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'DESCRIPTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: DocuTrackerTokens.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            DocuTrackerPeachDashedBox(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                doc.description!,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: DocuTrackerTokens.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showWorkflowMapDialog(List<WorkflowStep> steps, int current) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workflow map'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in steps) ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: s.stepOrder == current
                          ? DocuTrackerTokens.brand
                          : s.stepOrder < current
                          ? DocuTrackerTokens.brandSoft
                          : DocuTrackerTokens.borderSubtle,
                      child: Text(
                        '${s.stepOrder}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: s.stepOrder == current
                              ? Colors.white
                              : DocuTrackerTokens.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.label ?? 'Step ${s.stepOrder}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (s != steps.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowSection(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
    String currentUserId,
  ) {
    final cfg = _routingConfigFor(provider, doc);
    final steps =
        (cfg?.steps ?? const <WorkflowStep>[]).where((s) => s.enabled).toList()
          ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final current = doc.currentStep ?? 1;
    final currentRouting = _routingRecords
        .where((r) => r.stepOrder == current)
        .cast<DocumentRoutingRecord?>()
        .firstWhere((_) => true, orElse: () => null);
    final assigneeNames = currentRouting?.assigneeNames ?? const <String>[];
    // Same logic as the build() permission gate: include both holder and snapshot assignees.
    final isAssignedReviewer =
        !_routingLoading &&
        currentUserId.isNotEmpty &&
        (doc.currentHolderId == currentUserId ||
            (currentRouting?.assigneeIds.contains(currentUserId) ?? false) ||
            (currentRouting == null && doc.currentHolderId == currentUserId));
    final phase = _workflowPhaseFor(doc, provider);
    final stepSubtitle = phase.detail ?? phase.label;

    return DocuTrackerDetailSectionCard(
      icon: Icons.account_tree_outlined,
      title: 'Workflow & Routing',
      subtitle: stepSubtitle,
      trailing: steps.isEmpty
          ? null
          : TextButton(
              onPressed: () => _showWorkflowMapDialog(steps, current),
              style: TextButton.styleFrom(
                foregroundColor: DocuTrackerTokens.brand,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              child: const Text('View full map'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (steps.isNotEmpty) ...[
            _WorkflowStepStrip(
              steps: steps,
              document: doc,
              history: provider.documentHistory,
            ),
            const SizedBox(height: 20),
          ],
          _CurrentAssignmentCard(
            reviewers: assigneeNames,
            youAreAssigned: isAssignedReviewer,
            primaryHolderName: doc.assigneeName,
            primaryHolderId: doc.currentHolderId,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
    String userId,
    bool canAct,
    bool canSubmit, {
    required bool canApprove,
    required bool canForward,
    required bool canReject,
    required bool canReturn,
  }) {
    final enabledSteps =
        _routingConfigFor(
          provider,
          doc,
        )?.steps.where((step) => step.enabled).toList() ??
        const <WorkflowStep>[];
    final isFinalStep =
        enabledSteps.isNotEmpty &&
        doc.currentStep ==
            enabledSteps.map((step) => step.stepOrder).reduce(max);
    final currentStepRequiresSignature = enabledSteps.any(
      (step) => step.stepOrder == doc.currentStep && step.requiresSignature,
    );
    final primaryActions = <Widget>[
      if (canAct && canSubmit)
        Tooltip(
          message: 'Submit document to start the workflow',
          child: FilledButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
                    final confirmed = await _confirmWorkflowAction(
                      title: 'Submit draft?',
                      message:
                          'This starts the workflow and sends the document to the first assignee.',
                      confirmLabel: 'Submit Draft',
                    );
                    if (!confirmed || !mounted) return;
                    final ok = await provider.submitDocument(
                      doc,
                      actionBy: userId,
                      remarks: _remarkController.text,
                    );
                    if (!mounted) return;
                    if (ok) {
                      _onWorkflowActionSuccess(
                        'Document submitted successfully.',
                      );
                    } else {
                      _showActionError(
                        provider,
                        fallback: 'Failed to submit document.',
                      );
                    }
                  },
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Submit Draft'),
            style: DocuTrackerStyles.primaryBrandButtonStyle().copyWith(
              minimumSize: WidgetStateProperty.all(
                const Size(double.infinity, 48),
              ),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      if (canAct && canApprove)
        Tooltip(
          message: 'Approve this document to advance workflow',
          child: FilledButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
                    final confirmed = await _confirmWorkflowAction(
                      title: isFinalStep
                          ? 'Approve and complete?'
                          : 'Approve and continue?',
                      message: isFinalStep
                          ? 'This completes the workflow.'
                          : 'This sends the document to the next workflow step.',
                      confirmLabel: isFinalStep
                          ? 'Approve and Complete'
                          : 'Approve and Continue',
                    );
                    if (!confirmed || !mounted) return;
                    final ok = await provider.approveDocument(
                      doc,
                      actionBy: userId,
                      remarks: _remarkController.text,
                    );
                    if (!mounted) return;
                    if (ok) {
                      _onWorkflowActionSuccess('Document approved.');
                    } else {
                      _showActionError(
                        provider,
                        fallback: 'Failed to approve document.',
                      );
                    }
                  },
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: Text(
              isFinalStep ? 'Approve and Complete' : 'Approve and Continue',
            ),
            style: DocuTrackerStyles.approveButtonStyle().copyWith(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
    ];

    final secondaryActions = <Widget>[
      if (canAct && canForward)
        Tooltip(
          message: 'Send document to the next recipient',
          child: OutlinedButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
                    final ok = await provider.forwardDocument(
                      doc,
                      actionBy: userId,
                      remarks: _remarkController.text.trim().isEmpty
                          ? null
                          : _remarkController.text.trim(),
                    );
                    if (!mounted) return;
                    if (ok) {
                      _onWorkflowActionSuccess('Document forwarded.');
                    } else {
                      _showActionError(
                        provider,
                        fallback: 'Failed to forward document.',
                      );
                    }
                  },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Forward Without Approval'),
            style: DocuTrackerStyles.secondaryButtonStyle(),
          ),
        ),
      if (canAct && canReturn)
        Tooltip(
          message: 'Send back to sender for corrections',
          child: OutlinedButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
                    final returnCtrl = TextEditingController();
                    try {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Return document'),
                          content: TextField(
                            controller: returnCtrl,
                            decoration: DocuTrackerStyles.inputDecoration(
                              context,
                              'Reason for return (optional)',
                              Icons.reply_rounded,
                            ),
                            maxLines: 3,
                          ),
                          actions: [
                            OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: DocuTrackerStyles.outlinedButtonStyle(),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                final remarks = returnCtrl.text.trim();
                                Navigator.of(ctx).pop();
                                final ok = await provider.returnDocument(
                                  doc,
                                  remarks: remarks.isEmpty ? null : remarks,
                                  actionBy: userId,
                                );
                                if (!mounted) return;
                                if (ok) {
                                  _onWorkflowActionSuccess(
                                    'Document returned.',
                                  );
                                } else {
                                  _showActionError(
                                    provider,
                                    fallback: 'Failed to return document.',
                                  );
                                }
                              },
                              style: DocuTrackerStyles.primaryButtonStyle(),
                              child: const Text('Return'),
                            ),
                          ],
                        ),
                      );
                    } finally {
                      returnCtrl.dispose();
                    }
                  },
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: const Text('Return for Changes'),
            style: DocuTrackerStyles.warningButtonStyle(),
          ),
        ),
      if (canAct && canReject)
        Tooltip(
          message: 'Terminate document workflow permanently',
          child: FilledButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
                    final remarkCtrl = TextEditingController();
                    try {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Reject document'),
                          content: TextField(
                            controller: remarkCtrl,
                            autofocus: true,
                            decoration: DocuTrackerStyles.inputDecoration(
                              context,
                              'Reason for rejection (required)',
                              Icons.cancel_rounded,
                            ),
                            maxLines: 3,
                          ),
                          actions: [
                            OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: DocuTrackerStyles.outlinedButtonStyle(),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                final remarks = remarkCtrl.text.trim();
                                if (remarks.isEmpty) return;
                                Navigator.of(ctx).pop();
                                final ok = await provider.rejectDocument(
                                  doc,
                                  remarks: remarks,
                                  actionBy: userId,
                                );
                                if (!mounted) return;
                                if (ok) {
                                  _onWorkflowActionSuccess(
                                    'Document rejected.',
                                  );
                                } else {
                                  _showActionError(
                                    provider,
                                    fallback: 'Failed to reject document.',
                                  );
                                }
                              },
                              style: DocuTrackerStyles.destructiveButtonStyle(),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      );
                    } finally {
                      remarkCtrl.dispose();
                    }
                  },
            icon: const Icon(Icons.cancel_rounded, size: 18),
            label: const Text('Reject and Stop'),
            style: DocuTrackerStyles.destructiveButtonStyle(),
          ),
        ),
    ];

    final isDraft = DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
    final showQuickAccess = (_canEdit && isDraft) || _canDownloadAttachment;
    final forwardActions = canForward
        ? secondaryActions.take(1).toList(growable: false)
        : const <Widget>[];
    final moreWorkflowActions = secondaryActions
        .skip(forwardActions.length)
        .toList(growable: false);
    final hasMoreActions = showQuickAccess || moreWorkflowActions.isNotEmpty;

    Widget fullWidth(Widget child) =>
        SizedBox(width: double.infinity, child: child);

    return DocuTrackerDetailSectionCard(
      icon: Icons.touch_app_outlined,
      title: 'Workflow Actions',
      subtitle: 'Available actions for this workflow step',
      trailing: enabledSteps.isEmpty || isDraft
          ? null
          : Text(
              'Step ${doc.currentStep ?? 1}/${enabledSteps.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (provider.loading) ...[
            DocuTrackerStyles.stateMessage(
              icon: Icons.hourglass_top_rounded,
              color: DocuTrackerTokens.brand,
              message: 'Processing action… please wait.',
            ),
            const SizedBox(height: 12),
          ],
          if (canAct &&
              (canApprove || canForward) &&
              currentStepRequiresSignature) ...[
            KeyedSubtree(
              key: const Key('docutracker-detail-signature-required'),
              child: DocuTrackerStyles.stateMessage(
                icon: Icons.draw_outlined,
                color: const Color(0xFF7C3AED),
                message:
                    'This step requires your signature. Open the document, '
                    'use Signatures → Insert My Signature, then approve or '
                    'forward.',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (canAct && (canApprove || canForward)) ...[
            TextField(
              controller: _remarkController,
              maxLines: 2,
              decoration: DocuTrackerStyles.inputDecoration(
                context,
                'Optional note for next recipient…',
                Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 14),
          ],
          for (final w in primaryActions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: fullWidth(w),
            ),
          for (final w in forwardActions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: fullWidth(w),
            ),
          if (hasMoreActions)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text('More'),
              children: [
                if (showQuickAccess)
                  Row(
                    children: [
                      if (_canEdit && isDraft)
                        Expanded(
                          child: _QuickAccessChip(
                            label: 'Edit Draft',
                            icon: Icons.edit_outlined,
                            onTap: provider.loading
                                ? null
                                : () => _showEditDraftDialog(
                                    doc,
                                    provider,
                                    userId,
                                  ),
                          ),
                        ),
                      if (_canEdit && isDraft && _canDownloadAttachment)
                        const SizedBox(width: 8),
                      if (_canDownloadAttachment)
                        Expanded(
                          child: _QuickAccessChip(
                            label: 'Download Attachment',
                            icon: Icons.download_rounded,
                            onTap: provider.loading || doc.filePath == null
                                ? null
                                : () => _downloadAttachment(doc, provider),
                          ),
                        ),
                    ],
                  ),
                for (final w in moreWorkflowActions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: fullWidth(w),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmWorkflowAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: DocuTrackerStyles.primaryBrandButtonStyle(),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _downloadAttachment(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
  ) async {
    final docId = doc.id;
    if (docId == null) return;
    final bytes = await provider.getAttachmentBytes(docId);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No attachment to download.')),
      );
      return;
    }
    final name = doc.fileName?.trim().isNotEmpty == true
        ? doc.fileName!.trim()
        : 'document.pdf';
    await openDocuTrackerAttachmentBytes(bytes, name);
  }

  void _showEditDraftDialog(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
    String userId,
  ) {
    final remarkCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit draft'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: remarkCtrl,
            autofocus: true,
            maxLines: 4,
            decoration: DocuTrackerStyles.inputDecoration(
              context,
              'Add a note about your draft changes',
              Icons.edit_outlined,
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final remarks = remarkCtrl.text.trim();
              if (remarks.isEmpty) return;
              Navigator.of(ctx).pop();
              final ok = await provider.addRemark(
                doc,
                actorId: userId,
                remarks: remarks,
              );
              if (!mounted) return;
              if (ok) {
                provider.loadDocumentHistory(doc.id!);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Remark saved to history.')),
                );
              } else {
                _showActionError(provider, fallback: 'Could not save remark.');
              }
            },
            style: DocuTrackerStyles.primaryBrandButtonStyle(),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(remarkCtrl.dispose);
  }

  List<DocumentHistoryEntry> _sortedHistory(List<DocumentHistoryEntry> raw) {
    final copy = [...raw];
    int key(DocumentHistoryEntry e) => e.createdAt?.millisecondsSinceEpoch ?? 0;
    copy.sort((a, b) => key(a).compareTo(key(b)));
    return copy;
  }

  Future<void> _postNote(
    DocuTrackerProvider provider,
    DocuTrackerDocument doc,
    String userId,
  ) async {
    final remarks = _noteController.text.trim();
    if (remarks.isEmpty || _postingNote) return;
    setState(() => _postingNote = true);
    final ok = await provider.addRemark(doc, actorId: userId, remarks: remarks);
    if (!mounted) return;
    setState(() => _postingNote = false);
    if (ok) {
      _noteController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note posted.')));
      provider.loadDocumentHistory(doc.id!);
    } else {
      _showActionError(provider, fallback: 'Failed to post note.');
    }
  }

  Widget _buildNoteComposer(
    DocuTrackerProvider provider,
    DocuTrackerDocument doc,
    String userId,
  ) {
    final busy = _postingNote || provider.loading;
    return Container(
      key: const Key('docutracker-detail-note-composer'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.canvasOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ADD INTERNAL NOTE FOR REVIEWERS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DocuTrackerTokens.textMutedOf(context),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            enabled: !busy,
            minLines: 2,
            maxLines: 4,
            decoration: DocuTrackerStyles.inputDecoration(
              context,
              'Write a note (logged to the audit trail)',
              Icons.edit_note_rounded,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('docutracker-detail-post-note'),
              onPressed: busy ? null : () => _postNote(provider, doc, userId),
              style: DocuTrackerStyles.primaryButtonStyle(),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Post Note'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    DocuTrackerProvider provider,
    DocuTrackerDocument doc,
    String userId,
  ) {
    final sorted = _sortedHistory(provider.documentHistory);
    final showCount = !_permissionsLoading && _canViewAuditTrail;

    return DocuTrackerDetailSectionCard(
      icon: Icons.history_rounded,
      title: 'Activity & Audit Trail',
      subtitle: 'Document updates, status changes, and decisions in order',
      trailing: showCount
          ? Text(
              '${sorted.length} ${sorted.length == 1 ? 'event' : 'events'} logged',
              style: DocuTrackerTokens.metaStyle(context),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_permissionsLoading && _canEdit && userId.isNotEmpty) ...[
            _buildNoteComposer(provider, doc, userId),
            const SizedBox(height: 16),
          ],
          if (_permissionsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (!_canViewAuditTrail)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'You do not have access to view this activity.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
            )
          else if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No history yet.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ),
            )
          else
            _Timeline(entries: sorted),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

String _getInitials(String name) {
  if (name.isEmpty) return '??';
  final parts = name.trim().split(' ');
  if (parts.length >= 2) {
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }
  return parts[0][0].toUpperCase();
}

class _WorkflowStepStrip extends StatelessWidget {
  const _WorkflowStepStrip({
    required this.steps,
    required this.document,
    required this.history,
  });

  final List<WorkflowStep> steps;
  final DocuTrackerDocument document;
  final List<DocumentHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              _WorkflowStepNode(
                order: steps[i].stepOrder,
                label: steps[i].label ?? 'Step ${steps[i].stepOrder}',
                indicator: DocuTrackerWorkflowPhase.indicatorForStep(
                  doc: document,
                  stepOrder: steps[i].stepOrder,
                  history: history,
                ),
              ),
              if (i < steps.length - 1)
                Container(
                  margin: const EdgeInsets.only(top: 14, left: 4, right: 4),
                  width: 40,
                  height: 2,
                  color:
                      DocuTrackerWorkflowPhase.indicatorForStep(
                        doc: document,
                        stepOrder: steps[i].stepOrder,
                        history: history,
                      ).isCompleted
                      ? DocuTrackerTokens.brand
                      : DocuTrackerTokens.borderSubtle,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowStepNode extends StatelessWidget {
  const _WorkflowStepNode({
    required this.order,
    required this.label,
    required this.indicator,
  });

  final int order;
  final String label;
  final DocuTrackerStepIndicator indicator;

  @override
  Widget build(BuildContext context) {
    final isCurrent = indicator.kind == DocuTrackerStepIndicatorKind.current;
    final isDone = indicator.isCompleted;
    final isReturned = indicator.kind == DocuTrackerStepIndicatorKind.returned;
    final isRejected = indicator.kind == DocuTrackerStepIndicatorKind.rejected;
    final isOverdue = indicator.kind == DocuTrackerStepIndicatorKind.overdue;
    final isEscalated =
        indicator.kind == DocuTrackerStepIndicatorKind.escalated;
    final isCancelled =
        indicator.kind == DocuTrackerStepIndicatorKind.cancelled;

    final statusColor = switch (indicator.kind) {
      DocuTrackerStepIndicatorKind.approved => const Color(0xFF047857),
      DocuTrackerStepIndicatorKind.forwarded => DocuTrackerTokens.brand,
      DocuTrackerStepIndicatorKind.returned => const Color(0xFFB45309),
      DocuTrackerStepIndicatorKind.rejected => const Color(0xFFB91C1C),
      DocuTrackerStepIndicatorKind.overdue => const Color(0xFFDC2626),
      DocuTrackerStepIndicatorKind.escalated => const Color(0xFF7C3AED),
      DocuTrackerStepIndicatorKind.cancelled => DocuTrackerTokens.textMuted,
      DocuTrackerStepIndicatorKind.current => DocuTrackerTokens.brand,
      _ => DocuTrackerTokens.textMuted,
    };
    final emphasized =
        isCurrent ||
        isDone ||
        isReturned ||
        isRejected ||
        isOverdue ||
        isEscalated ||
        isCancelled;
    final nodeColor = emphasized ? statusColor : DocuTrackerTokens.surfaceCream;
    final borderColor = emphasized
        ? statusColor
        : DocuTrackerTokens.borderStrong;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: nodeColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: isCurrent || isReturned || isOverdue || isEscalated
                ? [
                    BoxShadow(
                      color: DocuTrackerTokens.brand.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : Text(
                    order.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: emphasized
                          ? Colors.white
                          : DocuTrackerTokens.textMuted,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 88,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              color: DocuTrackerTokens.textPrimary,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          indicator.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: statusColor,
          ),
        ),
      ],
    );
  }
}

class _CurrentAssignmentCard extends StatelessWidget {
  const _CurrentAssignmentCard({
    required this.reviewers,
    required this.youAreAssigned,
    this.primaryHolderName,
    this.primaryHolderId,
  });

  final List<String> reviewers;
  final bool youAreAssigned;
  final String? primaryHolderName;
  final String? primaryHolderId;

  @override
  Widget build(BuildContext context) {
    final primaryName = primaryHolderName?.trim().isNotEmpty == true
        ? primaryHolderName!.trim()
        : (reviewers.isNotEmpty ? reviewers.first : null);
    final backupNames = reviewers
        .where((name) => name.trim().isNotEmpty && name != primaryName)
        .toList();
    final hasLegacyHolder =
        (primaryHolderName != null && primaryHolderName!.trim().isNotEmpty) ||
        (primaryHolderId != null && primaryHolderId!.isNotEmpty);

    if (reviewers.isEmpty && !hasLegacyHolder) {
      return DocuTrackerPeachDashedBox(
        child: Text(
          'No reviewers recorded for this step.',
          style: DocuTrackerTokens.subtitleStyle(context),
        ),
      );
    }

    return DocuTrackerPeachDashedBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (youAreAssigned)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.person_pin_circle_rounded,
                    size: 18,
                    color: DocuTrackerTokens.brand,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You are assigned to this step',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DocuTrackerTokens.brand,
                    ),
                  ),
                ],
              ),
            ),
          if (primaryName != null) ...[
            const Text(
              'Primary assignee',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Chip(
              avatar: CircleAvatar(
                backgroundColor: DocuTrackerTokens.brandSoft,
                child: Text(
                  primaryName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.brand,
                  ),
                ),
              ),
              label: Text(
                primaryName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Colors.white,
              side: const BorderSide(color: DocuTrackerTokens.borderSubtle),
              visualDensity: VisualDensity.compact,
            ),
            if (backupNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Backup assignee',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DocuTrackerTokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: backupNames
                    .map((name) => Chip(label: Text(name)))
                    .toList(),
              ),
            ],
          ],
          if (hasLegacyHolder && reviewers.isEmpty) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: DocuTrackerTokens.brandSoft,
                  child: Icon(
                    Icons.person,
                    size: 16,
                    color: DocuTrackerTokens.brand,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryHolderName ?? 'Unknown user',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DocuTrackerTokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: DocuTrackerTokens.metaStyle(
                context,
              ).copyWith(fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: DocuTrackerTokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});

  final List<DocumentHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          _TimelineItem(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final DocumentHistoryEntry entry;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isSystemEvent =
        entry.isOverdueLog ||
        entry.isEscalationLog ||
        entry.action == 'overdue' ||
        entry.action == 'escalated';
    final isPositive =
        entry.action == 'approved' ||
        entry.action == 'created' ||
        entry.action == 'forwarded';
    final isNegative = entry.action == 'rejected' || entry.action == 'returned';

    Color dotColor = const Color(0xFF6B7280);
    Color bgColor = Colors.white;
    Color borderColor = const Color(0xFFE4E7ED);

    if (isSystemEvent) {
      dotColor = const Color(0xFFF59E0B);
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
    } else if (isPositive) {
      dotColor = const Color(0xFF10B981);
    } else if (isNegative) {
      dotColor = const Color(0xFFEF4444);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Track
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: dotColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isSystemEvent
                        ? Icon(
                            entry.isEscalationLog
                                ? Icons.trending_up_rounded
                                : Icons.alarm_rounded,
                            size: 16,
                            color: dotColor,
                          )
                        : CircleAvatar(
                            radius: 14,
                            backgroundColor: dotColor.withValues(alpha: 0.1),
                            child: Text(
                              _getInitials(_actorDisplayName(entry)),
                              style: TextStyle(
                                color: dotColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: const Color(0xFFE5E7EB)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Content Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    if (!isSystemEvent)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            isSystemEvent
                                ? _actionLabel(entry.action)
                                : '${_actionLabel(entry.action)} by ${_actorDisplayName(entry)}',
                            style: TextStyle(
                              color: isSystemEvent
                                  ? const Color(0xFF92400E)
                                  : const Color(0xFF111827),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (entry.createdAt != null)
                          Text(
                            _formatEntryTime(entry.createdAt!),
                            style: TextStyle(
                              color: isSystemEvent
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF6B7280),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    if (entry.fromStep != null ||
                        entry.toStep != null ||
                        entry.fromStatus != null ||
                        entry.toStatus != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: DocuTrackerTokens.highlightPeach,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: DocuTrackerTokens.highlightPeachBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.fromStep != null || entry.toStep != null)
                              Text(
                                'Step: ${_stepLine(entry)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: DocuTrackerTokens.textSecondary,
                                ),
                              ),
                            if ((entry.fromStep != null ||
                                    entry.toStep != null) &&
                                (entry.fromStatus != null ||
                                    entry.toStatus != null))
                              const SizedBox(height: 6),
                            if (entry.fromStatus != null ||
                                entry.toStatus != null)
                              Text(
                                'Status: ${_statusLine(entry)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: DocuTrackerTokens.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (entry.remarks != null && entry.remarks!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: DocuTrackerTokens.highlightPeach,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: DocuTrackerTokens.highlightPeachBorder,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 4,
                                color: isSystemEvent
                                    ? DocuTrackerTokens.alertOrange
                                    : DocuTrackerStyles.primaryGreen,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    entry.remarks!,
                                    style: const TextStyle(
                                      color: DocuTrackerTokens.textSecondary,
                                      fontSize: 12,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _actionLabel(String? action) {
    return switch (action) {
      'created' => 'Document Created',
      'assigned' => 'Document assigned',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'returned' => 'Returned to sender',
      'forwarded' => 'Forwarded',
      'overdue' => 'Overdue',
      'escalated' => 'Escalated',
      'remark' => 'Remark added',
      _ => action ?? '—',
    };
  }

  String _actorDisplayName(DocumentHistoryEntry entry) {
    final name = entry.actorName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final id = entry.actorId?.trim();
    if (id != null && id.isNotEmpty) {
      return 'Employee';
    }
    return 'Employee';
  }

  static String _formatEntryTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} • '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _stepLine(DocumentHistoryEntry e) {
    if (e.fromStep != null && e.toStep != null) {
      return 'Step ${e.fromStep} → ${e.toStep}';
    }
    if (e.toStep != null) return 'Step ${e.toStep}';
    if (e.fromStep != null) return 'Step ${e.fromStep}';
    return '';
  }

  static String _statusLine(DocumentHistoryEntry e) {
    final from = e.fromStatus?.displayName;
    final to = e.toStatus?.displayName;
    if (from != null && to != null) return '$from → $to';
    if (to != null) return to;
    if (from != null) return from;
    return '';
  }
}

class _HeroSummaryCell extends StatelessWidget {
  const _HeroSummaryCell({
    required this.label,
    required this.value,
    this.sub = '',
    this.subColor,
    this.leading,
  });

  final String label;
  final String value;
  final String sub;
  final Color? subColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DocuTrackerTokens.textMutedOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DocuTrackerTokens.textPrimaryOf(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: subColor == null
                    ? FontWeight.w500
                    : FontWeight.w700,
                color: subColor ?? DocuTrackerTokens.textMutedOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAccessChip extends StatelessWidget {
  const _QuickAccessChip({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DocuTrackerTokens.highlightPeach,
      borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
            border: Border.all(color: DocuTrackerTokens.highlightPeachBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: DocuTrackerTokens.brand),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DocuTrackerTokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
