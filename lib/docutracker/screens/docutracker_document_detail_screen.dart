import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../docutracker_provider.dart';
import '../docutracker_styles.dart';
import '../docutracker_repository.dart';
import '../models/document.dart';
import '../models/document_history.dart';
import '../models/document_status.dart';

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
          const SnackBar(content: Text('You do not have access to this document.')),
        );
        Navigator.of(context).pop();
        return;
      }
      provider.loadDocumentHistory(widget.document.id!);
    });
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();
    final doc = widget.document;
    final userId = auth.user?.id ?? '';
    final canAct = doc.status != DocumentStatus.approved &&
        doc.status != DocumentStatus.rejected;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RspFormHeader(
            formTitle: doc.title,
            subtitle: '${doc.documentNumber ?? '—'} • ${doc.documentType}',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(doc),
                const SizedBox(height: 24),
                _buildInfoCard(doc),
                const SizedBox(height: 24),
                if (canAct) _buildActionButtons(doc, provider, userId),
                const SizedBox(height: 24),
                _buildAuditTrail(provider),
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

  Widget _buildHeader(DocuTrackerDocument doc) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          style: DocuTrackerStyles.iconButtonStyle(),
        ),
        const Spacer(),
        _StatusChip(status: doc.status),
        if (doc.needsAdminIntervention)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Text(
              'Admin intervention',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoCard(DocuTrackerDocument doc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Type', value: doc.documentType),
          _InfoRow(label: 'Sender', value: doc.creatorName ?? doc.createdBy ?? '—'),
          _InfoRow(label: 'Current holder', value: doc.assigneeName ?? doc.currentHolderId ?? '—'),
          _InfoRow(label: 'Route step', value: '${doc.currentStep ?? 1}'),
          _InfoRow(
            label: 'Sent',
            value: doc.sentTime != null
                ? _formatDateTime(doc.sentTime!)
                : '—',
          ),
          _InfoRow(
            label: 'Deadline',
            value: doc.deadlineTime != null
                ? _formatDateTime(doc.deadlineTime!)
                : '—',
          ),
          if (doc.description != null && doc.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Description',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              doc.description!,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    DocuTrackerDocument doc,
    DocuTrackerProvider provider,
    String userId,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: provider.loading
              ? null
              : () async {
                  final ok = await provider.approveDocument(doc,
                      actionBy: userId, remarks: _remarkController.text);
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
        OutlinedButton.icon(
          onPressed: provider.loading
              ? null
              : () async {
                  _remarkController.clear();
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reject - Remarks'),
                      content: TextField(
                        controller: _remarkController,
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
                            final remarks = _remarkController.text.trim();
                            if (remarks.isEmpty) return;
                            Navigator.of(ctx).pop();
                            final ok = await provider.rejectDocument(doc,
                                remarks: remarks, actionBy: userId);
                            if (context.mounted && ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Document rejected.')),
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
                },
          icon: const Icon(Icons.cancel_rounded, size: 18),
          label: const Text('Reject'),
          style: DocuTrackerStyles.outlinedRedStyle(),
        ),
        OutlinedButton.icon(
          onPressed: provider.loading
              ? null
              : () async {
                  _remarkController.clear();
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Return - Remarks'),
                      content: TextField(
                        controller: _remarkController,
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
                            final ok = await provider.returnDocument(doc,
                                remarks: _remarkController.text.trim().isEmpty
                                    ? null
                                    : _remarkController.text.trim(),
                                actionBy: userId);
                            if (context.mounted && ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Document returned.')),
                              );
                              Navigator.of(ctx).pop();
                            }
                          },
                          style: DocuTrackerStyles.primaryButtonStyle(),
                          child: const Text('Return'),
                        ),
                      ],
                    ),
                  );
                },
          icon: const Icon(Icons.reply_rounded, size: 18),
          label: const Text('Return'),
          style: DocuTrackerStyles.outlinedButtonStyle(),
        ),
        OutlinedButton.icon(
          onPressed: provider.loading
              ? null
              : () async {
                  final ok = await provider.forwardDocument(doc,
                      actionBy: userId,
                      remarks: _remarkController.text.trim().isEmpty
                          ? null
                          : _remarkController.text.trim());
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
        OutlinedButton.icon(
          onPressed: provider.loading
              ? null
              : () {
                  _remarkController.clear();
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Add Remark'),
                      content: TextField(
                        controller: _remarkController,
                        decoration: DocuTrackerStyles.inputDecoration(
                          'Enter your remark or comment',
                          Icons.comment_rounded,
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
                            final remarks = _remarkController.text.trim();
                            if (remarks.isEmpty) return;
                            Navigator.of(ctx).pop();
                            final ok = await provider.addRemark(doc,
                                actorId: userId, remarks: remarks);
                            if (context.mounted && ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Remark added.')),
                              );
                              provider.loadDocumentHistory(doc.id!);
                            }
                          },
                          style: DocuTrackerStyles.primaryButtonStyle(),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  );
                },
          icon: const Icon(Icons.comment_rounded, size: 18),
          label: const Text('Add Remark'),
          style: DocuTrackerStyles.outlinedButtonStyle(),
        ),
      ],
    );
  }

  Widget _buildAuditTrail(DocuTrackerProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: AppTheme.primaryNavy, size: 22),
              const SizedBox(width: 10),
              Text(
                'Audit Trail',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.documentHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No history yet.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            _Timeline(entries: provider.documentHistory),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DocumentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DocumentStatus.pending => Colors.grey,
      DocumentStatus.inReview => Colors.blue,
      DocumentStatus.approved => Colors.green,
      DocumentStatus.rejected => Colors.red,
      DocumentStatus.returned => Colors.orange,
      DocumentStatus.forwarded => Colors.teal,
      DocumentStatus.overdue => Colors.deepOrange,
      DocumentStatus.escalated => Colors.purple,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
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
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
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
              child: Icon(
                _iconForAction(entry.action),
                size: 12,
                color: color,
              ),
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
                Text(
                  _actionLabel(entry.action),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.actorName != null || entry.actorId != null)
                  Text(
                    'By: ${entry.actorName ?? entry.actorId ?? '—'}',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                if (entry.remarks != null && entry.remarks!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.remarks!,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (entry.createdAt != null)
                  Text(
                    '${entry.createdAt!.toLocal().year}-${entry.createdAt!.toLocal().month.toString().padLeft(2, '0')}-${entry.createdAt!.toLocal().day.toString().padLeft(2, '0')} '
                    '${entry.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${entry.createdAt!.toLocal().minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
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
      'escalated' => 'Escalated',
      'remark' => 'Remark added',
      _ => action ?? '—',
    };
  }
}
