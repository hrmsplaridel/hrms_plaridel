import 'package:flutter/foundation.dart';
import 'models/document.dart';
import 'models/document_history.dart';
import 'models/document_notification.dart';
import 'models/document_permission.dart';
import 'models/document_routing_config.dart';
import 'models/document_status.dart';
import 'models/document_type.dart';
import 'docutracker_api_result.dart';
import 'docutracker_repository.dart';
import 'services/docutracker_workflow_service.dart';
import 'services/docutracker_notification_service.dart';

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

  @override
  void dispose() {
    super.dispose();
  }

  List<DocuTrackerDocument> _documents = [];
  List<DocumentRoutingConfig> _routingConfigs = [];
  List<DocumentPermission> _permissions = [];
  List<DocumentHistoryEntry> _documentHistory = [];
  List<DocumentNotification> _notifications = [];
  bool _loading = false;
  String? _error;

  // Prevent duplicate transitions due to double taps / retries.
  final Set<String> _transitionInFlight = <String>{};

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
    String? remarks,
    String? targetHolderId,
  }) {
    final r = (remarks ?? '').trim();
    final t = (targetHolderId ?? '').trim();
    return '$action:$actorId:$documentId:$fromStep:${_fnv1aHash(r)}:${_fnv1aHash(t)}';
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
        if (result is DocuTrackerFailure<DocuTrackerDocument>) {
          _error = result.message.isNotEmpty ? result.message : failureMessage;
          return false;
        }
        if (result is DocuTrackerSuccess<DocuTrackerDocument>) {
          _upsertLocalDocument(result.value);
          return true;
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
    if (!_beginTransition(documentId, action, fromStep)) return false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      return await run();
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
      _endTransition(documentId, action, fromStep);
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

  List<DocuTrackerDocument> get documents => List.unmodifiable(_documents);
  List<DocumentHistoryEntry> get documentHistory =>
      List.unmodifiable(_documentHistory);
  List<DocumentNotification> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadNotificationsCount =>
      _notificationService.unreadCount(_notifications);

  /// Step 10: Employee dashboard - incoming (assigned to me, pending/inReview).
  List<DocuTrackerDocument> incomingForUser(String userId) => _documents
      .where(
        (d) =>
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
              d.status != DocumentStatus.rejected,
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
                d.status != DocumentStatus.rejected),
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
  List<DocumentRoutingConfig> get routingConfigs =>
      List.unmodifiable(_routingConfigs);
  List<DocumentPermission> get permissions => List.unmodifiable(_permissions);
  bool get loading => _loading;
  String? get error => _error;

  /// Load routing configs (Step 1 & 3).
  Future<void> loadRoutingConfigs() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _routingConfigs = await _repo.getRoutingConfigs();
      if (_routingConfigs.isEmpty) {
        _routingConfigs = DocumentRoutingConfig.defaults;
      }
    } catch (e) {
      _routingConfigs = DocumentRoutingConfig.defaults;
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
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
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (isAdmin) {
        final r = await _repo.listAllDocuments(
          documentType: documentType,
          status: status,
          limit: 100,
        );
        if (r is DocuTrackerFailure<List<DocuTrackerDocument>>) {
          _documents = [];
          _error = r.message;
        } else if (r is DocuTrackerSuccess<List<DocuTrackerDocument>>) {
          _documents = r.value;
        } else {
          _documents = [];
        }
      } else {
        final r = await _repo.listDocumentsForUser(
          userId: userId,
          userRoleId: roleId,
          userDepartmentId: departmentId,
          userOfficeId: officeId,
          documentType: documentType,
          status: status,
          limit: 100,
        );
        if (r is DocuTrackerFailure<List<DocuTrackerDocument>>) {
          _documents = [];
          _error = r.message;
        } else if (r is DocuTrackerSuccess<List<DocuTrackerDocument>>) {
          _documents = r.value;
        } else {
          _documents = [];
        }
      }
    } catch (e) {
      _documents = [];
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  /// Load permissions (Step 4: Admin Privilege Management).
  Future<void> loadPermissions({
    String? roleId,
    String? userId,
    String? documentType,
    bool userOnly = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _permissions = await _repo.listPermissions(
        roleId: roleId,
        userId: userId,
        documentType: documentType,
        userOnly: userOnly,
      );
    } catch (e) {
      _permissions = [];
      _error = e.toString();
    }
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

  /// Load document history for audit trail (Step 9).
  Future<void> loadDocumentHistory(String documentId) async {
    try {
      _documentHistory = await _repo.listDocumentHistory(documentId);
      notifyListeners();
    } catch (_) {
      _documentHistory = [];
      notifyListeners();
    }
  }

  /// Load notifications for user (Step 7).
  Future<void> loadNotifications({bool forceRefresh = false}) async {
    try {
      _notifications = await _notificationService.fetchMyNotifications(
        forceRefresh: forceRefresh,
      );
      notifyListeners();
    } catch (_) {
      _notifications = [];
      notifyListeners();
    }
  }

  /// Persists read state and updates in-memory list.
  Future<bool> markNotificationRead(String notificationId) async {
    final updated = await _repo.markNotificationRead(notificationId);
    if (updated == null) return false;
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
    final updated = await _repo.markAllNotificationsRead();
    if (updated == null) return false;
    _notificationService.clearCache();
    await loadNotifications(forceRefresh: true);
    return true;
  }

  /// Refresh a single document from backend and update local state.
  /// Useful when server-side workflows (escalation worker) update status/holder.
  Future<void> refreshDocument(String documentId,
      {bool reloadHistory = false}) async {
    try {
      final res = await _repo.getDocument(documentId);
      if (res is! DocuTrackerSuccess<DocuTrackerDocument>) return;
      _upsertLocalDocument(res.value);
      if (reloadHistory) {
        await loadDocumentHistory(documentId);
      }
      notifyListeners();
    } catch (_) {}
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
      if (created is DocuTrackerFailure<DocuTrackerDocument>) {
        _error = created.message.isNotEmpty ? created.message : 'Failed to create document.';
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
      _error = e.toString();
      _loading = false;
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
    final ok = await _workflowService.addDocumentRemark(
      documentId: doc.id!,
      remarks: remarks.trim(),
    );
    if (!ok) {
      _error = 'Failed to add remark.';
      notifyListeners();
    }
    return ok;
  }

  /// Save permission (Step 4: Admin Privilege Management).
  Future<void> savePermission(DocumentPermission perm) async {
    try {
      await _repo.savePermission(perm);
      await loadPermissions();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
