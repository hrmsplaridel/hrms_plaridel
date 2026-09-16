import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

class RspApplicantWaitingState extends StatelessWidget {
  const RspApplicantWaitingState({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.hourglass_top_rounded,
    this.onRefresh,
    this.refreshBusy = false,
    this.lastUpdatedLabel,
  });

  final String title;
  final String body;
  final IconData icon;
  final VoidCallback? onRefresh;
  final bool refreshBusy;
  final String? lastUpdatedLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF1565C0)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          if (lastUpdatedLabel != null) ...[
            const SizedBox(height: 10),
            Text(
              lastUpdatedLabel!,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
          if (onRefresh != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: refreshBusy ? null : onRefresh,
              icon: refreshBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(refreshBusy ? 'Checking status…' : 'Refresh status'),
            ),
          ],
        ],
      ),
    );
  }
}
