import 'package:flutter/foundation.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_permission.dart';
import 'package:hrms_plaridel/features/docutracker/models/linked_source_document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_access_policy.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_workflow_service.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_notification_service.dart';

/// DocuTracker state management for UI.
/// Owns in-memory state and orchestrates backend calls.
class DocuTrackerProvider extends ChangeNotifier {
  DocuTrackerProvider({
    DocuTrackerRepository? repo,
    DocuTrackerWorkflowService? workflowService,
    DocuTrackerNotificationService? notificationService,
  }) {
    _repo = repo ?? DocuTrackerRepository.instance;
    _workflowService = workflowService ?? DocuTrackerWorkflowService(_repo);
    _notificationService =
        notificationService ?? DocuTrackerNotificationService(_repo);
  }

  late final DocuTrackerRepository _repo;
  late final DocuTrackerWorkflowService _workflowService;
  late final DocuTrackerNotificationService _notificationService;

  List<DocuTrackerDocument> _documents = [];
  List<DocumentRoutingConfig> _routingConfigs = [];
  List<DocumentPermission> _permissions = [];
  List<DocumentHistoryEntry> _documentHistory = [];
  List<DocumentNotification> _notifications = [];
  String? _permissionsLoadKey;
  String? _documentHistoryLoadDocumentId;
  bool _loading = false;
  String? _error;
  DocuTrackerDocumentBuilderData? _builderData;
  bool _builderLoading = false;
  String? _builderError;
  bool _sourceSignatureLoading = false;
  String? _sourceSignatureError;
  List<DocuTrackerRspSignatureRequest> _sourceSignatureRequests = const [];
  bool _sourceSignatureRequestsLoading = false;
  String? _sourceSignatureRequestsError;
  String? _authenticatedUserId;
  int _authGeneration = 0;
  bool _disposed = false;

  // Prevent duplicate transitions due to double taps / retries.
  final Set<String> _transitionInFlight = <String>{};

  /// Clears every user-bound value when the authenticated account changes.
  ///
  /// [_authGeneration] also prevents requests started by the previous account
  /// from restoring stale data after logout or an account switch.
  void onAuthUserChanged(String? userId) {
    if (_disposed) return;
    final normalizedUserId = _normalizeOptional(userId);
    if (_authenticatedUserId == normalizedUserId) return;

    _authenticatedUserId = normalizedUserId;
    _authGeneration += 1;
    _resetSessionState();
    notifyListeners();
  }

  void _resetSessionState() {
    _documents = [];
    _routingConfigs = [];
    _permissions = [];
    _documentHistory = [];
    _notifications = [];
    _permissionsLoadKey = null;
    _documentHistoryLoadDocumentId = null;
    _loading = false;
    _error = null;
    _builderData = null;
    _builderLoading = false;
    _builderError = null;
    _sourceSignatureLoading = false;
    _sourceSignatureError = null;
    _sourceSignatureRequests = const [];
    _sourceSignatureRequestsLoading = false;
    _sourceSignatureRequestsError = null;
    _documentsLoadScopeKey = null;
    _documentsLoadUserId = null;
    _documentsLoadRoleId = null;
    _documentsLoadDepartmentId = null;
    _documentsLoadOfficeId = null;
    _documentsLoadDocumentType = null;
    _documentsLoadStatus = null;
    _documentsLoadIsAdmin = false;
    _documentsLoadMobileRestricted = false;
    _transitionInFlight.clear();
    _notificationService.clearCache();
  }

  bool _isCurrentAuthGeneration(int generation) =>
      !_disposed && generation == _authGeneration;

  static String? _normalizeOptional(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  // ---------------------------
  // Workflow engine helpers
  // ---------------------------

  String _transitionKey(String documentId, String action, int? fromStep) =>
      '$documentId::$action::${fromStep ?? 0}';

  bool _beginTransition(String documentId, String action, int? fromStep) {
    final key = _transitionKey(documentId, action, fromStep);
    if (_transitionInFlight.contains(key)) return false;
    _transitionInFlight.add(key);
    return true;
  }

  void _endTransition(String documentId, String action, int? fromStep) {
    _transitionInFlight.remove(_transitionKey(documentId, action, fromStep));
  }

  int _fnv1aHash(String input) {
    // Small deterministic hash for idempotency keys (avoid including huge text).
    const int prime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash = (hash ^ codeUnit) * prime;
      // Keep it in 32-bit space.
      hash &= 0xFFFFFFFF;
    }
    return hash;
  }

  String _transitionIdempotencyKey({
    required String action,
    required String documentId,
    required int fromStep,
    required String actorId,
    required String stateToken,
    String? remarks,
    String? targetHolderId,
  }) {
    final r = (remarks ?? '').trim();
    final t = (targetHolderId ?? '').trim();
    return '$action:$actorId:$documentId:$fromStep:${_fnv1aHash(stateToken)}:${_fnv1aHash(r)}:${_fnv1aHash(t)}';
  }

