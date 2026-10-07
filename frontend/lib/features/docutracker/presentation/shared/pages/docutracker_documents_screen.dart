import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_document_navigation.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_create_document_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_library_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_rsp_signature_request_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_module_header.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_status_badge.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_status_theme.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_source_status_text.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_workflow_phase.dart';

String _statusLabel(
  DocuTrackerDocument document,
  DocumentStatus effectiveStatus,
) {
  if (effectiveStatus == DocumentStatus.pending &&
      DocuTrackerDocumentVisibility.isWorkInProgressDraft(document)) {
    return 'Draft';
  }
  return docuTrackerSourceBadgeLabel(document) ?? effectiveStatus.displayName;
}

String _assigneeLabel(DocuTrackerDocument document) {
  final name = document.assigneeName?.trim();
  if (name != null && name.isNotEmpty) return name;
  if (document.sourceOnly && document.sourceModule == 'dtr') {
    return 'Managed in DTR';
  }
  final sourceModule = docuTrackerSourceModuleLabel(document.sourceModule);
  if (document.sourceOnly && sourceModule != null) {
    return 'Managed in $sourceModule';
  }
  if (document.status == DocumentStatus.approved ||
      document.status == DocumentStatus.rejected ||
      document.status == DocumentStatus.cancelled) {
    return 'Workflow complete';
  }
  if (DocuTrackerDocumentVisibility.isWorkInProgressDraft(document)) {
    return 'Not submitted';
  }
  return 'Unassigned';
}

/// Document list screen. Step 2: Role-Based Visibility - shows only
/// documents assigned to user, their office, or department.
class DocuTrackerDocumentsScreen extends StatefulWidget {
  const DocuTrackerDocumentsScreen({
    super.key,
    this.isAdmin = false,
    this.showHeader = true,
    this.openSourceModule,
    this.openSourceTable,
    this.openSourceRecordId,
    this.onSourceDeepLinkConsumed,
  });

  final bool isAdmin;
  final bool showHeader;
  final String? openSourceModule;
  final String? openSourceTable;
  final String? openSourceRecordId;
  final VoidCallback? onSourceDeepLinkConsumed;

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
  bool _showMobileFilters = false;
  bool? _canCreateDocuments;
  List<DocumentType> _creatableDocumentTypes = const [];
  bool _deepLinkHandled = false;
  bool _deepLinkOpening = false;
  final _documentSearchController = TextEditingController();
  late final Map<String, Object?> _viewState;

