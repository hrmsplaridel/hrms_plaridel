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
import '../models/document_status.dart';
import '../models/document_type.dart';
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
    await provider.checkAndEscalateOverdue();
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
      action: DocumentAction.delete.name,
    );

    if (!mounted) return;
    setState(() => _canCreateDocuments = canCreate);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                ? () => _showCreateDialog(context, auth, provider)
                : null,
          )
        else
          _DocumentList(
            documents: provider.documents,
            isAdmin: widget.isAdmin,
            onRefresh: _load,
          ),
      ],
    );
  }

  void _showCreateDialog(
    BuildContext context,
    AuthProvider auth,
    DocuTrackerProvider provider,
  ) {
    String title = '';
    DocumentType type = DocumentType.memo;
    String? description;

    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.78).clamp(640.0, 960.0);
    final dialogHeight = (size.height * 0.75).clamp(520.0, 820.0);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 32,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RspFormHeader(
                            formTitle: 'Create Document',
                            subtitle: 'DocuTracker - Municipality of Plaridel',
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  decoration: DocuTrackerStyles.inputDecoration(
                                    'Enter title',
                                    Icons.title_rounded,
                                  ),
                                  onChanged: (v) => title = v,
                                ),
                                const SizedBox(height: 20),
                                DropdownButtonFormField<DocumentType>(
                                  value: type,
                                  decoration:
                                      DocuTrackerStyles.dropdownDecoration(
                                        'Document Type',
                                      ),
                                  items: DocumentType.values
                                      .map(
                                        (t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t.displayName),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => v != null
                                      ? setState(() => type = v)
                                      : null,
                                ),
                                const SizedBox(height: 20),
                                TextField(
                                  decoration: DocuTrackerStyles.inputDecoration(
                                    'Description (optional)',
                                    Icons.notes_rounded,
                                  ),
                                  maxLines: 6,
                                  onChanged: (v) =>
                                      description = v.isEmpty ? null : v,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(
                        top: BorderSide(color: Colors.black.withOpacity(0.06)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: DocuTrackerStyles.outlinedButtonStyle(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () async {
                            if (title.trim().isEmpty) return;
                            final created = await provider.createDocument(
                              title: title.trim(),
                              documentType: type,
                              description: description,
                              createdBy: auth.user?.id ?? '',
                            );
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              if (created != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Document created.'),
                                  ),
                                );
                                _load();
                              }
                            }
                          },
                          style: DocuTrackerStyles.primaryButtonStyle(),
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryNavy.withOpacity(0.12),
              child: Icon(
                Icons.description_rounded,
                color: AppTheme.primaryNavy,
                size: 24,
              ),
            ),
            title: Text(
              doc.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              '${doc.documentType} • ${doc.status.displayName} • ${doc.creatorName ?? '—'}',
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
