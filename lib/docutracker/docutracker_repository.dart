import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/document.dart';
import 'models/document_history.dart';
import 'models/document_notification.dart';
import 'models/document_permission.dart';
import 'models/document_routing_config.dart';
import 'models/document_status.dart';
import 'models/escalation_config.dart';

/// Repository for DocuTracker data. Uses Supabase when tables exist;
/// falls back to in-memory defaults for routing configs.
class DocuTrackerRepository {
  DocuTrackerRepository._();
  static final DocuTrackerRepository instance = DocuTrackerRepository._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Get routing configs for document types. Uses defaults if no DB table.
  Future<List<DocumentRoutingConfig>> getRoutingConfigs() async {
    try {
      final res = await _client
          .from('docutracker_routing_configs')
          .select()
          .order('document_type');
      if (res.isNotEmpty) {
        return (res)
            .map(
              (e) => DocumentRoutingConfig.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
    } catch (_) {
      // Table may not exist yet
    }
    return DocumentRoutingConfig.defaults;
  }

  /// List documents visible to user (Step 2: Role-Based Visibility).
  /// Filters by: assigned to user, user's office, user's department.
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
      dynamic query = _client
          .from(DocuTrackerDocument.tableName)
          .select('*, creator:profiles!created_by(full_name)');
      // Step 2 & 11: User sees docs they created OR are current holder (in route)
      query = query.or('created_by.eq.$userId,current_holder_id.eq.$userId');
      if (documentType != null && documentType.isNotEmpty) {
        query = query.eq('document_type', documentType);
      }
      if (status != null) {
        query = query.eq('status', status.value);
      }
      query = query.order('created_at', ascending: false);
      if (limit != null) query = query.limit(limit);

      final res = await query;
      return (res as List).map((e) => _documentFromRow(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Step 12: Fetch documents past deadline for auto-escalation.
  Future<List<DocuTrackerDocument>> listOverdueForEscalation() async {
    try {
      final now = DateTime.now().toIso8601String();
      final res = await _client
          .from(DocuTrackerDocument.tableName)
          .select()
          .lt('deadline_time', now);
      final list = (res as List)
          .map((e) => DocuTrackerDocument.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return list
          .where((d) =>
              d.status != DocumentStatus.approved &&
              d.status != DocumentStatus.rejected)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// List all documents (admin only).
  Future<List<DocuTrackerDocument>> listAllDocuments({
    String? documentType,
    DocumentStatus? status,
    int? limit,
  }) async {
    try {
      dynamic query = _client
          .from(DocuTrackerDocument.tableName)
          .select('*, creator:profiles!created_by(full_name)');
      if (documentType != null && documentType.isNotEmpty) {
        query = query.eq('document_type', documentType);
      }
      if (status != null) {
        query = query.eq('status', status.value);
      }
      query = query.order('created_at', ascending: false);
      if (limit != null) query = query.limit(limit);

      final res = await query;
      return (res as List).map((e) => _documentFromRow(e)).toList();
    } catch (_) {
      return [];
    }
  }

  DocuTrackerDocument _documentFromRow(dynamic row) {
    final m = Map<String, dynamic>.from(row as Map);
    final creator = m['creator'];
    if (creator != null && creator is Map) {
      m['creator_name'] = (creator as Map<String, dynamic>)['full_name'];
    }
    m.remove('creator');
    return DocuTrackerDocument.fromJson(m);
  }

  /// Get single document by ID.
  Future<DocuTrackerDocument?> getDocument(String id) async {
    try {
      final res = await _client
          .from(DocuTrackerDocument.tableName)
          .select('*, creator:profiles!created_by(full_name)')
          .eq('id', id)
          .maybeSingle();
      if (res == null) return null;
      return _documentFromRow(res);
    } catch (_) {
      return null;
    }
  }

  /// Get next document number (Step 9: DOC-YYYY-NNNN).
  Future<String> getNextDocumentNumber() async {
    try {
      final year = DateTime.now().year;
      final prefix = 'DOC-$year-';
      final res = await _client
          .from(DocuTrackerDocument.tableName)
          .select('document_number')
          .like('document_number', '$prefix%')
          .order('document_number', ascending: false)
          .limit(1);
      final list = res as List;
      if (list.isNotEmpty) {
        final last = (list.first as Map)['document_number']?.toString() ?? '';
        final numStr = last.replaceFirst(prefix, '');
        final num = int.tryParse(numStr) ?? 0;
        return '$prefix${(num + 1).toString().padLeft(4, '0')}';
      }
    } catch (_) {}
    return 'DOC-${DateTime.now().year}-0001';
  }

  /// Create document.
  Future<DocuTrackerDocument?> createDocument(DocuTrackerDocument doc) async {
    try {
      final payload = Map<String, dynamic>.from(doc.toJson())
        ..remove('id')
        ..remove('creator_name')
        ..remove('assignee_name');
      final res = await _client
          .from(DocuTrackerDocument.tableName)
          .insert(payload)
          .select()
          .single();
      return DocuTrackerDocument.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  /// Add document history entry (Step 6 & 9).
  Future<void> addDocumentHistory(DocumentHistoryEntry entry) async {
    try {
      final payload = Map<String, dynamic>.from(entry.toJson())..remove('id');
      await _client.from(DocumentHistoryEntry.tableName).insert(payload);
    } catch (_) {}
  }

  /// List document history for audit trail (Step 9).
  Future<List<DocumentHistoryEntry>> listDocumentHistory(String documentId) async {
    try {
      final res = await _client
          .from(DocumentHistoryEntry.tableName)
          .select()
          .eq('document_id', documentId)
          .order('created_at', ascending: false);
      return (res as List)
          .map((e) => DocumentHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Add notification (Step 7).
  Future<void> addNotification(DocumentNotification notif) async {
    try {
      final payload = Map<String, dynamic>.from(notif.toJson())..remove('id');
      await _client.from(DocumentNotification.tableName).insert(payload);
    } catch (_) {}
  }

  /// List notifications for user (Step 7).
  Future<List<DocumentNotification>> listNotificationsForUser(String userId) async {
    try {
      final res = await _client
          .from(DocumentNotification.tableName)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return (res as List)
          .map((e) => DocumentNotification.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get escalation config for document type (Step 6).
  Future<EscalationConfig?> getEscalationConfig(
    String documentType, {
    String? departmentId,
  }) async {
    try {
      dynamic query = _client
          .from(EscalationConfig.tableName)
          .select()
          .eq('document_type', documentType);
      if (departmentId != null) {
        query = query.eq('department_id', departmentId);
      }
      final res = await query;
      if (res is List && res.isNotEmpty) {
        return EscalationConfig.fromJson(Map<String, dynamic>.from(res.first as Map));
      }
    } catch (_) {}
    return null;
  }

  /// Update document.
  Future<void> updateDocument(DocuTrackerDocument doc) async {
    if (doc.id == null) return;
    final payload = Map<String, dynamic>.from(doc.toJson())
      ..remove('creator_name')
      ..remove('assignee_name');
    await _client
        .from(DocuTrackerDocument.tableName)
        .update(payload)
        .eq('id', doc.id!);
  }

  /// List permissions (Step 4: Admin Privilege Management).
  Future<List<DocumentPermission>> listPermissions({
    String? roleId,
    String? userId,
    String? documentType,
    bool userOnly = false,
  }) async {
    try {
      dynamic query = _client.from(DocumentPermission.tableName).select();
      if (roleId != null) query = query.eq('role_id', roleId);
      if (userId != null) query = query.eq('user_id', userId);
      if (documentType != null) query = query.eq('document_type', documentType);
      final res = await query;
      final perms = (res as List)
          .map(
            (e) => DocumentPermission.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      // "Per employee only": hide role-based grants from the admin table.
      if (userOnly) {
        return perms.where((p) => p.userId != null).toList();
      }

      return perms;
    } catch (_) {
      return [];
    }
  }

  /// Save permission.
  Future<void> savePermission(DocumentPermission perm) async {
    try {
      final payload = Map<String, dynamic>.from(perm.toJson())..remove('id');
      if (perm.id != null) {
        // Avoid attempting to update the primary key.
        final updatePayload = Map<String, dynamic>.from(payload);
        await _client
            .from(DocumentPermission.tableName)
          .update(updatePayload)
            .eq('id', perm.id!);
      } else {
        await _client.from(DocumentPermission.tableName).insert(payload);
      }
    } catch (_) {
      // Table may not exist
    }
  }

  /// Step 11: RBAC - Check if user can access document (in route).
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

  /// Check if user has permission for action on document type.
  Future<bool> hasPermission({
    required String userId,
    String? roleId,
    required String documentType,
    required String action,
  }) async {
    try {
      // Check user-specific first
      final userPerms = await listPermissions(
        userId: userId,
        documentType: documentType,
      );
      final userAction = userPerms.where((p) => p.action.name == action);
      if (userAction.isNotEmpty) return userAction.first.granted;

      // Then role
      if (roleId != null) {
        final rolePerms = await listPermissions(
          roleId: roleId,
          documentType: documentType,
        );
        final roleAction = rolePerms.where((p) => p.action.name == action);
        if (roleAction.isNotEmpty) return roleAction.first.granted;
      }

      // Wildcard
      // Resolve wildcard with the same precedence rules:
      // 1) user_id wildcard override
      // 2) role_id wildcard
      // 3) global wildcard (any role/user)
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
      final globalWildAction = globalWildPerms.where((p) => p.action.name == action);
      if (globalWildAction.isNotEmpty) return globalWildAction.first.granted;
    } catch (_) {}
    return true; // Default allow if no permissions table
  }
}