  @override
  void initState() {
    super.initState();
    final provider = context.read<DocuTrackerProvider>();
    _viewState = provider.viewState('documents:${widget.isAdmin}');
    _filterType = _viewState['filterType'] as String?;
    _filterStatus = _viewState['filterStatus'] as DocumentStatus?;
    _sortByDeadline = _viewState['sortByDeadline'] as bool? ?? false;
    _showMobileFilters = _viewState['showMobileFilters'] as bool? ?? false;
    _documentSearchController.text = _viewState['search'] as String? ?? '';
    _searchQuery = _documentSearchController.text.toLowerCase();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _viewState
      ..['filterType'] = _filterType
      ..['filterStatus'] = _filterStatus
      ..['sortByDeadline'] = _sortByDeadline
      ..['showMobileFilters'] = _showMobileFilters
      ..['search'] = _documentSearchController.text;
    _documentSearchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => _load(forceRefresh: true);

  @override
  void didUpdateWidget(covariant DocuTrackerDocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final deepLinkChanged =
        widget.openSourceRecordId != oldWidget.openSourceRecordId ||
        widget.openSourceTable != oldWidget.openSourceTable ||
        widget.openSourceModule != oldWidget.openSourceModule;
    if (deepLinkChanged &&
        (widget.openSourceRecordId?.trim().isNotEmpty ?? false)) {
      _deepLinkHandled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryOpenSourceDeepLink();
      });
    }
  }

  /// Shows cached data immediately; [forceRefresh] re-fetches quietly while
  /// the current rows stay visible (manual refresh, return from detail).
  Future<void> _load({bool forceRefresh = false}) async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<DocuTrackerProvider>();
    final repo = DocuTrackerRepository.instance;
    final creatableTypesRequest = repo.creatableDocumentTypes(
      forceRefresh: forceRefresh,
    );
    await Future.wait([
      provider.loadRoutingConfigs(),
      provider.loadDocumentsForUser(
        userId: auth.user?.id ?? '',
        isAdmin: widget.isAdmin,
        documentType: _filterType,
        status: _filterStatus,
        forceRefresh: forceRefresh,
      ),
      provider.loadSourceSignatureRequests(forceRefresh: forceRefresh),
    ]);
    final creatableTypes = await creatableTypesRequest;

    if (!mounted) return;
    if (_canCreateDocuments == null ||
        !listEquals(creatableTypes, _creatableDocumentTypes)) {
      setState(() {
        _creatableDocumentTypes = creatableTypes;
        _canCreateDocuments = creatableTypes.isNotEmpty;
      });
    }
    await _tryOpenSourceDeepLink();
  }

  Future<void> _tryOpenSourceDeepLink() async {
    final table = widget.openSourceTable?.trim() ?? '';
    final recordId = widget.openSourceRecordId?.trim() ?? '';
    if (_deepLinkHandled ||
        _deepLinkOpening ||
        table.isEmpty ||
        recordId.isEmpty) {
      return;
    }
    _deepLinkOpening = true;
    try {
      final provider = context.read<DocuTrackerProvider>();
      if (provider.sourceSignatureRequests.isEmpty) {
        await provider.loadSourceSignatureRequests();
      }
      if (!mounted) return;
      final module = widget.openSourceModule?.trim().toLowerCase();
      DocuTrackerRspSignatureRequest? match;
      for (final request in provider.sourceSignatureRequests) {
        final moduleMatches =
            module == null ||
            module.isEmpty ||
            request.sourceModule.toLowerCase() == module;
        if (moduleMatches &&
            request.sourceTable == table &&
            request.sourceRecordId == recordId) {
          match = request;
          break;
        }
      }
      _deepLinkHandled = true;
      widget.onSourceDeepLinkConsumed?.call();
      if (match == null || !mounted) return;
      await showDocuTrackerSourceSignatureRequestDialog(
        context,
        request: match,
      );
      if (!mounted) return;
      await provider.loadSourceSignatureRequests();
    } finally {
      _deepLinkOpening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocuTrackerProvider>();
    final auth = context.watch<AuthProvider>();
    final userId = auth.user?.id ?? '';
    final visibleDocuments = docuTrackerDocumentsForDisplay(
      documents: provider.documents,
      isAdmin: widget.isAdmin,
      userId: userId,
    );
    final requiredDocuments = docuTrackerRequiredActionDocuments(
      documents: visibleDocuments,
      userId: userId,
      isSingleReviewerStep: (document) => docuTrackerIsSingleReviewerStep(
        provider.getRoutingConfigForType(
          DocumentType.fromValue(document.documentType),
        ),
        document.currentStep ?? 1,
      ),
    );
    final pendingSourceRequests = provider.sourceSignatureRequests
        .where((request) => widget.isAdmin || request.isAssignedToViewer)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          DocuTrackerModuleHeader(
            title: 'Documents',
            subtitle: widget.isAdmin
                ? 'All routed documents in the organization.'
                : 'Documents you created, hold, or are assigned to review.',
          ),
          const SizedBox(height: 16),
        ],
        if (provider.sourceSignatureRequestsLoading ||
            requiredDocuments.isNotEmpty ||
            pendingSourceRequests.isNotEmpty ||
            provider.sourceSignatureRequestsError != null) ...[
          _RequiredActionsPanel(
            documents: requiredDocuments,
            sourceRequests: pendingSourceRequests,
            loading: provider.sourceSignatureRequestsLoading,
            hasPartialError: provider.sourceSignatureRequestsError != null,
            onRefreshSignatures: () =>
                provider.loadSourceSignatureRequests(forceRefresh: true),
            onDocumentTap: (document) => openDocuTrackerDocumentDetail(
              context,
              document: document,
              isAdmin: widget.isAdmin,
              userId: userId,
              onReturned: _refresh,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildDocumentToolbar(provider, auth),
        if (provider.error != null) ...[
          const SizedBox(height: 12),
          DocuTrackerErrorBanner(
            message: provider.error!,
            onDismiss: () => provider.clearError(),
          ),
        ],
        const SizedBox(height: 20),
        if (provider.loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppTheme.primaryNavy),
            ),
          )
        else if (visibleDocuments.isEmpty)
          _EmptyState(
            onCreateTap: _canCreateDocuments == true
                ? () => _openCreateDialog(auth, provider)
                : null,
          )
        else
          _DocumentList(
            documents: visibleDocuments,
            isAdmin: widget.isAdmin,
            userId: userId,
            onRefresh: _refresh,
            searchQuery: _searchQuery,
            sortByDeadline: _sortByDeadline,
          ),
      ],
    );
  }

  Future<void> _openCreateDialog(
    AuthProvider auth,
    DocuTrackerProvider provider,
  ) => showDocuTrackerCreateDocumentDialog(
    context,
    auth: auth,
    provider: provider,
    allowedDocumentTypes: _creatableDocumentTypes,
    onCreated: _refresh,
  );

  List<DocumentType> _availableFilterTypes(DocuTrackerProvider provider) {
    final byKey = <String, DocumentType>{};
    void add(DocumentType type) {
      final key = type.value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
      byKey.putIfAbsent(key, () => type);
    }

    for (final type in DocumentType.values) {
      add(type);
    }
    for (final type in _creatableDocumentTypes) {
      add(type);
    }
    for (final config in provider.routingConfigs) {
      add(config.documentType);
    }
    for (final doc in provider.documents) {
      final raw = doc.documentType.trim();
      if (raw.isNotEmpty) add(DocumentType.fromValue(raw));
    }
    // Source-backed modules always appear in the documents table.
    add(DocumentType.fromValue('dtr'));
    add(DocumentType.fromValue('ld'));

    final types = byKey.values.toList(growable: false)
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return types;
  }

  Widget _buildDocumentToolbar(
    DocuTrackerProvider provider,
    AuthProvider auth,
  ) {
    final filterTypes = _availableFilterTypes(provider);
    final filterTypeValues = filterTypes.map((type) => type.value).toSet();
    final selectedFilterType =
        _filterType != null && filterTypeValues.contains(_filterType)
        ? _filterType
        : null;
    final filterControls = <Widget>[
      _warmDropdown(
        context,
        DropdownButton<String?>(
          value: selectedFilterType,
          hint: const Text('Type'),
          underline: const SizedBox.shrink(),
          isDense: true,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('All types')),
            ...filterTypes.map(
              (type) => DropdownMenuItem(
                value: type.value,
                child: Text(type.displayName),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() => _filterType = value);
            _load();
          },
        ),
      ),
      _warmDropdown(
        context,
        DropdownButton<DocumentStatus?>(
          value: _filterStatus,
          hint: const Text('Status'),
          underline: const SizedBox.shrink(),
          isDense: true,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('All statuses')),
            ...DocumentStatus.values.map(
              (status) => DropdownMenuItem(
                value: status,
                child: Text(status.displayName),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() => _filterStatus = value);
            _load();
          },
        ),
      ),
      _warmDropdown(
        context,
        DropdownButton<bool>(
          value: _sortByDeadline,
          underline: const SizedBox.shrink(),
          isDense: true,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: false, child: Text('Newest first')),
            DropdownMenuItem(value: true, child: Text('Deadline first')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sortByDeadline = value);
          },
        ),
      ),
    ];

    final createButton = _canCreateDocuments == true
        ? FilledButton.icon(
            key: const ValueKey('docutracker-create-document'),
            onPressed: provider.loading
                ? null
                : () => _openCreateDialog(auth, provider),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create Draft'),
          )
        : null;

    final refreshButton = IconButton.outlined(
      tooltip: 'Refresh documents',
      onPressed: provider.loading ? null : _refresh,
      icon: const Icon(Icons.refresh_rounded),
    );
    final signaturesButton = OutlinedButton.icon(
      key: const ValueKey('docutracker-my-signatures'),
      onPressed: provider.loading
          ? null
          : () => showDocuTrackerSignatureLibraryDialog(
              context,
              provider: provider,
            ),
      icon: const Icon(Icons.draw_outlined, size: 18),
      label: const Text('My Signatures'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            key: const ValueKey('docutracker-document-search'),
            controller: _documentSearchController,
            onChanged: (value) =>
                setState(() => _searchQuery = value.toLowerCase()),
            decoration: AppTheme.dashInputDecoration(
              context,
              hintText: 'Search title, number, or sender',
              prefixIcon: const Icon(Icons.search_rounded),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          );
          if (constraints.maxWidth < 820) {
            final hasFilters =
                _filterType != null || _filterStatus != null || _sortByDeadline;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('docutracker-mobile-filters'),
                      onPressed: () => setState(
                        () => _showMobileFilters = !_showMobileFilters,
                      ),
                      icon: Icon(
                        _showMobileFilters
                            ? Icons.expand_less_rounded
                            : Icons.tune_rounded,
                      ),
                      label: Text(hasFilters ? 'Filters active' : 'Filters'),
                    ),
                    refreshButton,
                    signaturesButton,
                    if (createButton != null) createButton,
                  ],
                ),
                if (_showMobileFilters) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: filterControls),
                ],
                if (hasFilters) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_filterType != null)
                        Chip(
                          label: Text(
                            documentTypeFromString(_filterType).displayName,
                          ),
                        ),
                      if (_filterStatus != null)
                        Chip(label: Text(_filterStatus!.displayName)),
                      if (_sortByDeadline)
                        const Chip(label: Text('Deadline first')),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _filterType = null;
                            _filterStatus = null;
                            _sortByDeadline = false;
                          });
                          _load();
                        },
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                ],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              ...filterControls.expand(
                (control) => [control, const SizedBox(width: 8)],
              ),
              refreshButton,
              const SizedBox(width: 8),
              signaturesButton,
              if (createButton != null) ...[
                const SizedBox(width: 8),
                createButton,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _warmDropdown(BuildContext context, Widget child) {
    return SizedBox(
      width: 132,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.dashInputFillOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.dashInputBorderOf(context)),
        ),
        child: child,
      ),
    );
  }
}

