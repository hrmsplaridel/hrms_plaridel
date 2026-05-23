import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../landingpage/constants/app_theme.dart';

/// Inline About content for Settings (no separate dialog).
class SettingsAboutPanel extends StatelessWidget {
  const SettingsAboutPanel({super.key});

  static const _supportEmail = 'hrmdo.plaridel@example.gov.ph';

  Future<void> _openMail() async {
    final uri = Uri.parse(
      'mailto:$_supportEmail?subject=${Uri.encodeComponent('HRMS support request')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showTerms(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terms & conditions'),
        content: const SingleChildScrollView(
          child: Text(
            'This application is provided by the Municipality of Plaridel for authorized '
            'personnel only. By using HRMS you agree to follow applicable data privacy, '
            'acceptable use, and employment policies. Misuse may result in access being '
            'revoked. For the full legal text, contact your HR office.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        const _TileRow(
          icon: Icons.tag_rounded,
          label: 'App version',
          value: '1.0',
        ),
        const _TileRow(
          icon: Icons.business_rounded,
          label: 'System name',
          value: 'Human Resource Management System — Municipality of Plaridel',
        ),
        ListTile(
          leading:
              Icon(Icons.description_outlined, color: AppTheme.primaryNavy),
          title: Text(
            'Terms & conditions',
            style: TextStyle(color: AppTheme.dashTextPrimaryOf(context)),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          onTap: () => _showTerms(context),
        ),
        ListTile(
          leading: Icon(Icons.support_agent_rounded, color: AppTheme.primaryNavy),
          title: Text(
            'Contact support',
            style: TextStyle(color: AppTheme.dashTextPrimaryOf(context)),
          ),
          subtitle: Text(
            _supportEmail,
            style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
          ),
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          onTap: _openMail,
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryNavy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: AppTheme.primaryNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
