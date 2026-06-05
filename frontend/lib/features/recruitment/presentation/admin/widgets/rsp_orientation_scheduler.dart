import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

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
  bool _loading = true;
  final Set<String> _savingIds = {};
  final Set<String> _expandedIds = {};

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      if (!mounted) return;
      setState(() {
        _applications = apps
            .where((a) => a.finalRequirementsApproved)
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

  @override
  void initState() {
    super.initState();
    _load();
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

  String _formatSchedule(DateTime d, BuildContext context) {
    final local = d.toLocal();
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatFullDate(local)} · ${TimeOfDay.fromDateTime(local).format(context)}';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
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
    await _withSaveLock(app.id, () async {
      await RecruitmentRepo.instance.updateOrientationAt(app.id, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Orientation schedule cleared.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final filtered = _filtered;
    final accentNavy = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Text(
            'Schedule for Orientation',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Applicants listed here already complied with final requirements. '
            'Set their orientation date and time.',
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
        ],
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline),
                  ),
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All positions'),
                  ),
                  ...(_positionFilterOptions.toList()..sort())
                      .map((p) => DropdownMenuItem(value: p, child: Text(p))),
                ],
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _selectedPositionFilter = v),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _scheduleFilter,
                decoration: InputDecoration(
                  labelText: 'Schedule status',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('Not scheduled'),
                  ),
                  DropdownMenuItem(
                    value: 'scheduled',
                    child: Text('Scheduled'),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _scheduleFilter = v),
              ),
            ),
            OutlinedButton.icon(
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
            ),
            TextButton.icon(
              onPressed: _loading
                  ? null
                  : () => setState(() => _selectedAppliedDate = DateTime.now()),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Today'),
            ),
            TextButton.icon(
              onPressed: _loading ||
                      (_selectedPositionFilter == null &&
                          _selectedAppliedDate == null &&
                          _scheduleFilter == null)
                  ? null
                  : () => setState(() {
                      _selectedPositionFilter = null;
                      _selectedAppliedDate = null;
                      _scheduleFilter = null;
                    }),
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear filters'),
            ),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
              ),
            ),
            Text(
              '${filtered.length} shown',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_applications.isEmpty)
          _emptyBox(
            context,
            'No applicants with approved final requirements yet. '
            'Approve requirements in Final Requirements first.',
          )
        else if (filtered.isEmpty)
          _emptyBox(
            context,
            'No applicants match your filters. Try clearing filters or refresh.',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) => _buildCard(filtered[i], accentNavy),
          ),
      ],
    );
  }

  Widget _emptyBox(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        text,
        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
      ),
    );
  }

  Widget _buildCard(RecruitmentApplication app, Color accentNavy) {
    final busy = _savingIds.contains(app.id);
    final scheduled = app.orientationAt;
    final expanded = _expandedIds.contains(app.id) || scheduled == null;

    if (!expanded) {
      return Material(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expandedIds.add(app.id)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatSchedule(scheduled!, context),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.dashTextSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
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
                    if (app.positionAppliedFor?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Position: ${app.positionAppliedFor!.trim()}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: accentNavy,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (scheduled != null)
                TextButton.icon(
                  onPressed: () => setState(() => _expandedIds.remove(app.id)),
                  icon: const Icon(Icons.unfold_less_rounded, size: 18),
                  label: const Text('Show less'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.dashMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scheduled == null ? 'No date set' : _formatSchedule(scheduled, context),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Applicants see this orientation schedule when they refresh Step 8.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.dashTextSecondaryOf(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : () => _pickDateTime(app),
                      icon: const Icon(Icons.event_rounded, size: 20),
                      label: Text(
                        scheduled == null ? 'Set date & time' : 'Change schedule',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accentNavy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (scheduled != null)
                      TextButton.icon(
                        onPressed: busy ? null : () => _clearSchedule(app),
                        icon: const Icon(Icons.event_busy_rounded, size: 20),
                        label: const Text('Clear'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