class _RequiredActionsPanel extends StatefulWidget {
  const _RequiredActionsPanel({
    required this.documents,
    required this.sourceRequests,
    required this.loading,
    required this.hasPartialError,
    required this.onRefreshSignatures,
    required this.onDocumentTap,
  });

  final List<DocuTrackerDocument> documents;
  final List<DocuTrackerRspSignatureRequest> sourceRequests;
  final bool loading;
  final bool hasPartialError;
  final Future<void> Function() onRefreshSignatures;
  final Future<bool> Function(DocuTrackerDocument document) onDocumentTap;

  @override
  State<_RequiredActionsPanel> createState() => _RequiredActionsPanelState();
}

class _RequiredActionsPanelState extends State<_RequiredActionsPanel> {
  bool _showSecondary = false;
  bool _collapsed = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _moduleFilter; // RSP | L&D | DTR | DocuTracker
  String? _formFilter; // form name / document type label

  static final _isoStamp = RegExp(
    r'\s*\d{4}-\d{2}-\d{2}T[\d:\.\-]+Z?\s*$',
    caseSensitive: false,
  );

  late final Map<String, Object?> _viewState;

  @override
  void initState() {
    super.initState();
    _viewState = context.read<DocuTrackerProvider>().viewState(
      'requiredActions',
    );
    _collapsed = _viewState['collapsed'] as bool? ?? false;
    _showSecondary = _viewState['showSecondary'] as bool? ?? false;
    _moduleFilter = _viewState['moduleFilter'] as String?;
    _formFilter = _viewState['formFilter'] as String?;
    _searchQuery = _viewState['search'] as String? ?? '';
    _searchController.text = _searchQuery;
  }

  @override
  void dispose() {
    _viewState
      ..['collapsed'] = _collapsed
      ..['showSecondary'] = _showSecondary
      ..['moduleFilter'] = _moduleFilter
      ..['formFilter'] = _formFilter
      ..['search'] = _searchQuery;
    _searchController.dispose();
    super.dispose();
  }

  String _cleanTitle(String raw) {
    var title = raw.trim();
    title = title.replaceFirst(_isoStamp, '').trim();
    title = title.replaceAll(RegExp(r'\s{2,}'), ' ');
    return title.isEmpty ? raw.trim() : title;
  }

