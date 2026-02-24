import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';

/// Standard header for RSP forms (Republic of the Philippines, Province, Municipality, HRMDO).
class RspFormHeader extends StatelessWidget {
  const RspFormHeader({
    super.key,
    required this.formTitle,
    this.subtitle,
  });

  final String formTitle;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Placeholder for seal (circular)
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryNavy, width: 2),
              ),
              child: Icon(Icons.account_balance_rounded, color: AppTheme.primaryNavy, size: 32),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Republic of the Philippines', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                Text('PROVINCE OF MISAMIS OCCIDENTAL', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                Text('MUNICIPALITY OF PLARIDEL', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
                Text('HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE', style: TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(formTitle, style: TextStyle(color: AppTheme.primaryNavy, fontSize: 18, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Header variant for Merit Promotion Board forms (e.g. Comparative Assessment, Turn-Around Time).
class RspFormHeaderBoard extends StatelessWidget {
  const RspFormHeaderBoard({
    super.key,
    required this.formTitle,
    this.officeName = 'MGO-Plaridel, Misamis Occidental',
  });

  final String formTitle;
  final String? officeName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Republic of the Philippines', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        Text('PROVINCE OF MISAMIS OCCIDENTAL', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        Text('Municipality of Plaridel', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        const SizedBox(height: 8),
        Text('HUMAN RESOURCE MERIT PROMOTION AND SELECTION BOARD', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 12, fontWeight: FontWeight.bold)),
        if (officeName != null && officeName!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(officeName!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
        const SizedBox(height: 12),
        Text(formTitle, style: TextStyle(color: AppTheme.primaryNavy, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Standard footer for RSP forms (contact info, Asenso PLARIDEL).
class RspFormFooter extends StatelessWidget {
  const RspFormFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_rounded, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text('(088) 3448-200', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  const SizedBox(width: 12),
                  Icon(Icons.phone_rounded, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text('(088) 3448-358', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.email_rounded, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text('plaridel_misocc@yahoo.com', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          Text('Asenso PLARIDEL', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Underlined-style decoration for form fields (like the physical form's blank lines).
InputDecoration rspUnderlinedField(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
    border: const UnderlineInputBorder(),
    contentPadding: const EdgeInsets.only(bottom: 4),
    isDense: true,
  );
}
