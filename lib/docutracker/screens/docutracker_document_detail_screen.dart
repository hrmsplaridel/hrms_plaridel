import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../docutracker_provider.dart';
import '../docutracker_styles.dart';
import '../docutracker_repository.dart';
import '../models/document.dart';
import '../models/document_action.dart';
import '../models/document_history.dart';
import '../models/document_routing_config.dart';
import '../models/document_routing_record.dart';
import '../models/document_status.dart';
import '../models/document_type.dart';
import '../models/workflow_step.dart';
import '../services/docutracker_document_visibility.dart';
import '../services/docutracker_permission_service.dart';
import '../theme/docutracker_tokens.dart';
import '../utils/docutracker_open_attachment.dart';
import '../utils/docutracker_permission_reason_label.dart';
import '../utils/docutracker_workflow_phase.dart';
import '../widgets/docutracker_document_attachment_panel.dart';
import '../widgets/docutracker_document_detail_ui.dart';
import '../widgets/docutracker_error_banner.dart';
import '../widgets/docutracker_responsive_body.dart';
import '../widgets/docutracker_status_badge.dart';

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
    final explanations = <String, bool>{};
    final explanationDetails = <String, DocuTrackerPermissionExplanation>{};
    for (final action in actions) {
      final exp = await repo.explainPermission(
        userId: userId,
        roleId: roleId,
        documentType: doc.documentType,
        action: action,
        documentId: documentId,
        isAdmin: isAdmin,
      );
      explanations[action] = exp.granted;
      explanationDetails[action] = exp;
    }
    if (!mounted) return;
    setState(() {
      _permissionExplanations = explanationDetails;
      _canViewAuditTrail = explanations[DocumentAction.view.value] == true;
      _canEdit = isAdmin || explanations[DocumentAction.edit.value] == true;
      _canSubmitAction = explanations[DocumentAction.submit.value] == true;
      _canApproveAction = explanations[DocumentAction.approve.value] == true;
      _canForwardAction = explanations[DocumentAction.forward.value] == true;
      _canRejectAction = explanations[DocumentAction.reject.value] == true;
      _canReturnAction = explanations[DocumentAction.returnDoc.value] == true;
      _canDownloadAttachment =
          explanations[DocumentAction.download.value] == true ||
          explanations[DocumentAction.view.value] == true;
      _canModifyAttachment =
          isAdmin ||
          (DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc) &&
              doc.createdBy == userId) ||
          explanations[DocumentAction.edit.value] == true;
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
    final statusAllowsSubmit =
        doc.status == DocumentStatus.pending ||
        doc.status == DocumentStatus.returned;
    final canSubmit =
        workflowReady && canAct && _canSubmitAction && statusAllowsSubmit;

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
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 720;

                  final leftColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWorkflowSection(doc, provider, userId),
                      const SizedBox(height: 24),
                      _buildHistorySection(provider),
                    ],
                  );

                  final rightColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showActions) ...[
                        _buildActionsCard(
                          doc,
                          provider,
                          userId,
                          canAct,
                          canSubmit,
                          canApprove: canApprove,
                          canForward: canForward,
                          canReject: canReject,
                          canReturn: canReturn,
                        ),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWorkflowSection(doc, provider, userId),
                      const SizedBox(height: 24),
                      if (showActions) ...[
                        _buildActionsCard(
                          doc,
                          provider,
                          userId,
                          canAct,
                          canSubmit,
                          canApprove: canApprove,
                          canForward: canForward,
                          canReject: canReject,
                          canReturn: canReturn,
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildAttachmentSection(doc),
                      const SizedBox(height: 24),
                      _buildDocumentInfoSection(doc),
                      const SizedBox(height: 24),
                      _buildHistorySection(provider),
                    ],
                  );
                },
              ),
              const SizedBox(height: 48),
              Text(
                'END OF DOCUMENT DETAILS • DOCUTRACKER ENTERPRISE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DocuTrackerTokens.textMuted.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
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

    final savedLabel = docuTrackerFormatRelativeSaved(
      doc.updatedAt ?? doc.createdAt,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DocuTrackerDetailTag(label: typeName),
            if (doc.documentNumber != null)
              DocuTrackerDetailTag(label: doc.documentNumber!),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DocuTrackerStatusBadge(status: doc.status, dotStyle: true),
            if (savedLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(savedLabel, style: DocuTrackerTokens.metaStyle(context)),
            ],
            if (deadlineLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                    Icon(deadlineIcon, size: 14, color: deadlineColor),
                    const SizedBox(width: 6),
                    Text(
                      deadlineLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: deadlineColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          doc.title,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: DocuTrackerTokens.textPrimary,
            height: 1.15,
            letterSpacing: -0.6,
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
                ? 'Terminal state: approved. No further workflow actions are available.'
                : 'Terminal state: rejected. No further workflow actions are available.',
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
    final terminal =
        doc.status == DocumentStatus.approved ||
        doc.status == DocumentStatus.rejected;
    if (terminal) return _canEdit;
    return canApprove || canReject || canReturn || canForward || _canEdit;
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
    final total = steps.isEmpty ? null : steps.length;
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
    final stepLabel = steps.isEmpty
        ? null
        : () {
            for (final s in steps) {
              if (s.stepOrder == current) return s.label;
            }
            return null;
          }();

    final stepSubtitle = total != null
        ? (stepLabel != null && stepLabel.isNotEmpty
              ? 'Step $current of $total — $stepLabel'
              : 'Step $current of $total')
        : 'Step $current';

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
            _WorkflowStepStrip(steps: steps, currentStepOrder: current),
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
    final primaryActions = <Widget>[
      if (canAct && canSubmit)
        Tooltip(
          message: 'Submit document to start the workflow',
          child: FilledButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
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
            label: const Text('Submit Document'),
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
            label: const Text('Approve'),
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
            label: const Text('Forward'),
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
            label: const Text('Return'),
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
            label: const Text('Reject'),
            style: DocuTrackerStyles.destructiveButtonStyle(),
          ),
        ),
    ];

    final adminRemark = _canEdit
        ? OutlinedButton.icon(
            onPressed: provider.loading
                ? null
                : () async {
                    final remarkCtrl = TextEditingController();
                    try {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remark'),
                          content: TextField(
                            controller: remarkCtrl,
                            autofocus: true,
                            decoration: DocuTrackerStyles.inputDecoration(
                              context,
                              'Enter remark (logged to history)',
                              Icons.comment_rounded,
                            ),
                            maxLines: 4,
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
                                final ok = await provider.addRemark(
                                  doc,
                                  actorId: userId,
                                  remarks: remarks,
                                );
                                if (!mounted) return;
                                if (ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Remark added.'),
                                    ),
                                  );
                                  provider.loadDocumentHistory(doc.id!);
                                } else {
                                  _showActionError(
                                    provider,
                                    fallback: 'Failed to add remark.',
                                  );
                                }
                              },
                              style: DocuTrackerStyles.primaryButtonStyle(),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                    } finally {
                      remarkCtrl.dispose();
                    }
                  },
            icon: const Icon(Icons.comment_rounded, size: 18),
            label: const Text('Add remark'),
            style: DocuTrackerStyles.outlinedButtonStyle().copyWith(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          )
        : null;

    final isDraft = DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc);
    final showQuickAccess = _canEdit || _canDownloadAttachment;

    Widget fullWidth(Widget child) =>
        SizedBox(width: double.infinity, child: child);

    return DocuTrackerDetailSectionCard(
      icon: Icons.touch_app_outlined,
      title: 'Actions',
      subtitle: 'Workflow decisions and quick tools',
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
          if (adminRemark != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: fullWidth(
                OutlinedButton.icon(
                  onPressed: adminRemark.onPressed,
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('Add Remark'),
                  style: DocuTrackerTokens.brandOutlinedStyle().copyWith(
                    minimumSize: WidgetStateProperty.all(
                      const Size(double.infinity, 46),
                    ),
                  ),
                ),
              ),
            ),
          if (showQuickAccess) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: DocuTrackerTokens.brand.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 6),
                const Text(
                  'QUICK ACCESS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: DocuTrackerTokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_canEdit && isDraft)
                  Expanded(
                    child: _QuickAccessChip(
                      label: 'Edit Draft',
                      icon: Icons.edit_outlined,
                      onTap: provider.loading
                          ? null
                          : () => _showEditDraftDialog(doc, provider, userId),
                    ),
                  ),
                if (_canEdit && isDraft && _canDownloadAttachment)
                  const SizedBox(width: 8),
                if (_canDownloadAttachment)
                  Expanded(
                    child: _QuickAccessChip(
                      label: 'Download PDF',
                      icon: Icons.download_rounded,
                      onTap: provider.loading || doc.filePath == null
                          ? null
                          : () => _downloadAttachment(doc, provider),
                    ),
                  ),
              ],
            ),
          ],
          if (secondaryActions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'More workflow actions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            for (final w in secondaryActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: fullWidth(w),
              ),
          ],
        ],
      ),
    );
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

  Widget _buildHistorySection(DocuTrackerProvider provider) {
    final sorted = _sortedHistory(provider.documentHistory);

    return DocuTrackerDetailSectionCard(
      icon: Icons.history_rounded,
      title: 'History & Audit Trail',
      subtitle: 'Chronological activity log and decision remarks.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                'You do not have access to view the audit trail.',
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
    required this.currentStepOrder,
  });

  final List<WorkflowStep> steps;
  final int currentStepOrder;

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
                state: steps[i].stepOrder < currentStepOrder
                    ? _WorkflowStepVisual.complete
                    : steps[i].stepOrder == currentStepOrder
                    ? _WorkflowStepVisual.current
                    : _WorkflowStepVisual.upcoming,
              ),
              if (i < steps.length - 1)
                Container(
                  margin: const EdgeInsets.only(top: 14, left: 4, right: 4),
                  width: 40,
                  height: 2,
                  color: steps[i].stepOrder < currentStepOrder
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

enum _WorkflowStepVisual { complete, current, upcoming }

class _WorkflowStepNode extends StatelessWidget {
  const _WorkflowStepNode({
    required this.order,
    required this.label,
    required this.state,
  });

  final int order;
  final String label;
  final _WorkflowStepVisual state;

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _WorkflowStepVisual.current;
    final isDone = state == _WorkflowStepVisual.complete;

    final nodeColor = isCurrent || isDone
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.surfaceCream;

    final borderColor = isCurrent || isDone
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.borderStrong;

    final statusLabel = isCurrent
        ? 'ACTIVE'
        : isDone
        ? 'DONE'
        : 'PENDING';
    final statusColor = isCurrent
        ? DocuTrackerTokens.brand
        : isDone
        ? DocuTrackerTokens.textMuted
        : DocuTrackerTokens.textMuted;

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
            boxShadow: isCurrent
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
                      color: isCurrent || isDone
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
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              color: DocuTrackerTokens.textPrimary,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          statusLabel,
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
          if (reviewers.isNotEmpty) ...[
            const Text(
              'Designated reviewers',
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
              children: reviewers
                  .map(
                    (n) => Chip(
                      avatar: CircleAvatar(
                        backgroundColor: DocuTrackerTokens.brandSoft,
                        child: Text(
                          n[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: DocuTrackerTokens.brand,
                          ),
                        ),
                      ),
                      label: Text(
                        n,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(
                        color: DocuTrackerTokens.borderSubtle,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
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
                      if (primaryHolderId != null)
                        Text(
                          primaryHolderId!,
                          style: DocuTrackerTokens.metaStyle(context),
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
              style: DocuTrackerTokens.metaStyle(context).copyWith(fontSize: 13),
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
                            _actionLabel(entry.action),
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
                    if (entry.actorName != null || entry.actorId != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            isSystemEvent
                                ? 'System Action'
                                : _actorDisplayName(entry),
                            style: TextStyle(
                              color: isSystemEvent
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF111827),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isSystemEvent && entry.actorId != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '#${entry.actorId!.substring(0, min(8, entry.actorId!.length))}',
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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
                                'STEP: ${_stepLine(entry)}',
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
                                'STATUS TRANSITION: ${_statusLine(entry)}',
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
                                    "REMARK: '${entry.remarks!}'",
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
      return 'Employee #${id.substring(0, min(8, id.length))}';
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