  _ActionPriority _priorityFor(_RequiredActionEntry entry) {
    final request = entry.sourceRequest;
    final document = entry.document;
    if (request != null) {
      return switch (request.signatureState) {
        DocuTrackerSourceSignatureState.needsSetup =>
          _ActionPriority.needsSetup,
        DocuTrackerSourceSignatureState.needsYourSignature =>
          _ActionPriority.needsSignature,
        DocuTrackerSourceSignatureState.waitingOnOthers =>
          _ActionPriority.waiting,
        DocuTrackerSourceSignatureState.fullySigned =>
          _ActionPriority.completed,
      };
    }
    // Native / leave documents in this panel are already action-only.
    final action = (document?.sourceAction ?? '').trim();
    if (action.isNotEmpty) return _ActionPriority.needsSignature;
    return _ActionPriority.needsSignature;
  }

  String _moduleKey(_RequiredActionEntry entry) {
    final request = entry.sourceRequest;
    if (request != null) {
      return request.sourceModule == 'ld' ? 'L&D' : 'RSP';
    }
    final module = entry.document?.sourceModule?.toLowerCase();
    if (module == 'dtr') return 'DTR';
    if (module == 'ld') return 'L&D';
    if (module == 'rsp') return 'RSP';
    return 'DocuTracker';
  }

