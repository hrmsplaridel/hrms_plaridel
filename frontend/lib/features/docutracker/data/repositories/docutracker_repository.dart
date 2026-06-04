import 'package:dio/dio.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/escalation_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_ai_summary.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_notification.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_action.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_permission.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_record.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_document_visibility.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permission_service.dart';
import 'package:hrms_plaridel/features/docutracker/services/docutracker_permissions_datasource.dart';

String _apiErrorMessage(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is String && err.isNotEmpty) return err;
    }
    final code = e.response?.statusCode;
    if (code != null) return 'Request failed ($code)';
    if (e.message != null && e.message!.isNotEmpty) return e.message!;
  }
  return e.toString();
}

/// DocuTracker data via HRMS PostgreSQL API (replaces Supabase client).
class DocuTrackerRepository implements DocuTrackerPermissionsDataSource {
  DocuTrackerRepository._() {
    _permissionService = DocuTrackerPermissionService(this);
  }
  static final DocuTrackerRepository instance = DocuTrackerRepository._();

  static const _base = '/api/docutracker';

  late final DocuTrackerPermissionService _permissionService;

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

  Future<DocuTrackerResult<int>> saveRoutingConfig(
    DocumentRoutingConfig config,
  ) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '$_base/routing-configs',
        data: config.toJson(),
      );
      final row = res.data;
      final version = (row?['version'] as num?)?.toInt() ?? config.version + 1;
      return DocuTrackerSuccess(version);
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<List<EscalationConfig>> listEscalationConfigs({
    String? documentType,
    String? departmentId,
  }) async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/escalation-configs',
        queryParameters: {
          if (documentType != null && documentType.isNotEmpty)
            'document_type': documentType,
          if (departmentId != null && departmentId.isNotEmpty)
            'department_id': departmentId,
        },
      );
      final list = res.data ?? [];
      return list
          .map(
            (e) =>
                EscalationConfig.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<DocuTrackerResult<EscalationConfig>> createEscalationConfig(
    EscalationConfig config,
  ) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '$_base/escalation-configs',
        data: config.toJson(),
      );
      final row = res.data;
      if (row == null) {
        return DocuTrackerFailure<EscalationConfig>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(EscalationConfig.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<DocuTrackerResult<EscalationConfig>> updateEscalationConfig(
    EscalationConfig config,
  ) async {
    final id = config.id;
    if (id == null || id.isEmpty) {
      return DocuTrackerFailure<EscalationConfig>('Config id is required');
    }
    try {
      final res = await ApiClient.instance.patch<Map<String, dynamic>>(
        '$_base/escalation-configs/$id',
        data: config.toJson(),
      );
      final row = res.data;
      if (row == null) {
        return DocuTrackerFailure<EscalationConfig>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(EscalationConfig.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<DocuTrackerResult<List<DocuTrackerDocument>>> listDocumentsForUser({
    required String userId,
    String? userRoleId,
    String? userDepartmentId,
    String? userOfficeId,
    String? createdBy,
    String? documentType,
    DocumentStatus? status,
    int? limit,
  }) async {
    try {
      final qp = <String, dynamic>{
        if (documentType != null && documentType.isNotEmpty)
          'type': documentType,
        if (status != null) 'status': status.value,
        if (createdBy != null && createdBy.isNotEmpty) 'createdBy': createdBy,
        if (limit != null) 'limit': limit,
      };
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/documents',
        queryParameters: qp,
      );
      final list = res.data ?? [];
      final mapped = list
          .map(
            (e) => DocuTrackerDocument.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      return DocuTrackerSuccess(mapped);
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<DocuTrackerResult<List<DocuTrackerDocument>>> listAllDocuments({
    String? documentType,
    DocumentStatus? status,
    int? limit,
  }) async {
    try {
      final qp = <String, dynamic>{
        if (documentType != null && documentType.isNotEmpty)
          'type': documentType,
        if (status != null) 'status': status.value,
        if (limit != null) 'limit': limit,
      };
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/documents',
        queryParameters: qp,
      );
      final list = res.data ?? [];
      final mapped = list
          .map(
            (e) => DocuTrackerDocument.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      return DocuTrackerSuccess(mapped);
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<DocuTrackerResult<DocuTrackerDocument>> getDocument(String id) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_base/documents/$id',
      );
      final doc = res.data?['document'];
      if (doc is! Map) {
        return DocuTrackerFailure<DocuTrackerDocument>('Document not found');
      }
      return DocuTrackerSuccess(
        DocuTrackerDocument.fromJson(Map<String, dynamic>.from(doc)),
      );
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<List<DocumentRoutingRecord>> getDocumentRoutingRecords(
    String id,
  ) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_base/documents/$id',
      );
      final routing = res.data?['routing'];
      if (routing is! List) return const [];
      return routing
          .map(
            (e) => DocumentRoutingRecord.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<DocuTrackerResult<DocuTrackerDocument>> createDocument(
    DocuTrackerDocument doc,
  ) async {
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
      if (row == null) {
        return DocuTrackerFailure<DocuTrackerDocument>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(DocuTrackerDocument.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<List<DocumentHistoryEntry>> listDocumentHistory(
    String documentId,
  ) async {
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

  Future<DocuTrackerResult<DocuTrackerDocument>> transitionDocument({
    required String documentId,
    required String action,
    String? remarks,
    String? targetHolderId,
    String? idempotencyKey,
  }) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '$_base/documents/$documentId/transition',
        data: {
          'action': action,
          if (remarks != null) 'remarks': remarks,
          if (targetHolderId != null) 'target_holder_id': targetHolderId,
          if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        },
      );
      final row = res.data;
      if (row == null) {
        return DocuTrackerFailure<DocuTrackerDocument>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(DocuTrackerDocument.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<bool> addDocumentRemark({
    required String documentId,
    required String remarks,
  }) async {
    try {
      await ApiClient.instance.post<void>(
        '$_base/documents/$documentId/remark',
        data: {'remarks': remarks},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<DocuTrackerResult<DocumentAiSummary?>> getAiSummary(
    String documentId,
  ) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_base/documents/$documentId/ai-summary',
      );
      final row = res.data;
      if (row == null) return const DocuTrackerSuccess(null);
      return DocuTrackerSuccess(DocumentAiSummary.fromJson(row));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const DocuTrackerSuccess(null);
      }
      return DocuTrackerFailure(_apiErrorMessage(e));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<DocuTrackerResult<DocumentAiSummary>> generateAiSummary(
    String documentId,
  ) async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '$_base/documents/$documentId/ai-summary',
        data: const <String, dynamic>{},
      );
      final row = res.data;
      if (row == null) {
        return DocuTrackerFailure<DocumentAiSummary>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(DocumentAiSummary.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<List<DocumentNotification>> listMyNotifications() async {
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

  /// Marks one notification as read for the current user.
  Future<DocumentNotification?> markNotificationRead(
    String notificationId,
  ) async {
    try {
      final res = await ApiClient.instance.patch<Map<String, dynamic>>(
        '$_base/notifications/$notificationId/read',
        data: const <String, dynamic>{},
      );
      final row = res.data;
      if (row == null) return null;
      return DocumentNotification.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Marks all notifications read for the current user. Returns rows updated or null on failure.
  Future<int?> markAllNotificationsRead() async {
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '$_base/notifications/mark-all-read',
        data: const <String, dynamic>{},
      );
      final n = res.data?['updated'];
      if (n is num) return n.toInt();
      return 0;
    } catch (_) {
      return null;
    }
  }

  @override
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

  Future<List<Map<String, dynamic>>> getWorkflowSteps({
    required String documentType,
    required int workflowVersion,
  }) async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '$_base/workflow-steps',
        queryParameters: {
          'document_type': documentType,
          'workflow_version': workflowVersion,
        },
      );
      final list = res.data ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<DocuTrackerResult<bool>> updateWorkflowStepAssignees({
    required String stepId,
    required List<Map<String, dynamic>> assignees,
  }) async {
    try {
      await ApiClient.instance.put<void>(
        '$_base/workflow-steps/$stepId/assignees',
        data: {'assignees': assignees},
      );
      return const DocuTrackerSuccess(true);
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
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
      _permissionService.clearCache();
    } catch (e) {
      throw Exception(_apiErrorMessage(e));
    }
  }

  Future<int> resetPermissions({
    String? userId,
    String? roleId,
    required String documentType,
    String? action,
  }) async {
    try {
      final res = await ApiClient.instance.delete<Map<String, dynamic>>(
        '$_base/permissions',
        data: {
          if (userId != null) 'user_id': userId,
          if (roleId != null) 'role_id': roleId,
          'document_type': documentType,
          if (action != null) 'action': action,
        },
      );
      _permissionService.clearCache();
      final deleted = res.data?['deleted'];
      if (deleted is num) return deleted.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> canAccessDocument({
    required String userId,
    required String documentId,
    bool isAdmin = false,
    DocuTrackerDocument? document,
    List<DocumentRoutingRecord>? routingRecords,
  }) async {
    if (isAdmin) return true;
    try {
      DocuTrackerDocument? doc = document;
      if (doc == null) {
        final res = await getDocument(documentId);
        if (res is DocuTrackerFailure<DocuTrackerDocument>) return false;
        if (res is! DocuTrackerSuccess<DocuTrackerDocument>) return false;
        doc = res.value;
      }
      final routing =
          routingRecords ?? await getDocumentRoutingRecords(documentId);
      return DocuTrackerDocumentVisibility.isVisible(
        doc: doc,
        userId: userId,
        routingForDocument: routing,
      );
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
      return await _permissionService.hasPermission(
        userId: userId,
        roleId: roleId,
        documentType: documentType,
        action: action,
      );
    } catch (_) {
      // Default deny on any error (security > convenience).
      return false;
    }
  }

  Future<bool> hasCurrentUserPermission({
    required String documentType,
    required String action,
  }) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_base/permission-explain',
        queryParameters: {'document_type': documentType, 'action': action},
      );
      return res.data?['final_decision'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<DocumentType>> creatableDocumentTypes() async {
    const allTypes = DocumentType.values;
    final action = DocumentAction.createDraft.value;
    final wildcardAllowed = await hasCurrentUserPermission(
      documentType: '*',
      action: action,
    );
    if (wildcardAllowed) return allTypes;

    final allowed = <DocumentType>[];
    for (final type in allTypes) {
      final canCreate = await hasCurrentUserPermission(
        documentType: type.value,
        action: action,
      );
      if (canCreate) allowed.add(type);
    }
    return allowed;
  }

  Future<DocuTrackerPermissionExplanation> explainPermission({
    required String userId,
    String? roleId,
    required String documentType,
    required String action,
    String? documentId,
    bool isAdmin = false,
  }) async {
    // When a concrete document is provided, always delegate to backend explanation
    // because document-level rules include creator/holder/step-assignee context.
    if (!isAdmin && documentId != null && documentId.trim().isNotEmpty) {
      try {
        final res = await ApiClient.instance.get<Map<String, dynamic>>(
          '$_base/permission-explain',
          queryParameters: {
            'document_type': documentType,
            'action': action,
            'document_id': documentId,
          },
        );
        final data = res.data ?? const <String, dynamic>{};
        final granted = data['final_decision'] == true;
        final reason = data['reason']?.toString();
        final rel = data['relationship'];
        final isHolder = rel is Map && rel['isCurrentHolder'] == true;
        final isAssignee = rel is Map && rel['isStepAssignee'] == true;
        final source = isHolder
            ? DocuTrackerPermissionSource.currentHolder
            : isAssignee
            ? DocuTrackerPermissionSource.stepAssignee
            : DocuTrackerPermissionSource.defaultDeny;
        return DocuTrackerPermissionExplanation(
          granted: granted,
          source: granted ? source : DocuTrackerPermissionSource.defaultDeny,
          matchedDocumentType: documentType,
          matchedRoleId: null,
          reason: reason,
        );
      } catch (_) {
        // Default deny on any error.
        return const DocuTrackerPermissionExplanation(
          granted: false,
          source: DocuTrackerPermissionSource.defaultDeny,
          matchedDocumentType: null,
          matchedRoleId: null,
          reason: 'explain_failed',
        );
      }
    }

    return _permissionService.explainPermission(
      userId: userId,
      roleId: roleId,
      documentType: documentType,
      action: action,
      isAdmin: isAdmin,
    );
  }

  Future<DocuTrackerResult<DocuTrackerDocument>> uploadAttachment({
    required String documentId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    try {
      final res = await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
        '$_base/documents/$documentId/attachment',
        bytes: fileBytes,
        fileName: fileName,
        fieldName: 'file',
      );
      final row = res.data;
      if (row == null) {
        return DocuTrackerFailure<DocuTrackerDocument>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(DocuTrackerDocument.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<DocuTrackerResult<DocuTrackerDocument>> removeAttachment(
    String documentId,
  ) async {
    try {
      final res = await ApiClient.instance.delete<Map<String, dynamic>>(
        '$_base/documents/$documentId/attachment',
      );
      final row = res.data;
      if (row == null) {
        return DocuTrackerFailure<DocuTrackerDocument>(
          'Empty response from server',
        );
      }
      return DocuTrackerSuccess(DocuTrackerDocument.fromJson(row));
    } catch (e) {
      return DocuTrackerFailure(_apiErrorMessage(e));
    }
  }

  Future<List<int>?> getAttachmentBytes(String documentId) async {
    try {
      final res = await ApiClient.instance.dio.get<List<int>>(
        '$_base/documents/$documentId/attachment',
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
