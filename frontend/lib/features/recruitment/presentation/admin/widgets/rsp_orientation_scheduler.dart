import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_scheduling_ui.dart';

/// Admin: schedule orientation for applicants who complied with final requirements.
class RspOrientationScheduler extends StatefulWidget {
  const RspOrientationScheduler({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<RspOrientationScheduler> createState() =>
      _RspOrientationSchedulerState();
}

class _RspOrientationSchedulerState extends State<RspOrientationScheduler> {
  List<RecruitmentApplication> _applications = [];
  String? _selectedPositionFilter;
  DateTime? _selectedAppliedDate;
  String? _scheduleFilter; // all | scheduled | pending
  bool _latestFirst = true;
  bool _loading = true;
  final Set<String> _savingIds = {};
  final Set<String> _expandedIds = {};
  final Set<String> _collapsedIds = {};

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      if (!mounted) return;
      setState(() {
        _applications = apps.where((a) => a.finalRequirementsApproved).toList()
          ..sort(_compareBySchedulingActivity);
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Sort key = latest relevant orientation scheduling activity. Falls back
  /// to the application/record timestamp when no schedule has been set yet.
  DateTime? _schedulingActivityKey(RecruitmentApplication a) =>
      a.orientationAt ?? a.createdAt ?? a.updatedAt;

  int _compareBySchedulingActivity(
    RecruitmentApplication a,
    RecruitmentApplication b,
  ) {
    final ad = _schedulingActivityKey(a);
    final bd = _schedulingActivityKey(b);
    if (ad == null && bd == null) {
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    }
    if (ad == null) return 1;
    if (bd == null) return -1;
    return _latestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
  }

  void _resort() {
    setState(() {
      _applications = [..._applications]..sort(_compareBySchedulingActivity);
    });
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

  bool get _hasActiveFilters =>
      _selectedPositionFilter != null ||
      _selectedAppliedDate != null ||
      _scheduleFilter != null;

  List<RecruitmentApplication> get _filtered {
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
      if (_scheduleFilter == 'scheduled' && a.orientationAt == null) {
        return false;
      }
      if (_scheduleFilter == 'pending' && a.orientationAt != null) {
        return false;
      }
      return true;
    }).toList();
  }

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

  Future<void> _withSaveLock(
    String applicationId,
    Future<void> Function() fn,
  ) async {
    setState(() => _savingIds.add(applicationId));
    try {
      await fn();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingIds.remove(applicationId));
    }
  }

  Future<void> _pickDateTime(RecruitmentApplication app) async {
    final now = DateTime.now();
    final initial =
        app.orientationAt?.toLocal() ?? now.add(const Duration(days: 3));
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Orientation date',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Orientation time',
    );
    if (time == null || !mounted) return;
    final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateOrientationAt(app.id, dt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Orientation schedule saved.')),
        );
      }
    });
  }

  Future<void> _clearSchedule(RecruitmentApplication app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear orientation schedule?'),
        content: Text(
          'This removes the date and time for ${app.fullName}. '
          'They will no longer see a schedule on Step 8.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: RspSchedulingUi.accentOf(ctx),
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateOrientationAt(app.id, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Orientation schedule cleared.')),
        );
      }
    });
  }

  Widget _toolbar(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final accent = RspSchedulingUi.accentOf(context);
    final filteredCount = _filtered.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.dashSurfaceCard(context, radius: 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            height: RspSchedulingUi.controlHeight,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedPositionFilter,
              isExpanded: true,
              decoration: RspSchedulingUi.filterDecoration(
                context,
                label: 'Position',
                prefixIcon: const Icon(Icons.work_outline_rounded, size: 18),
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(
                  value: null,
                  child: RspSchedulingUi.ddText('All positions'),
                ),
                ...(_positionFilterOptions.toList()..sort()).map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: RspSchedulingUi.ddText(p),
                  ),
                ),
              ],
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _selectedPositionFilter = v),
            ),
          ),
          SizedBox(
            width: 190,
            height: RspSchedulingUi.controlHeight,
            child: DropdownButtonFormField<String>(
              initialValue: _scheduleFilter,
              isExpanded: true,
              decoration: RspSchedulingUi.filterDecoration(
                context,
                label: 'Schedule status',
                prefixIcon: const Icon(Icons.event_note_outlined, size: 18),
              ),
              items: [
                DropdownMenuItem(value: null, child: RspSchedulingUi.ddText('All')),
                DropdownMenuItem(
                  value: 'pending',
                  child: RspSchedulingUi.ddText('Not scheduled'),
                ),
                DropdownMenuItem(
                  value: 'scheduled',
                  child: RspSchedulingUi.ddText('Scheduled'),
                ),
              ],
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _scheduleFilter = v),
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: OutlinedButton.icon(
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
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    RspSchedulingUi.inputRadius,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: TextButton.icon(
              onPressed: _loading
                  ? null
                  : () =>
                      setState(() => _selectedAppliedDate = DateTime.now()),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Today'),
            ),
          ),
          RspSchedulingUi.sortDropdown(
            context: context,
            latestFirst: _latestFirst,
            enabled: !_loading,
            onChanged: (v) {
              setState(() => _latestFirst = v);
              _resort();
            },
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: TextButton.icon(
              onPressed: (_loading || !_hasActiveFilters)
                  ? null
                  : () => setState(() {
                      _selectedPositionFilter = null;
                      _selectedAppliedDate = null;
                      _scheduleFilter = null;
                    }),
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ),
          SizedBox(
            height: RspSchedulingUi.controlHeight,
            child: FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    RspSchedulingUi.inputRadius,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$filteredCount shown',
              style: TextStyle(
                fontFamily: 'NotoSans',
                color: AppTheme.dashTextSecondaryOf(context),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final accent = RspSchedulingUi.accentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_rounded, size: 24, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orientation Scheduling',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppTheme.dashTextPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Applicants listed here already complied with final requirements.',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _toolbar(context),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_applications.isEmpty)
          RspSchedulingUi.emptyState(
            context,
            icon: Icons.school_outlined,
            title: 'No eligible applicants yet',
            message:
                'No applicants with approved final requirements yet. Approve requirements in Final Requirements first.',
          )
        else if (filtered.isEmpty)
          RspSchedulingUi.emptyState(
            context,
            icon: Icons.filter_alt_off_rounded,
            title: 'No applicants found',
            message: 'Try adjusting your filters or refresh the list.',
            onClearFilters: _hasActiveFilters
                ? () => setState(() {
                    _selectedPositionFilter = null;
                    _selectedAppliedDate = null;
                    _scheduleFilter = null;
                  })
                : null,
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _buildCard(filtered[i], accent),
          ),
      ],
    );
  }

  Widget _collapsedCard(RecruitmentApplication app, Color accent) {
    final hairline = AppTheme.dashHairlineOf(context);
    final scheduled = app.orientationAt;
    final position = (app.positionAppliedFor ?? '').trim();
    final applicantNo = (app.applicantNumber ?? '').trim();

    return Container(
      decoration: RspSchedulingUi.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() {
            _expandedIds.add(app.id);
            _collapsedIds.remove(app.id);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final infoColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.fullName,
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.1,
                        color: AppTheme.dashTextPrimaryOf(context),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        if (applicantNo.isNotEmpty)
                          Text(
                            applicantNo,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        Text(
                          app.email,
                          style: TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: 12,
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        position,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.dashTextSecondaryOf(
                            context,
                          ).withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                );

                final scheduleBlock = scheduled == null
                    ? null
                    : RspSchedulingUi.dateTimeBlock(context, scheduled);

                final trailing = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RspSchedulingUi.statusBadge(
                      label: scheduled == null ? 'Not scheduled' : 'Scheduled',
                      icon: scheduled == null
                          ? Icons.schedule_rounded
                          : Icons.event_available_rounded,
                      fg: scheduled == null
                          ? AppTheme.dashTextSecondaryOf(context)
                          : accent,
                      bg: scheduled == null
                          ? AppTheme.dashMutedSurfaceOf(context)
                          : accent.withValues(alpha: 0.1),
                      border: scheduled == null
                          ? hairline
                          : accent.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.dashMutedSurfaceOf(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: hairline),
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                );

                if (compact) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RspSchedulingUi.initialsAvatar(context, app.fullName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            infoColumn,
                            if (scheduleBlock != null) ...[
                              const SizedBox(height: 8),
                              scheduleBlock,
                            ],
                            const SizedBox(height: 8),
                            trailing,
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RspSchedulingUi.initialsAvatar(context, app.fullName),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: infoColumn),
                    if (scheduleBlock != null)
                      Expanded(flex: 2, child: scheduleBlock)
                    else
                      const Spacer(flex: 2),
                    trailing,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(RecruitmentApplication app, Color accent) {
    final busy = _savingIds.contains(app.id);
    final scheduled = app.orientationAt;
    // Applicants without a schedule yet stay expanded by default so the
    // admin sees the call-to-action immediately; admins can still collapse.
    final expanded =
        !_collapsedIds.contains(app.id) &&
        (_expandedIds.contains(app.id) || scheduled == null);
    final hairline = AppTheme.dashHairlineOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final position = (app.positionAppliedFor ?? '').trim();
    final applicantNo = (app.applicantNumber ?? '').trim();

    if (!expanded) {
      return _collapsedCard(app, accent);
    }

    return Container(
      decoration: RspSchedulingUi.cardDecoration(context, highlighted: true),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RspSchedulingUi.initialsAvatar(context, app.fullName, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        app.fullName,
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.2,
                          color: AppTheme.dashTextPrimaryOf(context),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (applicantNo.isNotEmpty)
                            Text(
                              applicantNo,
                              style: TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          Text(
                            app.email,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 12.5,
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (position.isNotEmpty)
                            Text(
                              position,
                              style: TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: accent.withValues(alpha: 0.9),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RspSchedulingUi.statusBadge(
                        label: scheduled == null ? 'Not scheduled' : 'Scheduled',
                        icon: scheduled == null
                            ? Icons.schedule_rounded
                            : Icons.event_available_rounded,
                        fg: scheduled == null
                            ? AppTheme.dashTextSecondaryOf(context)
                            : accent,
                        bg: scheduled == null
                            ? AppTheme.dashMutedSurfaceOf(context)
                            : accent.withValues(alpha: 0.1),
                        border: scheduled == null
                            ? hairline
                            : accent.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _expandedIds.remove(app.id);
                    _collapsedIds.add(app.id);
                  }),
                  icon: const Icon(Icons.unfold_less_rounded, size: 18),
                  label: const Text('Collapse'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: hairline),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: muted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Orientation Schedule',
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: AppTheme.dashTextPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.dashPanelOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: hairline),
                    ),
                    child: scheduled == null
                        ? Row(
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 18,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'No orientation schedule has been set.',
                                  style: TextStyle(
                                    fontFamily: 'NotoSans',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.dashTextSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Icon(
                                Icons.event_available_rounded,
                                size: 18,
                                color: accent,
                              ),
                              const SizedBox(width: 10),
                              RspSchedulingUi.dateTimeBlock(context, scheduled),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: busy ? null : () => _pickDateTime(app),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                scheduled == null
                                    ? Icons.event_rounded
                                    : Icons.edit_calendar_rounded,
                                size: 17,
                              ),
                        label: Text(
                          scheduled == null
                              ? 'Set date & time'
                              : 'Change schedule',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      if (scheduled != null)
                        TextButton.icon(
                          onPressed: busy ? null : () => _clearSchedule(app),
                          icon: const Icon(Icons.event_busy_rounded, size: 17),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(foregroundColor: accent),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
