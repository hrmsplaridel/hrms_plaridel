import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/rsp_form_header_footer.dart';
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
import '../theme/docutracker_tokens.dart';
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
  bool _canViewAuditTrail = false;
  bool _canEdit = false; // Candidate documents / remark ability
  bool _canSubmitAction = false;
  bool _canApproveAction = false;
  bool _canForwardAction = false;
  bool _canRejectAction = false;
  bool _canReturnAction = false;

  Future<void> _refreshEffectivePermissions({
    required DocuTrackerDocument doc,
    required AuthProvider auth,
    required bool isAdmin,
  }) async {
    final repo = DocuTrackerRepository.instance;
    final userId = auth.user?.id ?? '';
    final roleId = auth.user?.role;
    final documentId = doc.id;
    if (documentId == null || documentId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _canViewAuditTrail = false;
        _canEdit = false;
        _canSubmitAction = false;
        _canApproveAction = false;
        _canForwardAction = false;
        _canRejectAction = false;
        _canReturnAction = false;
      });
      return;
    }

    final actions = <String>[
      DocumentAction.view.value,
      DocumentAction.submit.value,
      DocumentAction.approve.value,
      DocumentAction.forward.value,
      DocumentAction.reject.value,
      DocumentAction.returnDoc.value,
    ];
    final explanations = <String, bool>{};
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
    }
    if (!mounted) return;
    setState(() {
      _canViewAuditTrail = explanations[DocumentAction.view.value] == true;
      _canEdit = isAdmin;
      _canSubmitAction = explanations[DocumentAction.submit.value] == true;
      _canApproveAction = explanations[DocumentAction.approve.value] == true;
      _canForwardAction = explanations[DocumentAction.forward.value] == true;
      _canRejectAction = explanations[DocumentAction.reject.value] == true;
      _canReturnAction = explanations[DocumentAction.returnDoc.value] == true;
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
      // Step 11: RBAC - verify user can access document
      final canAccess = await repo.canAccessDocument(
        userId: auth.user?.id ?? '',
        documentId: widget.document.id!,
        isAdmin: widget.isAdmin,
      );
      if (!mounted) return;
      if (!canAccess) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have access to this document.'),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      // Load audit trail eagerly; we'll still hide it if permissions deny access.
      provider.loadDocumentHistory(widget.document.id!);
      _routingRecords = await repo.getDocumentRoutingRecords(
        widget.document.id!,
      );
      if (mounted) setState(() => _routingLoading = false);
      // Keep shared notification badges in sync while this screen is open.
      await provider.loadNotifications();
      final effectiveDoc = _resolveDocForView(provider);
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
        (
          doc.currentHolderId == userId ||
          (currentRouting?.assigneeIds.contains(userId) ?? false) ||
          // Fallback for legacy docs where snapshot table may be empty but holder is set.
          (currentRouting == null && doc.currentHolderId == userId)
        );

    final canSubmit = canAct && _canSubmitAction;

    // Review actions only valid if NOT pending.
    final canApprove = !isPending && canAct && _canApproveAction;
    final canForward = !isPending && canAct && _canForwardAction;
    final canReject = !isPending && canAct && _canRejectAction;
    final canReturn = !isPending && canAct && _canReturnAction;

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
      backgroundColor: DocuTrackerTokens.canvas,
      body: SingleChildScrollView(
        child: DocuTrackerResponsiveBody(
          maxWidth: DocuTrackerTokens.maxContentWidth,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroHeader(doc, showYourTurn),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 800;

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
                      _buildDocumentInfoSection(doc),
                      const SizedBox(height: 24),
                      _buildHistorySection(provider),
                    ],
                  );
                },
              ),
              const SizedBox(height: 48),
              const RspFormFooter(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(DocuTrackerDocument doc, bool showYourTurn) {
    final typeName = documentTypeFromString(doc.documentType).displayName;

    String deadlineLabel = '';
    Color deadlineColor = const Color(0xFF6B7280);
    IconData deadlineIcon = Icons.schedule_rounded;
    if (doc.deadlineTime == null &&
        doc.status == DocumentStatus.pending) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
                SizedBox(width: 4),
                Text(
                  'Back to documents',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 12,
          spacing: 16,
          children: [
            SizedBox(
              width: min(MediaQuery.sizeOf(context).width * 0.6, 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                      if (doc.documentNumber != null)
                        Text(
                          doc.documentNumber!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    doc.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DocuTrackerStatusBadge(status: doc.status),
                if (deadlineLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: deadlineColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: deadlineColor.withValues(alpha: 0.2),
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
          ],
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
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'It is your turn to act on this document.',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

  Widget _buildDocumentInfoSection(DocuTrackerDocument doc) {
    return _DocuTrackerDetailSection(
      icon: Icons.article_outlined,
      title: 'Document information',
      subtitle: 'Reference details and timeline for this routing.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Document no.', value: doc.documentNumber ?? '—'),
          _InfoRow(label: 'Type', value: doc.documentType),
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
          _InfoRow(
            label: 'Sent to reviewer',
            value: doc.sentTime != null ? _formatDateTime(doc.sentTime!) : '—',
          ),
          _InfoRow(
            label: 'Deadline',
            value: doc.deadlineTime != null
                ? _formatDateTime(doc.deadlineTime!)
                : '—',
          ),
          _InfoRow(
            label: 'Review completed',
            value: doc.reviewedTime != null
                ? _formatDateTime(doc.reviewedTime!)
                : '—',
          ),
          if (doc.workflowVersion != null)
            _InfoRow(
              label: 'Workflow version',
              value: '${doc.workflowVersion}',
            ),
          if (doc.description != null && doc.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'Description',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              doc.description!,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
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
        (
          doc.currentHolderId == currentUserId ||
          (currentRouting?.assigneeIds.contains(currentUserId) ?? false) ||
          (currentRouting == null && doc.currentHolderId == currentUserId)
        );
    final stepLabel = steps.isEmpty
        ? null
        : () {
            for (final s in steps) {
              if (s.stepOrder == current) return s.label;
            }
            return null;
          }();

    return _DocuTrackerDetailSection(
      icon: Icons.account_tree_outlined,
      title: 'Workflow & routing',
      subtitle:
          'Current status, step in the defined route, and who is assigned to act.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total != null ? 'Step $current of $total' : 'Step $current',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (stepLabel != null && stepLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              stepLabel,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 14),
            _WorkflowStepStrip(steps: steps, currentStepOrder: current),
          ],
          const SizedBox(height: 20),
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
                    if (mounted && ok) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Document submitted successfully.'),
                        ),
                      );
                      Navigator.of(context).pop();
                    }
                  },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Submit'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
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
                    if (mounted && ok) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Document approved.')),
                      );
                      Navigator.of(context).pop();
                    }
                  },
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('Approve'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981), // Green
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
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
                    if (mounted && ok) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Document forwarded.')),
                      );
                      Navigator.of(context).pop();
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
context,                               'Reason for return (optional)',
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
                                if (mounted && ok) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Document returned.'),
                                    ),
                                  );
                                  Navigator.of(context).pop();
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
context,                               'Reason for rejection (required)',
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
                                if (mounted && ok) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Document rejected.'),
                                    ),
                                  );
                                  Navigator.of(context).pop();
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
context,                               'Enter remark (logged to history)',
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
                                if (mounted && ok) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Remark added.'),
                                    ),
                                  );
                                  provider.loadDocumentHistory(doc.id!);
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
            label: const Text('Add remark (admin)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          )
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),
            if (provider.loading) ...[
              DocuTrackerStyles.stateMessage(
                icon: Icons.hourglass_top_rounded,
                color: AppTheme.primaryNavy,
                message: 'Processing action... please wait.',
              ),
              const SizedBox(height: 12),
            ],
            if (canAct && (canApprove || canForward)) ...[
              TextField(
                controller: _remarkController,
                maxLines: 2,
                decoration: DocuTrackerStyles.inputDecoration(
context,                   'Optional note for next recipient...',
                  Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (primaryActions.isNotEmpty) ...[
              const Text(
                'PRIMARY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: primaryActions
                    .map(
                      (w) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: w,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (secondaryActions.isNotEmpty) ...[
              const Text(
                'SECONDARY / WARNING / DANGER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: secondaryActions
                    .map(
                      (w) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: w,
                      ),
                    )
                    .toList(),
              ),
            ],
            if ((primaryActions.isNotEmpty || secondaryActions.isNotEmpty) &&
                adminRemark != null)
              const SizedBox(height: 6),
            if (adminRemark != null) adminRemark,
          ],
        ),
      ),
    );
  }

  List<DocumentHistoryEntry> _sortedHistory(List<DocumentHistoryEntry> raw) {
    final copy = [...raw];
    int key(DocumentHistoryEntry e) => e.createdAt?.millisecondsSinceEpoch ?? 0;
    copy.sort((a, b) => key(a).compareTo(key(b)));
    return copy;
  }

  Widget _buildHistorySection(DocuTrackerProvider provider) {
    final sorted = _sortedHistory(provider.documentHistory);

    return _DocuTrackerDetailSection(
      icon: Icons.history_rounded,
      title: 'History & audit trail',
      subtitle:
          'Oldest entries first. Includes routing, decisions, and remarks.',
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

class _DocuTrackerDetailSection extends StatelessWidget {
  const _DocuTrackerDetailSection({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusSm,
                    ),
                  ),
                  child: Icon(icon, color: AppTheme.primaryNavy, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: DocuTrackerTokens.subtitleStyle().copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: DocuTrackerTokens.borderSubtle.withValues(alpha: 0.9),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Material(color: Colors.transparent, child: child),
          ),
        ],
      ),
    );
  }
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
                  width: 32,
                  height: 2,
                  color: steps[i].stepOrder < currentStepOrder
                      ? const Color(0xFF3B5BDB)
                      : const Color(0xFFE5E7EB),
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

    final nodeColor = isCurrent
        ? const Color(0xFF3B5BDB)
        : isDone
        ? const Color(0xFF3B5BDB)
        : Colors.white;

    final borderColor = isCurrent || isDone
        ? const Color(0xFF3B5BDB)
        : const Color(0xFFD1D5DB);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: nodeColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B5BDB).withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    order.toString(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent
                  ? const Color(0xFF111827)
                  : const Color(0xFF6B7280),
              height: 1.2,
            ),
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

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: youAreAssigned ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: youAreAssigned
              ? const Color(0xFF93C5FD)
              : const Color(0xFFE5E7EB),
          width: youAreAssigned ? 1.5 : 1,
        ),
        boxShadow: [
          if (youAreAssigned)
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 12,
            ),
            child: Row(
              children: [
                Icon(
                  youAreAssigned
                      ? Icons.person_pin_circle_rounded
                      : Icons.pending_actions_rounded,
                  size: 20,
                  color: youAreAssigned
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF4B5563),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Currently assigned to',
                    style: TextStyle(
                      color: youAreAssigned
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF374151),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (youAreAssigned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Your Action Required',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Reviewers List
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reviewers.isEmpty && !hasLegacyHolder)
                  const Text(
                    'No reviewers recorded for this step.',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  )
                else ...[
                  if (reviewers.isNotEmpty) ...[
                    const Text(
                      'Designated Reviewers:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
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
                                backgroundColor: const Color(0xFFDBEAFE),
                                child: Text(
                                  n[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF1E40AF),
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
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (hasLegacyHolder && reviewers.isEmpty) ...[
                    const Text(
                      'Primary Holder:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(0xFFF3F4F6),
                          child: Icon(
                            Icons.person,
                            size: 16,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                primaryHolderName ?? 'Unknown User',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              if (primaryHolderId != null)
                                Text(
                                  'ID: $primaryHolderId',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
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
                              _getInitials(entry.actorName ?? '??'),
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
                                : (entry.actorName ?? 'Unknown User'),
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
                          color: isSystemEvent
                              ? Colors.white.withValues(alpha: 0.5)
                              : const Color(0xFFF8F9FB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSystemEvent
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFF3F4F6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.fromStep != null || entry.toStep != null)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.route_rounded,
                                    size: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _stepLine(entry),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF4B5563),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            if ((entry.fromStep != null ||
                                    entry.toStep != null) &&
                                (entry.fromStatus != null ||
                                    entry.toStatus != null))
                              const SizedBox(height: 4),
                            if (entry.fromStatus != null ||
                                entry.toStatus != null)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.track_changes_rounded,
                                    size: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _statusLine(entry),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF4B5563),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
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
                          color: isSystemEvent
                              ? Colors.white.withValues(alpha: 0.5)
                              : const Color(0xFFF8F9FB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSystemEvent
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFE4E7ED),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(width: 4, color: dotColor),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    entry.remarks!,
                                    style: TextStyle(
                                      color: isSystemEvent
                                          ? const Color(0xFF92400E)
                                          : const Color(0xFF374151),
                                      fontSize: 13,
                                      height: 1.4,
                                      fontStyle: FontStyle.italic,
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
      'created' => 'Document created',
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

  static String _formatEntryTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
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