  String _transitionStateToken(DocuTrackerDocument doc) {
    final updatedAt = doc.updatedAt?.toUtc().toIso8601String() ?? '';
    final sentTime = doc.sentTime?.toUtc().toIso8601String() ?? '';
    return '${doc.status.value}|${doc.currentStep ?? 0}|${doc.currentHolderId ?? ''}|$updatedAt|$sentTime';
  }

  Future<bool> _transitionWithAction({
    required DocuTrackerDocument doc,
    required String action,
    required String actionBy,
    required String failureMessage,
    String? remarks,
    String? targetHolderId,
  }) async {
    if (doc.id == null) return false;
    final authGeneration = _authGeneration;
    final documentId = doc.id!;
    final fromStep = doc.currentStep ?? 1;

    return _runTransition(
      documentId: documentId,
      action: action,
      fromStep: fromStep,
      run: () async {
        final idempotencyKey = _transitionIdempotencyKey(
          action: action,
          documentId: documentId,
          fromStep: fromStep,
          actorId: actionBy,
          stateToken: _transitionStateToken(doc),
          remarks: remarks,
          targetHolderId: targetHolderId,
        );

        final result = await _workflowService.transitionDocument(
          documentId: documentId,
          action: action,
          remarks: remarks,
          targetHolderId: targetHolderId,
          idempotencyKey: idempotencyKey,
        );
        if (!_isCurrentAuthGeneration(authGeneration)) return false;
        if (result is DocuTrackerFailure<DocuTrackerDocument>) {
          _error = result.message.isNotEmpty ? result.message : failureMessage;
          return false;
        }
        if (result is DocuTrackerSuccess<DocuTrackerDocument>) {
          _upsertLocalDocument(result.value);
          await refreshDocument(documentId, reloadHistory: true);
          if (!_isCurrentAuthGeneration(authGeneration)) return false;
          await loadNotifications(forceRefresh: true);
          if (!_isCurrentAuthGeneration(authGeneration)) return false;
          await _reloadDocumentsIfCached();
          return _isCurrentAuthGeneration(authGeneration);
        }
        _error = failureMessage;
        return false;
      },
    );
  }

