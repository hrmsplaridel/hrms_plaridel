import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../landingpage/constants/app_theme.dart';
import '../providers/auth_provider.dart';
import 'leave_provider.dart';
import 'models/leave_request.dart';
import 'screens/admin_leave_screen.dart';
import 'screens/employee_leave_screen.dart';
import 'screens/leave_request_form_screen.dart';
import 'utils/responsive_leave_form_host.dart';

/// High-level sections for the leave module.
enum LeaveSection { dashboard, requests, approvals, balances }

extension LeaveSectionExtension on LeaveSection {
  String get title => switch (this) {
    LeaveSection.dashboard => 'Dashboard',
    LeaveSection.requests => 'My Requests',
    LeaveSection.approvals => 'Approvals',
    LeaveSection.balances => 'Balances',
  };
}

/// Main leave module entry.
///
/// This acts as the shell/container for employee and admin leave pages.
/// Real screens can be plugged in later through the optional widget overrides.
class LeaveMain extends StatefulWidget {
  const LeaveMain({
    super.key,
    this.section,
    this.initialSection,
    this.isAdmin = false,
    this.isDepartmentHead = false,
    this.employeeRequestsContent,
    this.employeeBalancesContent,
    this.adminApprovalsContent,
  });

  /// Active section when controlled by sidebar navigation.
  final LeaveSection? section;

  /// One-time tab selection for employees (e.g. after opening a notification). Ignored if [section] is set.
  final LeaveSection? initialSection;

  /// Whether current user is HR/admin.
  final bool isAdmin;

  /// Whether current user is a department head (non-admin reviewer).
  final bool isDepartmentHead;

  /// Optional injected content for employee requests.
  final Widget? employeeRequestsContent;

  /// Optional injected content for employee balances.
  final Widget? employeeBalancesContent;

  /// Optional injected content for admin approvals.
  final Widget? adminApprovalsContent;

  @override
  State<LeaveMain> createState() => _LeaveMainState();
}

class _LeaveMainState extends State<LeaveMain> {
  LeaveSection _currentSection = LeaveSection.requests;

  @override
  void initState() {
    super.initState();
    // Dept heads should default to Approvals (but still be able to file their
    // own leave via the Requests tab).
    if (widget.isDepartmentHead) {
      _currentSection = LeaveSection.approvals;
    }
    if (widget.initialSection != null) {
      _currentSection = widget.initialSection!;
    }
  }

  LeaveSection get _activeSection {
    if (widget.section != null) return widget.section!;
    if (widget.isAdmin) return LeaveSection.approvals;
    return _currentSection;
  }

  @override
  Widget build(BuildContext context) {
    final useSidebarNav = widget.section != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Leave Management',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          (widget.isAdmin || widget.isDepartmentHead)
              ? 'Review employee leave requests, balances, and approvals.'
              : 'View leave balances, file requests, and track approvals.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        if (!useSidebarNav) ...[const SizedBox(height: 24), _buildSectionNav()],
        const SizedBox(height: 24),
        _buildContent(),
      ],
    );
  }

  Widget _buildSectionNav() {
    final sections = widget.isAdmin
        ? [LeaveSection.approvals]
        : widget.isDepartmentHead
        ? [LeaveSection.requests, LeaveSection.approvals]
        : [LeaveSection.requests];

    if (sections.length <= 1) return const SizedBox.shrink();

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: sections.map((section) {
        final isSelected = _currentSection == section;
        return Material(
          color: isSelected
              ? AppTheme.primaryNavy.withOpacity(0.12)
              : AppTheme.lightGray.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => setState(() => _currentSection = section),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForSection(section),
                    size: 20,
                    color: isSelected
                        ? AppTheme.primaryNavy
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryNavy
                          : AppTheme.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  static IconData _iconForSection(LeaveSection section) => switch (section) {
    LeaveSection.dashboard => Icons.dashboard_rounded,
    LeaveSection.requests => Icons.event_note_rounded,
    LeaveSection.approvals => Icons.fact_check_rounded,
    LeaveSection.balances => Icons.account_balance_wallet_rounded,
  };

  Widget _buildContent() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 220),
      child: switch (_activeSection) {
        LeaveSection.requests =>
          widget.employeeRequestsContent ??
              EmployeeLeaveScreen(onFileLeavePressed: _openLeaveRequestForm),
        LeaveSection.approvals =>
          widget.adminApprovalsContent ??
              AdminLeaveScreen(isDepartmentHead: widget.isDepartmentHead),
        LeaveSection.balances =>
          widget.employeeBalancesContent ??
              EmployeeLeaveScreen(onFileLeavePressed: _openLeaveRequestForm),
        LeaveSection.dashboard => _LeavePlaceholderCard(
          title: 'Leave Dashboard',
          subtitle:
              'This section can later summarize balances, upcoming leave, and pending approvals.',
          icon: Icons.dashboard_rounded,
        ),
      },
    );
  }

  Future<void> _openLeaveRequestForm() async {
    final result = await openResponsiveLeaveFormHost<bool>(
      context: context,
      builder: (_) => _buildLeaveRequestForm(),
    );
    if (!mounted || result != true) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId != null && userId.isNotEmpty) {
      await context.read<LeaveProvider>().loadMyLeaveData(userId);
    }
  }

  Widget _buildLeaveRequestForm() {
    return LeaveRequestFormScreen(
      onSaveDraft: (LeaveRequest request) async {
        // FIX #4: If the request already has an ID it was previously saved.
        // Route to updateRequest (PUT) to avoid creating a duplicate draft.
        final provider = context.read<LeaveProvider>();
        if (request.id != null && request.id!.isNotEmpty) {
          final updated = await provider.updateRequest(request);
          return updated != null;
        }
        final saved = await provider.saveDraft(request);
        return saved != null;
      },
      onSubmitRequest: (LeaveRequest request) async {
        final saved = await context.read<LeaveProvider>().submitRequest(
          request,
        );
        return saved != null;
      },
    );
  }
}

class _LeavePlaceholderCard extends StatelessWidget {
  const _LeavePlaceholderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryNavy, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.45,
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
