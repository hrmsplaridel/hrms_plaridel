import 'package:hrms_plaridel/features/docutracker/security/docutracker_roles.dart';

enum DocuTrackerAccessWarningLevel { caution, info }

class DocuTrackerAccessWarning {
  const DocuTrackerAccessWarning(this.code, this.level, this.message);

  final String code;
  final DocuTrackerAccessWarningLevel level;
  final String message;
}

/// Flags System Access combinations that do not behave the way an admin
/// would likely expect, based on how the backend enforces each action.
///
/// [effective] holds the final decision per action (`view`, `create_draft`,
/// `submit`, `download`); missing actions are treated as unknown, not blocked.
/// [exceptions] holds the employee's own rules for this scope and [inherited]
/// the value each action would have without them.
List<DocuTrackerAccessWarning> docuTrackerAccessWarnings({
  required Map<String, bool> effective,
  String? roleId,
  String documentType = '*',
  bool isRoleDefault = false,
  Map<String, bool?> exceptions = const {},
  Map<String, bool> inherited = const {},
  String Function(String action)? actionLabel,
}) {
  final role = roleId == null ? null : DocuTrackerRoles.normalize(roleId);
  if (role == DocuTrackerRoles.admin) return const [];
  String label(String action) => actionLabel?.call(action) ?? action;
  bool on(String action) => effective[action] == true;
  bool off(String action) => effective[action] == false;
  final warnings = <DocuTrackerAccessWarning>[];

  if (on('submit') && off('create_draft')) {
    warnings.add(
      DocuTrackerAccessWarning(
        'submit-without-create',
        DocuTrackerAccessWarningLevel.caution,
        '${label('submit')} is allowed but ${label('create_draft')} is '
            'blocked. Only a draft\'s creator can submit it, so this has no '
            'effect on its own.',
      ),
    );
  }
  if (on('create_draft') && off('submit')) {
    warnings.add(
      DocuTrackerAccessWarning(
        'create-without-submit',
        DocuTrackerAccessWarningLevel.caution,
        '${label('create_draft')} is allowed but ${label('submit')} is '
            'blocked. Drafts can be started but never sent into the workflow.',
      ),
    );
  }
  final roleWideEmployee = isRoleDefault && role == DocuTrackerRoles.employee;
  if (on('download') && (roleWideEmployee || exceptions['download'] == true)) {
    warnings.add(
      DocuTrackerAccessWarning(
        'download-broad',
        DocuTrackerAccessWarningLevel.info,
        '${label('download')} allows downloading attachments from any '
            'submitted document of this type, including ones not routed to '
            'this person. Files on documents they can open stay downloadable '
            'either way.',
      ),
    );
  }
  if (roleWideEmployee &&
      documentType != '*' &&
      (on('create_draft') || on('submit'))) {
    warnings.add(
      const DocuTrackerAccessWarning(
        'role-wide-create',
        DocuTrackerAccessWarningLevel.info,
        'Every employee can start or submit this document type. To limit it '
            'to selected staff, block it here and allow it with employee '
            'exceptions.',
      ),
    );
  }
  for (final entry in exceptions.entries) {
    final value = entry.value;
    if (value != null && inherited[entry.key] == value) {
      warnings.add(
        DocuTrackerAccessWarning(
          'redundant-${entry.key}',
          DocuTrackerAccessWarningLevel.info,
          'The ${label(entry.key)} exception matches the inherited setting '
              'and can be set back to the default.',
        ),
      );
    }
  }
  return warnings;
}