  /// Runs a workflow transition with:
  /// - idempotency/anti double-tap guard
  /// - consistent `_loading` + `_error` handling
  /// - guaranteed cleanup (locks are always released)
  Future<bool> _runTransition({
    required String documentId,
    required String action,
    required int fromStep,
    required Future<bool> Function() run,
  }) async {
    final authGeneration = _authGeneration;
    if (!_beginTransition(documentId, action, fromStep)) {
      _error = 'This action is already in progress. Please wait.';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      return await run();
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return false;
      _error = e.toString();
      return false;
    } finally {
      _endTransition(documentId, action, fromStep);
      if (_isCurrentAuthGeneration(authGeneration)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _upsertLocalDocument(DocuTrackerDocument updated) {
    final id = updated.id;
    if (id == null) return;
    final idx = _documents.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      _documents[idx] = updated;
      return;
    }
    // Keep created/new documents near the top.
    _documents = [updated, ..._documents];
  }

  String? _documentsLoadUserId;
  String? _documentsLoadScopeKey;
  bool _documentsLoadIsAdmin = false;
  String? _documentsLoadRoleId;
  String? _documentsLoadDepartmentId;
  String? _documentsLoadOfficeId;
  String? _documentsLoadDocumentType;
  DocumentStatus? _documentsLoadStatus;
  bool _documentsLoadMobileRestricted = false;

  String _documentsScopeKey({
    required String userId,
    String? roleId,
    String? departmentId,
    String? officeId,
    String? documentType,
    DocumentStatus? status,
    required bool isAdmin,
    required bool mobileRestricted,
  }) => [
    _normalizeOptional(userId) ?? '',
    _normalizeOptional(roleId) ?? '',
    _normalizeOptional(departmentId) ?? '',
    _normalizeOptional(officeId) ?? '',
    _normalizeOptional(documentType) ?? '',
    status?.value ?? '',
    isAdmin,
    mobileRestricted,
  ].join('|');

  List<DocuTrackerDocument> get documents => List.unmodifiable(_documents);
  List<DocumentHistoryEntry> get documentHistory =>
      List.unmodifiable(_documentHistory);
  List<DocumentNotification> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadNotificationsCount =>
      _notificationService.unreadCount(_notifications);

  /// Pending RSP/L&D e-sign tasks for the current user (and admin setup /
  /// still-unsigned assigned forms). Completed signatures stay in the list
  /// but do not inflate this badge count.
  int get pendingSourceSignatureActionCount =>
      _sourceSignatureRequests
          .where((request) => request.hasActionableRequiredAction)
          .length;

  /// DocuTracker sidebar attention: unread workflow notices + pending e-signs.
  int get docuTrackerAttentionCount =>
      unreadNotificationsCount + pendingSourceSignatureActionCount;

  /// WIP drafts created by [userId], not yet submitted into workflow.
  List<DocuTrackerDocument> myDraftsForUser(String userId) => _documents
      .where(
        (d) =>
            DocuTrackerDocumentVisibility.isWorkInProgressDraft(d) &&
            d.createdBy == userId,
      )
      .toList();

  /// Active reviews assigned to [userId] (excludes unsubmitted WIP drafts).
  List<DocuTrackerDocument> incomingForUser(String userId) => _documents
      .where(
        (d) =>
            !DocuTrackerDocumentVisibility.isWorkInProgressDraft(d) &&
            d.currentHolderId == userId &&
            (d.status == DocumentStatus.pending ||
                d.status == DocumentStatus.inReview ||
                d.status == DocumentStatus.escalated),
      )
      .toList();

  /// Step 10: Pending reviews (same as incoming).
  List<DocuTrackerDocument> pendingReviewsForUser(String userId) =>
      incomingForUser(userId);

  /// Step 10: Nearing deadline (within 1 hour).
  List<DocuTrackerDocument> nearingDeadlineForUser(String userId) {
    final now = DateTime.now();
    final threshold = now.add(const Duration(hours: 1));
    return _documents
        .where(
          (d) =>
              d.currentHolderId == userId &&
              d.deadlineTime != null &&
              d.deadlineTime!.isAfter(now) &&
              d.deadlineTime!.isBefore(threshold) &&
              d.status != DocumentStatus.approved &&
              d.status != DocumentStatus.rejected &&
              d.status != DocumentStatus.cancelled,
        )
        .toList();
  }

  /// Step 10: Overdue documents.
  List<DocuTrackerDocument> get overdueDocuments => _documents
      .where(
        (d) =>
            d.status == DocumentStatus.overdue ||
            (d.deadlineTime != null &&
                DateTime.now().isAfter(d.deadlineTime!) &&
                d.status != DocumentStatus.approved &&
                d.status != DocumentStatus.rejected &&
                d.status != DocumentStatus.cancelled),
      )
      .toList();

  /// Step 10: Returned documents.
  List<DocuTrackerDocument> get returnedDocuments =>
      _documents.where((d) => d.status == DocumentStatus.returned).toList();

  /// Step 10: Completed documents.
  List<DocuTrackerDocument> get completedDocuments => _documents
      .where(
        (d) =>
            d.status == DocumentStatus.approved ||
            d.status == DocumentStatus.rejected,
      )
      .toList();

  /// Step 10: Admin - escalated documents.
  List<DocuTrackerDocument> get escalatedDocuments =>
      _documents.where((d) => d.status == DocumentStatus.escalated).toList();

  /// Documents flagged by the escalation worker for admin attention.
  List<DocuTrackerDocument> get documentsNeedingAdminIntervention =>
      _documents.where((d) => d.needsAdminIntervention).toList();
  List<DocumentRoutingConfig> get routingConfigs =>
      List.unmodifiable(_routingConfigs);
  List<DocumentPermission> get permissions => List.unmodifiable(_permissions);
  bool get loading => _loading;
  String? get error => _error;
  DocuTrackerDocumentBuilderData? get builderData => _builderData;
  bool get builderLoading => _builderLoading;
  String? get builderError => _builderError;

  /// Load routing configs (Step 1 & 3).
  Future<void> loadRoutingConfigs() async {
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final routingConfigs = await _repo.getRoutingConfigs();
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _routingConfigs = routingConfigs;
      if (_routingConfigs.isEmpty) {
        _routingConfigs = DocumentRoutingConfig.defaults;
      }
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _error = e.toString();
    }
    if (!_isCurrentAuthGeneration(authGeneration)) return;
    _loading = false;
    notifyListeners();
  }

  Future<void> _reloadDocumentsIfCached() async {
    final userId = _documentsLoadUserId;
    if (userId == null || userId.isEmpty) return;
    await loadDocumentsForUser(
      userId: userId,
      roleId: _documentsLoadRoleId,
      departmentId: _documentsLoadDepartmentId,
      officeId: _documentsLoadOfficeId,
      documentType: _documentsLoadDocumentType,
      status: _documentsLoadStatus,
      isAdmin: _documentsLoadIsAdmin,
      mobileRestricted: _documentsLoadMobileRestricted,
      showLoading: false,
    );
  }

  /// Load documents for current user (Step 2: Role-Based Visibility).
  Future<void> loadDocumentsForUser({
    required String userId,
    String? roleId,
    String? departmentId,
    String? officeId,
    String? documentType,
    DocumentStatus? status,
    bool isAdmin = false,
    bool mobileRestricted = false,
    bool showLoading = true,
  }) async {
    final authGeneration = _authGeneration;
    final scopeKey = _documentsScopeKey(
      userId: userId,
      roleId: roleId,
      departmentId: departmentId,
      officeId: officeId,
      documentType: documentType,
      status: status,
      isAdmin: isAdmin,
      mobileRestricted: mobileRestricted,
    );
    final preservePreviousDocuments = _documentsLoadScopeKey == scopeKey;
    _documentsLoadScopeKey = scopeKey;
    _documentsLoadUserId = userId;
    _documentsLoadIsAdmin = isAdmin;
    _documentsLoadRoleId = roleId;
    _documentsLoadDepartmentId = departmentId;
    _documentsLoadOfficeId = officeId;
    _documentsLoadDocumentType = documentType;
    _documentsLoadStatus = status;
    _documentsLoadMobileRestricted = mobileRestricted;
    if (showLoading) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final effectiveIsAdmin = isAdmin && !mobileRestricted;
      if (effectiveIsAdmin) {
        final r = await _repo.listAllDocuments(
          documentType: documentType,
          status: status,
          limit: 100,
        );
        if (!_isCurrentDocumentRequest(authGeneration, scopeKey)) return;
        if (r is DocuTrackerFailure<List<DocuTrackerDocument>>) {
          if (!preservePreviousDocuments) _documents = [];
          _error = r.message;
        } else if (r is DocuTrackerSuccess<List<DocuTrackerDocument>>) {
          _documents = r.value;
        } else {
          if (!preservePreviousDocuments) _documents = [];
          _error = 'Could not load documents.';
        }
      } else {
        final r = await _repo.listDocumentsForUser(
          userId: userId,
          userRoleId: roleId,
          userDepartmentId: departmentId,
          userOfficeId: officeId,
          createdBy: mobileRestricted ? userId : null,
          documentType: documentType,
          status: status,
          limit: 100,
        );
        if (!_isCurrentDocumentRequest(authGeneration, scopeKey)) return;
        if (r is DocuTrackerFailure<List<DocuTrackerDocument>>) {
          if (!preservePreviousDocuments) _documents = [];
          _error = r.message;
        } else if (r is DocuTrackerSuccess<List<DocuTrackerDocument>>) {
          _documents = DocuTrackerDocumentVisibility.filterForUser(
            r.value,
            userId: userId,
          );
        } else {
          if (!preservePreviousDocuments) _documents = [];
          _error = 'Could not load documents.';
        }
      }
      if (mobileRestricted) {
        _documents = DocuTrackerAccessPolicy.filterDocumentsForMobileUser(
          _documents,
          userId: userId,
        );
      }
    } catch (e) {
      if (!_isCurrentDocumentRequest(authGeneration, scopeKey)) return;
      if (!preservePreviousDocuments) _documents = [];
      _error = e.toString();
    }
    if (!_isCurrentDocumentRequest(authGeneration, scopeKey)) return;
    _loading = false;
    notifyListeners();
  }

