/// A department a document can be released to.
class DocuTrackerReleaseDepartment {
  const DocuTrackerReleaseDepartment({required this.id, required this.name});

  final String id;
  final String name;

  factory DocuTrackerReleaseDepartment.fromJson(Map<String, dynamic> json) =>
      DocuTrackerReleaseDepartment(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

/// Backend-decided release state for the signed-in viewer.
class DocuTrackerReleaseOptions {
  const DocuTrackerReleaseOptions({
    required this.releaseRequired,
    required this.released,
    required this.canRelease,
    this.suggestedDepartmentId,
    this.departments = const [],
  });

  final bool releaseRequired;
  final bool released;
  final bool canRelease;
  final String? suggestedDepartmentId;
  final List<DocuTrackerReleaseDepartment> departments;

  factory DocuTrackerReleaseOptions.fromJson(Map<String, dynamic> json) =>
      DocuTrackerReleaseOptions(
        releaseRequired: json['release_required'] == true,
        released: json['released'] == true,
        canRelease: json['can_release'] == true,
        suggestedDepartmentId: json['suggested_department_id']?.toString(),
        departments: (json['departments'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => DocuTrackerReleaseDepartment.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((d) => d.id.isNotEmpty && d.name.isNotEmpty)
            .toList(growable: false),
      );
}

/// Per-document-type release policy (admin configuration).
class DocuTrackerReleasePolicy {
  const DocuTrackerReleasePolicy({
    required this.documentType,
    required this.requiresRelease,
  });

  final String documentType;
  final bool requiresRelease;

  factory DocuTrackerReleasePolicy.fromJson(Map<String, dynamic> json) =>
      DocuTrackerReleasePolicy(
        documentType: json['document_type']?.toString() ?? '',
        requiresRelease: json['requires_release'] == true,
      );
}