  String _formKey(_RequiredActionEntry entry) {
    final request = entry.sourceRequest;
    if (request != null) {
      final name = request.formName.trim();
      if (name.isNotEmpty) return name;
    }
    final document = entry.document;
    if (document?.sourceOnly == true && document?.sourceModule == 'dtr') {
      return 'Leave';
    }
    if (document?.sourceOnly == true) {
      switch (document?.sourceTable) {
        case 'recruitment_applications':
          return 'Recruitment Application';
        case 'training_daily_reports':
          return 'Training Daily Report';
      }
    }
    final type = (document?.documentType ?? '').trim();
    if (type.isEmpty) return 'Document';
    return type
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)} ${m.group(2)}',
        )
        .split(RegExp(r'[\s_-]+'))
        .where((p) => p.isNotEmpty)
        .map(
          (p) => p.length == 1
              ? p.toUpperCase()
              : '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _sortTitle(_RequiredActionEntry entry) {
    final raw =
        entry.sourceRequest?.title ??
        entry.document?.title ??
        entry.sourceRequest?.formName ??
        '';
    return _cleanTitle(raw).toLowerCase();
  }

  bool _matchesFilters(_RequiredActionEntry entry) {
    if (_moduleFilter != null && _moduleKey(entry) != _moduleFilter) {
      return false;
    }
    if (_formFilter != null && _formKey(entry) != _formFilter) {
      return false;
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      _cleanTitle(entry.sourceRequest?.title ?? entry.document?.title ?? ''),
      entry.sourceRequest?.formName ?? '',
      _moduleKey(entry),
      _formKey(entry),
      entry.document?.documentNumber ?? '',
      entry.document?.creatorName ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  List<_RequiredActionEntry> _sorted(List<_RequiredActionEntry> input) {
    final copy = List<_RequiredActionEntry>.from(input);
    copy.sort((a, b) {
      final module = _moduleKey(a).compareTo(_moduleKey(b));
      if (module != 0) return module;
      final form = _formKey(
        a,
      ).toLowerCase().compareTo(_formKey(b).toLowerCase());
      if (form != 0) return form;
      return _sortTitle(a).compareTo(_sortTitle(b));
    });
    return copy;
  }

  Widget _buildFindBar(
    BuildContext context, {
    required List<_RequiredActionEntry> allEntries,
  }) {
    final modules = allEntries.map(_moduleKey).toSet().toList(growable: false)
      ..sort();
    final forms = allEntries.map(_formKey).toSet().toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final hasFilters =
        _searchQuery.trim().isNotEmpty ||
        _moduleFilter != null ||
        _formFilter != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              // Searching signed forms should reveal them automatically.
              if (value.trim().isNotEmpty) _showSecondary = true;
            });
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Find a form by title, type, or module…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: hasFilters
                ? IconButton(
                    tooltip: 'Clear filters',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _moduleFilter = null;
                        _formFilter = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        if (modules.length > 1 || forms.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('All modules'),
                selected: _moduleFilter == null,
                onSelected: (_) => setState(() => _moduleFilter = null),
              ),
              ...modules.map(
                (module) => FilterChip(
                  label: Text(module),
                  selected: _moduleFilter == module,
                  onSelected: (selected) {
                    setState(() {
                      _moduleFilter = selected ? module : null;
                      if (_formFilter != null &&
                          !allEntries.any(
                            (e) =>
                                _moduleKey(e) == _moduleFilter &&
                                _formKey(e) == _formFilter,
                          )) {
                        _formFilter = null;
                      }
                      if (_moduleFilter != null) _showSecondary = true;
                    });
                  },
                ),
              ),
              if (forms.length > 1)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _formFilter,
                    hint: const Text('All form types'),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All form types'),
                      ),
                      ...forms.map(
                        (form) => DropdownMenuItem<String?>(
                          value: form,
                          child: Text(form),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _formFilter = value;
                        if (value != null) _showSecondary = true;
                      });
                    },
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = <_RequiredActionEntry>[
      ...widget.sourceRequests.map(_RequiredActionEntry.source),
      ...widget.documents.map(_RequiredActionEntry.document),
    ];
    final entries = allEntries.where(_matchesFilters).toList(growable: false);
    final needsSignature = <_RequiredActionEntry>[];
    final needsSetup = <_RequiredActionEntry>[];
    final waiting = <_RequiredActionEntry>[];
    final completed = <_RequiredActionEntry>[];
    for (final entry in entries) {
      switch (_priorityFor(entry)) {
        case _ActionPriority.needsSignature:
          needsSignature.add(entry);
        case _ActionPriority.needsSetup:
          needsSetup.add(entry);
        case _ActionPriority.waiting:
          waiting.add(entry);
        case _ActionPriority.completed:
          completed.add(entry);
      }
    }
    final primary = [..._sorted(needsSignature), ..._sorted(needsSetup)];
    final secondary = [..._sorted(waiting), ..._sorted(completed)];
    final actionableCount = allEntries
        .where(
          (e) =>
              _priorityFor(e) == _ActionPriority.needsSignature ||
              _priorityFor(e) == _ActionPriority.needsSetup,
        )
        .length;
    final filtering =
        _searchQuery.trim().isNotEmpty ||
        _moduleFilter != null ||
        _formFilter != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DocuTrackerTokens.cardDecoration(context: context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _collapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 22,
                    color: DocuTrackerTokens.textMuted,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.task_alt_rounded, size: 21),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Required actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (actionableCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: DocuTrackerTokens.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$actionableCount',
                        style: const TextStyle(
                          color: DocuTrackerTokens.brand,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_collapsed) ...[
            if (allEntries.isNotEmpty)
              _buildFindBar(context, allEntries: allEntries),
            if (filtering)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  entries.isEmpty
                      ? 'No forms match your search or filters.'
                      : 'Showing ${entries.length} matching',
                  style: const TextStyle(
                    color: DocuTrackerTokens.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            if (widget.loading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (widget.hasPartialError) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Some signature requests could not be loaded.',
                      style: TextStyle(
                        color: DocuTrackerTokens.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.loading
                        ? null
                        : widget.onRefreshSignatures,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
            if (primary.isEmpty &&
                secondary.isEmpty &&
                !widget.loading &&
                allEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Nothing needs your attention right now.',
                  style: TextStyle(color: DocuTrackerTokens.textMuted),
                ),
              ),
            if (needsSignature.isNotEmpty)
              _buildSection(
                context,
                title: 'Needs your signature',
                entries: _sorted(needsSignature),
              ),
            if (needsSetup.isNotEmpty)
              _buildSection(
                context,
                title: 'Needs setup',
                entries: _sorted(needsSetup),
              ),
            if (secondary.isNotEmpty) ...[
              if (primary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showSecondary = !_showSecondary),
                    icon: Icon(
                      _showSecondary
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _showSecondary
                          ? 'Hide waiting & signed'
                          : 'Show waiting (${waiting.length}) & fully signed '
                                '(${completed.length})',
                    ),
                  ),
                ),
              ],
              if (_showSecondary || primary.isEmpty) ...[
                if (waiting.isNotEmpty)
                  _buildSection(
                    context,
                    title: 'Waiting on other signers',
                    entries: _sorted(waiting),
                  ),
                if (completed.isNotEmpty)
                  _buildSection(
                    context,
                    title: 'Fully signed',
                    entries: _sorted(completed),
                  ),
              ],
            ],
            if (allEntries.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'DTR, RSP, and L&D records remain managed by their source modules.',
                style: TextStyle(
                  color: DocuTrackerTokens.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<_RequiredActionEntry> entries,
  }) {
    // Group cards under module labels within the section.
    final byModule = <String, List<_RequiredActionEntry>>{};
    for (final entry in entries) {
      byModule.putIfAbsent(_moduleKey(entry), () => []).add(entry);
    }
    final moduleOrder = ['RSP', 'L&D', 'DTR', 'DocuTracker'];
    final modules = byModule.keys.toList()
      ..sort((a, b) {
        final ai = moduleOrder.indexOf(a);
        final bi = moduleOrder.indexOf(b);
        return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: DocuTrackerTokens.textMuted,
            letterSpacing: 0.2,
          ),
        ),
        for (final module in modules) ...[
          const SizedBox(height: 8),
          Text(
            module,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: byModule[module]!
                    .map(
                      (entry) => SizedBox(
                        width: itemWidth,
                        child: _buildActionCard(context, entry),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, _RequiredActionEntry entry) {
    final document = entry.document;
    final request = entry.sourceRequest;
    final isDtr = document?.sourceModule == 'dtr';
    final sourceLabel = request != null
        ? '${request.sourceModule == 'ld' ? 'L&D' : 'RSP'} · ${request.formName}'
        : isDtr
        ? 'DTR · Leave'
        : 'DocuTracker';
    final title = _cleanTitle(
      request?.title ?? document?.title ?? 'Required action',
    );
    final needsSetup = request?.requiresSetup == true;
    final canSignNow = request?.hasUnsignedAssignedSlot == true;
    final fullySigned = request != null && !needsSetup && request.isFullySigned;
    final alreadySigned =
        request != null &&
        !needsSetup &&
        !canSignNow &&
        (fullySigned || request.viewerHasCompletedAssignedSlots);
    final awaitingOthers =
        request != null &&
        !needsSetup &&
        !canSignNow &&
        !alreadySigned &&
        request.hasPendingAssignedSignature;
    final partiallySigned =
        request != null && !fullySigned && request.signedCount > 0;
    final signatureProgress = request == null
        ? ''
        : '${request.signedCount} of '
              '${request.signatureBundle.signatures.length} signed · ';
    final documentActionPending =
        document != null &&
        request == null &&
        (document.sourceAction ?? '').trim().isNotEmpty;
    final isNativeDocumentCard = document != null && request == null;
    final unassignedCount = request == null
        ? 0
        : request.signatureBundle.signatures
              .where((signature) => signature.assignedSignerId.trim().isEmpty)
              .length;
    final actionLabel = request != null
        ? needsSetup
              ? 'Assign required signers'
              : canSignNow
              ? 'Review and sign'
              : alreadySigned
              ? 'View signed form'
              : awaitingOthers
              ? 'View signature status'
              : 'Review and sign'
        : document?.sourceActionLabel ?? 'Review document';
    final sourceModuleLabel = request == null
        ? docuTrackerSourceModuleLabel(document?.sourceModule)
        : null;
    final pendingSigners = request?.pendingSignerNames ?? const <String>[];
    final waitingHint = request?.viewerWaitingOnLabel != null
        ? 'You sign after ${request!.viewerWaitingOnLabel}'
        : alreadySigned
        ? pendingSigners.isEmpty
              ? 'You already signed — reopen to review'
              : 'You signed — waiting on ${pendingSigners.join(', ')}'
        : awaitingOthers
        ? pendingSigners.isEmpty
              ? 'Assigned signer has not signed yet'
              : 'Waiting on ${pendingSigners.join(', ')}'
        : 'Awaiting your e-signature';
    final statusHint = request == null
        ? sourceModuleLabel == null ||
                  (document?.sourceStatus ?? '').trim().isEmpty
              ? null
              : docuTrackerLinkedSourceStatusText(
                  sourceModule: document!.sourceModule!.toLowerCase(),
                  status: document.sourceStatus!,
                ).description
        : needsSetup
        ? unassignedCount > 0
              ? '$unassignedCount signer${unassignedCount == 1 ? '' : 's'} still unassigned'
              : 'Assign required signers before this form can be completed'
        : canSignNow
        ? '${partiallySigned ? signatureProgress : ''}Awaiting your e-signature'
        : fullySigned
        ? 'All signatures complete'
        : '${partiallySigned ? signatureProgress : ''}$waitingHint';
    final chipLabel = needsSetup
        ? 'Needs setup'
        : documentActionPending && sourceModuleLabel != null
        ? 'Action'
        : canSignNow || documentActionPending
        ? 'Sign'
        : fullySigned
        ? 'Signed'
        : partiallySigned
        ? 'Partially signed'
        : alreadySigned
        ? 'Signed'
        : awaitingOthers
        ? 'Pending'
        : 'Sign';
    final showEsignChip = request != null || documentActionPending;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (request != null) {
          await showDocuTrackerSourceSignatureRequestDialog(
            context,
            request: request,
          );
          await widget.onRefreshSignatures();
          return;
        }
        if (document != null) await widget.onDocumentTap(document);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: needsSetup
                ? const Color(0xFFF59E0B).withValues(alpha: 0.55)
                : DocuTrackerTokens.borderSubtleOf(context),
          ),
          borderRadius: BorderRadius.circular(12),
          color: needsSetup
              ? const Color(0xFFFFFBEB).withValues(alpha: 0.65)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              request != null
                  ? (needsSetup
                        ? Icons.person_add_alt_1_rounded
                        : Icons.draw_outlined)
                  : isDtr
                  ? Icons.event_note_rounded
                  : Icons.description_outlined,
              color: needsSetup
                  ? const Color(0xFFB45309)
                  : DocuTrackerTokens.brand,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sourceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: DocuTrackerTokens.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isNativeDocumentCard) ...[
                        const SizedBox(width: 6),
                        DocuTrackerStatusBadge(
                          status: document.status,
                          compact: true,
                          label: _statusLabel(document, document.status),
                        ),
                      ] else if (showEsignChip) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: needsSetup
                                ? const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.16)
                                : DocuTrackerTokens.brand.withValues(
                                    alpha: 0.12,
                                  ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            chipLabel,
                            style: TextStyle(
                              color: needsSetup
                                  ? const Color(0xFFB45309)
                                  : DocuTrackerTokens.brand,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    actionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: needsSetup
                          ? const Color(0xFFB45309)
                          : DocuTrackerTokens.brand,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (statusHint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      statusHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DocuTrackerTokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _RequiredActionEntry {
  const _RequiredActionEntry.document(this.document) : sourceRequest = null;
  const _RequiredActionEntry.source(this.sourceRequest) : document = null;

  final DocuTrackerDocument? document;
  final DocuTrackerRspSignatureRequest? sourceRequest;
}

enum _ActionPriority { needsSignature, needsSetup, waiting, completed }

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onCreateTap});

  final VoidCallback? onCreateTap;

  @override
  Widget build(BuildContext context) {
    final canCreate = onCreateTap != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 32),
      decoration: DocuTrackerTokens.cardDecoration(),
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
                      ? DocuTrackerTokens.surfaceCream
                      : DocuTrackerTokens.borderSubtle.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  canCreate ? Icons.description_outlined : Icons.inbox_outlined,
                  size: 40,
                  color: canCreate
                      ? DocuTrackerTokens.terracotta
                      : DocuTrackerTokens.textMuted,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                canCreate ? 'No documents yet' : 'No documents assigned to you',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DocuTrackerTokens.textPrimaryOf(context),
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
                style: DocuTrackerTokens.subtitleStyle(context),
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
                    color: DocuTrackerTokens.surfaceCream,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DocuTrackerTokens.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: DocuTrackerTokens.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Only selected personnel are authorized to create documents.',
                          style: DocuTrackerTokens.metaStyle(context),
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
                  style: DocuTrackerTokens.terracottaFilledStyle().copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
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

class _DocumentList extends StatefulWidget {
  const _DocumentList({
    required this.documents,
    required this.isAdmin,
    required this.userId,
    required this.onRefresh,
    required this.searchQuery,
    required this.sortByDeadline,
  });

  final List<DocuTrackerDocument> documents;
  final bool isAdmin;
  final String userId;
  final VoidCallback onRefresh;
  final String searchQuery;
  final bool sortByDeadline;

  @override
  State<_DocumentList> createState() => _DocumentListState();
}

class _DocumentListState extends State<_DocumentList> {
  static const _pageSize = 10;
  int _page = 0;

  @override
  void didUpdateWidget(covariant _DocumentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.sortByDeadline != widget.sortByDeadline) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = widget.documents;
    final searchQuery = widget.searchQuery;
    final isAdmin = widget.isAdmin;
    final userId = widget.userId;
    final onRefresh = widget.onRefresh;
    var filtered = documents.where((doc) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return doc.title.toLowerCase().contains(q) ||
          (doc.documentNumber?.toLowerCase().contains(q) ?? false) ||
          (doc.creatorName?.toLowerCase().contains(q) ?? false) ||
          (doc.createdBy?.toLowerCase().contains(q) ?? false);
    }).toList();

    if (widget.sortByDeadline) {
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
        decoration: DocuTrackerTokens.cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: DocuTrackerTokens.surfaceCream,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 32,
                color: DocuTrackerTokens.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No matching documents',
              style: DocuTrackerTokens.titleStyle(context),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filter criteria.',
              style: DocuTrackerTokens.subtitleStyle(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final pageCount = (filtered.length / _pageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageDocuments = filtered
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 860) {
              return _DocumentTable(
                documents: pageDocuments,
                isAdmin: isAdmin,
                userId: userId,
                onRefresh: onRefresh,
              );
            }
            return Column(
              children: pageDocuments.map((doc) {
                final statusForUi = docuTrackerStatusForDisplay(doc);
                final isOverdue = statusForUi == DocumentStatus.overdue;
                return _DocumentRowCard(
                  doc: doc,
                  statusForUi: statusForUi,
                  isOverdue: isOverdue,
                  isAdmin: isAdmin,
                  userId: userId,
                  onRefresh: onRefresh,
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        _DocumentPager(
          page: page,
          pageCount: pageCount,
          onPageChanged: (value) => setState(() => _page = value),
        ),
      ],
    );
  }
}

class _DocumentPager extends StatelessWidget {
  const _DocumentPager({
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final canGoBack = page > 0;
    final canGoForward = page < pageCount - 1;
    final muted = DocuTrackerTokens.textMutedOf(context);
    Widget arrow({
      required IconData icon,
      required String tooltip,
      required int? target,
    }) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        color: muted,
        onPressed: target == null ? null : () => onPageChanged(target),
        icon: Icon(icon, size: 20),
      );
    }

    return Row(
      key: const ValueKey('docutracker-document-pager'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        arrow(
          icon: Icons.keyboard_double_arrow_left_rounded,
          tooltip: 'First page',
          target: canGoBack ? 0 : null,
        ),
        arrow(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous page',
          target: canGoBack ? page - 1 : null,
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 30),
          height: 30,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3B82F6)),
          ),
          child: Text(
            '${page + 1}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D4ED8),
            ),
          ),
        ),
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              'of $pageCount',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
        arrow(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next page',
          target: canGoForward ? page + 1 : null,
        ),
        arrow(
          icon: Icons.keyboard_double_arrow_right_rounded,
          tooltip: 'Last page',
          target: canGoForward ? pageCount - 1 : null,
        ),
      ],
    );
  }
}

