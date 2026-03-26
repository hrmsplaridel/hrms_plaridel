import 'package:flutter/material.dart';

import '../../landingpage/constants/app_theme.dart';
import '../models/leave_type.dart';
import '../utils/leave_guidance.dart';

// ── A. General Instruction Panel ─────────────────────────────────────────────

/// Shows a short, scannable list of general reminders at the top of the
/// leave filing form.
class LeaveGeneralInstructionsPanel extends StatelessWidget {
  const LeaveGeneralInstructionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return _GuidanceContainer(
      color: const Color(0xFFFFF8ED),
      borderColor: const Color(0xFFFBBC04).withOpacity(0.45),
      icon: Icons.info_outline_rounded,
      iconColor: const Color(0xFFB45309),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: const Color(0xFFB45309),
              ),
              const SizedBox(width: 8),
              Text(
                'Before Filing',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF92400E),
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              // "View Full Guidelines" text button
              _FullGuidelinesTextButton(),
            ],
          ),
          const SizedBox(height: 10),
          ...LeaveGuidance.generalReminders.map(
            (reminder) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB45309),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reminder,
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF78350F),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── B. Dynamic Leave-Type Guidance Card ──────────────────────────────────────

/// Shows contextual, per-leave-type guidance below the leave type dropdown.
/// Driven entirely by [LeaveGuidance.forType].
class LeaveTypeGuidanceCard extends StatelessWidget {
  const LeaveTypeGuidanceCard({super.key, required this.leaveType});

  final LeaveType leaveType;

  @override
  Widget build(BuildContext context) {
    final guidance = LeaveGuidance.forType(leaveType);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: _GuidanceContainer(
        key: ValueKey(leaveType),
        color: const Color(0xFFF0F7FF),
        borderColor: AppTheme.primaryNavy.withOpacity(0.18),
        icon: Icons.lightbulb_outline_rounded,
        iconColor: AppTheme.primaryNavy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 17,
                  color: AppTheme.primaryNavy,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${leaveType.displayName} — Quick Guide',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Description
            Text(
              guidance.description,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 10),

            // Requirements
            _GuidanceRow(
              icon: Icons.description_outlined,
              label: 'Requirements',
              value: guidance.requirements,
            ),

            // Limits
            if (guidance.limits != null) ...[
              const SizedBox(height: 6),
              _GuidanceRow(
                icon: Icons.event_available_outlined,
                label: 'Limit',
                value: guidance.limits!,
              ),
            ],

            // Advance filing
            if (guidance.advanceFiling != null) ...[
              const SizedBox(height: 6),
              _GuidanceRow(
                icon: Icons.schedule_outlined,
                label: 'Advance Filing',
                value: guidance.advanceFiling!,
              ),
            ],

            // Notes
            if (guidance.notes != null) ...[
              const SizedBox(height: 6),
              _GuidanceRow(
                icon: Icons.warning_amber_outlined,
                label: 'Note',
                value: guidance.notes!,
                valueColor: const Color(0xFF92400E),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── C. Full Guidelines Viewer ────────────────────────────────────────────────

/// A small text button that opens [LeaveFullGuidelinesSheet].
class _FullGuidelinesTextButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => LeaveFullGuidelinesSheet.show(context),
      child: Text(
        'View Full Guidelines',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryNavy,
          decoration: TextDecoration.underline,
          decorationColor: AppTheme.primaryNavy,
        ),
      ),
    );
  }
}

/// A prominently styled outlined button for "View Full Leave Guidelines".
/// Suitable for placement anywhere in the form (e.g. below the guidance card).
class ViewFullGuidelinesButton extends StatelessWidget {
  const ViewFullGuidelinesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => LeaveFullGuidelinesSheet.show(context),
      icon: const Icon(Icons.menu_book_rounded, size: 18),
      label: const Text('View Full Leave Guidelines'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        side: BorderSide(color: AppTheme.primaryNavy.withOpacity(0.5)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

/// A modal bottom sheet that displays the complete leave filing guidelines,
/// organized into collapsible sections.
class LeaveFullGuidelinesSheet extends StatelessWidget {
  const LeaveFullGuidelinesSheet._();

  /// Convenience launcher — call from any widget.
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const LeaveFullGuidelinesSheet._(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle + header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  // Pill handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book_rounded,
                        color: AppTheme.primaryNavy,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LeaveGuidance.fullGuidelinesTitle,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'CSC-based government leave guidelines',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
              ),
            ),
            // Scrollable body
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 16, 20, mq.padding.bottom + 24),
                children: [
                  ...LeaveGuidance.fullGuidelines.map(
                    (section) => _GuidelineSectionTile(section: section),
                  ),
                  const SizedBox(height: 8),
                  // Per-leave-type summary table
                  _PerTypeQuickReferenceTable(),
                  const SizedBox(height: 16),
                  Text(
                    'For queries, contact your HR Office.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// An expandable tile for each section of the full guidelines.
class _GuidelineSectionTile extends StatelessWidget {
  const _GuidelineSectionTile({required this.section});

  final LeaveGuidelineSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.07)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(
              _iconFromName(section.icon),
              color: AppTheme.primaryNavy,
              size: 20,
            ),
            title: Text(
              section.title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
            initiallyExpanded: true,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: section.items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryNavy.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  IconData _iconFromName(String name) => switch (name) {
        'rule' => Icons.rule_rounded,
        'schedule' => Icons.schedule_rounded,
        'description' => Icons.description_rounded,
        'event_available' => Icons.event_available_rounded,
        'payments' => Icons.payments_rounded,
        _ => Icons.article_rounded,
      };
}

/// A compact scrollable table showing the max days per leave type.
class _PerTypeQuickReferenceTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = LeaveType.values
        .where((t) => t.employeeCanFile)
        .map((t) {
          final g = LeaveGuidance.forType(t);
          final limit = g.limits ?? (t.maxDays != null ? '${t.maxDays} days' : 'No fixed limit');
          return _TableRowData(type: t.displayName, limit: limit, needsDocs: t.requiresAttachment);
        })
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.table_chart_outlined, color: AppTheme.primaryNavy, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Quick Reference',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          // Header
          Container(
            color: AppTheme.offWhite,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Leave Type',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Limit / Duration',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    'Docs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return Container(
              color: i.isOdd ? AppTheme.offWhite.withOpacity(0.5) : AppTheme.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      row.type,
                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.4),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row.limit,
                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.4),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Icon(
                      row.needsDocs
                          ? Icons.check_circle_outline_rounded
                          : Icons.remove_rounded,
                      size: 16,
                      color: row.needsDocs ? Colors.green.shade600 : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TableRowData {
  const _TableRowData({
    required this.type,
    required this.limit,
    required this.needsDocs,
  });

  final String type;
  final String limit;
  final bool needsDocs;
}

// ── Shared container used by guidance components ──────────────────────────────

class _GuidanceContainer extends StatelessWidget {
  const _GuidanceContainer({
    super.key,
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

// ── Shared row widget ─────────────────────────────────────────────────────────

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppTheme.primaryNavy.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? AppTheme.textPrimary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
