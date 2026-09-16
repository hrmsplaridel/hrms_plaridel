import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';

/// One vacancy form entry (headline + education / experience / training).
class _VacancyFormItem {
  _VacancyFormItem()
    : headline = TextEditingController(),
      education = TextEditingController(),
      experience = TextEditingController(),
      training = TextEditingController(),
      closingDate = TextEditingController(),
      maxApplicants = TextEditingController();
  final TextEditingController headline;
  final TextEditingController education;
  final TextEditingController experience;
  final TextEditingController training;
  final TextEditingController closingDate;
  final TextEditingController maxApplicants;

  /// Display-only from GET. Never sent on save.
  int? applicationCount;
  bool? isClosedFromServer;

  void dispose() {
    headline.dispose();
    education.dispose();
    experience.dispose();
    training.dispose();
    closingDate.dispose();
    maxApplicants.dispose();
  }
}

/// RSP: Job Vacancies announcement form for the landing page.
class RspJobVacanciesSection extends StatefulWidget {
  const RspJobVacanciesSection({super.key});

  @override
  State<RspJobVacanciesSection> createState() => _RspJobVacanciesSectionState();
}

class _RspJobVacanciesSectionState extends State<RspJobVacanciesSection> {
  bool _loading = true;
  bool _hasVacancies = false;
  final List<_VacancyFormItem> _vacancies = [];

  /// Parallel to [_vacancies]: when false, only the header row is shown.
  final List<bool> _vacancyExpanded = [];
  bool _saving = false;
  bool _savingToggle = false;

  /// Fingerprint of vacancy entries last saved to the server (not including hiring toggle).
  String _savedVacanciesFingerprint = '';

  static const _green = Color(0xFF2E7D32);

  List<Map<String, String?>> _vacancyMapsFromForm() {
    return _vacancies.map((v) {
      return <String, String?>{
        'headline': v.headline.text.trim(),
        'education': v.education.text.trim(),
        'experience': v.experience.text.trim(),
        'training': v.training.text.trim(),
        'closing_date': v.closingDate.text.trim(),
        'max_applicants': v.maxApplicants.text.trim(),
      };
    }).toList();
  }

  String _fingerprintVacancyMaps(List<Map<String, String?>> maps) {
    return jsonEncode(maps);
  }

  bool get _vacanciesDirty =>
      !_loading &&
      _fingerprintVacancyMaps(_vacancyMapsFromForm()) !=
          _savedVacanciesFingerprint;

