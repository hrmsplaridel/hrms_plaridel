import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

class RspApplicantNextActionCard extends StatelessWidget {
  const RspApplicantNextActionCard({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.enabled = true,
    this.icon = Icons.arrow_forward_rounded,
    this.emphasized = true,
    this.eyebrow = 'Next action',
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onPressed;
  final bool busy;
  final String? busyLabel;
  final bool enabled;
  final IconData icon;
  final bool emphasized;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryNavy;
    final canPress = enabled && !busy && onPressed != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: emphasized
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFFF7F0),
                  Colors.white,
                  accent.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: emphasized ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: emphasized ? 0.34 : 0.16),
          width: emphasized ? 1.4 : 1,
        ),
        boxShadow: emphasized
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.1),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.55,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: AppTheme.dashTextPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: FilledButton(
              onPressed: canPress ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: accent.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