  bool _isCurrentDocumentRequest(int authGeneration, String scopeKey) =>
      _isCurrentAuthGeneration(authGeneration) &&
      _documentsLoadScopeKey == scopeKey;

  /// Load permissions (Step 4: Admin Privilege Management).
  Future<void> loadPermissions({
    String? roleId,
    String? userId,
    String? documentType,
    bool userOnly = false,
  }) async {
    final loadKey = [roleId, userId, documentType, userOnly].join('|');
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final permissions = await _repo.listPermissions(
        roleId: roleId,
        userId: userId,
        documentType: documentType,
        userOnly: userOnly,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _permissions = permissions;
      _permissionsLoadKey = loadKey;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      if (_permissionsLoadKey != loadKey) _permissions = [];
      _error = e.toString();
    }
    if (!_isCurrentAuthGeneration(authGeneration)) return;
    _loading = false;
    notifyListeners();
  }

  /// Get routing config for document type (Step 3).
  DocumentRoutingConfig? getRoutingConfigForType(DocumentType type) {
    for (final c in _routingConfigs) {
      if (c.documentType == type) return c;
    }
    return null;
  }

  /// True when the document type has at least one enabled workflow step.
  bool hasRunnableWorkflowForType(DocumentType type) {
    final cfg = getRoutingConfigForType(type);
    if (cfg == null) return false;
    return cfg.steps.any((s) => s.enabled && s.stepOrder > 0);
  }