const _documentTableFlex = (title: 4, type: 2, status: 2, deadline: 2);

class _DocumentTable extends StatelessWidget {
  const _DocumentTable({
    required this.documents,
    required this.isAdmin,
    required this.userId,
    required this.onRefresh,
  });

  final List<DocuTrackerDocument> documents;
  final bool isAdmin;
  final String userId;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: DocuTrackerTokens.textMutedOf(context),
    );
    return Column(
      key: const ValueKey('docutracker-document-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Expanded(
                flex: _documentTableFlex.title,
                child: Text('Document Title', style: headerStyle),
              ),
              Expanded(
                flex: _documentTableFlex.type,
                child: Text('Type', style: headerStyle),
              ),
              Expanded(
                flex: _documentTableFlex.status,
                child: Text('Status', style: headerStyle),
              ),
              Expanded(
                flex: _documentTableFlex.deadline,
                child: Text('Deadline', style: headerStyle),
              ),
              SizedBox(width: 150, child: Text('Assignee', style: headerStyle)),
            ],
          ),
        ),
        for (final doc in documents)
          _DocumentTableRow(
            doc: doc,
            onTap: () => openDocuTrackerDocumentDetail(
              context,
              document: doc,
              isAdmin: isAdmin,
              userId: userId,
              onReturned: onRefresh,
            ),
          ),
      ],
    );
  }
}

