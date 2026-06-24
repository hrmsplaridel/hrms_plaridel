import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_overlay.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/admin_leave_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/employee/employee_leave_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_request_form_screen.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/responsive_leave_form_host.dart';

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
    this.onFileLeavePressed,
    this.hideEmployeeFileLeaveAction = false,
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

  /// Optional external handler for filing leave, useful when a parent shell owns
  /// the mobile floating action button.
  final VoidCallback? onFileLeavePressed;

  /// Hide the in-page File Leave button when the parent shell shows its own.
  final bool hideEmployeeFileLeaveAction;

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
    final hideMobileEmployeeChrome =
        MediaQuery.sizeOf(context).width < 600 &&
        !widget.isAdmin &&
        !widget.isDepartmentHead &&
        !useSidebarNav;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hideMobileEmployeeChrome) ...[
          Text(
            'Leave Management',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (widget.isAdmin || widget.isDepartmentHead)
                ? 'Review employee leave requests, balances, and approvals.'
                : 'View leave balances, file requests, and track approvals.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 14,
            ),
          ),
          if (!useSidebarNav) ...[
            const SizedBox(height: 24),
            _buildSectionNav(),
          ],
          const SizedBox(height: 24),
        ],
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
        final dark = AppTheme.dashIsDark(context);
        return Material(
          color: isSelected
              ? (dark
                    ? AppTheme.primaryNavy.withValues(alpha: 0.35)
                    : AppTheme.primaryNavy.withValues(alpha: 0.12))
              : (dark
                    ? AppTheme.dashMutedSurfaceOf(context)
                    : AppTheme.lightGray.withValues(alpha: 0.6)),
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
                        : AppTheme.dashTextSecondaryOf(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.title,
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryNavy
                          : AppTheme.dashTextPrimaryOf(context),
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
    final VoidCallback fileLeaveHandler =
        widget.onFileLeavePressed ?? () => _openLeaveRequestForm();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 220),
      child: switch (_activeSection) {
        LeaveSection.requests =>
          widget.employeeRequestsContent ??
              EmployeeLeaveScreen(
                onFileLeavePressed: fileLeaveHandler,
                showFileLeaveAction: !widget.hideEmployeeFileLeaveAction,
              ),
        LeaveSection.approvals =>
          widget.adminApprovalsContent ??
              AdminLeaveScreen(isDepartmentHead: widget.isDepartmentHead),
        LeaveSection.balances =>
          widget.employeeBalancesContent ??
              EmployeeLeaveScreen(
                onFileLeavePressed: fileLeaveHandler,
                showFileLeaveAction: !widget.hideEmployeeFileLeaveAction,
              ),
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
    final result = await openResponsiveLeaveFormHost<String?>(
      context: context,
      builder: (_) => _buildLeaveRequestForm(),
    );
    if (!mounted || result == null) return;
    if (result != kLeaveFormResultDraftSaved &&
        result != kLeaveFormResultSubmitted) {
      return;
    }
    final userId = context.read<AuthProvider>().user?.id;
    if (userId != null && userId.isNotEmpty) {
      await context.read<LeaveProvider>().loadMyLeaveData(userId);
    }
    if (!mounted) return;
    showLeaveFormSuccessSnackBar(context, result);
  }

  Widget _buildLeaveRequestForm() {
    final form = LeaveRequestFormScreen(
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
        final provider = context.read<LeaveProvider>();
        if (request.id != null && request.id!.isNotEmpty) {
          final updated = await provider.updateRequest(
            request.copyWith(status: LeaveRequestStatus.pending),
          );
          return updated != null;
        }
        final saved = await provider.submitRequest(request);
        return saved != null;
      },
      onSubmitRequestWithAttachment:
          (LeaveRequest request, List<int> fileBytes, String fileName) async {
            final provider = context.read<LeaveProvider>();
            final saved = await provider.submitRequestWithAttachment(
              request: request,
              fileBytes: fileBytes,
              fileName: fileName,
            );
            return saved != null;
          },
    );
    if (widget.isAdmin) return form;
    return EmployeeHrmsAssistantOverlay(initialBottom: 36, child: form);
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
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
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
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
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
