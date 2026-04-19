import 'dart:async';
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
import '../widgets/docutracker_document_summary_header.dart';
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
      if (!context.mounted) return;
      if (!canAccess) {
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
      _routingRecords = await repo.getDocumentRoutingRecords(widget.document.id!);
      if (mounted) setState(() => _routingLoading = false);
      // Keep shared notification badges in sync while this screen is open.
      await provider.loadNotifications();

      final userId = auth.user?.id ?? '';
      final roleId = auth.user?.role;
      final docType = widget.document.documentType;

      // Role-based permissions are only for general access.
      final results = await Future.wait<bool>([
        repo.hasPermission(
          userId: userId,
          roleId: roleId,
          documentType: docType,
          action: DocumentAction.view.name,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _canViewAuditTrail = results[0];
        _canEdit = widget.isAdmin;
        _permissionsLoading = false;
      });

      // Poll for server-side workflow changes (escalation, overdue transitions).
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
        if (!mounted) return;
        final provider = context.read<DocuTrackerProvider>();
        final auth = context.read<AuthProvider>();
        final userId = auth.user?.id ?? '';
        final roleId = auth.user?.role;
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

        final results2 = await Future.wait<bool>([
          repo.hasPermission(
            userId: userId,
            roleId: roleId,
            documentType: updatedDoc.documentType,
            action: DocumentAction.view.name,
          ),
        ]);

        setState(() {
          _canViewAuditTrail = results2[0];
          _canEdit = widget.isAdmin;
        });
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
    final canAct =
        doc.status != DocumentStatus.approved &&
        doc.status != DocumentStatus.rejected;
    final currentStep = doc.currentStep ?? 1;
    final currentRouting = _routingRecords
        .where((r) => r.stepOrder == currentStep)
        .cast<DocumentRoutingRecord?>()
        .firstWhere((_) => true, orElse: () => null);
    final isAssignedReviewer = !_routingLoading &&
        userId.isNotEmpty &&
        (doc.currentHolderId == userId ||
            (currentRouting?.assigneeIds.contains(userId) ?? false));
    final canApprove = isAssignedReviewer;
    final canForward = isAssignedReviewer;
    final canReject = isAssignedReviewer;
    final canReturn = isAssignedReviewer;
    final showYourTurn =
        canAct &&
        !_permissionsLoading &&
        userId.isNotEmpty &&
        isAssignedReviewer;

    final showActions = _shouldShowActionsPanel(doc,
        canApprove: canApprove,
        canForward: canForward,
        canReject: canReject,
        canReturn: canReturn);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RspFormHeader(
            formTitle: doc.title,
            subtitle: '${doc.documentNumber ?? '—'} • ${doc.documentType}',
          ),
          DocuTrackerResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DocuTrackerDocumentSummaryHeader(
                  document: doc,
                  onBack: () => Navigator.of(context).pop(),
                  showYourTurnBanner: showYourTurn,
                ),
                const SizedBox(height: 20),
                _buildDocumentInfoSection(doc),
                const SizedBox(height: 20),
                _buildWorkflowSection(doc, provider, userId),
                const SizedBox(height: 20),
                if (showActions) ...[
                  _buildActionsSection(
                    doc,
                    provider,
                    userId,
                    canAct,
                    canApprove: canApprove,
                    canForward: canForward,
                    canReject: canReject,
                    canReturn: canReturn,
                  ),
                  const SizedBox(height: 20),
                ],
                _buildHistorySection(provider),
                const SizedBox(height: 24),
                const RspFormFooter(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
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
    final isAssignedReviewer =
        !_routingLoading &&
        currentUserId.isNotEmpty &&
        (doc.currentHolderId == currentUserId ||
            (currentRouting?.assigneeIds.contains(currentUserId) ?? false));
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DocuTrackerStatusBadge(
                          status: doc.status,
                          compact: true,
                        ),
                        Text(
                          doc.status.displayName,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          _CurrentStepReviewersCard(
            reviewers: assigneeNames,
            youAreAssigned: isAssignedReviewer,
          ),
          const SizedBox(height: 10),
          _CurrentHolderCard(
            name: doc.assigneeName,
            userId: doc.currentHolderId,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
    String userId,
    bool canAct,
    {required bool canApprove,
    required bool canForward,
    required bool canReject,
    required bool canReturn}
  ) {
    final actions = <Widget>[
      if (canAct && canApprove)
        FilledButton.icon(
          onPressed: provider.loading
              ? null
              : () async {
                  final ok = await provider.approveDocument(
                    doc,
                    actionBy: userId,
                    remarks: _remarkController.text,
                  );
                  if (context.mounted && ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Document approved.')),
                    );
                    Navigator.of(context).pop();
                  }
                },
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('Approve'),
          style: DocuTrackerStyles.approveButtonStyle(),
        ),
      if (canAct && canReject)
        OutlinedButton.icon(
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
                              if (context.mounted && ok) {
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
          style: DocuTrackerStyles.outlinedRedStyle(),
        ),
      if (canAct && canReturn)
        OutlinedButton.icon(
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
                              if (context.mounted && ok) {
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
          icon: const Icon(Icons.reply_rounded, size: 18),
          label: const Text('Return'),
          style: DocuTrackerStyles.outlinedButtonStyle(),
        ),
      if (canAct && canForward)
        OutlinedButton.icon(
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
                  if (context.mounted && ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Document forwarded.')),
                    );
                    Navigator.of(context).pop();
                  }
                },
          icon: const Icon(Icons.forward_rounded, size: 18),
          label: const Text('Forward'),
          style: DocuTrackerStyles.outlinedButtonStyle(),
        ),
      if (_canEdit)
        OutlinedButton.icon(
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
                              if (context.mounted && ok) {
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
          label: const Text('Remark'),
          style: DocuTrackerStyles.outlinedButtonStyle(),
        ),
    ];

    return _DocuTrackerDetailSection(
      icon: Icons.touch_app_outlined,
      title: 'Actions',
      subtitle:
          'Workflow buttons appear only when you are assigned to the current step.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canAct && (canApprove || canForward)) ...[
            Text(
              'Optional note (Approve / Forward)',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remarkController,
              maxLines: 2,
              decoration: DocuTrackerStyles.inputDecoration(
                'Add context for approver or next recipient',
                Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final w in actions)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: w,
                ),
            ],
          ),
        ],
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
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
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
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
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.textSecondary.withOpacity(0.45),
                ),
              ),
            _WorkflowStepPill(
              order: steps[i].stepOrder,
              label: steps[i].label ?? 'Step ${steps[i].stepOrder}',
              state: steps[i].stepOrder < currentStepOrder
                  ? _WorkflowStepVisual.complete
                  : steps[i].stepOrder == currentStepOrder
                  ? _WorkflowStepVisual.current
                  : _WorkflowStepVisual.upcoming,
            ),
          ],
        ],
      ),
    );
  }
}