class _DocumentTableRow extends StatefulWidget {
  const _DocumentTableRow({required this.doc, required this.onTap});

  final DocuTrackerDocument doc;
  final Future<void> Function() onTap;

  @override
  State<_DocumentTableRow> createState() => _DocumentTableRowState();
}

class _DocumentTableRowState extends State<_DocumentTableRow> {
  bool _hovered = false;
  bool _opening = false;

  static const _typeChipColors = <String, (Color, Color)>{
    'ld': (Color(0xFFEEF0FB), Color(0xFF4F5BA8)),
    'rsp': (Color(0xFFEAF5F0), Color(0xFF2F7A5B)),
  };

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _dateRange(BuildContext context) {
    final created = widget.doc.createdAt?.toLocal();
    final updated = widget.doc.updatedAt?.toLocal();
    final l10n = MaterialLocalizations.of(context);
    if (created == null && updated == null) return '';
    if (created == null || updated == null) {
      return l10n.formatShortDate((created ?? updated)!);
    }
    final sameDay =
        created.year == updated.year &&
        created.month == updated.month &&
        created.day == updated.day;
    if (sameDay) return l10n.formatShortDate(created);
    if (created.year == updated.year) {
      return '${l10n.formatShortMonthDay(created)} - '
          '${l10n.formatShortDate(updated)}';
    }
    return '${l10n.formatShortDate(created)} - '
        '${l10n.formatShortDate(updated)}';
  }

