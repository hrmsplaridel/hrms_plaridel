import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Step 8 card after HR finishes creating the employee account.
/// Login details are emailed, not shown on this page.
class RspApplicantAccountDetailsCard extends StatelessWidget {
  const RspApplicantAccountDetailsCard({
    super.key,
    this.gmailAddress = '',
    this.emailSentAt,
    this.onRefresh,
    this.refreshBusy = false,
  });

  final String gmailAddress;
  final DateTime? emailSentAt;
  final VoidCallback? onRefresh;
  final bool refreshBusy;

  @override
  Widget build(BuildContext context) {
    final gmail = gmailAddress.trim();
    final sentAt = emailSentAt;
    String emailNote;
    if (sentAt != null) {
      final loc = MaterialLocalizations.of(context);
      emailNote =
          'Your HRMS login details were sent to '
          '${gmail.isNotEmpty ? gmail : 'your Gmail'} on '
          '${loc.formatFullDate(sentAt.toLocal())}. '
          'Check your inbox and spam folder.';
    } else if (gmail.isNotEmpty) {
      emailNote =
          'Your HRMS login details were sent to $gmail. '
          'Check your inbox and spam folder.';
    } else {
      emailNote =
          'Your HRMS login details were sent to your Gmail. '
          'Check your inbox and spam folder.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_rounded,
            size: 36,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(height: 12),
          Text(
            'Congratulations — your application is successful',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome to the Municipality of Plaridel. You can now start work. '
            'We wish you a great first day.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            emailNote,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          if (onRefresh != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: refreshBusy ? null : onRefresh,
              icon: refreshBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                refreshBusy ? 'Checking status…' : 'Refresh status',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