enum _WorkflowStepVisual { complete, current, upcoming }

class _WorkflowStepPill extends StatelessWidget {
  const _WorkflowStepPill({
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
    final bg = isCurrent
        ? AppTheme.primaryNavy.withOpacity(0.12)
        : isDone
        ? AppTheme.primaryNavy.withOpacity(0.06)
        : AppTheme.lightGray.withOpacity(0.85);
    final border = isCurrent
        ? AppTheme.primaryNavy
        : Colors.black.withOpacity(0.08);
    final fg = isCurrent
        ? AppTheme.primaryNavy
        : isDone
        ? AppTheme.textPrimary
        : AppTheme.textSecondary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: isCurrent ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDone)
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: AppTheme.primaryNavy,
                )
              else if (isCurrent)
                Icon(
                  Icons.radio_button_checked_rounded,
                  size: 14,
                  color: AppTheme.primaryNavy,
                )
              else
                Icon(
                  Icons.radio_button_off_rounded,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
              const SizedBox(width: 6),
              Text(
                'Step $order',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: fg, height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _CurrentStepReviewersCard extends StatelessWidget {
  const _CurrentStepReviewersCard({
    required this.reviewers,
    required this.youAreAssigned,
  });

  final List<String> reviewers;
  final bool youAreAssigned;

  @override
  Widget build(BuildContext context) {
    final title = 'Current step reviewers (${reviewers.length})';
    final bg = youAreAssigned
        ? AppTheme.primaryNavy.withValues(alpha: 0.07)
        : AppTheme.lightGray.withValues(alpha: 0.45);
    final border = youAreAssigned
        ? AppTheme.primaryNavy.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                youAreAssigned ? Icons.verified_user_rounded : Icons.group_rounded,
                size: 18,
                color: youAreAssigned ? AppTheme.primaryNavy : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (youAreAssigned)
                Chip(
                  label: const Text(
                    'You are assigned',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.22)),
                  backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.08),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (reviewers.isEmpty)
            Text(
              'No reviewers recorded for this step.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in reviewers)
                  Chip(
                    label: Text(
                      n,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CurrentHolderCard extends StatelessWidget {
  const _CurrentHolderCard({this.name, this.userId});

  final String? name;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final display = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()
        : null;
    final idLine = userId != null && userId!.isNotEmpty ? userId : null;

    if (display == null && idLine == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.lightGray.withOpacity(0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Text(
          'No primary holder recorded. Use “Current step reviewers” as the source of truth.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.primaryNavy.withOpacity(0.14),
            child: Icon(Icons.person_rounded, color: AppTheme.primaryNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Primary holder (legacy)',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (display != null)
                  Text(
                    display,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (idLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      display != null ? 'User ID: $idLine' : idLine,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
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
        for (var i = 0; i < entries.length; i++) ...[
          _TimelineItem(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
          if (i < entries.length - 1)
            Container(
              margin: const EdgeInsets.only(left: 11),
              width: 2,
              height: 8,
              color: Colors.black.withOpacity(0.06),
            ),
        ],
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
    final isOverdue = entry.isOverdueLog;
    final isEscalation = entry.isEscalationLog;
    final color = isOverdue || isEscalation
        ? Colors.orange
        : AppTheme.primaryNavy.withOpacity(0.6);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(_iconForAction(entry.action), size: 12, color: color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: Colors.black.withOpacity(0.06),
              ),
          ],
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.createdAt != null)
                  Text(
                    _formatEntryTime(entry.createdAt!),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (entry.createdAt != null) const SizedBox(height: 4),
                Text(
                  _actionLabel(entry.action),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.actorName != null || entry.actorId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'By ${entry.actorName ?? entry.actorId ?? '—'}',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (entry.fromStep != null || entry.toStep != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _stepLine(entry),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (entry.fromStatus != null || entry.toStatus != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _statusLine(entry),
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (entry.remarks != null && entry.remarks!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      entry.remarks!,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForAction(String? action) {
    return switch (action) {
      'created' => Icons.add_circle_outline,
      'assigned' => Icons.person_add_outlined,
      'approved' => Icons.check_circle_outline,
      'rejected' => Icons.cancel_outlined,
      'returned' => Icons.reply,
      'forwarded' => Icons.forward,
      'overdue' => Icons.warning_amber_rounded,
      'escalated' => Icons.trending_up,
      'remark' => Icons.comment_outlined,
      _ => Icons.circle_outlined,
    };
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