  double _progressFor(DocuTrackerDocument doc, DocumentStatus status) {
    if (status == DocumentStatus.pending &&
        DocuTrackerDocumentVisibility.isWorkInProgressDraft(doc)) {
      return 0.2;
    }
    return switch (status) {
      DocumentStatus.pending => 0.3,
      DocumentStatus.returned => 0.4,
      DocumentStatus.inReview ||
      DocumentStatus.overdue ||
      DocumentStatus.escalated => 0.6,
      DocumentStatus.approved ||
      DocumentStatus.rejected ||
      DocumentStatus.cancelled => 1.0,
    };
  }

  Color _progressColor(DocumentStatus status) => switch (status) {
    DocumentStatus.rejected ||
    DocumentStatus.cancelled => const Color(0xFFDC2626),
    _ => DocuTrackerStatusTheme.foreground(status),
  };

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final statusForUi = docuTrackerStatusForDisplay(doc);
    final isOverdue = statusForUi == DocumentStatus.overdue;
    final isEscalated = doc.status == DocumentStatus.escalated;
    final typeName = documentTypeFromString(doc.documentType).displayName;
    final (chipBg, chipFg) =
        _typeChipColors[doc.documentType.trim().toLowerCase()] ??
        (const Color(0xFFF6EBDD), const Color(0xFF8A5A2B));
    final dateRange = _dateRange(context);
    final deadline = doc.deadlineTime;
    final textPrimary = DocuTrackerTokens.textPrimaryOf(context);
    final textMuted = DocuTrackerTokens.textMutedOf(context);

    Color background = DocuTrackerTokens.surfaceOf(context);
    if (isOverdue) {
      background = const Color(0xFFFEF2F2);
    } else if (isEscalated) {
      background = const Color(0xFFF5F3FF);
    } else if (_hovered) {
      background = const Color(0xFFF0F5FF);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onHover: (value) => setState(() => _hovered = value),
          onTap: _opening ? null : _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? const Color(0xFFBFD3F5)
                    : DocuTrackerTokens.borderSubtleOf(context),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: _documentTableFlex.title,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? const Color(0xFF991B1B)
                              : textPrimary,
                        ),
                      ),
                      if (dateRange.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          dateRange,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  flex: _documentTableFlex.type,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: chipFg,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: _documentTableFlex.status,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DocuTrackerStatusBadge(
                        status: statusForUi,
                        compact: true,
                        label: _statusLabel(doc, statusForUi),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 46,
                          height: 3,
                          child: LinearProgressIndicator(
                            value: _progressFor(doc, statusForUi),
                            backgroundColor: const Color(0xFFE5E7EB),
                            color: _progressColor(statusForUi),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: _documentTableFlex.deadline,
                  child: Text(
                    deadline == null
                        ? 'No deadline'
                        : MaterialLocalizations.of(
                            context,
                          ).formatShortDate(deadline.toLocal()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: deadline == null
                          ? FontWeight.w400
                          : FontWeight.w700,
                      color: isOverdue
                          ? const Color(0xFFB91C1C)
                          : (deadline == null ? textMuted : textPrimary),
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 15,
                        color: textMuted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _assigneeLabel(doc),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    required this.userId,
    required this.onRefresh,
  });

  final DocuTrackerDocument doc;
  final DocumentStatus statusForUi;
  final bool isOverdue;
  final bool isAdmin;
  final String userId;
  final VoidCallback onRefresh;

  @override
  State<_DocumentRowCard> createState() => _DocumentRowCardState();
}

class _DocumentRowCardState extends State<_DocumentRowCard> {
  bool _isHovered = false;
  bool _opening = false;

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

  Future<void> _openDetail() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openDocuTrackerDocumentDetail(
        context,
        document: widget.doc,
        isAdmin: widget.isAdmin,
        userId: widget.userId,
        onReturned: widget.onRefresh,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
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
    Color bgColor = DocuTrackerTokens.surface;
    if (isOverdue) {
      bgColor = DocuTrackerTokens.overduePink;
    } else if (isEscalated) {
      bgColor = const Color(0xFFF5F3FF);
    } else if (_isHovered) {
      bgColor = DocuTrackerTokens.surfaceCream;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(
          color: _isHovered
              ? DocuTrackerTokens.terracotta.withValues(alpha: 0.35)
              : (isOverdue
                    ? DocuTrackerTokens.overdueAccent.withValues(alpha: 0.35)
                    : DocuTrackerTokens.borderSubtle),
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
            onTap: _opening ? null : _openDetail,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                if (compact) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
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
                                      : DocuTrackerTokens.textPrimaryOf(
                                          context,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DocuTrackerStatusBadge(
                              status: widget.statusForUi,
                              compact: true,
                              showIcon: false,
                              dotStyle: true,
                              label: _statusLabel(doc, widget.statusForUi),
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
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DocuTrackerTokens.textMutedOf(context),
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
                        const SizedBox(height: 8),
                        Text(
                          'Current assignee: ${_assigneeLabel(doc)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: DocuTrackerTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                                    : DocuTrackerTokens.textPrimaryOf(context),
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
                                    _assigneeLabel(doc),
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
                              label: _statusLabel(doc, widget.statusForUi),
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
