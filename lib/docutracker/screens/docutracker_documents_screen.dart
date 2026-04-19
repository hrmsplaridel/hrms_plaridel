import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../docutracker_provider.dart';
import '../docutracker_styles.dart';
import '../docutracker_repository.dart';
import '../models/document.dart';
import '../models/document_action.dart';
import '../models/document_status.dart';
import '../models/document_type.dart';
import '../widgets/docutracker_create_document_dialog.dart';
import '../widgets/docutracker_responsive_body.dart';
import '../widgets/docutracker_status_badge.dart';
import '../widgets/docutracker_status_theme.dart';
import 'docutracker_document_detail_screen.dart';

/// Document list screen. Step 2: Role-Based Visibility - shows only
/// documents assigned to user, their office, or department.
class DocuTrackerDocumentsScreen extends StatefulWidget {
  const DocuTrackerDocumentsScreen({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  State<DocuTrackerDocumentsScreen> createState() =>
      _DocuTrackerDocumentsScreenState();
}

class _DocuTrackerDocumentsScreenState
    extends State<DocuTrackerDocumentsScreen> {
  String? _filterType;
  DocumentStatus? _filterStatus;
  bool? _canCreateDocuments;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<DocuTrackerProvider>();
    await provider.loadRoutingConfigs();
    await provider.loadDocumentsForUser(
      userId: auth.user?.id ?? '',
      isAdmin: widget.isAdmin,
      documentType: _filterType,
      status: _filterStatus,
    );

    // Map "Job posting" permission to the ability to create documents.
    final repo = DocuTrackerRepository.instance;
    final userId = auth.user?.id ?? '';
    final roleId = auth.user?.role;
    final canCreate = await repo.hasPermission(
      userId: userId,
      roleId: roleId,
      documentType: '*',
      action: DocumentAction.create.name,
    );

    if (!mounted) return;
    setState(() => _canCreateDocuments = canCreate);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();

    return DocuTrackerResponsiveBody(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Documents',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_canCreateDocuments == true) ...[
              FilledButton.icon(
                onPressed: provider.loading
                    ? null
                    : () => showDocuTrackerCreateDocumentDialog(
                          context,
                          auth: auth,
                          provider: provider,
                          onCreated: _load,
                        ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create'),
                style: DocuTrackerStyles.primaryButtonStyleNavy(),
              ),
              const SizedBox(width: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DocuTrackerStyles.filterDropdownWrapper(
                  DropdownButton<String?>(
                    value: _filterType,
                    hint: const Text('All types'),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All types'),
                      ),
                      ...DocumentType.values.map(
                        (t) => DropdownMenuItem(
                          value: t.value,
                          child: Text(t.displayName),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _filterType = v);
                      _load();
                    },
                  ),
                ),
                DocuTrackerStyles.filterDropdownWrapper(
                  DropdownButton<DocumentStatus?>(
                    value: _filterStatus,
                    hint: const Text('All statuses'),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      ...DocumentStatus.values.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.displayName),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _filterStatus = v);
                      _load();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: provider.loading ? null : _load,
                  tooltip: 'Refresh',
                  style: DocuTrackerStyles.iconButtonStyle(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Documents assigned to you, your office, or department.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        if (provider.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.error!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => provider.clearError(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryNavy,
                  ),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (provider.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (provider.documents.isEmpty)
          _EmptyState(
            onCreateTap: _canCreateDocuments == true
                ? () => showDocuTrackerCreateDocumentDialog(
                      context,
                      auth: auth,
                      provider: provider,
                      onCreated: _load,
                    )
                : null,
          )
        else
          _DocumentList(
            documents: provider.documents,
            isAdmin: widget.isAdmin,
            onRefresh: _load,
          ),
      ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onCreateTap});

  final VoidCallback? onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No documents yet',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              onCreateTap != null
                  ? 'Create a document to start the workflow.'
                  : 'You do not have access to create documents.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Document'),
              style: DocuTrackerStyles.primaryButtonStyleNavy(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({
    required this.documents,
    required this.isAdmin,
    required this.onRefresh,
  });

  final List<DocuTrackerDocument> documents;
  final bool isAdmin;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DocuTrackerStyles.listCardDecoration(),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: documents.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.black.withOpacity(0.06)),
        itemBuilder: (context, i) {
          final doc = documents[i];
          final isOverdue = doc.status == DocumentStatus.overdue ||
              (doc.deadlineTime != null &&
                  DateTime.now().isAfter(doc.deadlineTime!));
          final statusForUi =
              isOverdue ? DocumentStatus.overdue : doc.status;
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor:
                  DocuTrackerStatusTheme.chipBackground(statusForUi),
              child: Icon(
                DocuTrackerStatusTheme.icon(statusForUi),
                color: DocuTrackerStatusTheme.foreground(statusForUi),
                size: 22,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    doc.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isOverdue
                          ? DocuTrackerStatusTheme.foreground(
                              DocumentStatus.overdue,
                            )
                          : AppTheme.textPrimary,
                    ),
                  ),
                ),
                DocuTrackerStatusBadge(
                  status: statusForUi,
                  compact: true,
                  showIcon: false,
                ),
              ],
            ),
            subtitle: Text(
              '${doc.documentType} • ${doc.creatorName ?? '—'}',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocuTrackerDocumentDetailScreen(
                    document: doc,
                    isAdmin: isAdmin,
                  ),
                ),
              );
              onRefresh();
            },
          );
        },
      ),
    );
  }
}