  Future<void> _onHasVacanciesChanged(bool value) async {
    if (_savingToggle) return;
    final previous = _hasVacancies;
    setState(() {
      _hasVacancies = value;
      _savingToggle = true;
    });
    try {
      await JobVacancyAnnouncementRepo.instance.updateHasVacancies(value);
      if (!mounted) return;
      final hasListedTitle = _vacancies.any(
        (v) => v.headline.text.trim().isNotEmpty,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? (hasListedTitle
                    ? 'Landing page is now open for hiring.'
                    : 'Hiring is on, but no job title is listed. Applicants cannot apply until you add a vacant position and save.')
                : 'Landing page now shows no vacancies.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _hasVacancies = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update hiring status. ${userFacingApiError(e)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  String _vacancyEntrySummary(_VacancyFormItem v) {
    final h = v.headline.text.trim();
    if (h.isNotEmpty) {
      return h.length > 52 ? '${h.substring(0, 52)}…' : h;
    }
    final parts = <String>[
      v.education.text.trim(),
      v.experience.text.trim(),
      v.training.text.trim(),
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      final joined = parts.join(' · ');
      return joined.length > 64 ? '${joined.substring(0, 64)}…' : joined;
    }
    final m = v.maxApplicants.text.trim();
    if (m.isNotEmpty) return 'Max applicants: $m';
    return 'No headline yet — expand to edit';
  }

  String _vacancyHeaderTitle(int index, _VacancyFormItem v) {
    final h = v.headline.text.trim();
    if (h.isNotEmpty) return h;
    return 'Position ${index + 1}';
  }

  bool _vacancyIsDraft(_VacancyFormItem v) => v.headline.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    JobVacancyAnnouncementRepo.instance.fetch().then((a) {
      if (!mounted) return;
      final List<_VacancyFormItem> next = [];
      if (a.vacancies.isNotEmpty) {
        for (final v in a.vacancies) {
          final item = _VacancyFormItem();
          item.headline.text = v.headline ?? '';
          item.education.text = v.education ?? '';
          item.experience.text = v.experience ?? '';
          item.training.text = v.training ?? '';
          item.closingDate.text = v.closingDate != null
              ? '${v.closingDate!.year.toString().padLeft(4, '0')}-${v.closingDate!.month.toString().padLeft(2, '0')}-${v.closingDate!.day.toString().padLeft(2, '0')}'
              : _autoCloseDate();
          if (item.education.text.isEmpty &&
              item.experience.text.isEmpty &&
              item.training.text.isEmpty) {
            final legacy = v.body?.trim();
            if (legacy != null && legacy.isNotEmpty) {
              item.education.text = legacy;
            }
          }
          item.maxApplicants.text = v.maxApplicants != null
              ? '${v.maxApplicants}'
              : '';
          item.applicationCount = v.applicationCount;
          item.isClosedFromServer = v.isClosed;
          next.add(item);
        }
      } else {
        final item = _VacancyFormItem();
        item.headline.text = a.headline ?? '';
        final legacy = a.body?.trim();
        if (legacy != null && legacy.isNotEmpty) {
          item.education.text = legacy;
        }
        item.closingDate.text = _autoCloseDate();
        next.add(item);
      }
      if (mounted) {
        _vacancies
          ..clear()
          ..addAll(next);
        setState(() {
          _vacancyExpanded
            ..clear()
            ..addAll(List<bool>.filled(_vacancies.length, true));
          _loading = false;
          _hasVacancies = a.hasVacancies;
          _savedVacanciesFingerprint = _fingerprintVacancyMaps(
            _vacancyMapsFromForm(),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    for (final v in _vacancies) {
      v.dispose();
    }
    super.dispose();
  }

  /// Returns "YYYY-MM-DD" for [n] days from today.
  static String _autoCloseDate([int days = 15]) {
    final d = DateTime.now().add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _addVacancy() {
    final item = _VacancyFormItem();
    item.closingDate.text = _autoCloseDate();
    setState(() {
      _vacancies.add(item);
      _vacancyExpanded.add(true);
    });
  }

  void _removeVacancy(int index) {
    if (_vacancies.length <= 1) return;
    setState(() {
      _vacancies[index].dispose();
      _vacancies.removeAt(index);
      if (index < _vacancyExpanded.length) {
        _vacancyExpanded.removeAt(index);
      }
    });
  }

  void _confirmDeleteVacancy(BuildContext context, int index) {
    if (_vacancies.length <= 1) return;
    final headline = _vacancies[index].headline.text.trim();
    final title = headline.isEmpty ? 'Position ${index + 1}' : headline;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vacancy?'),
        content: Text(
          'Remove "$title" from the list? Use this when the job hiring is done. You can add it again later if needed. Tap "Save vacancy entries" below to publish this change on the landing page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true && mounted) _removeVacancy(index);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final list = _vacancies.map((v) {
        final rawMax = v.maxApplicants.text.trim();
        int? maxParsed;
        if (rawMax.isNotEmpty) {
          maxParsed = int.tryParse(rawMax);
          if (maxParsed != null && maxParsed < 1) maxParsed = null;
        }
        final ed = v.education.text.trim();
        final ex = v.experience.text.trim();
        final tr = v.training.text.trim();
        final cdRaw = v.closingDate.text.trim();
        final cd = cdRaw.isNotEmpty ? DateTime.tryParse(cdRaw) : null;
        return JobVacancyItem(
          headline: v.headline.text.trim().isEmpty
              ? null
              : v.headline.text.trim(),
          body: null,
          education: ed.isEmpty ? null : ed,
          experience: ex.isEmpty ? null : ex,
          training: tr.isEmpty ? null : tr,
          closingDate: cd,
          maxApplicants: maxParsed,
        );
      }).toList();
      final a = JobVacancyAnnouncement(
        hasVacancies: _hasVacancies,
        headline: list.isNotEmpty ? list.first.headline : null,
        body: list.isNotEmpty ? list.first.body : null,
        vacancies: list,
      );
      await JobVacancyAnnouncementRepo.instance.update(a);
      if (mounted) {
        setState(() {
          _savedVacanciesFingerprint = _fingerprintVacancyMaps(
            _vacancyMapsFromForm(),
          );
        });
        final hasListedTitle = list.any(
          (v) => (v.headline ?? '').trim().isNotEmpty,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _hasVacancies && !hasListedTitle
                  ? 'Saved. Applicants still cannot apply until a job title is listed.'
                  : 'Vacancy entries saved. Landing page will show the updated positions.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDueDateLabel(String raw) {
    final s = raw.trim().isEmpty ? _autoCloseDate() : raw.trim();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    const months = <String>[
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  InputDecoration _vacancyInput(
    BuildContext context, {
    required String hint,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: hint,
      helperText: helperText,
      suffixIcon: suffixIcon,
      radius: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.dashTextPrimaryOf(context),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _helperText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.92),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageHeader(BuildContext context) {
    final panel = AppTheme.dashPanelOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.work_outline_rounded,
              color: AppTheme.dashIsDark(context)
                  ? AppTheme.primaryNavyLight
                  : AppTheme.primaryNavy,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Vacancies Announcement',
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage and publish job vacancies shown on the recruitment landing page.',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptingCard(BuildContext context, {required bool compact}) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final hiring = _hasVacancies;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Accepting Applications',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Allow applicants to view and apply for active vacancies.',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    final status = _statusChip(
      label: hiring ? 'Hiring' : 'Closed',
      color: hiring ? _green : AppTheme.dashTextSecondaryOf(context),
      icon: hiring
          ? Icons.check_circle_rounded
          : Icons.pause_circle_outline_rounded,
    );

    final toggle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_savingToggle)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Semantics(
          label: hiring
              ? 'Accepting applications is on'
              : 'Accepting applications is off',
          child: Switch(
            value: hiring,
            onChanged: _savingToggle ? null : _onHasVacanciesChanged,
            activeTrackColor: _green.withValues(alpha: 0.45),
            activeThumbColor: _green,
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 16,
        compact ? 14 : 14,
        compact ? 12 : 14,
        compact ? 14 : 14,
      ),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hiring
                          ? Icons.campaign_rounded
                          : Icons.pause_circle_outline_rounded,
                      color: hiring
                          ? AppTheme.primaryNavy
                          : AppTheme.dashTextSecondaryOf(context),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: titleBlock),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    status,
                    const Spacer(),
                    toggle,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  hiring
                      ? Icons.campaign_rounded
                      : Icons.pause_circle_outline_rounded,
                  color: hiring
                      ? AppTheme.primaryNavy
                      : AppTheme.dashTextSecondaryOf(context),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(child: titleBlock),
                const SizedBox(width: 12),
                status,
                const SizedBox(width: 8),
                toggle,
              ],
            ),
    );
  }

  Widget _toolbar(BuildContext context, {required bool compact}) {
    final count = _vacancies.length;
    final countLabel = count == 1 ? '1 vacancy' : '$count vacancies';
    final addBtn = FilledButton.icon(
      onPressed: _addVacancy,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text('Add Vacancy'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Job Vacancies',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          countLabel,
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: addBtn),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: title),
        addBtn,
      ],
    );
  }

  Widget _textArea(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      minLines: 2,
      maxLines: 8,
      decoration: _vacancyInput(context, hint: hint),
    );
  }

  Widget _dueDateField(BuildContext context, _VacancyFormItem v) {
    final hairline = AppTheme.dashHairlineOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Due Date'),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: AppTheme.dashInputFillOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dashInputBorderOf(context)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_rounded,
                size: 18,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatDueDateLabel(v.closingDate.text),
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  v.closingDate.text = _autoCloseDate();
                }),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.dashTextSecondaryOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        _helperText(
          context,
          'Automatically closes 15 days after the position is posted. The system will stop accepting applicants on this date.',
        ),
      ],
    );
  }