  /// User-facing hint when workflow routing is missing or empty.
  String? workflowConfigIssueForType(DocumentType type) {
    final cfg = getRoutingConfigForType(type);
    if (cfg == null) {
      return 'No workflow is configured for ${type.displayName}. '
          'Ask an admin to set up routing in DocuTracker → Admin → Workflows.';
    }
    final enabled = cfg.steps
        .where((s) => s.enabled && s.stepOrder > 0)
        .toList();
    if (enabled.isEmpty) {
      return 'The ${type.displayName} workflow has no active steps. '
          'An admin must add at least one step with assignees and save.';
    }
    return null;
  }

  /// Load document history for audit trail (Step 9).
  Future<void> loadDocumentHistory(String documentId) async {
    final authGeneration = _authGeneration;
    try {
      final history = await _repo.listDocumentHistory(documentId);
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _documentHistory = history;
      _documentHistoryLoadDocumentId = documentId;
      _error = null;
      notifyListeners();
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      if (_documentHistoryLoadDocumentId != documentId) {
        _documentHistory = [];
      }
      _error = e.toString().trim().isEmpty
          ? 'Could not load document activity.'
          : e.toString();
      notifyListeners();
    }
  }

  /// Load notifications for user (Step 7).
  Future<void> loadNotifications({bool forceRefresh = false}) async {
    final authGeneration = _authGeneration;
    try {
      final notifications = await _notificationService.fetchMyNotifications(
        forceRefresh: forceRefresh,
      );
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _notifications = notifications;
      _error = null;
      notifyListeners();
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _error = e.toString().trim().isEmpty
          ? 'Could not load notifications.'
          : e.toString();
      notifyListeners();
    }
  }

  /// Persists read state and updates in-memory list.
  Future<bool> markNotificationRead(String notificationId) async {
    final authGeneration = _authGeneration;
    final updated = await _repo.markNotificationRead(notificationId);
    if (updated == null || !_isCurrentAuthGeneration(authGeneration)) {
      return false;
    }
    _notifications = [
      for (final n in _notifications)
        if (n.id == notificationId) updated else n,
    ];
    _notificationService.clearCache();
    notifyListeners();
    return true;
  }

  /// Marks all notifications read for the current user (server + refresh list).
  Future<bool> markAllNotificationsRead() async {
    final authGeneration = _authGeneration;
    final updated = await _repo.markAllNotificationsRead();
    if (updated == null || !_isCurrentAuthGeneration(authGeneration)) {
      return false;
    }
    _notificationService.clearCache();
    await loadNotifications(forceRefresh: true);
    return _isCurrentAuthGeneration(authGeneration);
  }

