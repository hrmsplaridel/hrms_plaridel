import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class EmployeeLocatorMobileDetailsDialog extends StatelessWidget {
  const EmployeeLocatorMobileDetailsDialog({
    super.key,
    required this.requestTypeLabel,
    required this.dateLabel,
    required this.requestTypeIcon,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusBg,
    required this.statusBorder,
    required this.statusText,
    required this.body,
    required this.actions,
    required this.onClose,
  });

  final String requestTypeLabel;
  final String dateLabel;
  final IconData requestTypeIcon;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusBg;
  final Color statusBorder;
  final Color statusText;
  final Widget body;
  final Widget actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dark = AppTheme.dashIsDark(context);
    final maxH = screen.height * 0.88;
    final maxW = (screen.width - 28).clamp(320.0, 640.0);
    final panelColor = AppTheme.dashPanelOf(context);
    final borderColor = AppTheme.dashHairlineOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            color: panelColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EmployeeLocatorMobileDetailHeader(
                  requestTypeLabel: requestTypeLabel,
                  dateLabel: dateLabel,
                  requestTypeIcon: requestTypeIcon,
                  statusLabel: statusLabel,
                  statusIcon: statusIcon,
                  statusBg: statusBg,
                  statusBorder: statusBorder,
                  statusText: statusText,
                  onClose: onClose,
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    child: body,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark
                        ? AppTheme.dashMutedSurfaceOf(context)
                        : AppTheme.offWhite,
                    border: Border(top: BorderSide(color: borderColor)),
                  ),
                  child: SafeArea(top: false, child: actions),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeLocatorMobileDetailHeader extends StatelessWidget {
  const _EmployeeLocatorMobileDetailHeader({
    required this.requestTypeLabel,
    required this.dateLabel,
    required this.requestTypeIcon,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusBg,
    required this.statusBorder,
    required this.statusText,
    required this.onClose,
  });

  final String requestTypeLabel;
  final String dateLabel;
  final IconData requestTypeIcon;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusBg;
  final Color statusBorder;
  final Color statusText;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.primaryNavy.withValues(alpha: 0.18)
            : AppTheme.primaryNavy.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Request Details',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(
                    alpha: dark ? 0.24 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  requestTypeIcon,
                  color: AppTheme.primaryNavy,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requestTypeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              EmployeeLocatorMobileDetailStatusPill(
                label: statusLabel,
                icon: statusIcon,
                background: statusBg,
                border: statusBorder,
                foreground: statusText,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class EmployeeLocatorMobileDetailSection extends StatelessWidget {
  const EmployeeLocatorMobileDetailSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryNavy),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 470;
              final tileWidth = wide
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final child in children)
                    SizedBox(width: tileWidth, child: child),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class EmployeeLocatorMobileDetailTile extends StatelessWidget {
  const EmployeeLocatorMobileDetailTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
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

class EmployeeLocatorMobileStatusPanel extends StatelessWidget {
  const EmployeeLocatorMobileStatusPanel({
    super.key,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusSubtitle,
    required this.statusBg,
    required this.statusBorder,
    required this.statusText,
  });

  final String statusLabel;
  final IconData statusIcon;
  final String statusSubtitle;
  final Color statusBg;
  final Color statusBorder;
  final Color statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusText.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(statusIcon, color: statusText, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusSubtitle,
                  style: TextStyle(
                    color: statusText.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class EmployeeLocatorMobileDetailStatusPill extends StatelessWidget {
  const EmployeeLocatorMobileDetailStatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeLocatorMobileReasonPanel extends StatelessWidget {
  const EmployeeLocatorMobileReasonPanel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 19, color: AppTheme.primaryNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason / Purpose',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class EmployeeLocatorMobileDetailActions extends StatelessWidget {
  const EmployeeLocatorMobileDetailActions({
    super.key,
    required this.canCancel,
    required this.canPrint,
    required this.onHistory,
    required this.onCancel,
    required this.onPrint,
    this.canReject = false,
    this.canApprove = false,
    this.onReject,
    this.onApprove,
  });

  final bool canCancel;
  final bool canPrint;
  final bool canReject;
  final bool canApprove;
  final VoidCallback onHistory;
  final VoidCallback onCancel;
  final VoidCallback onPrint;
  final VoidCallback? onReject;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = _secondaryButtonStyle(context);
    final dangerStyle = _dangerButtonStyle(context);
    final primaryStyle = _primaryButtonStyle();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onHistory,
                    style: secondaryStyle,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('History'),
                  ),
                ),
                if (canCancel) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      style: dangerStyle,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancel Request'),
                    ),
                  ),
                ],
                if (canPrint) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onPrint,
                      style: primaryStyle,
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                    ),
                  ),
                ],
                if (canReject || canApprove) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canReject ? onReject : null,
                          style: dangerStyle,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canApprove ? onApprove : null,
                          style: primaryStyle,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: onHistory,
                  style: secondaryStyle,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('History'),
                ),
                if (canCancel)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    style: dangerStyle,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancel Request'),
                  ),
                if (canReject)
                  OutlinedButton.icon(
                    onPressed: onReject,
                    style: dangerStyle,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                if (canApprove)
                  FilledButton.icon(
                    onPressed: onApprove,
                    style: primaryStyle,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                if (canPrint)
                  FilledButton.icon(
                    onPressed: onPrint,
                    style: primaryStyle,
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Print'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  ButtonStyle _secondaryButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(116, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      foregroundColor: AppTheme.dashTextPrimaryOf(context),
      side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _dangerButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(116, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      foregroundColor: Colors.red.shade700,
      side: BorderSide(color: Colors.red.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size(116, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
