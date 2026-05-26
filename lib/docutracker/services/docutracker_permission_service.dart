import '../models/document_permission.dart';
import '../security/docutracker_roles.dart';
import 'docutracker_permission_evaluator.dart';
import 'docutracker_permissions_datasource.dart';

/// Permission helper with caching.
///
/// Centralizes the 5-point precedence:
/// 1) user override (document type)
/// 2) user override ('*')
/// 3) role baseline (document type) with legacy read equivalents
/// 4) role baseline ('*') with legacy read equivalents
/// 5) deny (default)
class DocuTrackerPermissionService {
  DocuTrackerPermissionService(
    this._dataSource, {
    DocuTrackerPermissionEvaluator? evaluator,
  }) : _evaluator = evaluator ?? const DocuTrackerPermissionEvaluator();

  final DocuTrackerPermissionsDataSource _dataSource;
  final DocuTrackerPermissionEvaluator _evaluator;

  /// Cache of permission record lists keyed by query parameters.
  final Map<String, List<DocumentPermission>> _cache = {};

  /// Call after any backend permission write to avoid stale cached decisions.
  void clearCache() => _cache.clear();

  String _cacheKey({
    required String? roleId,
    required String? userId,
    required String? documentType,
    required bool userOnly,
  }) =>
      'role=${roleId ?? ""}|user=${userId ?? ""}|doc=${documentType ?? ""}|userOnly=$userOnly';

  Future<List<DocumentPermission>> _getPermissions({
    required String? roleId,
    required String? userId,
    required String? documentType,
    required bool userOnly,
  }) async {
    final key = _cacheKey(
      roleId: roleId,
      userId: userId,
      documentType: documentType,
      userOnly: userOnly,
    );
    final cached = _cache[key];
    if (cached != null) return cached;

    final perms = await _dataSource.listPermissions(
      roleId: roleId,
      userId: userId,
      documentType: documentType,
      userOnly: userOnly,
    );
    _cache[key] = perms;
    return perms;
  }

  bool? _grantedForAction(List<DocumentPermission> perms, String action) {
    String normalize(String raw) => raw
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    final wanted = normalize(action);
    final aliases = <String>{
      wanted,
      if (wanted == 'create') 'create_draft',
      if (wanted == 'create_draft') 'create',
      if (wanted == 'returndoc') 'return',
      if (wanted == 'return') 'returndoc',
    };
    for (final p in perms) {
      final actionName = normalize(p.action.name);
      if (aliases.contains(actionName)) {
        return p.granted;
      }
    }
    return null;
  }

  Future<DocuTrackerPermissionExplanation> explainPermission({
    required String userId,
    required String? roleId,
    required String documentType,
    required String action,
    bool isAdmin = false,
  }) async {
    if (isAdmin) {
      return const DocuTrackerPermissionExplanation(
        granted: true,
        source: DocuTrackerPermissionSource.admin,
        matchedDocumentType: null,
        matchedRoleId: null,
      );
    }

    final normalizedRoleId = DocuTrackerRoles.normalize(roleId);
    final roleEquivalents = normalizedRoleId.isEmpty
        ? const <String>[]
        : DocuTrackerRoles.equivalentsForRead(normalizedRoleId);

    // 1) user override (specific type)
    final userSpecificPerms = await _getPermissions(
      roleId: null,
      userId: userId,
      documentType: documentType,
      userOnly: false,
    );
    final userSpecificGranted = _grantedForAction(userSpecificPerms, action);
    if (userSpecificGranted != null) {
      return DocuTrackerPermissionExplanation(
        granted: userSpecificGranted,
        source: DocuTrackerPermissionSource.userSpecific,
        matchedDocumentType: documentType,
        matchedRoleId: null,
      );
    }

    // 2) user override (*)
    final userWildcardPerms = await _getPermissions(
      roleId: null,
      userId: userId,
      documentType: '*',
      userOnly: false,
    );
    final userWildcardGranted = _grantedForAction(userWildcardPerms, action);
    if (userWildcardGranted != null) {
      return DocuTrackerPermissionExplanation(
        granted: userWildcardGranted,
        source: DocuTrackerPermissionSource.userWildcard,
        matchedDocumentType: '*',
        matchedRoleId: null,
      );
    }

    // 3) role baseline (specific type)
    for (final r in roleEquivalents) {
      final perms = await _getPermissions(
        roleId: r,
        userId: null,
        documentType: documentType,
        userOnly: false,
      );
      final granted = _grantedForAction(perms, action);
      if (granted != null) {
        return DocuTrackerPermissionExplanation(
          granted: granted,
          source: DocuTrackerPermissionSource.roleSpecific,
          matchedDocumentType: documentType,
          matchedRoleId: r,
        );
      }
    }

    // 4) role baseline (*)
    for (final r in roleEquivalents) {
      final perms = await _getPermissions(
        roleId: r,
        userId: null,
        documentType: '*',
        userOnly: false,
      );
      final granted = _grantedForAction(perms, action);
      if (granted != null) {
        return DocuTrackerPermissionExplanation(
          granted: granted,
          source: DocuTrackerPermissionSource.roleWildcard,
          matchedDocumentType: '*',
          matchedRoleId: r,
        );
      }
    }

    return const DocuTrackerPermissionExplanation(
      granted: false,
      source: DocuTrackerPermissionSource.defaultDeny,
      matchedDocumentType: null,
      matchedRoleId: null,
    );
  }

