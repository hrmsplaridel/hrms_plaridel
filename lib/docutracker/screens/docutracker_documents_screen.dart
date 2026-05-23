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
import '../theme/docutracker_tokens.dart';
import '../widgets/docutracker_create_document_dialog.dart';
import '../widgets/docutracker_module_header.dart';
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
  String _searchQuery = '';
  bool _sortByDeadline = false;
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
      action: DocumentAction.createDraft.value,
    );

    if (!mounted) return;
    setState(() => _canCreateDocuments = canCreate);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();

    return DocuTrackerResponsiveBody(
      maxWidth: DocuTrackerTokens.maxContentWidth,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DocuTrackerModuleHeader(
            title: 'Documents',
            subtitle:
                'Everything you can see by assignment, office, or department.',
            trailing: _canCreateDocuments == true
                ? FilledButton.icon(
                    onPressed: provider.loading
                        ? null
                        : () => showDocuTrackerCreateDocumentDialog(
                            context,
                            auth: auth,
                            provider: provider,
                            onCreated: _load,
                          ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Draft'),
                    style: DocuTrackerStyles.primaryButtonStyleNavy(),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          // Modern Dashboard Toolbar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  onChanged: (val) {
                    setState(() => _searchQuery = val.toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: 'Search documents by title, number, or sender...',
                    hintStyle: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF9CA3AF),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Color(0xFF3B82F6),
                        width: 1.5,
                      ),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                // Filter Chips & Sort
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.filter_list_rounded,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                    DocuTrackerStyles.filterDropdownWrapper(
                      DropdownButton<String?>(
                        value: _filterType,
                        hint: const Text('Type'),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        iconSize: 18,
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
                        hint: const Text('Status'),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        iconSize: 18,
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
                    DocuTrackerStyles.filterDropdownWrapper(
                      DropdownButton<bool>(
                        value: _sortByDeadline,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        iconSize: 18,
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: Text('Sort by newest'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Sort by deadline'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _sortByDeadline = v);
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: provider.loading ? null : _load,
                      tooltip: 'Refresh',
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFF4B5563),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickStatusChip(
                      label: 'Overdue',
                      selected: _filterStatus == DocumentStatus.overdue,
                      onTap: () {
                        setState(() {
                          _filterStatus = _filterStatus == DocumentStatus.overdue
                              ? null
                              : DocumentStatus.overdue;
                        });
                        _load();
                      },
                    ),
                    _QuickStatusChip(
                      label: 'Escalated',
                      selected: _filterStatus == DocumentStatus.escalated,
                      onTap: () {
                        setState(() {
                          _filterStatus = _filterStatus == DocumentStatus.escalated
                              ? null
                              : DocumentStatus.escalated;
                        });
                        _load();
                      },
                    ),
                    _QuickStatusChip(
                      label: 'In Review',
                      selected: _filterStatus == DocumentStatus.inReview,
                      onTap: () {
                        setState(() {
                          _filterStatus = _filterStatus == DocumentStatus.inReview
                              ? null
                              : DocumentStatus.inReview;
                        });
                        _load();
                      },
                    ),
                  ],
                ),
              ],
            ),
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
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.error!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 13,
                      ),
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
              searchQuery: _searchQuery,
              sortByDeadline: _sortByDeadline,
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
    final canCreate = onCreateTap != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Illustration circle
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: canCreate
                      ? const Color(0xFFEEF2FF)
                      : const Color(0xFFF3F4F6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  canCreate ? Icons.description_outlined : Icons.inbox_outlined,
                  size: 40,
                  color: canCreate
                      ? const Color(0xFF3B5BDB)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                canCreate ? 'No documents yet' : 'No documents assigned to you',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Subtext
              Text(
                canCreate
                    ? 'Create your first document to begin a workflow. It will be routed to the assigned reviewers automatically.'
                    : 'Documents assigned to you for review will appear here. You will also receive a notification when action is required.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),

              // Extra info for read-only users
              if (!canCreate) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Only selected personnel are authorized to create documents.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // CTA — only shown when user has permission
              if (canCreate) ...[
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onCreateTap,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create Draft'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3B5BDB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
    required this.searchQuery,
    required this.sortByDeadline,
  });

  final List<DocuTrackerDocument> documents;
  final bool isAdmin;
  final VoidCallback onRefresh;
  final String searchQuery;
  final bool sortByDeadline;

  @override
  Widget build(BuildContext context) {
    var filtered = documents.where((doc) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return doc.title.toLowerCase().contains(q) ||
          (doc.documentNumber?.toLowerCase().contains(q) ?? false) ||
          (doc.creatorName?.toLowerCase().contains(q) ?? false) ||
          (doc.createdBy?.toLowerCase().contains(q) ?? false);
    }).toList();

    if (sortByDeadline) {
      filtered.sort((a, b) {
        if (a.deadlineTime == null && b.deadlineTime == null) return 0;
        if (a.deadlineTime == null) return 1;
        if (b.deadlineTime == null) return -1;
        return a.deadlineTime!.compareTo(b.deadlineTime!);
      });
    }

    if (filtered.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 32,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No matching documents',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try adjusting your search or filter criteria.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1020) {
          return _DocumentDataTable(
            documents: filtered,
            isAdmin: isAdmin,
            onRefresh: onRefresh,
          );
        }
        return Column(
          children: filtered.map((doc) {
            final isOverdue =
                doc.status == DocumentStatus.overdue ||
                (doc.deadlineTime != null &&
                    DateTime.now().isAfter(doc.deadlineTime!));
            final statusForUi = isOverdue ? DocumentStatus.overdue : doc.status;
            return _DocumentRowCard(
              doc: doc,
              statusForUi: statusForUi,
              isOverdue: isOverdue,
              isAdmin: isAdmin,
              onRefresh: onRefresh,
            );
          }).toList(),
        );
      },
    );
  }
}

