import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_employee_account_setup_panel.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_final_requirements_ui.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_attachment_actions.dart';

enum _FinalReqStatusFilter { all, incomplete, readyForReview, approved, hired }

/// Admin: track medical certificate, drug test, and NBI clearance for applicants
/// who passed deliberation, then proceed to employee account setup.
class RspFinalRequirementsSection extends StatefulWidget {
  const RspFinalRequirementsSection({
    super.key,
    this.onGoToCreateAccount,
    this.expandApplicationId,
    this.onExpandApplicationConsumed,
  });

  /// Opens the admin **Create Account** screen (sidebar); parent supplies navigation.
  final VoidCallback? onGoToCreateAccount;

  /// Expands this applicant after returning from Create Account.
  final String? expandApplicationId;
  final VoidCallback? onExpandApplicationConsumed;

  @override
  State<RspFinalRequirementsSection> createState() =>
      _RspFinalRequirementsSectionState();
}

class _RspFinalRequirementsSectionState
    extends State<RspFinalRequirementsSection> {
  List<RecruitmentApplication> _applications = [];
  bool _loading = true;
  final Set<String> _savingIds = {};
  final Set<String> _expandedIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedPositionFilter;
  DateTime? _selectedAppliedDate;
  _FinalReqStatusFilter _statusFilter = _FinalReqStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    _queueExpandApplication(widget.expandApplicationId);
    _load();
  }

  @override
  void didUpdateWidget(covariant RspFinalRequirementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.expandApplicationId?.trim();
    final prev = oldWidget.expandApplicationId?.trim();
    if (next != null && next.isNotEmpty && next != prev) {
      _queueExpandApplication(next);
    }
  }

  void _queueExpandApplication(String? id) {
    final trimmed = id?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    _expandedIds.add(trimmed);
    _statusFilter = _FinalReqStatusFilter.all;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onExpandApplicationConsumed?.call();
    });
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
        _applications =
            apps.where((a) => a.finalInterviewPassed == true).toList()
              ..sort(_compareLatestAppliedFirst);
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

  /// Newest application first (`created_at DESC`, then `id DESC`).
  static int _compareLatestAppliedFirst(
    RecruitmentApplication a,
    RecruitmentApplication b,
  ) {
    final ad = a.createdAt;
    final bd = b.createdAt;
    if (ad != null && bd != null) {
      final byDate = bd.compareTo(ad);
      if (byDate != 0) return byDate;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    return b.id.toLowerCase().compareTo(a.id.toLowerCase());
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
    if (_isHired(app)) return RspFinalReqUi.success;
    if (app.finalRequirementsApproved) return RspFinalReqUi.success;
    if (app.hasAllFinalRequirementsUploaded) return RspFinalReqUi.readyBlue;
    return RspFinalReqUi.warning;
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
    // Preserve newest-first order from [_applications].
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
            '${a.applicantNumber ?? ''} ${a.fullName} ${a.email} ${a.positionAppliedFor ?? ''}'
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
        (a) =>
            a.hasAllFinalRequirementsUploaded && !a.finalRequirementsApproved,
      )
      .length;

  int get _approvedCount => _applications
      .where((a) => a.finalRequirementsApproved && !_isHired(a))
      .length;

  int get _hiredCount => _applications.where(_isHired).length;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
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
      await RecruitmentRepo.instance.updateOrientationAttended(
        app.id,
        attended,
      );
      if (!mounted) return;
      final msg = attended == null
          ? 'Orientation attendance reset to pending.'
          : attended
          ? 'Orientation marked as attended.'
          : 'Orientation marked as no-show.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
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

  void _clearFilters() {
    setState(() {
      _selectedPositionFilter = null;
      _selectedAppliedDate = null;
      _statusFilter = _FinalReqStatusFilter.all;
      _searchController.clear();
    });
  }

  void _toggleExpanded(RecruitmentApplication app, {required bool needsAttention}) {
    setState(() {
      if (_expandedIds.contains(app.id)) {
        if (!needsAttention) _expandedIds.remove(app.id);
      } else {
        _expandedIds.add(app.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredApplications;
    final hasActiveFilters =
        _selectedPositionFilter != null ||
        _selectedAppliedDate != null ||
        _statusFilter != _FinalReqStatusFilter.all ||
        _searchQuery.isNotEmpty;
    final ac = RspFinalReqUi.accentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(ac),
        const SizedBox(height: 16),
        if (!_loading && _applications.isNotEmpty) ...[
          _buildStatsRow(ac),
          const SizedBox(height: 14),
        ],
        _buildToolbar(hasActiveFilters: hasActiveFilters, shown: filtered.length),
        const SizedBox(height: 16),
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
        else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _buildApplicantCard(filtered[i]),
          ),
          const SizedBox(height: 14),
          _sortHintBanner(),
        ],
      ],
    );
  }

  Widget _buildHeader(Color ac) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 22, color: ac),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Final Requirements',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        color: RspFinalReqUi.primaryTextOf(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Review applicant documents, monitor orientation attendance, and manage employee account setup.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: RspFinalReqUi.secondaryTextOf(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh List'),
          style: FilledButton.styleFrom(
            backgroundColor: ac,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(Color ac) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final cards = [
          _statCard(
            label: 'Total Applicants',
            count: _applications.length,
            icon: Icons.groups_rounded,
            color: ac,
            selected: _statusFilter == _FinalReqStatusFilter.all,
            onTap: () =>
                setState(() => _statusFilter = _FinalReqStatusFilter.all),
          ),
          _statCard(
            label: 'Incomplete',
            count: _incompleteCount,
            icon: Icons.assignment_late_outlined,
            color: const Color(0xFFEA580C),
            selected: _statusFilter == _FinalReqStatusFilter.incomplete,
            onTap: () => setState(
              () => _statusFilter = _FinalReqStatusFilter.incomplete,
            ),
          ),
          _statCard(
            label: 'Ready for Review',
            count: _readyCount,
            icon: Icons.hourglass_top_rounded,
            color: RspFinalReqUi.readyBlue,
            selected: _statusFilter == _FinalReqStatusFilter.readyForReview,
            onTap: () => setState(
              () => _statusFilter = _FinalReqStatusFilter.readyForReview,
            ),
          ),
          _statCard(
            label: 'Approved',
            count: _approvedCount,
            icon: Icons.check_circle_outline_rounded,
            color: RspFinalReqUi.success,
            selected: _statusFilter == _FinalReqStatusFilter.approved,
            onTap: () => setState(
              () => _statusFilter = _FinalReqStatusFilter.approved,
            ),
          ),
          _statCard(
            label: 'Hired',
            count: _hiredCount,
            icon: Icons.badge_outlined,
            color: RspFinalReqUi.hiredPurple,
            selected: _statusFilter == _FinalReqStatusFilter.hired,
            onTap: () =>
                setState(() => _statusFilter = _FinalReqStatusFilter.hired),
          ),
        ];

        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (card) => SizedBox(
                  width: c.maxWidth >= 560
                      ? (c.maxWidth - 10) / 2
                      : c.maxWidth,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _statCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.14 : 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.50 : 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: color,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: color.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar({
    required bool hasActiveFilters,
    required int shown,
  }) {
    final hairline = RspFinalReqUi.hairlineOf(context);

    final search = TextField(
      controller: _searchController,
      decoration: RspFinalReqUi.filterDecoration(
        context,
        hint: 'Search by applicant ID, name, email, or position...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
      ),
    );

    final positionDd = DropdownButtonFormField<String>(
      initialValue: _selectedPositionFilter,
      isExpanded: true,
      decoration: RspFinalReqUi.filterDecoration(
        context,
        label: 'Position',
      ),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem<String>(
          value: null,
          child: Text('All positions'),
        ),
        ...(_positionFilterOptions.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
            .map(
              (p) => DropdownMenuItem<String>(
                value: p,
                child: RspFinalReqUi.ddText(p),
              ),
            ),
      ],
      onChanged: _loading
          ? null
          : (value) => setState(() => _selectedPositionFilter = value),
    );

    final statusDd = DropdownButtonFormField<_FinalReqStatusFilter>(
      initialValue: _statusFilter,
      isExpanded: true,
      decoration: RspFinalReqUi.filterDecoration(
        context,
        label: 'Compliance status',
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
              if (value != null) setState(() => _statusFilter = value);
            },
    );

    final dateBtn = OutlinedButton.icon(
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
      icon: const Icon(Icons.event_outlined, size: 16),
      label: Text(
        _selectedAppliedDate == null
            ? 'Applied date'
            : RspFinalReqUi.formatDateShort(_selectedAppliedDate!),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: hairline),
        foregroundColor: RspFinalReqUi.primaryTextOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: RspFinalReqUi.toolbarDecoration(context),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 980;
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 35, child: search),
                const SizedBox(width: 10),
                Expanded(flex: 16, child: positionDd),
                const SizedBox(width: 10),
                Expanded(flex: 16, child: statusDd),
                const SizedBox(width: 10),
                dateBtn,
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _loading
                      ? null
                      : () =>
                            setState(() => _selectedAppliedDate = DateTime.now()),
                  icon: const Icon(Icons.today_outlined, size: 16),
                  label: const Text('Today'),
                ),
                TextButton(
                  onPressed: _loading || !hasActiveFilters ? null : _clearFilters,
                  child: const Text('Clear filters'),
                ),
                const SizedBox(width: 6),
                Text(
                  '$shown shown',
                  style: TextStyle(
                    color: RspFinalReqUi.secondaryTextOf(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 200, child: positionDd),
                  SizedBox(width: 200, child: statusDd),
                  dateBtn,
                  TextButton.icon(
                    onPressed: _loading
                        ? null
                        : () => setState(
                              () => _selectedAppliedDate = DateTime.now(),
                            ),
                    icon: const Icon(Icons.today_outlined, size: 16),
                    label: const Text('Today'),
                  ),
                  TextButton(
                    onPressed:
                        _loading || !hasActiveFilters ? null : _clearFilters,
                    child: const Text('Clear filters'),
                  ),
                  Text(
                    '$shown shown',
                    style: TextStyle(
                      color: RspFinalReqUi.secondaryTextOf(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sortHintBanner() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: RspFinalReqUi.accentOf(context).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: RspFinalReqUi.accentOf(context).withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 16,
              color: RspFinalReqUi.accentOf(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Showing newest applicants first — Latest applications appear at the top of the list.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RspFinalReqUi.secondaryTextOf(context),
              ),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(28),
      decoration: RspFinalReqUi.cardDecoration(context),
      child: Column(
        children: [
          Icon(icon, size: 36, color: RspFinalReqUi.secondaryTextOf(context)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: RspFinalReqUi.primaryTextOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: RspFinalReqUi.secondaryTextOf(context),
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
    final needsAttention =
        !hired &&
        (!allUploaded ||
            !approved ||
            app.hasRejectedFinalRequirement ||
            saving);
    final expanded = needsAttention || _expandedIds.contains(app.id);
    final isNew = RspFinalReqUi.isNewApplication(app.createdAt);
    final ac = RspFinalReqUi.accentOf(context);

    return Container(
      decoration: RspFinalReqUi.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Orange top accent (matches reference image 2).
          Container(height: 4, color: ac),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  _toggleExpanded(app, needsAttention: needsAttention),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: _buildCardHeader(
                  app: app,
                  statusLabel: statusLabel,
                  statusColor: statusColor,
                  expanded: expanded,
                  isNew: isNew,
                  canCollapse: !needsAttention,
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _buildExpandedBody(
                app: app,
                saving: saving,
                allUploaded: allUploaded,
                approved: approved,
                hired: hired,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardHeader({
    required RecruitmentApplication app,
    required String statusLabel,
    required Color statusColor,
    required bool expanded,
    required bool isNew,
    required bool canCollapse,
  }) {
    final position = (app.positionAppliedFor ?? '').trim();
    final id = (app.applicantNumber ?? '').trim();
    final applied = app.createdAt;
    final metaParts = <InlineSpan>[];
    if (id.isNotEmpty) {
      metaParts.add(
        TextSpan(
          text: id,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: RspFinalReqUi.accentOf(context),
          ),
        ),
      );
    }
    void addSep() {
      if (metaParts.isEmpty) return;
      metaParts.add(
        TextSpan(
          text: '  •  ',
          style: TextStyle(
            fontSize: 12,
            color: RspFinalReqUi.secondaryTextOf(context),
          ),
        ),
      );
    }

    if (app.email.trim().isNotEmpty) {
      addSep();
      metaParts.add(
        TextSpan(
          text: app.email.trim(),
          style: TextStyle(
            fontSize: 12,
            color: RspFinalReqUi.secondaryTextOf(context),
          ),
        ),
      );
    }
    if (position.isNotEmpty) {
      addSep();
      metaParts.add(
        TextSpan(
          text: position,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: RspFinalReqUi.primaryTextOf(context).withValues(alpha: 0.85),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RspFinalReqUi.initialsAvatar(context, app.fullName, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      app.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: RspFinalReqUi.primaryTextOf(context),
                      ),
                    ),
                  ),
                  if (isNew) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: RspFinalReqUi.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: RspFinalReqUi.orange.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: RspFinalReqUi.orange,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (metaParts.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(children: metaParts),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (applied != null) ...[
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: RspFinalReqUi.accentOf(context),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Applied: ${RspFinalReqUi.formatDateShort(applied)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: RspFinalReqUi.primaryTextOf(context),
                    ),
                  ),
                  Text(
                    RspFinalReqUi.relativeApplied(applied),
                    style: TextStyle(
                      fontSize: 11,
                      color: RspFinalReqUi.secondaryTextOf(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(width: 10),
        RspFinalReqUi.statusBadge(label: statusLabel, color: statusColor),
        const SizedBox(width: 4),
        Icon(
          expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
          color: canCollapse || !expanded
              ? RspFinalReqUi.accentOf(context)
              : RspFinalReqUi.secondaryTextOf(context),
        ),
      ],
    );
  }

  Widget _buildExpandedBody({
    required RecruitmentApplication app,
    required bool saving,
    required bool allUploaded,
    required bool approved,
    required bool hired,
  }) {
    final uploadedCount = RspFinalRequirementDocKind.values
        .where((k) {
          final p = app.finalRequirementPath(k)?.trim();
          return p != null && p.isNotEmpty;
        })
        .length;
    final step3Enabled = app.orientationAttended == true || hired;
    final showStep8 = approved;

    final docsCol = _buildDocsColumn(
      app: app,
      uploadedCount: uploadedCount,
      allUploaded: allUploaded,
      approved: approved,
      hired: hired,
      saving: saving,
      forceDocRow: true,
    );

    if (!approved) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dashIsDark(context)
                  ? AppTheme.dashMutedSurfaceOf(context)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: RspFinalReqUi.hairlineOf(context)),
            ),
            child: _buildDocsColumn(
              app: app,
              uploadedCount: uploadedCount,
              allUploaded: allUploaded,
              approved: approved,
              hired: hired,
              saving: saving,
              forceDocRow: false,
            ),
          ),
        ],
      );
    }

    final orientCol = _buildOrientationAttendancePanel(app);
    final accountCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: RspFinalReqUi.readyBlue,
            ),
            const SizedBox(width: 6),
            Text(
              'Employee Account',
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: RspFinalReqUi.primaryTextOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RspEmployeeAccountSetupPanel(
          app: app,
          enabled: step3Enabled,
          busy: saving,
          compact: true,
          showApplicantStatus: false,
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

    Widget threeColShell(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashIsDark(context)
            ? AppTheme.dashMutedSurfaceOf(context)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RspFinalReqUi.hairlineOf(context)),
      ),
      child: child,
    );

    Widget divider() => Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: RspFinalReqUi.hairlineOf(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        threeColShell(
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 860) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: docsCol),
                    divider(),
                    Expanded(flex: 3, child: orientCol),
                    divider(),
                    Expanded(flex: 3, child: accountCol),
                  ],
                );
              }
              if (c.maxWidth >= 640) {
                return Column(
                  children: [
                    docsCol,
                    const SizedBox(height: 10),
                    Divider(height: 1, color: RspFinalReqUi.hairlineOf(context)),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: orientCol),
                        divider(),
                        Expanded(child: accountCol),
                      ],
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  docsCol,
                  const SizedBox(height: 10),
                  Divider(height: 1, color: RspFinalReqUi.hairlineOf(context)),
                  const SizedBox(height: 10),
                  orientCol,
                  const SizedBox(height: 10),
                  Divider(height: 1, color: RspFinalReqUi.hairlineOf(context)),
                  const SizedBox(height: 10),
                  accountCol,
                ],
              );
            },
          ),
        ),
        if (showStep8) ...[
          const SizedBox(height: 10),
          _buildStep8Footer(app: app, saving: saving, locked: !step3Enabled),
        ],
      ],
    );
  }

  Widget _buildDocsColumn({
    required RecruitmentApplication app,
    required int uploadedCount,
    required bool allUploaded,
    required bool approved,
    required bool hired,
    required bool saving,
    required bool forceDocRow,
  }) {
    final ac = RspFinalReqUi.accentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 16, color: ac),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Document Requirements',
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: RspFinalReqUi.primaryTextOf(context),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (allUploaded
                        ? RspFinalReqUi.success
                        : RspFinalReqUi.warning)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: (allUploaded
                          ? RspFinalReqUi.success
                          : RspFinalReqUi.warning)
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (allUploaded) ...[
                    const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: RspFinalReqUi.success,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    '$uploadedCount/3 Completed',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: allUploaded
                          ? RspFinalReqUi.success
                          : RspFinalReqUi.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final tiles = RspFinalRequirementDocKind.values
                .map((kind) => _docTile(app: app, kind: kind))
                .toList();
            if (forceDocRow || c.maxWidth >= 280) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(child: tiles[i]),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  tiles[i],
                ],
              ],
            );
          },
        ),
        if (!approved) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: saving || !allUploaded || approved
                  ? null
                  : () => _setApproved(app, true),
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_rounded, size: 16),
              label: const Text('Mark approved'),
              style: FilledButton.styleFrom(
                backgroundColor: ac,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ] else if (!hired)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: saving ? null : () => _setApproved(app, false),
              icon: const Icon(Icons.undo_rounded, size: 15),
              label: const Text('Clear approval'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _setHrAccountMonitoring(
    RecruitmentApplication app,
    bool done,
  ) async {
    setState(() => _savingIds.add(app.id));
    try {
      await RecruitmentRepo.instance.updateHrAccountSetupMonitoring(
        app.id,
        done,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done
                ? 'Applicants will see: account setup complete.'
                : 'Applicants will see: still setting up account.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    } finally {
      if (mounted) setState(() => _savingIds.remove(app.id));
    }
  }

  Widget _buildStep8Footer({
    required RecruitmentApplication app,
    required bool saving,
    required bool locked,
  }) {
    final monitoringDone = app.hrAccountSetupDone;
    final ac = RspFinalReqUi.accentOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RspFinalReqUi.hairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Applicant status (Step 8)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: RspFinalReqUi.primaryTextOf(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  monitoringDone
                      ? 'Shown to applicant: account setup complete.'
                      : 'Shown to applicant: still setting up account.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: RspFinalReqUi.secondaryTextOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: saving || locked,
            child: Opacity(
              opacity: saving || locked ? 0.45 : 1,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppTheme.dashMutedSurfaceOf(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: RspFinalReqUi.hairlineOf(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _step8Chip(
                        label: 'Not yet',
                        icon: Icons.schedule_rounded,
                        active: !monitoringDone,
                        accent: ac,
                        onTap: () {
                          if (saving || locked || !monitoringDone) return;
                          _setHrAccountMonitoring(app, false);
                        },
                      ),
                    ),
                    Expanded(
                      child: _step8Chip(
                        label: 'Done',
                        icon: Icons.check_rounded,
                        active: monitoringDone,
                        accent: ac,
                        onTap: () {
                          if (saving || locked || monitoringDone) return;
                          _setHrAccountMonitoring(app, true);
                        },
                      ),
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

  Widget _step8Chip({
    required String label,
    required IconData icon,
    required bool active,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: active
                ? Border.all(color: accent.withValues(alpha: 0.45))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active
                    ? accent
                    : RspFinalReqUi.secondaryTextOf(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? accent
                      : RspFinalReqUi.primaryTextOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrientationAttendancePanel(RecruitmentApplication app) {
    final saving = _savingIds.contains(app.id);
    final attended = app.orientationAttended;
    final selected = attended == null ? 0 : (attended ? 1 : 2);
    final scheduled = app.orientationAt;
    final ac = RspFinalReqUi.accentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event_available_outlined, size: 16, color: ac),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Orientation Attendance',
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: RspFinalReqUi.primaryTextOf(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          scheduled == null
              ? 'Schedule orientation in Scheduling, then record attendance.'
              : 'Scheduled: ${_formatScheduleDateTime(scheduled, context)}',
          style: TextStyle(
            fontSize: 11,
            height: 1.3,
            color: RspFinalReqUi.secondaryTextOf(context),
          ),
        ),
        const SizedBox(height: 10),
        IgnorePointer(
          ignoring: saving,
          child: Opacity(
            opacity: saving ? 0.45 : 1,
            child: Row(
              children: [
                for (final entry in [
                  (0, 'Pending', Icons.schedule_rounded),
                  (1, 'Attended', Icons.check_rounded),
                  (2, 'No Show', Icons.person_off_rounded),
                ]) ...[
                  if (entry.$1 > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _orientChip(
                      label: entry.$2,
                      icon: entry.$3,
                      active: selected == entry.$1,
                      accent: ac,
                      onTap: () {
                        if (saving) return;
                        final want = entry.$1 == 0 ? null : (entry.$1 == 1);
                        if (want == attended) return;
                        _setOrientationAttendance(app, want);
                      },
                    ),
                  ),
                ],
              ],
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
            fontSize: 11,
            color: RspFinalReqUi.secondaryTextOf(context),
          ),
        ),
      ],
    );
  }

  Widget _orientChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? accent : RspFinalReqUi.hairlineOf(context),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? accent
                    : RspFinalReqUi.secondaryTextOf(context),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? accent
                      : RspFinalReqUi.primaryTextOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rejectRequirement(
    RecruitmentApplication app,
    RspFinalRequirementDocKind kind,
  ) async {
    final hired = _isHired(app);
    if (hired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot reject requirements after the applicant is hired.',
          ),
        ),
      );
      return;
    }
    final path = app.finalRequirementPath(kind)?.trim();
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No uploaded file to reject.')),
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Reject ${_kindLabel(kind)}?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This removes the uploaded file. The applicant must re-submit '
                  '${_kindLabel(kind).toLowerCase()}.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppTheme.dashTextSecondaryOf(ctx),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason for applicant (optional)',
                    hintText:
                        'e.g. Unreadable scan — please upload a clearer PDF',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
              ),
              child: const Text('Reject & request resubmit'),
            ),
          ],
        );
      },
    );
    final reason = reasonCtrl.text;
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _savingIds.add(app.id));
    try {
      await RecruitmentRepo.instance.rejectFinalRequirement(
        app.id,
        kind,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_kindLabel(kind)} rejected. Applicant must re-upload.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    } finally {
      if (mounted) setState(() => _savingIds.remove(app.id));
    }
  }

  Widget _docTile({
    required RecruitmentApplication app,
    required RspFinalRequirementDocKind kind,
  }) {
    final path = app.finalRequirementPath(kind)?.trim();
    final name = app.finalRequirementDisplayName(kind)?.trim();
    final hasFile = path != null && path.isNotEmpty;
    final displayName = (name != null && name.isNotEmpty)
        ? name
        : (hasFile ? path.split('/').last : '');
    final rejectReason = app.finalRequirementRejectReason(kind)?.trim();
    final saving = _savingIds.contains(app.id);
    final canReject = hasFile && !_isHired(app) && !saving;
    final rejected =
        rejectReason != null && rejectReason.isNotEmpty && !hasFile;

    final statusColor = hasFile
        ? RspFinalReqUi.success
        : rejected
        ? RspFinalReqUi.error
        : RspFinalReqUi.warning;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: rejected
              ? RspFinalReqUi.error.withValues(alpha: 0.45)
              : RspFinalReqUi.hairlineOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFile
                    ? Icons.picture_as_pdf_rounded
                    : rejected
                    ? Icons.cancel_rounded
                    : Icons.pending_rounded,
                size: 15,
                color: statusColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _kindLabel(kind),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              Icon(
                hasFile
                    ? Icons.check_circle_rounded
                    : rejected
                    ? Icons.error_rounded
                    : Icons.schedule_rounded,
                size: 13,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hasFile) ...[
            RspAttachmentActions(path: path, fileName: displayName),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Reject',
                onPressed: canReject
                    ? () => _rejectRequirement(app, kind)
                    : null,
                icon: const Icon(Icons.close_rounded, size: 16),
                style: IconButton.styleFrom(
                  foregroundColor: RspFinalReqUi.error,
                  padding: const EdgeInsets.all(2),
                  minimumSize: const Size(26, 26),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ] else if (rejected) ...[
            Text(
              'Rejected — awaiting resubmit',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: RspFinalReqUi.error.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rejectReason,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                color: RspFinalReqUi.secondaryTextOf(context),
              ),
            ),
          ] else
            Text(
              'Not submitted',
              style: TextStyle(
                fontSize: 11,
                color: RspFinalReqUi.secondaryTextOf(context),
              ),
            ),
        ],
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