  /// Refresh a single document from backend and update local state.
  /// Useful when server-side workflows (escalation worker) update status/holder.
  Future<void> refreshDocument(
    String documentId, {
    bool reloadHistory = false,
  }) async {
    final authGeneration = _authGeneration;
    try {
      final res = await _repo.getDocument(documentId);
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      if (res is DocuTrackerFailure<DocuTrackerDocument>) {
        _error = res.message.isNotEmpty
            ? res.message
            : 'Could not refresh document.';
        notifyListeners();
        return;
      }
      if (res is! DocuTrackerSuccess<DocuTrackerDocument>) return;
      _upsertLocalDocument(res.value);
      if (reloadHistory) {
        await loadDocumentHistory(documentId);
        if (!_isCurrentAuthGeneration(authGeneration)) return;
      }
      notifyListeners();
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Create document and start workflow.
  Future<DocuTrackerDocument?> createDocument({
    required String title,
    required DocumentType documentType,
    String? description,
    String? filePath,
    String? fileName,
    required String createdBy,
  }) async {
    final authGeneration = _authGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final doc = DocuTrackerDocument(
        documentType: documentType.value,
        title: title,
        description: description,
        filePath: filePath,
        fileName: fileName,
        createdBy: createdBy,
      );

      // Delegate to backend workflow engine so creation is transactional:
      // doc insert + routing_record step 1 + history + notification.
      final created = await _repo.createDocument(doc);
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      if (created is DocuTrackerFailure<DocuTrackerDocument>) {
        _error = created.message.isNotEmpty
            ? created.message
            : 'Failed to create document.';
        _loading = false;
        notifyListeners();
        return null;
      }
      if (created is! DocuTrackerSuccess<DocuTrackerDocument>) {
        _error = 'Failed to create document.';
        _loading = false;
        notifyListeners();
        return null;
      }

      _documents = [created.value, ..._documents];
      _loading = false;
      notifyListeners();
      return created.value;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<DocuTrackerDocumentBuilderData?> loadDocumentBuilder(
    String documentId,
  ) async {
    final authGeneration = _authGeneration;
    _builderLoading = true;
    _builderError = null;
    notifyListeners();
    final result = await _repo.getDocumentBuilder(documentId);
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _builderLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerDocumentBuilderData>(:final value):
        _builderData = value;
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerDocumentBuilderData>(:final message):
        _builderError = message;
        notifyListeners();
        return null;
    }
  }

  Future<DocuTrackerDocumentBuilderData?> saveDocumentBuilder({
    required String documentId,
    required List<DocuTrackerDocumentPage> pages,
    required List<DocuTrackerSignatureField> signatureFields,
    required int revision,
  }) async {
    if (_builderLoading) return null;
    final authGeneration = _authGeneration;
    _builderLoading = true;
    _builderError = null;
    notifyListeners();
    final result = await _repo.saveDocumentBuilder(
      documentId: documentId,
      pages: pages,
      signatureFields: signatureFields,
      revision: revision,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _builderLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerDocumentBuilderData>(:final value):
        _builderData = value;
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerDocumentBuilderData>(:final message):
        _builderError = message;
        notifyListeners();
        return null;
    }
  }

  Future<List<DocuTrackerSignatureAsset>> listSavedSignatures() async {
    final result = await _repo.listSavedSignatureAssets();
    return switch (result) {
      DocuTrackerSuccess<List<DocuTrackerSignatureAsset>>(:final value) =>
        value,
      DocuTrackerFailure<List<DocuTrackerSignatureAsset>>(:final message) =>
        throw Exception(message),
    };
  }

  Future<DocuTrackerLinkedSourceDocument> loadLinkedSourceDocument({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async {
    final result = await _repo.getLinkedSourceDocument(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
    );
    return switch (result) {
      DocuTrackerSuccess<DocuTrackerLinkedSourceDocument>(:final value) =>
        value,
      DocuTrackerFailure<DocuTrackerLinkedSourceDocument>(:final message) =>
        throw Exception(message),
    };
  }

  Future<DocuTrackerSignatureAsset> createSavedSignature({
    required Uint8List imageBytes,
    required String mimeType,
    required String sourceType,
    required String displayName,
  }) async {
    final result = await _repo.createSignatureAsset(
      imageBytes: imageBytes,
      mimeType: mimeType,
      sourceType: sourceType,
      displayName: displayName,
      saveForReuse: true,
    );
    return switch (result) {
      DocuTrackerSuccess<DocuTrackerSignatureAsset>(:final value) => value,
      DocuTrackerFailure<DocuTrackerSignatureAsset>(:final message) =>
        throw Exception(message),
    };
  }

  Future<DocuTrackerSignatureAsset> renameSavedSignature({
    required String assetId,
    required String displayName,
  }) async {
    final result = await _repo.renameSavedSignatureAsset(
      assetId: assetId,
      displayName: displayName,
    );
    return switch (result) {
      DocuTrackerSuccess<DocuTrackerSignatureAsset>(:final value) => value,
      DocuTrackerFailure<DocuTrackerSignatureAsset>(:final message) =>
        throw Exception(message),
    };
  }

  Future<void> removeSavedSignature(String assetId) async {
    final result = await _repo.removeSavedSignatureAsset(assetId);
    switch (result) {
      case DocuTrackerSuccess<void>():
        return;
      case DocuTrackerFailure<void>(:final message):
        throw Exception(message);
    }
  }

  bool get sourceSignatureLoading => _sourceSignatureLoading;
  String? get sourceSignatureError => _sourceSignatureError;
  List<DocuTrackerRspSignatureRequest> get sourceSignatureRequests =>
      List.unmodifiable(_sourceSignatureRequests);
  bool get sourceSignatureRequestsLoading => _sourceSignatureRequestsLoading;
  String? get sourceSignatureRequestsError => _sourceSignatureRequestsError;

  List<DocuTrackerRspSignatureRequest> get rspSignatureRequests =>
      sourceSignatureRequests
          .where((request) => request.sourceModule == 'rsp')
          .toList(growable: false);
  bool get rspSignatureRequestsLoading => sourceSignatureRequestsLoading;
  String? get rspSignatureRequestsError => sourceSignatureRequestsError;

  Future<void> loadSourceSignatureRequests() async {
    if (_sourceSignatureRequestsLoading) return;
    final authGeneration = _authGeneration;
    _sourceSignatureRequestsLoading = true;
    _sourceSignatureRequestsError = null;
    notifyListeners();
    final results = await Future.wait([
      _repo.getSourceSignatureRequests(sourceModule: 'rsp'),
      _repo.getSourceSignatureRequests(sourceModule: 'ld'),
    ]);
    if (!_isCurrentAuthGeneration(authGeneration)) return;
    _sourceSignatureRequestsLoading = false;
    final requests = <DocuTrackerRspSignatureRequest>[];
    final errors = <String>[];
    for (final result in results) {
      switch (result) {
        case DocuTrackerSuccess<List<DocuTrackerRspSignatureRequest>>(
          :final value,
        ):
          requests.addAll(value);
        case DocuTrackerFailure<List<DocuTrackerRspSignatureRequest>>(
          :final message,
        ):
          errors.add(message);
      }
    }
    _sourceSignatureRequests = requests;
    _sourceSignatureRequestsError = errors.isEmpty ? null : errors.join(' ');
    notifyListeners();
  }

  Future<void> loadRspSignatureRequests() => loadSourceSignatureRequests();

  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async {
    final authGeneration = _authGeneration;
    _sourceSignatureLoading = true;
    _sourceSignatureError = null;
    notifyListeners();
    final result = await _repo.getSourceSignatures(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _sourceSignatureLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerSourceSignatureBundle>(:final value):
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerSourceSignatureBundle>(:final message):
        _sourceSignatureError = message;
        notifyListeners();
        return null;
    }
  }

  Future<DocuTrackerSourceSignatureBundle?> signSourceApplicant({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
    String? signatureAssetId,
    Uint8List? imageBytes,
    String mimeType = 'image/png',
    String sourceType = 'drawn',
    bool saveForReuse = false,
  }) async {
    return signSourceSignature(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
      slotKey: 'applicant',
      signatureAssetId: signatureAssetId,
      imageBytes: imageBytes,
      mimeType: mimeType,
      sourceType: sourceType,
      saveForReuse: saveForReuse,
    );
  }

  Future<DocuTrackerSourceSignatureBundle?> signSourceSignature({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
    required String slotKey,
    String? signatureAssetId,
    Uint8List? imageBytes,
    String mimeType = 'image/png',
    String sourceType = 'drawn',
    bool saveForReuse = false,
  }) async {
    if (_sourceSignatureLoading) return null;
    final authGeneration = _authGeneration;
    _sourceSignatureLoading = true;
    _sourceSignatureError = null;
    notifyListeners();
    final result = await _repo.signSourceSignature(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
      slotKey: slotKey,
      signatureAssetId: signatureAssetId,
      imageBytes: imageBytes,
      mimeType: mimeType,
      sourceType: sourceType,
      saveForReuse: saveForReuse,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _sourceSignatureLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerSourceSignatureBundle>(:final value):
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerSourceSignatureBundle>(:final message):
        _sourceSignatureError = message;
        notifyListeners();
        return null;
    }
  }

  Future<DocuTrackerSourceSignatureBundle?> assignSourceSignature({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
    required String slotKey,
    required String assignedSignerId,
    String? recoveryRemarks,
  }) async {
    if (_sourceSignatureLoading) return null;
    final authGeneration = _authGeneration;
    _sourceSignatureLoading = true;
    _sourceSignatureError = null;
    notifyListeners();
    final result = await _repo.assignSourceSignature(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
      slotKey: slotKey,
      assignedSignerId: assignedSignerId,
      recoveryRemarks: recoveryRemarks,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _sourceSignatureLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerSourceSignatureBundle>(:final value):
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerSourceSignatureBundle>(:final message):
        _sourceSignatureError = message;
        notifyListeners();
        return null;
    }
  }

  Future<DocuTrackerDocumentBuilderData?> signDocumentField({
    required String documentId,
    required String fieldId,
    String? signatureAssetId,
    Uint8List? imageBytes,
    String mimeType = 'image/png',
    String sourceType = 'drawn',
    bool saveForReuse = false,
  }) async {
    if (_builderLoading) return null;
    final authGeneration = _authGeneration;
    _builderLoading = true;
    _builderError = null;
    notifyListeners();
    final result = await _repo.signDocumentField(
      documentId: documentId,
      fieldId: fieldId,
      signatureAssetId: signatureAssetId,
      imageBytes: imageBytes,
      mimeType: mimeType,
      sourceType: sourceType,
      saveForReuse: saveForReuse,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _builderLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerDocumentBuilderData>(:final value):
        _builderData = value;
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerDocumentBuilderData>(:final message):
        _builderError = message;
        notifyListeners();
        return null;
    }
  }

  Future<DocuTrackerDocumentBuilderData?> moveSignedDocumentField({
    required String documentId,
    required String fieldId,
    required double x,
    required double y,
  }) async {
    if (_builderLoading) return null;
    final authGeneration = _authGeneration;
    _builderLoading = true;
    _builderError = null;
    notifyListeners();
    final result = await _repo.moveSignedDocumentField(
      documentId: documentId,
      fieldId: fieldId,
      x: x,
      y: y,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    _builderLoading = false;
    switch (result) {
      case DocuTrackerSuccess<DocuTrackerDocumentBuilderData>(:final value):
        _builderData = value;
        notifyListeners();
        return value;
      case DocuTrackerFailure<DocuTrackerDocumentBuilderData>(:final message):
        _builderError = message;
        notifyListeners();
        return null;
    }
  }

  /// Submit document to start workflow (Step 10).
  Future<bool> submitDocument(
    DocuTrackerDocument doc, {
    required String actionBy,
    String? remarks,
  }) async {
    return _transitionWithAction(
      doc: doc,
      action: 'submit',
      actionBy: actionBy,
      remarks: remarks,
      failureMessage: 'Failed to submit document.',
    );
  }

  /// Forward document to next reviewer (Step 3, Step 8).
  Future<bool> forwardDocument(
    DocuTrackerDocument doc, {
    required String actionBy,
    String? remarks,
  }) async {
    return _transitionWithAction(
      doc: doc,
      action: 'forward',
      actionBy: actionBy,
      remarks: remarks,
      failureMessage: 'Failed to forward document.',
    );
  }

  /// Approve document (Step 8).
  Future<bool> approveDocument(
    DocuTrackerDocument doc, {
    String? remarks,
    required String actionBy,
  }) async {
    return _transitionWithAction(
      doc: doc,
      action: 'approve',
      actionBy: actionBy,
      remarks: remarks,
      failureMessage: 'Failed to approve document.',
    );
  }

  /// Reject document (Step 8).
  Future<bool> rejectDocument(
    DocuTrackerDocument doc, {
    String? remarks,
    required String actionBy,
  }) async {
    return _transitionWithAction(
      doc: doc,
      action: 'reject',
      actionBy: actionBy,
      remarks: remarks,
      failureMessage: 'Failed to reject document.',
    );
  }

  /// Return document to previous step (Step 8).
  Future<bool> returnDocument(
    DocuTrackerDocument doc, {
    String? remarks,
    required String actionBy,
  }) async {
    return _transitionWithAction(
      doc: doc,
      action: 'return',
      actionBy: actionBy,
      remarks: remarks,
      failureMessage: 'Failed to return document.',
    );
  }

  /// Add remark/comment to document (Step 8).
  Future<bool> addRemark(
    DocuTrackerDocument doc, {
    required String actorId,
    required String remarks,
  }) async {
    if (doc.id == null || remarks.trim().isEmpty) return false;
    final authGeneration = _authGeneration;
    final ok = await _workflowService.addDocumentRemark(
      documentId: doc.id!,
      remarks: remarks.trim(),
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return false;
    if (!ok) {
      _error = 'Failed to add remark.';
      notifyListeners();
    }
    return ok;
  }

  /// Save permission (Step 4: Admin Privilege Management).
  Future<void> savePermission(DocumentPermission perm) async {
    final authGeneration = _authGeneration;
    try {
      await _repo.savePermission(perm);
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      await loadPermissions();
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return;
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<DocuTrackerDocument?> uploadAttachment({
    required String documentId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final authGeneration = _authGeneration;
    _error = null;
    final res = await _repo.uploadAttachment(
      documentId: documentId,
      fileBytes: fileBytes,
      fileName: fileName,
    );
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    if (res is DocuTrackerFailure<DocuTrackerDocument>) {
      _error = res.message.isNotEmpty ? res.message : 'Upload failed.';
      notifyListeners();
      return null;
    }
    if (res is! DocuTrackerSuccess<DocuTrackerDocument>) return null;
    _upsertLocalDocument(res.value);
    notifyListeners();
    return res.value;
  }

  Future<DocuTrackerDocument?> removeAttachment(String documentId) async {
    final authGeneration = _authGeneration;
    _error = null;
    final res = await _repo.removeAttachment(documentId);
    if (!_isCurrentAuthGeneration(authGeneration)) return null;
    if (res is DocuTrackerFailure<DocuTrackerDocument>) {
      _error = res.message.isNotEmpty ? res.message : 'Could not remove file.';
      notifyListeners();
      return null;
    }
    if (res is! DocuTrackerSuccess<DocuTrackerDocument>) return null;
    _upsertLocalDocument(res.value);
    notifyListeners();
    return res.value;
  }

  Future<List<int>?> getAttachmentBytes(String documentId) async {
    final authGeneration = _authGeneration;
    try {
      final bytes = await _repo.getAttachmentBytes(documentId);
      return _isCurrentAuthGeneration(authGeneration) ? bytes : null;
    } catch (e) {
      if (!_isCurrentAuthGeneration(authGeneration)) return null;
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authGeneration += 1;
    _notificationService.clearCache();
    super.dispose();
  }
}