class _QuickStatusChip extends StatelessWidget {
  const _QuickStatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.14),
      side: BorderSide(
        color: selected
            ? AppTheme.primaryNavy.withValues(alpha: 0.5)
            : const Color(0xFFE5E7EB),
      ),
      labelStyle: TextStyle(
        color: selected ? AppTheme.primaryNavy : const Color(0xFF4B5563),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DocumentDataTable extends StatelessWidget {
  const _DocumentDataTable({
    required this.documents,
    required this.isAdmin,
    required this.onRefresh,
  });

  final List<DocuTrackerDocument> documents;
  final bool isAdmin;
  final VoidCallback onRefresh;

  String _deadlineLabel(DateTime? date) {
    if (date == null) return '—';
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 980),
        child: DataTable(
          columnSpacing: 18,
          headingRowHeight: 44,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('Document')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Deadline')),
            DataColumn(label: Text('Holder')),
          ],
          rows: documents.map((doc) {
            final isOverdue = doc.status == DocumentStatus.overdue ||
                (doc.deadlineTime != null && DateTime.now().isAfter(doc.deadlineTime!));
            final statusForUi = isOverdue ? DocumentStatus.overdue : doc.status;
            final title = doc.title;
            return DataRow(
              onSelectChanged: (_) async {
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
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (isOverdue) return const Color(0xFFFEF2F2);
                if (doc.status == DocumentStatus.escalated) return const Color(0xFFF5F3FF);
                return null;
              }),
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                DataCell(Text(documentTypeFromString(doc.documentType).displayName)),
                DataCell(DocuTrackerStatusBadge(status: statusForUi, compact: true)),
                DataCell(Text(_deadlineLabel(doc.deadlineTime))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      doc.assigneeName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DocumentRowCard extends StatefulWidget {
  const _DocumentRowCard({
    required this.doc,
    required this.statusForUi,
    required this.isOverdue,
    required this.isAdmin,
    required this.onRefresh,
  });

  final DocuTrackerDocument doc;
  final DocumentStatus statusForUi;
  final bool isOverdue;
  final bool isAdmin;
  final VoidCallback onRefresh;

  @override
  State<_DocumentRowCard> createState() => _DocumentRowCardState();
}

class _DocumentRowCardState extends State<_DocumentRowCard> {
  bool _isHovered = false;

  static const _typeColors = <String, Color>{
    'memo': Color(0xFF3B82F6),
    'purchaseRequest': Color(0xFF8B5CF6),
  };
  static const _typeIcons = <String, IconData>{
    'memo': Icons.description_rounded,
    'purchaseRequest': Icons.receipt_long_rounded,
  };

  Color get _statusColor =>
      DocuTrackerStatusTheme.foreground(widget.statusForUi);

  String _deadlineLabel() {
    final dl = widget.doc.deadlineTime;
    if (dl == null) return '';
    final diff = dl.difference(DateTime.now());
    if (diff.isNegative) return 'Overdue';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    if (d > 0) return '$d days left';
    if (h > 0) return '${diff.inHours}h left';
    final m = diff.inMinutes % 60;
    return '${m}m left';
  }

  bool get _isUrgent {
    final dl = widget.doc.deadlineTime;
    if (dl == null) return false;
    return dl.difference(DateTime.now()).inHours < 24 &&
        !dl.difference(DateTime.now()).isNegative;
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final isOverdue = widget.isOverdue;
    final typeColor = _typeColors[doc.documentType] ?? const Color(0xFF6B7280);
    final typeIcon = _typeIcons[doc.documentType] ?? Icons.article_rounded;
    final docTypeName = documentTypeFromString(doc.documentType).displayName;
    final deadlineLabel = _deadlineLabel();
    final isTerminal =
        doc.status == DocumentStatus.approved ||
        doc.status == DocumentStatus.rejected;
    final isEscalated = doc.status == DocumentStatus.escalated;

    // Background logic
    Color bgColor = Colors.white;
    if (isOverdue) {
      bgColor = const Color(0xFFFEF2F2); // Red 50
    } else if (isEscalated) {
      bgColor = const Color(0xFFF5F3FF); // Purple 50
    } else if (_isHovered) {
      bgColor = const Color(0xFFF9FAFB); // Gray 50
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isHovered
              ? const Color(0xFFD1D5DB)
              : (isOverdue ? const Color(0xFFFECACA) : const Color(0xFFE5E7EB)),
        ),
        boxShadow: _isHovered
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isOverdue
                    ? const Color(0xFFDC2626)
                    : (isEscalated ? const Color(0xFF7C3AED) : _statusColor),
                width: 3,
              ),
            ),
          ),
          child: InkWell(
            onHover: (val) => setState(() => _isHovered = val),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocuTrackerDocumentDetailScreen(
                    document: doc,
                    isAdmin: widget.isAdmin,
                  ),
                ),
              );
              widget.onRefresh();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                if (compact) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(typeIcon, color: typeColor, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                doc.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: isOverdue
                                      ? const Color(0xFF991B1B)
                                      : const Color(0xFF111827),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DocuTrackerStatusBadge(
                              status: widget.statusForUi,
                              compact: true,
                              showIcon: false,
                              dotStyle: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            if (doc.documentNumber != null)
                              Text(
                                doc.documentNumber!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              docTypeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: typeColor,
                              ),
                            ),
                            if (deadlineLabel.isNotEmpty && !isTerminal)
                              Text(
                                deadlineLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _isUrgent || isOverdue
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF4B5563),
                                ),
                              ),
                          ],
                        ),
                        if (doc.assigneeName != null || doc.creatorName != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            doc.assigneeName != null
                                ? 'Holder: ${doc.assigneeName}'
                                : 'From ${doc.creatorName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                  // 1. Icon & Core Details (Left)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 22),
                  ),
                  const SizedBox(width: 16),

                  // 2. Title and Subtitle (Flex)
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (doc.documentNumber != null) ...[
                              Text(
                                doc.documentNumber!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '•',
                                style: TextStyle(
                                  color: Color(0xFFD1D5DB),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              docTypeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: typeColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          doc.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isOverdue
                                ? const Color(0xFF991B1B)
                                : const Color(0xFF111827),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 3. Current State / Workflow Details (Flex)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isTerminal && doc.currentStep != null) ...[
                          Row(
                            children: [
                              const Text(
                                'Step',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _StepDots(current: doc.currentStep!),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (doc.assigneeName != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                size: 13,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  doc.assigneeName!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF4B5563),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        else if (doc.creatorName != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.send_rounded,
                                size: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'From ${doc.creatorName}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF4B5563),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // 4. Deadline Indicator
                  if (deadlineLabel.isNotEmpty && !isTerminal) ...[
                    Container(
                      width: 100,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isUrgent || isOverdue
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isUrgent || isOverdue
                              ? const Color(0xFFFECACA)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOverdue
                                ? Icons.warning_amber_rounded
                                : Icons.schedule_rounded,
                            size: 12,
                            color: _isUrgent || isOverdue
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              deadlineLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _isUrgent || isOverdue
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF4B5563),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  // 5. Status Badge & Chevron (Right)
                  SizedBox(
                    width: 130,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DocuTrackerStatusBadge(
                          status: widget.statusForUi,
                          compact: true,
                          showIcon: false,
                          dotStyle: true,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: _isHovered
                              ? const Color(0xFF6B7280)
                              : const Color(0xFFD1D5DB),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    const total = 4; // Assuming max 4 steps for visual
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isDone = i < current - 1;
        final isActive = i == current - 1;
        return Container(
          width: isActive ? 16 : 8,
          height: 4,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: isDone
                ? const Color(0xFF3B82F6)
                : isActive
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFE5E7EB),
          ),
        );
      }),
    );
  }
}
