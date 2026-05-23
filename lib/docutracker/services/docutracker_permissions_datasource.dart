import '../models/document_permission.dart';

/// Small abstraction so services can fetch permission records without depending
/// on a concrete repository implementation.
abstract class DocuTrackerPermissionsDataSource {
  Future<List<DocumentPermission>> listPermissions({
    String? roleId,
    String? userId,
    String? documentType,
    bool userOnly = false,
  });
}