  Widget _vacancyFields(
    BuildContext context,
    _VacancyFormItem v, {
    required bool twoCol,
    bool threeCol = false,
  }) {
    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Headline'),
        TextField(
          controller: v.headline,
          onChanged: (_) => setState(() {}),
          maxLines: 1,
          decoration: _vacancyInput(
            context,
            hint: 'e.g. Now Hiring: Human Resource Assistant',
          ),
        ),
      ],
    );
    final education = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Education'),
        _textArea(
          context,
          controller: v.education,
          hint: 'e.g. Bachelor\'s degree in a relevant field',
        ),
      ],
    );
    final experience = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Experience'),
        _textArea(
          context,
          controller: v.experience,
          hint: 'e.g. 2 years relevant experience',
        ),
      ],
    );
    final training = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Training'),
        _textArea(
          context,
          controller: v.training,
          hint: 'e.g. 8 hours of relevant training or seminars',
        ),
      ],
    );
    final maxApplicants = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Max Applicants'),
        TextField(
          controller: v.maxApplicants,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          maxLines: 1,
          decoration: _vacancyInput(context, hint: 'e.g. 50'),
        ),
        _helperText(
          context,
          'Leave blank for no limit. Landing page slots use pipeline applicants only — hired, declined, failed exam, or failed final interview do not count.',
        ),
      ],
    );
    final due = _dueDateField(context, v);

    if (!twoCol) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headline,
          const SizedBox(height: 14),
          education,
          const SizedBox(height: 14),
          experience,
          const SizedBox(height: 14),
          training,
          const SizedBox(height: 14),
          due,
          const SizedBox(height: 14),
          maxApplicants,
        ],
      );
    }

    if (threeCol) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headline,
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: education),
              const SizedBox(width: 14),
              Expanded(child: experience),
              const SizedBox(width: 14),
              Expanded(child: training),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: due),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: maxApplicants),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headline,
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: education),
            const SizedBox(width: 14),
            Expanded(child: experience),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: training),
            const SizedBox(width: 14),
            Expanded(child: maxApplicants),
          ],
        ),
        const SizedBox(height: 14),
        due,
      ],
    );
  }

  Widget _vacancyCard(
    BuildContext context, {
    required int index,
    required _VacancyFormItem v,
    required bool expanded,
    required bool twoCol,
    required bool compact,
    bool threeCol = false,
  }) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final draft = _vacancyIsDraft(v);
    final title = _vacancyHeaderTitle(index, v);

    final maxText = v.maxApplicants.text.trim();
    final dueText = v.closingDate.text.trim().isEmpty
        ? _autoCloseDate()
        : v.closingDate.text.trim();
    final pipeline = v.applicationCount;

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                if (index < _vacancyExpanded.length) {
                  _vacancyExpanded[index] = !_vacancyExpanded[index];
                }
              }),
              child: Semantics(
                button: true,
                label: expanded
                    ? 'Collapse vacancy ${index + 1}'
                    : 'Expand vacancy ${index + 1}',
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 5,
                        color: draft
                            ? AppTheme.dashTextSecondaryOf(
                                context,
                              ).withValues(alpha: 0.35)
                            : AppTheme.primaryNavy,
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 12 : 14,
                            14,
                            8,
                            14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: AppTheme.dashIsDark(context)
                                        ? AppTheme.primaryNavyLight
                                        : AppTheme.primaryNavy,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppTheme.dashTextPrimaryOf(
                                          context,
                                        ),
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.15,
                                      ),
                                    ),
                                    if (compact) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _metaChip(
                                            context,
                                            icon: Icons.event_outlined,
                                            text: _formatDueDateLabel(dueText),
                                          ),
                                          _metaChip(
                                            context,
                                            icon: Icons.groups_outlined,
                                            text: maxText.isEmpty
                                                ? 'No limit'
                                                : 'Max $maxText',
                                          ),
                                        ],
                                      ),
                                    ] else if (!expanded && draft) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _vacancyEntrySummary(v),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppTheme.dashTextSecondaryOf(
                                            context,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      _metaChip(
                                        context,
                                        icon: Icons.event_outlined,
                                        text: _formatDueDateLabel(dueText),
                                      ),
                                      _metaChip(
                                        context,
                                        icon: Icons.groups_outlined,
                                        text: maxText.isEmpty
                                            ? 'No applicant limit'
                                            : 'Max $maxText',
                                      ),
                                      if (pipeline != null)
                                        _metaChip(
                                          context,
                                          icon: Icons.how_to_reg_outlined,
                                          text: pipeline == 1
                                              ? '1 in pipeline'
                                              : '$pipeline in pipeline',
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(width: 10),
                              _statusChip(
                                label: v.isClosedFromServer == true
                                    ? 'Closed'
                                    : (draft ? 'Draft' : 'Active'),
                                color: v.isClosedFromServer == true
                                    ? AppTheme.dashTextSecondaryOf(context)
                                    : (draft
                                          ? const Color(0xFF1565C0)
                                          : _green),
                                icon: v.isClosedFromServer == true
                                    ? Icons.event_busy_outlined
                                    : (draft
                                          ? Icons.edit_outlined
                                          : Icons.check_circle_outline_rounded),
                              ),
                              Icon(
                                expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: AppTheme.dashTextSecondaryOf(context),
                              ),
                              if (_vacancies.length > 1 && !compact)
                                IconButton(
                                  tooltip: 'Delete vacancy',
                                  onPressed: () =>
                                      _confirmDeleteVacancy(context, index),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 16,
                      0,
                      compact ? 12 : 16,
                      16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 1, color: hairline),
                        const SizedBox(height: 14),
                        _vacancyFields(
                          context,
                          v,
                          twoCol: twoCol,
                          threeCol: threeCol,
                        ),
                        if (_vacancies.length > 1) ...[
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _confirmDeleteVacancy(context, index),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Colors.red.shade700,
                              ),
                              label: Text(
                                'Delete Vacancy',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _saveBar(BuildContext context, {required bool compact}) {
    final canSave = !_saving && _vacanciesDirty;
    final button = FilledButton.icon(
      onPressed: canSave ? _save : null,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_rounded, size: 18),
      label: Text(
        _saving
            ? 'Saving changes…'
            : _vacanciesDirty
            ? 'Save Vacancy Changes'
            : 'No vacancy changes to save',
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        disabledBackgroundColor: AppTheme.dashTextSecondaryOf(
          context,
        ).withValues(alpha: 0.28),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
        elevation: 0,
        minimumSize: Size(compact ? double.infinity : 220, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_vacanciesDirty && !_saving)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Hiring on/off saves automatically. Use Save only after you change positions, add vacancies, or edit vacancy details.',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        compact
            ? button
            : Align(alignment: Alignment.centerRight, child: button),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final compact = w < 768;
        final twoCol = w >= 900;
        final threeCol = w >= 1200;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageHeader(context),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _acceptingCard(context, compact: compact),
              const SizedBox(height: 20),
              _toolbar(context, compact: compact),
              const SizedBox(height: 12),
              ...List.generate(_vacancies.length, (i) {
                final expanded = i < _vacancyExpanded.length
                    ? _vacancyExpanded[i]
                    : true;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _vacancyCard(
                    context,
                    index: i,
                    v: _vacancies[i],
                    expanded: expanded,
                    twoCol: twoCol,
                    threeCol: threeCol,
                    compact: compact,
                  ),
                );
              }),
              const SizedBox(height: 8),
              _saveBar(context, compact: compact),
            ],
          ],
        );
      },
    );
  }
}
