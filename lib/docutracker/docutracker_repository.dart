import '../api/client.dart';
import 'models/document.dart';
import 'models/document_history.dart';
import 'models/document_notification.dart';
import 'models/document_action.dart';
import 'models/document_permission.dart';
import 'models/document_routing_config.dart';
import 'models/document_status.dart';
import 'models/escalation_config.dart';

/// DocuTracker data via HRMS PostgreSQL API (replaces Supabase client).
class DocuTrackerRepository {
  DocuTrackerRepository._();
  static final DocuTrackerRepository instance = DocuTrackerRepository._();

  static const _base = '/api/docutracker';

  Future<List<DocumentRoutingConfig>> getRoutingConfigs() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/routing-configs',
      );
      final list = res.data ?? [];
      if (list.isEmpty) return DocumentRoutingConfig.defaults;
      return list
          .map(
            (e) => DocumentRoutingConfig.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return DocumentRoutingConfig.defaults;
    }
  }

  Future<List<DocuTrackerDocument>> listDocumentsForUser({
    required String userId,
    String? userRoleId,
    String? userDepartmentId,
    String? userOfficeId,
    String? documentType,
    DocumentStatus? status,
    int? limit,
  }) async {
    try {
      final qp = <String, dynamic>{
        if (documentType != null && documentType.isNotEmpty) 'type': documentType,
        if (status != null) 'status': status.value,
        if (limit != null) 'limit': limit,
      };
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/documents',
        queryParameters: qp,
      );
      final list = res.data ?? [];
      return list
          .map(
            (e) => DocuTrackerDocument.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<DocuTrackerDocument>> listOverdueForEscalation() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/documents-overdue',
      );
      final list = res.data ?? [];
      return list
          .map(
            (e) => DocuTrackerDocument.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<DocuTrackerDocument>> listAllDocuments({
    String? documentType,
    DocumentStatus? status,
    int? limit,
  }) async {
    try {
      final qp = <String, dynamic>{
        if (documentType != null && documentType.isNotEmpty) 'type': documentType,
        if (status != null) 'status': status.value,
        if (limit != null) 'limit': limit,
      };
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/documents',
        queryParameters: qp,
      );
      final list = res.data ?? [];
      return list
          .map(
            (e) => DocuTrackerDocument.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<DocuTrackerDocument?> getDocument(String id) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_base/documents/$id',
      );
      final doc = res.data?['document'];
      if (doc is! Map) return null;
      return DocuTrackerDocument.fromJson(Map<String, dynamic>.from(doc));
    } catch (_) {
      return null;
    }
  }

  Future<String> getNextDocumentNumber() async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_base/next-document-number',
      );
      final n = res.data?['document_number']?.toString();
      if (n != null && n.isNotEmpty) return n;
    } catch (_) {}
    return 'DOC-${DateTime.now().year}-0001';
  }

  Future<DocuTrackerDocument?> createDocument(DocuTrackerDocument doc) async {
    try {
      final payload = Map<String, dynamic>.from(doc.toJson())
        ..remove('id')
        ..remove('creator_name')
        ..remove('assignee_name')
        ..remove('created_at')
        ..remove('updated_at');
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '$_base/documents',
        data: payload,
      );
      final row = res.data;
      if (row == null) return null;
      return DocuTrackerDocument.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> addDocumentHistory(DocumentHistoryEntry entry) async {
    try {
      final payload = Map<String, dynamic>.from(entry.toJson())
        ..remove('id')
        ..remove('created_at');
      await ApiClient.instance.post<void>(
        '$_base/documents/${entry.documentId}/history',
        data: payload,
      );
    } catch (_) {}
  }

  Future<List<DocumentHistoryEntry>> listDocumentHistory(String documentId) async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/documents/$documentId/history',
      );
      final list = res.data ?? [];
      return list
          .map(
            (e) => DocumentHistoryEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addNotification(DocumentNotification notif) async {
    try {
      final payload = Map<String, dynamic>.from(notif.toJson())..remove('id');
      await ApiClient.instance.post<void>('$_base/notifications', data: payload);
    } catch (_) {}
  }

  Future<List<DocumentNotification>> listNotificationsForUser(String userId) async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/notifications',
      );
      final list = res.data ?? [];
      return list
          .map(
            (e) => DocumentNotification.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<EscalationConfig?> getEscalationConfig(
    String documentType, {
    String? departmentId,
  }) async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/escalation-configs',
        queryParameters: {
          'document_type': documentType,
          if (departmentId != null) 'department_id': departmentId,
        },
      );
      final list = res.data ?? [];
      if (list.isEmpty) return null;
      return EscalationConfig.fromJson(
        Map<String, dynamic>.from(list.first as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> updateDocument(DocuTrackerDocument doc) async {
    if (doc.id == null) return;
    try {
      final payload = Map<String, dynamic>.from(doc.toJson())
        ..remove('creator_name')
        ..remove('assignee_name')
        ..remove('created_at');
      await ApiClient.instance.put<void>(
        '$_base/documents/${doc.id}',
        data: payload,
      );
    } catch (_) {}
  }

  Future<List<DocumentPermission>> listPermissions({
    String? roleId,
    String? userId,
    String? documentType,
    bool userOnly = false,
  }) async {
    try {
      final qp = <String, dynamic>{};
      if (roleId != null) qp['role_id'] = roleId;
      if (userId != null) qp['user_id'] = userId;
      if (documentType != null) qp['document_type'] = documentType;

      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/permission-records',
        queryParameters: qp,
      );
      final list = res.data ?? [];
      final perms = list
          .map(
            (e) => DocumentPermission.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      if (userOnly) {
        return perms.where((p) => p.userId != null).toList();
      }
      return perms;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePermission(DocumentPermission perm) async {
    try {
      await ApiClient.instance.post<void>(
        '$_base/permissions',
        data: {
          if (perm.userId != null) 'user_id': perm.userId,
          if (perm.roleId != null) 'role_id': perm.roleId,
          'document_type': perm.documentType,
          'action': perm.action.value,
          'granted': perm.granted,
        },
      );
    } catch (_) {}
  }

  Future<bool> canAccessDocument({
    required String userId,
    required String documentId,
    bool isAdmin = false,
  }) async {
    if (isAdmin) return true;
    try {
      final doc = await getDocument(documentId);
      if (doc == null) return false;
      if (doc.createdBy == userId || doc.currentHolderId == userId) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission({
    required String userId,
    String? roleId,
    required String documentType,
    required String action,
  }) async {
    try {
      final userPerms = await listPermissions(
        userId: userId,
        documentType: documentType,
      );
      final userAction = userPerms.where((p) => p.action.name == action);
      if (userAction.isNotEmpty) return userAction.first.granted;

      if (roleId != null) {
        final rolePerms = await listPermissions(
          roleId: roleId,
          documentType: documentType,
        );
        final roleAction = rolePerms.where((p) => p.action.name == action);
        if (roleAction.isNotEmpty) return roleAction.first.granted;
      }

      final wildUserPerms = await listPermissions(
        userId: userId,
        documentType: '*',
      );
      final wildUserAction = wildUserPerms.where((p) => p.action.name == action);
      if (wildUserAction.isNotEmpty) return wildUserAction.first.granted;

      if (roleId != null) {
        final wildRolePerms = await listPermissions(
          roleId: roleId,
          documentType: '*',
        );
        final wildRoleAction = wildRolePerms.where((p) => p.action.name == action);
        if (wildRoleAction.isNotEmpty) return wildRoleAction.first.granted;
      }

      final globalWildPerms = await listPermissions(documentType: '*');
      final globalWildAction = globalWildPerms.where(
        (p) => p.action.name == action,
      );
      if (globalWildAction.isNotEmpty) return globalWildAction.first.granted;
    } catch (_) {}
    return true;
  }
}
