import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Shared public notices for the portal and the municipal landing page.
/// Privacy reference: https://privacy.gov.ph/the-right-to-be-informed/
/// Rights reference: https://privacy.gov.ph/data-subject-rights/
class LegalPage extends StatelessWidget {
  const LegalPage.privacy({super.key}) : _isPrivacy = true;
  const LegalPage.terms({super.key}) : _isPrivacy = false;

  final bool _isPrivacy;

  static const privacyRoute = '/privacy';
  static const termsRoute = '/terms';

  static Map<String, WidgetBuilder> get routes => {
    privacyRoute: (_) => const LegalPage.privacy(),
    termsRoute: (_) => const LegalPage.terms(),
  };

  static Future<void> openPrivacy(BuildContext context) =>
      _open(context, const LegalPage.privacy(), privacyRoute);

  static Future<void> openTerms(BuildContext context) =>
      _open(context, const LegalPage.terms(), termsRoute);

  static Future<void> _open(
    BuildContext context,
    LegalPage page,
    String route,
  ) async {
    // Open above dashboard content navigators and drawers, at full screen width.
    FocusScope.of(context).unfocus();
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: route),
        builder: (_) => page,
      ),
    );
  }

  static const _contact =
      'Contact the Municipality of Plaridel Human Resource Management and '
      'Development Office. For personal-data concerns, request assistance '
      'from the designated Data Protection Officer. Include the record or '
      'service concerned and a way to reach you; do not send passwords or '
      'one-time codes.';

  static const _privacySections = <(String, String)>[
    (
      'About this notice',
      'Unity Pillar supports human resource services of the Municipality of '
          'Plaridel. This notice describes personal information handled through '
          'the portal, including recruitment, attendance, leave, learning and '
          'development, and document routing. Processing is subject to the '
          'Data Privacy Act of 2012 (Republic Act No. 10173) and applicable '
          'municipal records requirements. Reading this notice does not replace '
          'any specific consent requested for an optional service.',
    ),
    (
      'Information we process',
      'Depending on the service you use, records may include your name, contact '
          'details, account and employment information, department and position '
          'assignments, attendance identifiers and punch times, leave requests '
          'and supporting documents, recruitment applications and assessments, '
          'training records, routed documents, and electronic signatures. '
          'Attachments may contain sensitive information, including health '
          'information. Account activity, review history, device information and '
          'IP addresses may also be recorded for security and accountability.',
    ),
    (
      'Why information is used',
      'Information supports account access, personnel administration, '
          'attendance processing, leave balances and approvals, recruitment, '
          'training, document routing, notifications, and audit trails. It comes '
          'from information you submit, authorized staff, and connected '
          'attendance devices. Required official records are processed for '
          'the Municipality’s employment and public-service functions, subject '
          'to the applicable legal basis. HR can explain the basis and required '
          'fields for a particular service. Where consent is required, it '
          'must be obtained for that purpose.',
    ),
    (
      'Access and service providers',
      'Access depends on assigned roles, permissions and review duties. '
          'Authorized HR staff, department reviewers, approving officials '
          'and system administrators may access records needed for their '
          'responsibilities. Configured providers may process information '
          'needed for hosting, email, SMS or push notifications. If you choose '
          'an external AI assistant option, review its separate disclosure '
          'and consent before sending information. Disclosures for official '
          'reporting or lawful requests remain subject to applicable rules.',
    ),
    (
      'Storage, security and retention',
      'The portal uses account permissions and activity records to control '
          'access and trace actions. Keep your credentials private and report '
          'suspected unauthorized access. Your device may store sign-in '
          'information, preferences or assistant history to support the '
          'features you use; sign out on shared devices. Retention depends '
          'on the record type, applicable law, municipal records schedules '
          'and any audit or legal obligations. Ask HR for the schedule '
          'applicable to your record. Deactivating an account does not '
          'automatically erase official records or backup copies.',
    ),
    (
      'Your privacy rights',
      'Subject to applicable conditions and lawful limitations, you may request '
          'information about processing, access to your personal data, '
          'correction of inaccurate records, and erasure or blocking where '
          'applicable. Other rights include objection and data portability '
          'where applicable. You may raise a concern with the designated '
          'Data Protection Officer or file a complaint with the National '
          'Privacy Commission. Requests may require identity verification '
          'and review of records-retention obligations.',
    ),
    ('Contact and privacy requests', _contact),
    (
      'Changes to this notice',
      'This page may be updated when services or data-handling practices '
          'change. Refer to the revision date above and ask HR about any '
          'processing that is unclear to you.',
    ),
  ];

  static const _termsSections = <(String, String)>[
    (
      'Purpose and access',
      'Unity Pillar provides municipal HR services for authorized employees, '
          'officials and administrators, with public recruitment features '
          'for applicants. Use only the services and records you are '
          'authorized to access. These terms operate alongside applicable '
          'municipal policies and law; they do not change employment rights '
          'or appointment conditions.',
    ),
    (
      'Accounts and responsible use',
      'Use your own account and protect your password, reset codes and '
          'sign-in sessions. Do not share credentials, impersonate another '
          'person, bypass permissions, disrupt the service or attempt to '
          'access records beyond your role. Sign out after using a shared '
          'device. Report suspected account compromise or misuse to the '
          'HR office or system administrator promptly.',
    ),
    (
      'Accurate submissions',
      'Provide accurate information and legitimate supporting documents. '
          'Review dates, attachments and other details before submitting. '
          'Upload only information necessary for the requested service '
          'and that you are authorized to provide. Report errors through '
          'the relevant correction or review process rather than creating '
          'misleading or duplicate records.',
    ),
    (
      'Approvals and electronic signatures',
      'Submitting a request does not mean it has been approved. Official '
          'decisions follow the assigned workflow and authorized reviewers. '
          'Apply an electronic signature only as yourself and only after '
          'reviewing the document and your assigned signing role. Do not '
          'upload or apply another person’s signature without authority. '
          'Corrections may require a new review or signature; preserve '
          'the official record and its history.',
    ),
    (
      'Confidentiality and documents',
      'Use personal information and documents only for your authorized '
          'duties or application. Do not disclose, copy, download or forward '
          'another person’s records without authority. Keep downloaded '
          'files secure and follow municipal handling and retention '
          'requirements. Report an accidental disclosure promptly.',
    ),
    (
      'Availability and assistant guidance',
      'Maintenance, connectivity issues or service interruptions may '
          'temporarily affect access. Contact HR about urgent submissions '
          'and the appropriate alternative process. Assistant responses '
          'are guidance and may contain errors; verify them against '
          'official records and HR instructions. An assistant response '
          'does not itself approve a request or determine an entitlement.',
    ),
    (
      'Access changes and updates',
      'Access may be changed or suspended by authorized administrators '
          'in accordance with municipal policy, employment status or '
          'security requirements. These terms may be updated as services '
          'change. Refer to the revision date above and contact HR for '
          'clarification.',
    ),
    ('Contact and support', _contact),
  ];

  @override
  Widget build(BuildContext context) {
    final title = _isPrivacy ? 'Privacy Policy' : 'Terms of Use';
    final sections = _isPrivacy ? _privacySections : _termsSections;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Unity Pillar',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Municipality of Plaridel • Last updated: 10 November 2026',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    for (final (heading, body) in sections) ...[
                      Semantics(
                        header: true,
                        child: Text(
                          heading,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
