import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_employee_account_setup_panel.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_attachment_actions.dart';

enum _FinalReqStatusFilter {
  all,
  incomplete,
  readyForReview,
  approved,
  hired,
}

/// Admin: track medical certificate, drug test, and NBI clearance for applicants
/// who passed deliberation, then proceed to employee account setup.
class RspFinalRequirementsSection extends StatefulWidget {
  const RspFinalRequirementsSection({super.key, this.onGoToCreateAccount});

  /// Opens the admin **Create Account** screen (sidebar); parent supplies navigation.
  final VoidCallback? onGoToCreateAccount;

  @override
  State<RspFinalRequirementsSection> createState() =>
      _RspFinalRequirementsSectionState();
}

class _RspFinalRequirementsSectionState
    extends State<RspFinalRequirementsSection> {
  List<RecruitmentApplication> _applications = [];
  bool _loading = true;
  final Set<String> _savingIds = {};
  final Set<String> _expandedApplicantIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedPositionFilter;
  DateTime? _selectedAppliedDate;
  _FinalReqStatusFilter _statusFilter = _FinalReqStatusFilter.all;

  static const _kCardPadding = 24.0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      if (!mounted) return;
      setState(() {
        _applications = apps
            .where((a) => a.finalInterviewPassed == true)
            .toList()
          ..sort(
            (a, b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applications = [];
        _loading = false;
      });
    }
  }

  static bool _isHired(RecruitmentApplication a) {
    return a.status == 'registered' ||
        (a.hiredUserId != null && a.hiredUserId!.trim().isNotEmpty);
  }

  static String _complianceLabel(RecruitmentApplication app) {
    if (_isHired(app)) return 'Hired';
    if (app.finalRequirementsApproved) return 'Approved';
    if (app.hasAllFinalRequirementsUploaded) return 'Ready for review';
    return 'Incomplete';
  }

  static Color _complianceColor(RecruitmentApplication app) {
    if (_isHired(app)) return const Color(0xFF2E7D32);
    if (app.finalRequirementsApproved) return const Color(0xFF2E7D32);
    if (app.hasAllFinalRequirementsUploaded) return const Color(0xFF1565C0);
    return Colors.orange.shade800;
  }

  bool _matchesStatusFilter(RecruitmentApplication app) {
    switch (_statusFilter) {
      case _FinalReqStatusFilter.all:
        return true;
      case _FinalReqStatusFilter.incomplete:
        return !app.hasAllFinalRequirementsUploaded &&
            !app.finalRequirementsApproved;
      case _FinalReqStatusFilter.readyForReview:
        return app.hasAllFinalRequirementsUploaded &&
            !app.finalRequirementsApproved;
      case _FinalReqStatusFilter.approved:
        return app.finalRequirementsApproved && !_isHired(app);
      case _FinalReqStatusFilter.hired:
        return _isHired(app);
    }
  }

  Set<String> get _positionFilterOptions {
    final out = <String>{};
    for (final a in _applications) {
      final p = (a.positionAppliedFor ?? '').trim();
      if (p.isNotEmpty) out.add(p);
    }
    return out;
  }

  bool _isSameLocalDate(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  List<RecruitmentApplication> get _filteredApplications {
    return _applications.where((a) {
      final position = (a.positionAppliedFor ?? '').trim();
      if (_selectedPositionFilter != null &&
          _selectedPositionFilter!.isNotEmpty &&
          position != _selectedPositionFilter) {
        return false;
      }
      if (_selectedAppliedDate != null) {
        final createdAt = a.createdAt;
        if (createdAt == null ||
            !_isSameLocalDate(createdAt, _selectedAppliedDate!)) {
          return false;
        }
      }
      if (!_matchesStatusFilter(a)) return false;
      if (_searchQuery.isNotEmpty) {
        final hay =
            '${a.fullName} ${a.email} ${a.positionAppliedFor ?? ''}'
                .toLowerCase();
        if (!hay.contains(_searchQuery)) return false;
      }
      return true;
    }).toList();
  }

  int get _incompleteCount => _applications
      .where(
        (a) =>
            !a.hasAllFinalRequirementsUploaded && !a.finalRequirementsApproved,
      )
      .length;

  int get _readyCount => _applications
      .where(
        (a) => a.hasAllFinalRequirementsUploaded && !a.finalRequirementsApproved,
      )
      .length;

  int get _approvedCount =>
      _applications.where((a) => a.finalRequirementsApproved && !_isHired(a))
          .length;

  int get _hiredCount => _applications.where(_isHired).length;

  String _formatDateShort(DateTime date) {
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = date.toLocal();
    return '${monthNames[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _setApproved(RecruitmentApplication app, bool approved) async {
    setState(() => _savingIds.add(app.id));
    try {
      await RecruitmentRepo.instance.updateFinalRequirementsApproved(
        app.id,
        approved,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Final requirements marked as approved.'
                : 'Final requirements approval cleared.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    } finally {
      if (mounted) setState(() => _savingIds.remove(app.id));
    }
  }

  Future<void> _setOrientationAttendance(
    RecruitmentApplication app,
    bool? attended,
  ) async {
    setState(() => _savingIds.add(app.id));
    try {
      await RecruitmentRepo.instance.updateOrientationAttended(app.id, attended);
      if (!mounted) return;
      final msg = attended == null
          ? 'Orientation attendance reset to pending.'
          : attended
          ? 'Orientation marked as attended.'
          : 'Orientation marked as no-show.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    } finally {
      if (mounted) setState(() => _savingIds.remove(app.id));
    }
  }

  String _formatScheduleDateTime(DateTime at, BuildContext context) {
    final local = at.toLocal();
    final dateStr = MaterialLocalizations.of(context).formatFullDate(local);
    final timeStr = TimeOfDay.fromDateTime(local).format(context);
    return '$dateStr · $timeStr';
  }

  Widget _buildOrientationAttendancePanel(RecruitmentApplication app) {
    final saving = _savingIds.contains(app.id);
    final attended = app.orientationAttended;
    final selected = attended == null ? 0 : (attended ? 1 : 2);
    final scheduled = app.orientationAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE85D04).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Text(
                '2',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE85D04),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Orientation attendance',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scheduled == null
                        ? 'Schedule orientation in Scheduling, then record attendance.'
                        : 'Scheduled: ${_formatScheduleDateTime(scheduled, context)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        IgnorePointer(
          ignoring: saving,
          child: Opacity(
            opacity: saving ? 0.45 : 1,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Pending'),
                  icon: Icon(Icons.schedule_rounded, size: 18),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Attended'),
                  icon: Icon(Icons.check_rounded, size: 18),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('No show'),
                  icon: Icon(Icons.person_off_rounded, size: 18),
                ),
              ],
              selected: {selected},
              onSelectionChanged: (s) {
                if (saving) return;
                final v = s.first;
                final want = v == 0 ? null : (v == 1);
                if (want == attended) return;
                _setOrientationAttendance(app, want);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          attended == true
              ? 'Applicant attended orientation.'
              : attended == false
              ? 'Applicant did not attend orientation.'
              : scheduled == null
              ? 'Waiting for orientation schedule.'
              : 'Orientation scheduled — record attendance after the session.',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedPositionFilter = null;
      _selectedAppliedDate = null;
      _statusFilter = _FinalReqStatusFilter.all;
      _searchController.clear();
    });
  }

  BoxDecoration _shellCardDecoration(BuildContext context) {
    return BoxDecoration(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primaryNavy.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _shellTopAccent() => Container(
    height: 4,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE85D04), Color(0xFFFFB74D)],
      ),
    ),
  );

  Widget _applicantInitials(BuildContext context, String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.2),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
        ),
      ),
    );
  }

  Widget _statPill({
    required String label,
    required int count,
    required Color color,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.16)
                : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.55)
                  : color.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final accentNavy = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;
    final filtered = _filteredApplications;
    final hasActiveFilters = _selectedPositionFilter != null ||
        _selectedAppliedDate != null ||
        _statusFilter != _FinalReqStatusFilter.all ||
        _searchQuery.isNotEmpty;

    final refreshBtn = FilledButton.icon(
      onPressed: _loading ? null : _load,
      icon: const Icon(Icons.refresh_rounded, size: 20),
      label: const Text('Refresh list'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final dateFilterBtn = OutlinedButton.icon(
      onPressed: _loading
          ? null
          : () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedAppliedDate ?? now,
                firstDate: DateTime(now.year - 10),
                lastDate: DateTime(now.year + 1),
                helpText: 'Filter by applied date',
              );
              if (picked == null || !mounted) return;
              setState(() => _selectedAppliedDate = picked);
            },
      icon: const Icon(Icons.event_outlined, size: 18),
      label: Text(
        _selectedAppliedDate == null
            ? 'Applied date'
            : _formatDateShort(_selectedAppliedDate!),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: hairline),
        foregroundColor: AppTheme.dashTextPrimaryOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFE85D04).withValues(alpha: 0.18),
                    const Color(0xFFFFB74D).withValues(alpha: 0.1),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFE85D04).withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                Icons.health_and_safety_outlined,
                size: 26,
                color: accentNavy,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Final Requirements',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applicants who passed deliberation must submit medical certificate, '
                    'drug test result, and NBI clearance. Review uploads, mark compliance, '
                    'then create the employee account and email credentials.',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            refreshBtn,
          ],
        ),
        if (!_loading && _applications.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statPill(
                label: 'Total',
                count: _applications.length,
                color: accentNavy,
                selected: _statusFilter == _FinalReqStatusFilter.all,
                onTap: () =>
                    setState(() => _statusFilter = _FinalReqStatusFilter.all),
              ),
              _statPill(
                label: 'Incomplete',
                count: _incompleteCount,
                color: Colors.orange.shade800,
                selected: _statusFilter == _FinalReqStatusFilter.incomplete,
                onTap: () => setState(
                  () => _statusFilter = _FinalReqStatusFilter.incomplete,
                ),
              ),
              _statPill(
                label: 'Ready for review',
                count: _readyCount,
                color: const Color(0xFF1565C0),
                selected: _statusFilter == _FinalReqStatusFilter.readyForReview,
                onTap: () => setState(
                  () => _statusFilter = _FinalReqStatusFilter.readyForReview,
                ),
              ),
              _statPill(
                label: 'Approved',
                count: _approvedCount,
                color: const Color(0xFF2E7D32),
                selected: _statusFilter == _FinalReqStatusFilter.approved,
                onTap: () => setState(
                  () => _statusFilter = _FinalReqStatusFilter.approved,
                ),
              ),
              _statPill(
                label: 'Hired',
                count: _hiredCount,
                color: const Color(0xFF6A1B9A),
                selected: _statusFilter == _FinalReqStatusFilter.hired,
                onTap: () =>
                    setState(() => _statusFilter = _FinalReqStatusFilter.hired),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name, email, or position…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
            filled: true,
            fillColor: AppTheme.dashMutedSurfaceOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedPositionFilter,
                decoration: InputDecoration(
                  labelText: 'Position',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline),
                  ),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All positions'),
                  ),
                  ...(_positionFilterOptions.toList()..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      ))
                      .map(
                        (p) =>
                            DropdownMenuItem<String>(value: p, child: Text(p)),
                      ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() => _selectedPositionFilter = value);
                      },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<_FinalReqStatusFilter>(
                initialValue: _statusFilter,
                decoration: InputDecoration(
                  labelText: 'Compliance status',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: _FinalReqStatusFilter.all,
                    child: Text('All statuses'),
                  ),
                  DropdownMenuItem(
                    value: _FinalReqStatusFilter.incomplete,
                    child: Text('Incomplete'),
                  ),
                  DropdownMenuItem(
                    value: _FinalReqStatusFilter.readyForReview,
                    child: Text('Ready for review'),
                  ),
                  DropdownMenuItem(
                    value: _FinalReqStatusFilter.approved,
                    child: Text('Approved'),
                  ),
                  DropdownMenuItem(
                    value: _FinalReqStatusFilter.hired,
                    child: Text('Hired'),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _statusFilter = value);
                        }
                      },
              ),
            ),
            dateFilterBtn,
            TextButton.icon(
              onPressed: _loading
                  ? null
                  : () => setState(() => _selectedAppliedDate = DateTime.now()),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Today'),
            ),
            TextButton.icon(
              onPressed: _loading || !hasActiveFilters ? null : _clearFilters,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear filters'),
            ),
            Text(
              '${filtered.length} shown',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_applications.isEmpty)
          _emptyState(
            context,
            icon: Icons.people_outline_rounded,
            title: 'No deliberation-passed applicants yet',
            body:
                'Record deliberation results in Scheduling first. '
                'Applicants who pass will appear here for final requirements.',
          )
        else if (filtered.isEmpty)
          _emptyState(
            context,
            icon: Icons.filter_alt_off_rounded,
            title: 'No applicants match your filters',
            body:
                'Try clearing filters, choosing a different status, or refreshing the list.',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, i) => _buildApplicantCard(filtered[i]),
          ),
      ],
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      decoration: _shellCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shellTopAccent(),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Icon(icon, size: 40, color: AppTheme.dashTextSecondaryOf(context)),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicantCard(RecruitmentApplication app) {
    final saving = _savingIds.contains(app.id);
    final allUploaded = app.hasAllFinalRequirementsUploaded;
    final approved = app.finalRequirementsApproved;
    final hired = _isHired(app);
    final statusLabel = _complianceLabel(app);
    final statusColor = _complianceColor(app);
    final useMinimalRow =
        approved && !_expandedApplicantIds.contains(app.id) && !saving;

    if (useMinimalRow) {
      return Container(
        decoration: _shellCardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _shellTopAccent(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    setState(() => _expandedApplicantIds.add(app.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      _applicantInitials(context, app.fullName),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.fullName,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: AppTheme.dashTextPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _statusChip(label: statusLabel, color: statusColor),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: _shellCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shellTopAccent(),
          Padding(
            padding: const EdgeInsets.all(_kCardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (approved) ...[
                  Row(
                    children: [
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _expandedApplicantIds.remove(app.id),
                        ),
                        icon: const Icon(Icons.unfold_less_rounded, size: 20),
                        label: const Text('Show less'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _applicantInitials(context, app.fullName),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppTheme.dashTextPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            app.email,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          ),
                          if (app.positionAppliedFor != null &&
                              app.positionAppliedFor!.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Position: ${app.positionAppliedFor!.trim()}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryNavy.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                          if (app.createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Applied: ${_formatDateShort(app.createdAt!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _statusChip(label: statusLabel, color: statusColor),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'REQUIREMENTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.65,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 720;
                    final tiles = RspFinalRequirementDocKind.values
                        .map((kind) => _docTile(app: app, kind: kind))
                        .toList();
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: tiles
                            .map(
                              (t) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: t,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    }
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: tiles,
                    );
                  },
                ),
                if (!approved) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: saving || !allUploaded || approved
                            ? null
                            : () => _setApproved(app, true),
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_rounded, size: 20),
                        label: const Text('Mark approved'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!hired)
                        TextButton.icon(
                          onPressed: saving
                              ? null
                              : () => _setApproved(app, false),
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          label: const Text('Clear approval'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                  const SizedBox(height: 20),
                  _buildOrientationAttendancePanel(app),
                  const SizedBox(height: 20),
                  Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
                  const SizedBox(height: 20),
                  Builder(
                    builder: (context) {
                      final step3Enabled =
                          app.orientationAttended == true || hired;
                      String step3Subtitle;
                      if (hired) {
                        step3Subtitle = 'Account linked.';
                      } else if (step3Enabled) {
                        step3Subtitle = 'Create login, then email credentials.';
                      } else if (app.orientationAttended == false) {
                        step3Subtitle =
                            'Disabled until orientation is marked attended.';
                      } else {
                        step3Subtitle =
                            'Mark orientation as attended in Step 2 first.';
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE85D04)
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '3',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: step3Enabled
                                          ? const Color(0xFFE85D04)
                                          : AppTheme.dashTextSecondaryOf(
                                              context,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Employee account',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: step3Enabled
                                              ? AppTheme.dashTextPrimaryOf(
                                                  context,
                                                )
                                              : AppTheme.dashTextSecondaryOf(
                                                  context,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        step3Subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.dashTextSecondaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            RspEmployeeAccountSetupPanel(
                              app: app,
                              enabled: step3Enabled,
                              busy: saving,
                              onBusyChanged: (v) {
                                if (v) {
                                  setState(() => _savingIds.add(app.id));
                                } else {
                                  setState(() => _savingIds.remove(app.id));
                                }
                              },
                              onReload: _load,
                              onGoToCreateAccount: widget.onGoToCreateAccount,
                            ),
                          ],
                        );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _docTile({
    required RecruitmentApplication app,
    required RspFinalRequirementDocKind kind,
  }) {
    final path = app.finalRequirementPath(kind);
    final name = app.finalRequirementDisplayName(kind);
    final hasFile = path != null && path.isNotEmpty && name != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFile ? Icons.check_circle_rounded : Icons.pending_rounded,
                size: 16,
                color: hasFile
                    ? const Color(0xFF2E7D32)
                    : AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _kindLabel(kind),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasFile)
            RspAttachmentActions(path: path, fileName: name)
          else
            Text(
              'Not submitted',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _kindLabel(RspFinalRequirementDocKind kind) {
    switch (kind) {
      case RspFinalRequirementDocKind.medicalCertificate:
        return 'Medical Certificate';
      case RspFinalRequirementDocKind.drugTestResult:
        return 'Drug Test Result';
      case RspFinalRequirementDocKind.nbiClearance:
        return 'NBI Clearance';
    }
  }
}