  Future<bool> hasPermission({
    required String userId,
    required String? roleId,
    required String documentType,
    required String action,
    bool isAdmin = false,
  }) async {
    if (isAdmin) return true;

    final normalizedRoleId = DocuTrackerRoles.normalize(roleId);
    final roleEquivalents = normalizedRoleId.isEmpty
        ? const <String>[]
        : DocuTrackerRoles.equivalentsForRead(normalizedRoleId);

    // User precedence.
    final userSpecificPerms = await _getPermissions(
      roleId: null,
      userId: userId,
      documentType: documentType,
      userOnly: false,
    );
    final userSpecificGranted = _grantedForAction(userSpecificPerms, action);
    if (userSpecificGranted != null) {
      return _evaluator.evaluate(
        userSpecificGranted: userSpecificGranted,
        userWildcardGranted: null,
        roleSpecificGranted: null,
        roleWildcardGranted: null,
      );
    }

    final userWildcardPerms = await _getPermissions(
      roleId: null,
      userId: userId,
      documentType: '*',
      userOnly: false,
    );
    final userWildcardGranted = _grantedForAction(userWildcardPerms, action);
    if (userWildcardGranted != null) {
      return _evaluator.evaluate(
        userSpecificGranted: null,
        userWildcardGranted: userWildcardGranted,
        roleSpecificGranted: null,
        roleWildcardGranted: null,
      );
    }

    // Role precedence (preserve legacy-equivalent ordering).
    bool? roleSpecificGranted;
    for (final r in roleEquivalents) {
      final perms = await _getPermissions(
        roleId: r,
        userId: null,
        documentType: documentType,
        userOnly: false,
      );
      final granted = _grantedForAction(perms, action);
      if (granted != null) {
        roleSpecificGranted = granted;
        break;
      }
    }
    if (roleSpecificGranted != null) {
      return _evaluator.evaluate(
        userSpecificGranted: null,
        userWildcardGranted: null,
        roleSpecificGranted: roleSpecificGranted,
        roleWildcardGranted: null,
      );
    }

    bool? roleWildcardGranted;
    for (final r in roleEquivalents) {
      final perms = await _getPermissions(
        roleId: r,
        userId: null,
        documentType: '*',
        userOnly: false,
      );
      final granted = _grantedForAction(perms, action);
      if (granted != null) {
        roleWildcardGranted = granted;
        break;
      }
    }

    return _evaluator.evaluate(
      userSpecificGranted: null,
      userWildcardGranted: null,
      roleSpecificGranted: roleSpecificGranted,
      roleWildcardGranted: roleWildcardGranted,
    );
  }
}

enum DocuTrackerPermissionSource {
  admin,
  currentHolder,
  stepAssignee,
  userSpecific,
  userWildcard,
  roleSpecific,
  roleWildcard,
  defaultDeny,
}

class DocuTrackerPermissionExplanation {
  const DocuTrackerPermissionExplanation({
    required this.granted,
    required this.source,
    required this.matchedDocumentType,
    required this.matchedRoleId,
    this.reason,
  });

  final bool granted;
  final DocuTrackerPermissionSource source;
  final String? matchedDocumentType;
  final String? matchedRoleId;
  final String? reason;
}
