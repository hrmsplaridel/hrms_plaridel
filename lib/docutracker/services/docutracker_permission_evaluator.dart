/// Pure permission precedence evaluator for DocuTracker (default deny).
///
/// Precedence (matches the backend + app requirement):
/// 1) user override for document type
/// 2) user override for wildcard '*'
/// 3) role baseline for document type (including legacy read equivalents)
/// 4) role baseline for wildcard '*'
/// 5) deny (default)
class DocuTrackerPermissionEvaluator {
  const DocuTrackerPermissionEvaluator();

  bool evaluate({
    required bool? userSpecificGranted,
    required bool? userWildcardGranted,
    required bool? roleSpecificGranted,
    required bool? roleWildcardGranted,
  }) {
    if (userSpecificGranted != null) return userSpecificGranted;
    if (userWildcardGranted != null) return userWildcardGranted;
    if (roleSpecificGranted != null) return roleSpecificGranted;
    if (roleWildcardGranted != null) return roleWildcardGranted;
    return false; // default deny
  }
}

