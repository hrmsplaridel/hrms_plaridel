import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'models/document.dart';
import 'models/document_history.dart';
import 'models/document_notification.dart';
import 'models/document_permission.dart';
import 'models/document_routing_config.dart';
import 'models/document_status.dart';
import 'models/document_type.dart';
import 'docutracker_repository.dart';

/// DocuTracker state management. Handles document list, routing configs,
/// permissions, and next-reviewer logic (Step 3).
class DocuTrackerProvider extends ChangeNotifier {
  DocuTrackerProvider() {
    _repo = DocuTrackerRepository.instance;
    _startEscalationTimer();
  }

  late final DocuTrackerRepository _repo;
  Timer? _escalationTimer;

  /// Step 12: Periodic check for overdue documents (every 2 min).
  void _startEscalationTimer() {
    _escalationTimer?.cancel();
    _escalationTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      checkAndEscalateOverdue();
    });
  }

  @override
  void dispose() {
    _escalationTimer?.cancel();
    super.dispose();
  }

  List<DocuTrackerDocument> _documents = [];
  List<DocumentRoutingConfig> _routingConfigs = [];
  List<DocumentPermission> _permissions = [];
  List<DocumentHistoryEntry> _documentHistory = [];
  List<DocumentNotification> _notifications = [];
  bool _loading = false;
  String? _error;

  List<DocuTrackerDocument> get documents => List.unmodifiable(_documents);
  List<DocumentHistoryEntry> get documentHistory =>
      List.unmodifiable(_documentHistory);
  List<DocumentNotification> get notifications =>
      List.unmodifiable(_notifications);

  /// Step 10: Employee dashboard - incoming (assigned to me, pending/inReview).
  List<DocuTrackerDocument> incomingForUser(String userId) => _documents
      .where((d) =>
          d.currentHolderId == userId &&
          (d.status == DocumentStatus.pending ||
              d.status == DocumentStatus.inReview))
      .toList();

  /// Step 10: Pending reviews (same as incoming).
  List<DocuTrackerDocument> pendingReviewsForUser(String userId) =>
      incomingForUser(userId);

  /// Step 10: Nearing deadline (within 1 hour).
  List<DocuTrackerDocument> nearingDeadlineForUser(String userId) {
    final now = DateTime.now();
    final threshold = now.add(const Duration(hours: 1));
    return _documents
        .where((d) =>
            d.currentHolderId == userId &&
            d.deadlineTime != null &&
            d.deadlineTime!.isAfter(now) &&
            d.deadlineTime!.isBefore(threshold) &&
            d.status != DocumentStatus.approved &&
            d.status != DocumentStatus.rejected)
        .toList();
  }

  /// Step 10: Overdue documents.
  List<DocuTrackerDocument> get overdueDocuments => _documents
      .where((d) =>
          d.status == DocumentStatus.overdue ||
          (d.deadlineTime != null &&
              DateTime.now().isAfter(d.deadlineTime!) &&
              d.status != DocumentStatus.approved &&
              d.status != DocumentStatus.rejected))
      .toList();

  /// Step 10: Returned documents.
  List<DocuTrackerDocument> get returnedDocuments =>
      _documents.where((d) => d.status == DocumentStatus.returned).toList();

  /// Step 10: Completed documents.
  List<DocuTrackerDocument> get completedDocuments => _documents
      .where((d) =>
          d.status == DocumentStatus.approved ||
          d.status == DocumentStatus.rejected)
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
        _documents = await _repo.listAllDocuments(
          documentType: documentType,
          status: status,
          limit: 100,
        );
      } else {
        _documents = await _repo.listDocumentsForUser(
          userId: userId,
          userRoleId: roleId,
          userDepartmentId: departmentId,
          userOfficeId: officeId,
          documentType: documentType,
          status: status,
          limit: 100,
        );
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

  /// Determine next step and assignee from current step (Step 3).
  /// Returns (nextStepOrder, assigneeIds) or null if workflow complete.
  (int, List<String>)? getNextStepAssignees(
    DocumentType docType,
    int currentStep,
  ) {
    final config = getRoutingConfigForType(docType);
    if (config == null) return null;
    final nextOrder = currentStep + 1;
    final nextStep = config.steps
        .where((s) => s.stepOrder == nextOrder)
        .firstOrNull;
    if (nextStep == null) return null;
    // Resolve assignee IDs from role/department/office/user
    final ids = <String>[];
    if (nextStep.userIds != null) ids.addAll(nextStep.userIds!);
    // TODO: resolve roleId -> userIds, departmentId -> userIds, etc. from HR data
    return (nextOrder, ids);
  }

  /// Load document history for audit trail (Step 9).
  Future<void> loadDocumentHistory(String documentId) async {
    try {
      _documentHistory =
          await _repo.listDocumentHistory(documentId);
      notifyListeners();
    } catch (_) {
      _documentHistory = [];
      notifyListeners();
    }
  }

  /// Load notifications for user (Step 7).
  Future<void> loadNotifications(String userId) async {
    try {
      _notifications = await _repo.listNotificationsForUser(userId);
      notifyListeners();
    } catch (_) {
      _notifications = [];
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
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final config = getRoutingConfigForType(documentType);
      final deadlineHours = config?.reviewDeadlineHours ?? 1;
      final now = DateTime.now();
      final deadline = now.add(Duration(hours: deadlineHours));
      final docNumber = await _repo.getNextDocumentNumber();

      final doc = DocuTrackerDocument(
        documentNumber: docNumber,
        documentType: documentType.value,
        title: title,
        description: description,
        filePath: filePath,
        fileName: fileName,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
        currentStep: 1,
        status: DocumentStatus.pending,
        sentTime: now,
        deadlineTime: deadline,
        currentHolderId: createdBy,
      );
      final created = await _repo.createDocument(doc);
      if (created != null) {
        _documents = [created, ..._documents];
        await _repo.addDocumentHistory(DocumentHistoryEntry(
          documentId: created.id!,
          action: 'created',
          actorId: createdBy,
          toStep: 1,
          toStatus: DocumentStatus.pending,
          createdAt: now,
        ));
      }
      _loading = false;
      notifyListeners();
      return created;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  /// Forward document to next reviewer (Step 3, Step 8).
  Future<bool> forwardDocument(
    DocuTrackerDocument doc, {
    required String actionBy,
    String? remarks,
  }) async {
    if (doc.id == null) return false;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final docType = documentTypeFromString(doc.documentType);
      final currentStep = doc.currentStep ?? 1;
      final next = getNextStepAssignees(docType, currentStep);
      final config = getRoutingConfigForType(docType);
      final deadlineHours = config?.reviewDeadlineHours ?? 1;
      final now = DateTime.now();
      final deadline = now.add(Duration(hours: deadlineHours));

      final updated = doc.copyWith(
        currentStep: next != null ? next.$1 : currentStep,
        status: next != null ? DocumentStatus.forwarded : DocumentStatus.approved,
        sentTime: now,
        deadlineTime: deadline,
        reviewedTime: now,
      );
      await _repo.updateDocument(updated);
      final idx = _documents.indexWhere((d) => d.id == doc.id);
      if (idx >= 0) _documents[idx] = updated;
      await _repo.addDocumentHistory(DocumentHistoryEntry(
        documentId: doc.id!,
        action: 'forwarded',
        actorId: actionBy,
        fromStep: doc.currentStep,
        toStep: updated.currentStep,
        fromStatus: doc.status,
        toStatus: updated.status,
        remarks: remarks,
        createdAt: DateTime.now(),
      ));
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Approve document (Step 8).
  Future<bool> approveDocument(DocuTrackerDocument doc,
      {String? remarks, required String actionBy}) async {
    if (doc.id == null) return false;
    try {
      final now = DateTime.now();
      final updated = doc.copyWith(
        status: DocumentStatus.approved,
        reviewedTime: now,
      );
      await _repo.updateDocument(updated);
      final idx = _documents.indexWhere((d) => d.id == doc.id);
      if (idx >= 0) _documents[idx] = updated;
      await _repo.addDocumentHistory(DocumentHistoryEntry(
        documentId: doc.id!,
        action: 'approved',
        actorId: actionBy,
        fromStep: doc.currentStep,
        fromStatus: doc.status,
        toStatus: DocumentStatus.approved,
        remarks: remarks,
        createdAt: now,
      ));
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Reject document (Step 8).
  Future<bool> rejectDocument(DocuTrackerDocument doc,
      {String? remarks, required String actionBy}) async {
    if (doc.id == null) return false;
    try {
      final now = DateTime.now();
      final updated = doc.copyWith(
        status: DocumentStatus.rejected,
        reviewedTime: now,
      );
      await _repo.updateDocument(updated);
      final idx = _documents.indexWhere((d) => d.id == doc.id);
      if (idx >= 0) _documents[idx] = updated;
      await _repo.addDocumentHistory(DocumentHistoryEntry(
        documentId: doc.id!,
        action: 'rejected',
        actorId: actionBy,
        fromStep: doc.currentStep,
        fromStatus: doc.status,
        toStatus: DocumentStatus.rejected,
        remarks: remarks,
        createdAt: now,
      ));
      if (doc.createdBy != null) {
        await _repo.addNotification(DocumentNotification(
          documentId: doc.id!,
          userId: doc.createdBy!,
          type: DocumentNotification.typeRejected,
          title: 'Document rejected',
          body: '${doc.title} was rejected${remarks != null ? ': $remarks' : ''}',
          createdAt: now,
        ));
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Return document to previous step (Step 8).
  Future<bool> returnDocument(DocuTrackerDocument doc,
      {String? remarks, required String actionBy}) async {
    if (doc.id == null) return false;
    try {
      final now = DateTime.now();
      final currentStep = (doc.currentStep ?? 1) - 1;
      final toStep = currentStep > 0 ? currentStep : 1;
      final updated = doc.copyWith(
        currentStep: toStep,
        status: DocumentStatus.returned,
        reviewedTime: now,
      );
      await _repo.updateDocument(updated);
      final idx = _documents.indexWhere((d) => d.id == doc.id);
      if (idx >= 0) _documents[idx] = updated;
      await _repo.addDocumentHistory(DocumentHistoryEntry(
        documentId: doc.id!,
        action: 'returned',
        actorId: actionBy,
        fromStep: doc.currentStep,
        toStep: toStep,
        fromStatus: doc.status,
        toStatus: DocumentStatus.returned,
        remarks: remarks,
        createdAt: now,
      ));
      if (doc.createdBy != null) {
        await _repo.addNotification(DocumentNotification(
          documentId: doc.id!,
          userId: doc.createdBy!,
          type: DocumentNotification.typeReturned,
          title: 'Document returned',
          body: '${doc.title} was returned to you${remarks != null ? ': $remarks' : ''}',
          createdAt: now,
        ));
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Add remark/comment to document (Step 8).
  Future<bool> addRemark(
    DocuTrackerDocument doc, {
    required String actorId,
    required String remarks,
  }) async {
    if (doc.id == null || remarks.trim().isEmpty) return false;
    try {
      await _repo.addDocumentHistory(DocumentHistoryEntry(
        documentId: doc.id!,
        action: 'remark',
        actorId: actorId,
        fromStep: doc.currentStep,
        fromStatus: doc.status,
        remarks: remarks.trim(),
        createdAt: DateTime.now(),
      ));
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Step 6 & 12: Check and escalate overdue documents.
  Future<void> checkAndEscalateOverdue() async {
    try {
      final overdue = await _repo.listOverdueForEscalation();
      for (final doc in overdue) {
        await _escalateDocument(doc);
      }
    } catch (_) {}
  }

  Future<void> _escalateDocument(DocuTrackerDocument doc) async {
    if (doc.id == null) return;
    try {
      final config = await _repo.getEscalationConfig(doc.documentType);
      final maxLevel = config?.maxEscalationLevel ?? 3;
      final currentLevel = doc.escalationLevel;
      if (currentLevel >= maxLevel) {
        await _repo.updateDocument(doc.copyWith(
          status: DocumentStatus.overdue,
          needsAdminIntervention: true,
        ));
        await _repo.addDocumentHistory(DocumentHistoryEntry(
          documentId: doc.id!,
          action: 'escalated',
          fromStatus: doc.status,
          toStatus: DocumentStatus.overdue,
          isOverdueLog: true,
          isEscalationLog: true,
          escalationLevel: currentLevel,
          remarks: 'Max escalation level reached. Admin intervention required.',
          createdAt: DateTime.now(),
        ));
      } else {
        final docType = documentTypeFromString(doc.documentType);
        final next = getNextStepAssignees(docType, doc.currentStep ?? 1);
        final deadlineHours = getRoutingConfigForType(docType)?.reviewDeadlineHours ?? 1;
        final newDeadline = DateTime.now().add(Duration(hours: deadlineHours));
        final updated = doc.copyWith(
          status: DocumentStatus.escalated,
          escalationLevel: currentLevel + 1,
          currentStep: next?.$1 ?? doc.currentStep,
          sentTime: DateTime.now(),
          deadlineTime: newDeadline,
        );
        await _repo.updateDocument(updated);
        await _repo.addDocumentHistory(DocumentHistoryEntry(
          documentId: doc.id!,
          action: 'escalated',
          fromStep: doc.currentStep,
          toStep: updated.currentStep,
          fromStatus: doc.status,
          toStatus: DocumentStatus.escalated,
          isOverdueLog: true,
          isEscalationLog: true,
          escalationLevel: updated.escalationLevel,
          remarks: 'Automatically escalated - deadline missed',
          createdAt: DateTime.now(),
        ));
        await _repo.addNotification(DocumentNotification(
          documentId: doc.id!,
          userId: doc.currentHolderId ?? doc.createdBy ?? '',
          type: DocumentNotification.typeOverdue,
          title: 'Document overdue',
          body: '${doc.title} was not reviewed in time and has been escalated.',
          createdAt: DateTime.now(),
        ));
      }
      notifyListeners();
    } catch (_) {}
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
