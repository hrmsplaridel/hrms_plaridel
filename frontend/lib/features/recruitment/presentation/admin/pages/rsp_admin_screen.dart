import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ignore: avoid_web_libraries_in_flutter
// ignore: avoid_web_libraries_in_flutter
import 'package:url_launcher/url_launcher.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/models/rsp_screening_scores.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/shared/widgets/read_only_saved_entry_dialog.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_form_header_footer.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_saved_records_browser.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_bei_grading_dialog.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_exam_editor_ui.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/rsp_scheduling_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/rsp_final_requirements_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/computation_of_points_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/work_experience_sheet_section.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_applications_report_export.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_generate_report_dialog.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_applications_report_preview_screen.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_attachment_actions.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_admin_hub.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';

/// RSP module: hub with buttons for each RSP feature (Job Vacancies, Applications, Exam Results).
class RspAdminContent extends StatefulWidget {
  const RspAdminContent({super.key, this.onOpenCreateAccount});

  /// Switches the admin shell to **Create Account** (sidebar) so the hire form opens.
  final VoidCallback? onOpenCreateAccount;

  @override
  State<RspAdminContent> createState() => _RspAdminContentState();
}

class _RspAdminContentState extends State<RspAdminContent> {
  /// 0 = menu, 1 = Job Vacancies, 2 = Applications, 16 = Exam Results, 15 = Scheduling.
  int _rspSectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_rspSectionIndex != 0 &&
                  _rspSectionIndex != 20 &&
                  _rspSectionIndex != 21) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _rspSectionIndex = 0),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Back to RSP'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_rspSectionIndex == 0)
                RspAdminHub(
                  onOpenSection: (index) =>
                      setState(() => _rspSectionIndex = index),
                )
              else if (_rspSectionIndex == 1)
                const _RspJobVacanciesForm()
              else if (_rspSectionIndex == 2)
                const _RspApplicationsMonitor(
                  view: _RspMonitorView.applications,
                )
              else if (_rspSectionIndex == 16)
                const _RspApplicationsMonitor(view: _RspMonitorView.examResults)
              else if (_rspSectionIndex == 20)
                _RspExamsSection(
                  onBackToRsp: () => setState(() => _rspSectionIndex = 0),
                )
              else if (_rspSectionIndex == 21)
                _RspFormsSection(
                  onBackToRsp: () => setState(() => _rspSectionIndex = 0),
                )
              else if (_rspSectionIndex == 15)
                const RspSchedulingSection()
              else if (_rspSectionIndex == 19)
                RspFinalRequirementsSection(
                  onGoToCreateAccount: widget.onOpenCreateAccount,
                )
              else
                const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }
}

class _RspExamPickerItem {
  const _RspExamPickerItem({
    required this.examKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.format,
    this.isCustom = false,
    this.customId,
    this.isOpenEnded = false,
  });

  final String examKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final String format;
  final bool isCustom;
  final String? customId;
  final bool isOpenEnded;
}

const _builtInExamPickerItems = <_RspExamPickerItem>[
  _RspExamPickerItem(
    examKey: 'bei',
    title: 'BEI / Exam Questions',
    subtitle:
        'View and edit the 8 Behavioral Event Interview questions applicants answer.',
    icon: Icons.psychology_alt_rounded,
    format: 'Open-ended',
    isOpenEnded: true,
  ),
  _RspExamPickerItem(
    examKey: 'general',
    title: 'General Exam (LGU-Plaridel)',
    subtitle:
        'View and edit the General Exam multiple-choice questions for applicants.',
    icon: Icons.assignment_turned_in_rounded,
    format: 'Multiple choice',
  ),
  _RspExamPickerItem(
    examKey: 'math',
    title: 'Mathematics Exam',
    subtitle: 'View and edit the Mathematics exam questions for applicants.',
    icon: Icons.calculate_rounded,
    format: 'Multiple choice',
  ),
  _RspExamPickerItem(
    examKey: 'general_info',
    title: 'General Information Exam',
    subtitle:
        'View and edit the General Information exam questions for applicants.',
    icon: Icons.info_outline_rounded,
    format: 'Multiple choice',
  ),
];

/// RSP: "Exams" hub — pick which exam to view/edit (BEI, General, Math, General Info).
class _RspExamsSection extends StatefulWidget {
  const _RspExamsSection({required this.onBackToRsp});

  /// Called when the back button is pressed at the picker level (top of this section).
  final VoidCallback onBackToRsp;

  @override
  State<_RspExamsSection> createState() => _RspExamsSectionState();
}

class _RspExamsSectionState extends State<_RspExamsSection> {
  _RspExamPickerItem? _selected;
  List<CustomRspExam> _customExams = const [];
  Set<String> _hiddenBuiltin = {};
  bool _loadingCustom = true;

  List<_RspExamPickerItem> get _allItems {
    final extra = <_RspExamPickerItem>[];
    for (var i = 0; i < _customExams.length; i++) {
      final exam = _customExams[i];
      extra.add(
        _RspExamPickerItem(
          examKey: exam.examType,
          title: exam.name,
          subtitle: exam.isOpenEnded
              ? 'Open-ended exam. View and edit the questions applicants answer.'
              : 'Multiple-choice exam. View and edit questions, options, and the correct answer.',
          icon: exam.isOpenEnded
              ? Icons.short_text_rounded
              : Icons.checklist_rounded,
          format: exam.isOpenEnded ? 'Open-ended' : 'Multiple choice',
          isCustom: true,
          customId: exam.id,
          isOpenEnded: exam.isOpenEnded,
        ),
      );
    }
    return [
      ..._builtInExamPickerItems.where(
        (i) => !_hiddenBuiltin.contains(i.examKey),
      ),
      ...extra,
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadCustomExams();
  }

  Future<void> _loadCustomExams() async {
    setState(() => _loadingCustom = true);
    final catalog = await RecruitmentRepo.instance.loadExamCatalog();
    if (!mounted) return;
    setState(() {
      _customExams = catalog.exams;
      _hiddenBuiltin = catalog.hiddenBuiltin;
      _loadingCustom = false;
    });
  }

  Widget _buildSelectedExam(_RspExamPickerItem item) {
    switch (item.examKey) {
      case 'bei':
        return const _RspBeiQuestionsEditor();
      case 'general':
        return const _RspGeneralExamEditor();
      case 'math':
        return const _RspMathExamEditor();
      case 'general_info':
        return const _RspGeneralInfoExamEditor();
      default:
        if (item.isOpenEnded) {
          return _RspCustomOpenEndedExamEditor(
            examKey: item.examKey,
            title: item.title,
          );
        }
        return _RspCustomMcqExamEditor(
          examKey: item.examKey,
          title: item.title,
        );
    }
  }

  Widget _buildBreadcrumb() {
    final navy = AppTheme.primaryNavy;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final selectedItem = _selected;
    return Row(
      children: [
        TextButton.icon(
          onPressed: selectedItem == null
              ? widget.onBackToRsp
              : () => setState(() => _selected = null),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          label: const Text('Back'),
          style: TextButton.styleFrom(foregroundColor: navy),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
        const SizedBox(width: 2),
        Text(
          'Exams',
          style: TextStyle(
            color: selectedItem == null ? navy : secondary,
            fontSize: 13,
            fontWeight: selectedItem == null
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        if (selectedItem != null) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              selectedItem.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openCreateExamDialog() async {
    final created = await showDialog<CustomRspExam>(
      context: context,
      builder: (ctx) => const _CreateCustomExamDialog(),
    );
    if (created == null || !mounted) return;
    await _loadCustomExams();
    if (!mounted) return;
    final match = _allItems.where((i) => i.customId == created.id);
    setState(() => _selected = match.isEmpty ? null : match.first);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created "${created.name}". Add questions, then save.'),
      ),
    );
  }

  Future<void> _deleteExam(_RspExamPickerItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete exam?'),
        content: Text(
          'This will remove "${item.title}" from Exams and delete its questions. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (item.isCustom) {
        final id = item.customId;
        if (id == null) return;
        await RecruitmentRepo.instance.deleteCustomExam(id);
      } else {
        await RecruitmentRepo.instance.hideBuiltinExam(item.examKey);
      }
      if (!mounted) return;
      if (_selected?.examKey == item.examKey) {
        setState(() => _selected = null);
      }
      await _loadCustomExams();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted "${item.title}".')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    }
  }

  Widget _examGrid(List<_RspExamPickerItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        Widget row(_RspExamPickerItem item) => _RspExamPickerRow(
          item: item,
          onTap: () => setState(() => _selected = item),
          onDelete: () => _deleteExam(item),
        );
        if (columns == 1) {
          return Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: row(item),
                ),
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: row(item),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 12),
          _buildSelectedExam(_selected!),
        ],
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final items = _allItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBreadcrumb(),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(isNarrow ? 20 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.dashIsDark(context)
                  ? [const Color(0xFF252D3D), const Color(0xFF1E2430)]
                  : [
                      const Color(0xFFFFF8F3),
                      Colors.white,
                      const Color(0xFFF5F8FF),
                    ],
            ),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy.withValues(alpha: 0.16),
                      AppTheme.letterheadNavy.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.14),
                  ),
                ),
                child: const Icon(
                  Icons.quiz_rounded,
                  color: AppTheme.primaryNavy,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exams',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose which exam you want to view or edit, or create a new exam.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    if (isNarrow) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _openCreateExamDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create exam'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _openCreateExamDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create exam'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_loadingCustom)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No exams yet. Create an exam to get started.',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 13.5,
                ),
              ),
            ),
          )
        else
          _examGrid(items),
      ],
    );
  }
}

const _builtInFormPickerItems = <_RspExamPickerItem>[
  _RspExamPickerItem(
    examKey: 'bi',
    title: 'Background Investigation (BI Form)',
    subtitle:
        'Record BI evaluations: applicant, respondent, and competency ratings.',
    icon: Icons.verified_user_rounded,
    format: 'Investigation form',
  ),
  _RspExamPickerItem(
    examKey: 'applicants_profile',
    title: 'Applicants Profile',
    subtitle:
        'Job vacancy details and list of applicants (name, course, address, sex, age, civil status).',
    icon: Icons.people_alt_rounded,
    format: 'Profile form',
  ),
  _RspExamPickerItem(
    examKey: 'selection_lineup',
    title: 'Selection Line-Up',
    subtitle:
        'Date, agency/office, vacant position, item no., and applicants table.',
    icon: Icons.format_list_numbered_rounded,
    format: 'Line-up form',
  ),
  _RspExamPickerItem(
    examKey: 'computation_of_points',
    title: 'Computation of Points',
    subtitle:
        'Personnel Selection Board scoring: education, eligibility, experience, training, and ranking.',
    icon: Icons.calculate_rounded,
    format: 'Scoring form',
  ),
  _RspExamPickerItem(
    examKey: 'work_experience',
    title: 'Work Experience Sheet',
    subtitle:
        'Position, department, minimum standards, last work description, and applicant signature.',
    icon: Icons.work_history_rounded,
    format: 'Experience form',
  ),
  _RspExamPickerItem(
    examKey: 'turn_around_time',
    title: 'Turn Around Time',
    subtitle:
        'Position, office, dates, and applicant tracking through hiring milestones.',
    icon: Icons.schedule_rounded,
    format: 'Tracking form',
  ),
];

/// RSP: "Forms" hub — pick which form to view/edit.
class _RspFormsSection extends StatefulWidget {
  const _RspFormsSection({required this.onBackToRsp});

  final VoidCallback onBackToRsp;

  @override
  State<_RspFormsSection> createState() => _RspFormsSectionState();
}

class _RspFormsSectionState extends State<_RspFormsSection> {
  _RspExamPickerItem? _selected;

  Widget _buildSelectedForm(_RspExamPickerItem item) {
    switch (item.examKey) {
      case 'bi':
        return const _RspBiFormSection();
      case 'applicants_profile':
        return const _RspApplicantsProfileSection();
      case 'selection_lineup':
        return const _RspSelectionLineupSection();
      case 'computation_of_points':
        return const RspComputationOfPointsSection();
      case 'work_experience':
        return const RspWorkExperienceSheetSection();
      case 'turn_around_time':
        return const _RspTurnAroundTimeSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBreadcrumb() {
    final navy = AppTheme.primaryNavy;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final selectedItem = _selected;
    return Row(
      children: [
        TextButton.icon(
          onPressed: selectedItem == null
              ? widget.onBackToRsp
              : () => setState(() => _selected = null),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          label: const Text('Back'),
          style: TextButton.styleFrom(foregroundColor: navy),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
        const SizedBox(width: 2),
        Text(
          'Forms',
          style: TextStyle(
            color: selectedItem == null ? navy : secondary,
            fontSize: 13,
            fontWeight: selectedItem == null
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        if (selectedItem != null) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              selectedItem.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _formGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        Widget row(_RspExamPickerItem item) => _RspExamPickerRow(
          item: item,
          onTap: () => setState(() => _selected = item),
        );
        if (columns == 1) {
          return Column(
            children: [
              for (final item in _builtInFormPickerItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: row(item),
                ),
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in _builtInFormPickerItems)
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: row(item),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 12),
          _buildSelectedForm(_selected!),
        ],
      );
    }

    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBreadcrumb(),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.all(isNarrow ? 20 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.dashIsDark(context)
                  ? [const Color(0xFF252D3D), const Color(0xFF1E2430)]
                  : [
                      const Color(0xFFFFF8F3),
                      Colors.white,
                      const Color(0xFFF5F8FF),
                    ],
            ),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy.withValues(alpha: 0.16),
                      AppTheme.letterheadNavy.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.14),
                  ),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppTheme.primaryNavy,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Forms',
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose which form you want to view or edit.',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _formGrid(),
      ],
    );
  }
}

/// Color-coded exam picker row (distinct from the card-grid hub layout).
class _RspExamPickerRow extends StatefulWidget {
  const _RspExamPickerRow({
    required this.item,
    required this.onTap,
    this.onDelete,
  });

  final _RspExamPickerItem item;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  State<_RspExamPickerRow> createState() => _RspExamPickerRowState();
}

class _RspExamPickerRowState extends State<_RspExamPickerRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.primaryNavy;
    final dark = AppTheme.dashIsDark(context);
    final baseBg = AppTheme.dashPanelOf(context);
    final baseBorder = AppTheme.dashHairlineOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovering ? -2 : 0, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _hovering
              ? color.withValues(alpha: dark ? 0.1 : 0.05)
              : baseBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering ? color.withValues(alpha: 0.5) : baseBorder,
            width: _hovering ? 1.4 : 1,
          ),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: dark ? 0.22 : 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: dark ? 0.28 : 0.14),
                              color.withValues(alpha: dark ? 0.16 : 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Icon(widget.item.icon, size: 22, color: color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.title,
                              style: TextStyle(
                                color: AppTheme.dashTextPrimaryOf(context),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.item.subtitle,
                              style: TextStyle(
                                color: AppTheme.dashTextSecondaryOf(context),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(
                                  alpha: dark ? 0.16 : 0.1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.item.format,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _hovering
                              ? color
                              : color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: _hovering ? Colors.white : color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Delete exam',
                onPressed: widget.onDelete,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFFC62828),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateCustomExamDialog extends StatefulWidget {
  const _CreateCustomExamDialog();

  @override
  State<_CreateCustomExamDialog> createState() =>
      _CreateCustomExamDialogState();
}

class _CreateCustomExamDialogState extends State<_CreateCustomExamDialog> {
  final _nameController = TextEditingController();
  String _format = 'open_ended';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name for the exam.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final exam = await RecruitmentRepo.instance.createCustomExam(
        name: name,
        format: _format,
      );
      if (!mounted) return;
      Navigator.of(context).pop(exam);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create exam'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: AppTheme.dashFieldTextStyle(context),
              decoration: AppTheme.dashInputDecoration(
                context,
                labelText: 'Exam name',
                hintText: 'e.g. Technical Skills Exam',
              ),
              onSubmitted: (_) => _saving ? null : _submit(),
            ),
            const SizedBox(height: 18),
            Text(
              'Question type',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'open_ended',
                  label: Text('Open-ended'),
                  icon: Icon(Icons.short_text_rounded, size: 18),
                ),
                ButtonSegment(
                  value: 'multiple_choice',
                  label: Text('Multiple choice'),
                  icon: Icon(Icons.checklist_rounded, size: 18),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (s) => setState(() => _format = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _RspCustomOpenEndedExamEditor extends StatefulWidget {
  const _RspCustomOpenEndedExamEditor({
    required this.examKey,
    required this.title,
  });

  final String examKey;
  final String title;

  @override
  State<_RspCustomOpenEndedExamEditor> createState() =>
      _RspCustomOpenEndedExamEditorState();
}

class _RspCustomOpenEndedExamEditorState
    extends State<_RspCustomOpenEndedExamEditor> {
  List<TextEditingController> _controllers = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestions(
        widget.examKey,
      );
      if (!mounted) return;
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = list.isEmpty
          ? [TextEditingController()]
          : list.map((q) => TextEditingController(text: q)).toList();
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = [TextEditingController()];
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final questions = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one question.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestions(
        widget.examKey,
        questions,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} questions saved.')),
      );
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RspExamPageHeader(
          icon: Icons.short_text_rounded,
          title: widget.title,
          subtitle:
              'Open-ended questions. Edit below; applicants can answer in their own words.',
        ),
        const SizedBox(height: 22),
        _RspExamTimeLimitEditor(examType: widget.examKey),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: RspExamEditorUi.elevatedPanel(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...List.generate(_controllers.length, (i) {
                return RspBeiQuestionRow(
                  index: i,
                  controller: _controllers[i],
                  onChanged: () => setState(() {}),
                  canRemove: _controllers.length > 1,
                  onRemove: () {
                    _controllers[i].dispose();
                    _controllers.removeAt(i);
                    setState(() {});
                  },
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _controllers.add(TextEditingController());
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: RspExamEditorUi.ghostAction(context),
              ),
              const SizedBox(height: 20),
              RspExamSaveButton(
                label: 'Save ${widget.title} questions',
                saving: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RspCustomMcqExamEditor extends StatefulWidget {
  const _RspCustomMcqExamEditor({required this.examKey, required this.title});

  final String examKey;
  final String title;

  @override
  State<_RspCustomMcqExamEditor> createState() =>
      _RspCustomMcqExamEditorState();
}

class _RspCustomMcqExamEditorState extends State<_RspCustomMcqExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) {
        c.dispose();
      }
    }
    _items = [];
  }

  _GeneralExamItem _makeItem(
    String question,
    List<String> options,
    int correctIndex,
  ) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options
          .map((o) => TextEditingController(text: o))
          .toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        widget.examKey,
      );
      if (!mounted) return;
      _disposeItems();
      if (list.isEmpty) {
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
      } else {
        for (final q in list) {
          final opts =
              (q['options'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];
          while (opts.length < 2) {
            opts.add('');
          }
          _items.add(
            _makeItem(
              q['question_text'] as String? ?? '',
              opts,
              (q['correct'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      _disposeItems();
      _items.add(_makeItem('', <String>['', '', '', ''], 0));
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one question with 2+ options.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions(
        widget.examKey,
        questions,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} questions saved.')),
      );
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RspExamPageHeader(
          icon: Icons.checklist_rounded,
          title: widget.title,
          subtitle:
              'Multiple-choice questions. Edit below; set the correct option per question.',
        ),
        const SizedBox(height: 22),
        _RspExamTimeLimitEditor(examType: widget.examKey),
        _rspMcqQuestionsPanel(
          context: context,
          items: _items,
          onRefresh: () => setState(() {}),
          onCreateItem: () => _makeItem('', <String>['', '', '', ''], 0),
        ),
        const SizedBox(height: 20),
        RspExamSaveButton(
          label: 'Save ${widget.title} questions',
          saving: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// Default 8 BEI questions when DB has none (so admin can edit and save).
const _defaultBeiQuestions = [
  'Tell me about a time when you had to collaborate with a co-worker that you had a hard time getting along with?',
  'Describe for me a time when you were under a significant amount of pressure at work. How did you deal with it?',
  'Tell me about a time when you were asked to work on a task that you had never done before.',
  'Tell me about a time when you had to cultivate a relationship with a new client. What did you do?',
  'Describe a time when you disagreed with your boss. What did you do?',
  'Describe your greatest challenge.',
  'What was your greatest accomplishment?',
  'Tell me about a time you failed.',
];

class _RspBeiQuestionsEditor extends StatefulWidget {
  const _RspBeiQuestionsEditor();

  @override
  State<_RspBeiQuestionsEditor> createState() => _RspBeiQuestionsEditorState();
}

class _RspBeiQuestionsEditorState extends State<_RspBeiQuestionsEditor> {
  List<TextEditingController> _controllers = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestions('bei');
      final questions = list.isNotEmpty ? list : _defaultBeiQuestions;
      if (mounted) {
        for (final c in _controllers) {
          c.dispose();
        }
        _controllers = questions
            .map((q) => TextEditingController(text: q))
            .toList();
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        for (final c in _controllers) {
          c.dispose();
        }
        _controllers = _defaultBeiQuestions
            .map((q) => TextEditingController(text: q))
            .toList();
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final questions = _controllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one question.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestions('bei', questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BEI questions saved. Applicants will see these when taking the exam.',
            ),
          ),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RspExamPageHeader(
          icon: Icons.psychology_rounded,
          title: '8 Behavioral Event Interview (BEI) Questions',
          subtitle:
              'For New Applicant/s and Promotion/s. Edit the questions below; applicants will see these when they take the exam.',
        ),
        const SizedBox(height: 22),
        const _RspExamTimeLimitEditor(examType: 'bei'),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: RspExamEditorUi.elevatedPanel(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...List.generate(_controllers.length, (i) {
                return RspBeiQuestionRow(
                  index: i,
                  controller: _controllers[i],
                  onChanged: () => setState(() {}),
                  canRemove: _controllers.length > 1,
                  onRemove: () {
                    _controllers[i].dispose();
                    _controllers.removeAt(i);
                    setState(() {});
                  },
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _controllers.add(TextEditingController());
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: RspExamEditorUi.ghostAction(context),
              ),
              const SizedBox(height: 20),
              RspExamSaveButton(
                label: 'Save BEI questions',
                saving: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One general exam item for admin edit: question + options + correct index.
class _GeneralExamItem {
  _GeneralExamItem({
    required this.questionController,
    required this.optionControllers,
    required this.correctIndex,
  });
  final TextEditingController questionController;
  final List<TextEditingController> optionControllers;
  int correctIndex;
}

/// Admin-only: minutes per exam (0 = no time limit for applicants).
class _RspExamTimeLimitEditor extends StatefulWidget {
  const _RspExamTimeLimitEditor({required this.examType});
  final String examType;

  @override
  State<_RspExamTimeLimitEditor> createState() =>
      _RspExamTimeLimitEditorState();
}

class _RspExamTimeLimitEditorState extends State<_RspExamTimeLimitEditor> {
  final _minutesController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final limits = await RecruitmentRepo.instance.getExamTimeLimits();
      if (!mounted) return;
      final sec = limits[widget.examType] ?? 0;
      _minutesController.text = sec <= 0 ? '0' : '${(sec + 59) ~/ 60}';
    } catch (_) {
      if (mounted) {
        _minutesController.text = '0';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final parsed = int.tryParse(_minutesController.text.trim());
    if (parsed == null || parsed < 0 || parsed > 24 * 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter minutes between 0 (no limit) and 1440 (24 hours).',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamTimeLimitSeconds(
        widget.examType,
        parsed * 60,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Time limit saved.')));
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

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RspExamTimeLimitPanel(
      minutesController: _minutesController,
      saving: _saving,
      loading: _loading,
      onSave: _save,
    );
  }
}

/// Shared MCQ question list UI for General / Math / General Information editors.
Widget _rspMcqQuestionsPanel({
  required BuildContext context,
  required List<_GeneralExamItem> items,
  required VoidCallback onRefresh,
  required _GeneralExamItem Function() onCreateItem,
}) {
  final secondary = AppTheme.dashTextSecondaryOf(context);

  return Container(
    padding: const EdgeInsets.all(22),
    decoration: RspExamEditorUi.elevatedPanel(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(items.length, (i) {
          final item = items[i];
          final optCount = item.optionControllers.length;
          return RspMcqQuestionCard(
            index: i,
            onRemove: items.length > 1
                ? () {
                    final removed = items.removeAt(i);
                    removed.questionController.dispose();
                    for (final c in removed.optionControllers) {
                      c.dispose();
                    }
                    onRefresh();
                  }
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: item.questionController,
                  onChanged: (_) => onRefresh(),
                  maxLines: 3,
                  style: AppTheme.dashFieldTextStyle(context),
                  decoration: RspExamEditorUi.inputDecoration(
                    context,
                    hintText: 'Question textâ€¦',
                  ).copyWith(labelText: null),
                ),
                const SizedBox(height: 14),
                Text(
                  'OPTIONS (SELECT CORRECT ONE)',
                  style: TextStyle(
                    color: secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<int>(
                  groupValue: item.correctIndex,
                  onChanged: (v) {
                    item.correctIndex = v ?? 0;
                    onRefresh();
                  },
                  child: Column(
                    children: List.generate(optCount, (j) {
                      return RspMcqOptionRow(
                        index: j,
                        groupValue: item.correctIndex,
                        controller: item.optionControllers[j],
                        onSelected: (v) {
                          item.correctIndex = v ?? 0;
                          onRefresh();
                        },
                        onChanged: onRefresh,
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        () {
                          if (optCount == 0) return 'No options yet';
                          final safeIndex = item.correctIndex.clamp(
                            0,
                            optCount - 1,
                          );
                          final selected = item
                              .optionControllers[safeIndex]
                              .text
                              .trim();
                          if (selected.isEmpty) {
                            return 'Correct answer: Option ${safeIndex + 1}';
                          }
                          return 'Correct answer: ${selected.length > 72 ? '${selected.substring(0, 72)}...' : selected}';
                        }(),
                        style: TextStyle(
                          color: AppTheme.dashTextSecondaryOf(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: optCount < 2
                          ? null
                          : () async {
                              var selected = item.correctIndex.clamp(
                                0,
                                optCount - 1,
                              );
                              final picked = await showDialog<int>(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Set Correct Answer'),
                                    content: SizedBox(
                                      width: 520,
                                      child: StatefulBuilder(
                                        builder: (context, setDialogState) {
                                          return SingleChildScrollView(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: List.generate(
                                                optCount,
                                                (idx) {
                                                  final txt = item
                                                      .optionControllers[idx]
                                                      .text
                                                      .trim();
                                                  return RadioListTile<int>(
                                                    value: idx,
                                                    groupValue: selected,
                                                    onChanged: (v) {
                                                      if (v == null) return;
                                                      setDialogState(
                                                        () => selected = v,
                                                      );
                                                    },
                                                    title: Text(
                                                      txt.isEmpty
                                                          ? 'Option ${idx + 1}'
                                                          : txt,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    dense: true,
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  );
                                                },
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(selected),
                                        child: const Text('Apply'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (picked == null) return;
                              item.correctIndex = picked;
                              onRefresh();
                            },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        optCount < 2
                            ? 'Need 2+ options'
                            : 'Set/Change Correct Answer',
                      ),
                    ),
                  ],
                ),
                if (optCount < 6)
                  TextButton.icon(
                    onPressed: () {
                      item.optionControllers.add(TextEditingController());
                      onRefresh();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add option'),
                    style: RspExamEditorUi.ghostAction(context),
                  ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () {
            items.add(onCreateItem());
            onRefresh();
          },
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add question'),
          style: RspExamEditorUi.ghostAction(context),
        ),
      ],
    ),
  );
}

class _RspGeneralExamEditor extends StatefulWidget {
  const _RspGeneralExamEditor();

  @override
  State<_RspGeneralExamEditor> createState() => _RspGeneralExamEditorState();
}

class _RspGeneralExamEditorState extends State<_RspGeneralExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) {
        c.dispose();
      }
    }
    _items = [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        'general',
      );
      if (mounted) {
        _disposeItems();
        if (list.isEmpty) {
          _items.add(_makeItem('', <String>['', '', '', ''], 0));
        } else {
          for (final q in list) {
            final opts =
                (q['options'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[];
            while (opts.length < 2) {
              opts.add('');
            }
            _items.add(
              _makeItem(
                q['question_text'] as String? ?? '',
                opts,
                (q['correct'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        _disposeItems();
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
        setState(() => _loading = false);
      }
    }
  }

  _GeneralExamItem _makeItem(
    String question,
    List<String> options,
    int correctIndex,
  ) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options
          .map((o) => TextEditingController(text: o))
          .toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one question with 2+ options.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions(
        'general',
        questions,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('General Exam questions saved.')),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RspExamPageHeader(
          icon: Icons.assignment_turned_in_rounded,
          title: 'General Exam for LGU-Plaridel Applicants',
          subtitle:
              'Multiple-choice questions. Edit below; set the correct option per question. Applicants will see these after the BEI.',
        ),
        const SizedBox(height: 22),
        const _RspExamTimeLimitEditor(examType: 'general'),
        _rspMcqQuestionsPanel(
          context: context,
          items: _items,
          onRefresh: () => setState(() {}),
          onCreateItem: () => _makeItem('', <String>['', '', '', ''], 0),
        ),
        const SizedBox(height: 20),
        RspExamSaveButton(
          label: 'Save General Exam questions',
          saving: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// Mathematics exam editor (same structure as General, exam_type 'math').
class _RspMathExamEditor extends StatefulWidget {
  const _RspMathExamEditor();

  @override
  State<_RspMathExamEditor> createState() => _RspMathExamEditorState();
}

class _RspMathExamEditorState extends State<_RspMathExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) {
        c.dispose();
      }
    }
    _items = [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        'math',
      );
      if (mounted) {
        _disposeItems();
        if (list.isEmpty) {
          _items.add(_makeItem('', <String>['', '', '', ''], 0));
        } else {
          for (final q in list) {
            final opts =
                (q['options'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[];
            while (opts.length < 2) {
              opts.add('');
            }
            _items.add(
              _makeItem(
                q['question_text'] as String? ?? '',
                opts,
                (q['correct'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        _disposeItems();
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
        setState(() => _loading = false);
      }
    }
  }

  _GeneralExamItem _makeItem(
    String question,
    List<String> options,
    int correctIndex,
  ) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options
          .map((o) => TextEditingController(text: o))
          .toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one question with 2+ options.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions(
        'math',
        questions,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mathematics Exam questions saved.')),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RspExamPageHeader(
          icon: Icons.calculate_rounded,
          title: 'Mathematics Exam',
          subtitle:
              'Multiple-choice mathematics questions. Edit below; set the correct option per question. Applicants will see these after the General Exam.',
        ),
        const SizedBox(height: 22),
        const _RspExamTimeLimitEditor(examType: 'math'),
        _rspMcqQuestionsPanel(
          context: context,
          items: _items,
          onRefresh: () => setState(() {}),
          onCreateItem: () => _makeItem('', <String>['', '', '', ''], 0),
        ),
        const SizedBox(height: 20),
        RspExamSaveButton(
          label: 'Save Mathematics Exam questions',
          saving: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// General Information exam editor (exam_type 'general_info').
class _RspGeneralInfoExamEditor extends StatefulWidget {
  const _RspGeneralInfoExamEditor();

  @override
  State<_RspGeneralInfoExamEditor> createState() =>
      _RspGeneralInfoExamEditorState();
}

class _RspGeneralInfoExamEditorState extends State<_RspGeneralInfoExamEditor> {
  List<_GeneralExamItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.questionController.dispose();
      for (final c in item.optionControllers) {
        c.dispose();
      }
    }
    _items = [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions(
        'general_info',
      );
      if (mounted) {
        _disposeItems();
        if (list.isEmpty) {
          _items.add(_makeItem('', <String>['', '', '', ''], 0));
        } else {
          for (final q in list) {
            final opts =
                (q['options'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[];
            while (opts.length < 2) {
              opts.add('');
            }
            _items.add(
              _makeItem(
                q['question_text'] as String? ?? '',
                opts,
                (q['correct'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        _disposeItems();
        _items.add(_makeItem('', <String>['', '', '', ''], 0));
        setState(() => _loading = false);
      }
    }
  }

  _GeneralExamItem _makeItem(
    String question,
    List<String> options,
    int correctIndex,
  ) {
    return _GeneralExamItem(
      questionController: TextEditingController(text: question),
      optionControllers: options
          .map((o) => TextEditingController(text: o))
          .toList(),
      correctIndex: correctIndex.clamp(0, options.length - 1),
    );
  }

  @override
  void dispose() {
    _disposeItems();
    super.dispose();
  }

  Future<void> _save() async {
    final questions = <Map<String, dynamic>>[];
    for (final item in _items) {
      final q = item.questionController.text.trim();
      final opts = item.optionControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (q.isEmpty || opts.length < 2) continue;
      final correct = item.correctIndex.clamp(0, opts.length - 1);
      questions.add({'question_text': q, 'options': opts, 'correct': correct});
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one question with 2+ options.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveExamQuestionsWithOptions(
        'general_info',
        questions,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('General Information Exam questions saved.'),
          ),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RspExamPageHeader(
          icon: Icons.info_outline_rounded,
          title: 'General Information Exam',
          subtitle:
              'Multiple-choice questions on general information (e.g. constitution, labor). Edit below; set the correct option per question.',
        ),
        const SizedBox(height: 22),
        const _RspExamTimeLimitEditor(examType: 'general_info'),
        _rspMcqQuestionsPanel(
          context: context,
          items: _items,
          onRefresh: () => setState(() {}),
          onCreateItem: () => _makeItem('', <String>['', '', '', ''], 0),
        ),
        const SizedBox(height: 20),
        RspExamSaveButton(
          label: 'Save General Information Exam questions',
          saving: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// RSP: Background Investigation (BI) Form Ã¢â‚¬â€ list entries and add/edit form.
class _RspBiFormSection extends StatefulWidget {
  const _RspBiFormSection();

  @override
  State<_RspBiFormSection> createState() => _RspBiFormSectionState();
}

class _RspBiFormSectionState extends State<_RspBiFormSection> {
  List<BiFormEntry> _entries = [];
  bool _loading = true;
  BiFormEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await BiFormRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _startNew() {
    setState(
      () => _editing = BiFormEntry(
        applicantName: '',
        respondentName: '',
        respondentRelationship: 'supervisor',
      ),
    );
  }

  void _edit(BiFormEntry e) {
    setState(() => _editing = e);
  }

  void _cancelEdit() {
    setState(() => _editing = null);
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved BI records',
      emptyMessage: 'No BI entries yet. Add an entry first.',
      loading: _loading,
      items: _entries
          .map(
            (e) => SavedRecordListItem(
              title: e.applicantName.trim().isEmpty
                  ? '(No applicant name)'
                  : e.applicantName,
              subtitle: '${e.respondentName} Â· ${e.respondentRelationship}',
              detailDialogTitle: 'BI form â€” ${e.applicantName}',
              previewContentWidth: 920,
              previewBuilder: () => _BiFormEditor(
                readOnly: true,
                entry: e,
                onSave: (_) {},
                onCancel: () {},
                onPrint: (_) async {},
                onDownloadPdf: (_) async {},
              ),
              onPrint: () => _printBi(e),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Background Investigation (BI) Form',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Record BI evaluations: applicant and respondent details, plus competency ratings (1\u20135).',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _BiFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSaveBi,
            onCancel: _cancelEdit,
            onPrint: _printBi,
            onDownloadPdf: _downloadBi,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add BI entry'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _loading ? null : _openSavedRecordsBrowser,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
              label: const Text('View records'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          const RspFormEmptyState(
            message: 'No BI entries yet. Tap "Add BI entry" to add one.',
            icon: Icons.fact_check_outlined,
          )
        else
          _BiFormList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDeleteBi,
            onPrint: _printBi,
            onDownloadPdf: _downloadBi,
          ),
      ],
    );
  }

  Future<void> _onSaveBi(BiFormEntry entry) async {
    try {
      if (entry.id == null) {
        await BiFormRepo.instance.insert(entry);
      } else {
        await BiFormRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('BI entry saved.')));
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
      }
    }
  }

  Future<void> _onDeleteBi(String id) async {
    try {
      await BiFormRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('BI entry deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printBi(BiFormEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildBiFormPdf(entry),
        filename: 'BI_Form.pdf',
        format: FormPdf.biPrintPageFormat,
        dynamicLayout: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadBi(BiFormEntry entry) async {
    try {
      final doc = await FormPdf.buildBiFormPdf(entry);
      await FormPdf.sharePdf(doc, name: 'BI_Form.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }
}

class _BiFormEditor extends StatefulWidget {
  const _BiFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final BiFormEntry entry;

  /// When true, same layout as edit mode but fields are not editable and save/cancel are hidden.
  final bool readOnly;
  final void Function(BiFormEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(BiFormEntry) onPrint;
  final Future<void> Function(BiFormEntry) onDownloadPdf;

  @override
  State<_BiFormEditor> createState() => _BiFormEditorState();
}

class _BiFormEditorState extends State<_BiFormEditor> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _applicantName;
  late TextEditingController _applicantDept;
  late TextEditingController _applicantPosition;
  late TextEditingController _positionApplied;
  late TextEditingController _respondentName;
  late TextEditingController _respondentPosition;
  late String _relationship;
  late List<int?> _ratings;
  late List<bool> _functionalChecks;
  late TextEditingController _otherArea;
  late TextEditingController _perf3Years;
  late TextEditingController _challenges;
  late TextEditingController _compliance;
  late TextEditingController _otherRelevant;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _applicantName = TextEditingController(text: e.applicantName);
    _applicantDept = TextEditingController(text: e.applicantDepartment ?? '');
    _applicantPosition = TextEditingController(text: e.applicantPosition ?? '');
    _positionApplied = TextEditingController(text: e.positionAppliedFor ?? '');
    _respondentName = TextEditingController(text: e.respondentName);
    _respondentPosition = TextEditingController(
      text: e.respondentPosition ?? '',
    );
    _relationship = e.respondentRelationship;
    _ratings = [
      e.rating1,
      e.rating2,
      e.rating3,
      e.rating4,
      e.rating5,
      e.rating6,
      e.rating7,
      e.rating8,
      e.rating9,
    ];
    _otherArea = TextEditingController(text: e.otherFunctionalArea ?? '');
    _perf3Years = TextEditingController(text: e.performance3Years ?? '');
    _challenges = TextEditingController(text: e.challengesCoping ?? '');
    _compliance = TextEditingController(text: e.complianceAttendance ?? '');
    _otherRelevant = TextEditingController(
      text: e.otherRelevantInformation ?? '',
    );
    _functionalChecks = List.generate(
      BiFormEntry.functionalAreaOptions.length,
      (i) => e.functionalAreas.contains(BiFormEntry.functionalAreaOptions[i]),
    );
  }

  @override
  void dispose() {
    _applicantName.dispose();
    _applicantDept.dispose();
    _applicantPosition.dispose();
    _positionApplied.dispose();
    _respondentName.dispose();
    _respondentPosition.dispose();
    _otherArea.dispose();
    _perf3Years.dispose();
    _challenges.dispose();
    _compliance.dispose();
    _otherRelevant.dispose();
    super.dispose();
  }

  BiFormEntry _buildCurrentEntry() {
    final areas = <String>[];
    for (var i = 0; i < BiFormEntry.functionalAreaOptions.length; i++) {
      if (_functionalChecks[i]) {
        areas.add(BiFormEntry.functionalAreaOptions[i]);
      }
    }
    return BiFormEntry(
      id: widget.entry.id,
      applicantName: _applicantName.text.trim(),
      applicantDepartment: _applicantDept.text.trim().isEmpty
          ? null
          : _applicantDept.text.trim(),
      applicantPosition: _applicantPosition.text.trim().isEmpty
          ? null
          : _applicantPosition.text.trim(),
      positionAppliedFor: _positionApplied.text.trim().isEmpty
          ? null
          : _positionApplied.text.trim(),
      respondentName: _respondentName.text.trim(),
      respondentPosition: _respondentPosition.text.trim().isEmpty
          ? null
          : _respondentPosition.text.trim(),
      respondentRelationship: _relationship,
      rating1: _ratings[0],
      rating2: _ratings[1],
      rating3: _ratings[2],
      rating4: _ratings[3],
      rating5: _ratings[4],
      rating6: _ratings[5],
      rating7: _ratings[6],
      rating8: _ratings[7],
      rating9: _ratings[8],
      functionalAreas: areas,
      otherFunctionalArea: _otherArea.text.trim().isEmpty
          ? null
          : _otherArea.text.trim(),
      performance3Years: _perf3Years.text.trim().isEmpty
          ? null
          : _perf3Years.text.trim(),
      challengesCoping: _challenges.text.trim().isEmpty
          ? null
          : _challenges.text.trim(),
      complianceAttendance: _compliance.text.trim().isEmpty
          ? null
          : _compliance.text.trim(),
      otherRelevantInformation: _otherRelevant.text.trim().isEmpty
          ? null
          : _otherRelevant.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    const functionalOptions = BiFormEntry.functionalAreaOptions;
    const functionalLeftCount = 6;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RspFormHeader(
                formTitle: 'BACKGROUND INVESTIGATION (BI FORM)',
              ),
              // Two-column: Applicant under BI | Respondents
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'APPLICANT UNDER BI:',
                          style: TextStyle(
                            color: AppTheme.primaryNavy,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _applicantName,
                            readOnly: ro,
                            decoration: rspUnderlinedField('Name:'),
                            validator: (v) =>
                                v?.trim().isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _applicantDept,
                            readOnly: ro,
                            decoration: rspUnderlinedField('Department:'),
                          ),
                        ),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _applicantPosition,
                            readOnly: ro,
                            decoration: rspUnderlinedField('Position:'),
                          ),
                        ),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _positionApplied,
                            readOnly: ro,
                            decoration: rspUnderlinedField(
                              'Position Applied for in LGU-Plaridel:',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RESPONDENTS:',
                          style: TextStyle(
                            color: AppTheme.primaryNavy,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _respondentName,
                            decoration: rspUnderlinedField('Name:'),
                            validator: (v) =>
                                v?.trim().isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _respondentPosition,
                            decoration: rspUnderlinedField('Position:'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Work relationship to the applicants: (Kindly check the appropriate box)',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        RadioGroup<String>(
                          groupValue: _relationship,
                          onChanged: (v) => setState(() => _relationship = v!),
                          child: Column(
                            children: [
                              ...BiFormEntry.relationshipOptions.map(
                                (r) => RadioListTile<String>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    r == 'supervisor'
                                        ? 'Applicants Supervisor'
                                        : r == 'peer'
                                        ? 'Applicants Peer/ Co-Employee'
                                        : 'Applicants Subordinates',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  value: r,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // I. ON COMPETENCIES
              Text(
                'I. ON COMPETENCIES',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Core and Organizational Competencies:',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Using the following rating guide please check (/) the appropriate box opposite each behavioral Indicator:',
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.lightGray),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rating Guide:',
                          style: TextStyle(
                            color: AppTheme.primaryNavy,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '5- Shows Strength',
                          style: TextStyle(fontSize: 11),
                        ),
                        Text(
                          '4- Very Proficient',
                          style: TextStyle(fontSize: 11),
                        ),
                        Text('3- Proficient', style: TextStyle(fontSize: 11)),
                        Text(
                          '2- Minimal Development',
                          style: TextStyle(fontSize: 11),
                        ),
                        Text(
                          '1- Much Development Needed',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Competency table: AREA | CORE DESCRIPTION | 5 | 4 | 3 | 2 | 1
              Table(
                border: TableBorder.all(color: Colors.black87),
                columnWidths: const {
                  0: FlexColumnWidth(0.5),
                  1: FlexColumnWidth(4),
                  2: FlexColumnWidth(0.4),
                  3: FlexColumnWidth(0.4),
                  4: FlexColumnWidth(0.4),
                  5: FlexColumnWidth(0.4),
                  6: FlexColumnWidth(0.4),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    ),
                    children: [
                      _tableCell('AREA', bold: true),
                      _tableCell('CORE DESCRIPTION', bold: true),
                      _tableCell('5', bold: true),
                      _tableCell('4', bold: true),
                      _tableCell('3', bold: true),
                      _tableCell('2', bold: true),
                      _tableCell('1', bold: true),
                    ],
                  ),
                  ...List.generate(
                    9,
                    (i) => TableRow(
                      children: [
                        _tableCell('${i + 1}'),
                        _tableCell(
                          BiFormEntry.competencyDescriptions[i],
                          small: true,
                        ),
                        _ratingCell(i, 5),
                        _ratingCell(i, 4),
                        _ratingCell(i, 3),
                        _ratingCell(i, 2),
                        _ratingCell(i, 1),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Divider(color: AppTheme.lightGray, height: 1),
              const SizedBox(height: 20),
              Text(
                'Page 2 â€” Functional areas & performance',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A. Functional Areas:',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Please check (/) the boxes opposite the functional area where the applicant can perform effectively.',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          var i = 0;
                          i < functionalLeftCount &&
                              i < functionalOptions.length;
                          i++
                        )
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              functionalOptions[i],
                              style: const TextStyle(fontSize: 13),
                            ),
                            value: _functionalChecks[i],
                            onChanged: ro
                                ? null
                                : (v) => setState(
                                    () => _functionalChecks[i] = v ?? false,
                                  ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          var i = functionalLeftCount;
                          i < functionalOptions.length;
                          i++
                        )
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              functionalOptions[i],
                              style: const TextStyle(fontSize: 13),
                            ),
                            value: _functionalChecks[i],
                            onChanged: ro
                                ? null
                                : (v) => setState(
                                    () => _functionalChecks[i] = v ?? false,
                                  ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Other (Please specify)',
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 13,
                          ),
                        ),
                        RspSpacedOutlineField(
                          child: TextFormField(
                            controller: _otherArea,
                            readOnly: ro,
                            decoration: rspUnderlinedField(''),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'I. On performance and other relevant information.',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please tell us about the work performance of the applicants in the last three (3) years. What are the applicant\'s outstanding accomplishments recognition received and significant contributions to your office if any?',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              RspSpacedOutlineField(
                child: TextFormField(
                  controller: _perf3Years,
                  readOnly: ro,
                  decoration: rspUnderlinedField(''),
                  maxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'What do you think are the challenges or difficulties of the applicant in performing his/her duties and responsibilities in his/her position? How did the applicant cope with these challenges?',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              RspSpacedOutlineField(
                child: TextFormField(
                  controller: _challenges,
                  readOnly: ro,
                  decoration: rspUnderlinedField(''),
                  maxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'In terms of compliance with rules and regulation, please provide us information on the applicant\'s attendance to flag ceremonies/ retreats and other office programs and activities?',
                style: TextStyle(
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              RspSpacedOutlineField(
                child: TextFormField(
                  controller: _compliance,
                  readOnly: ro,
                  decoration: rspUnderlinedField(''),
                  maxLines: 4,
                ),
              ),
              const SizedBox(height: 28),
              Divider(color: AppTheme.lightGray, height: 1),
              const SizedBox(height: 20),
              Text(
                'Page 3 â€” Other relevant information',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Other relevant information/ data (critical incidents, family background, health profile habits, vices, membership in unions/ associations, or any derogatory records) about the applicants, if any.',
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              RspSpacedOutlineField(
                child: TextFormField(
                  controller: _otherRelevant,
                  readOnly: ro,
                  decoration: rspUnderlinedField(''),
                  maxLines: 8,
                ),
              ),
              const SizedBox(height: 24),
              const RspFormFooter(),
              const SizedBox(height: 24),
              if (!ro) ...[
                Row(
                  children: [
                    FilledButton(onPressed: _save, child: const Text('Save')),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () => widget.onPrint(_buildCurrentEntry()),
                      icon: const Icon(Icons.print_rounded),
                      tooltip: 'Print',
                    ),
                    IconButton(
                      onPressed: () =>
                          widget.onDownloadPdf(_buildCurrentEntry()),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      tooltip: 'Download PDF',
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  widget.entry.createdAt != null
                      ? 'Created: ${widget.entry.createdAt!.toLocal()}'
                      : '',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                if (widget.entry.updatedAt != null)
                  Text(
                    'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCell(String text, {bool bold = false, bool small = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: small ? 9 : 11,
          fontWeight: bold ? FontWeight.bold : null,
        ),
      ),
    );
  }

  Widget _ratingCell(int rowIndex, int rating) {
    final selected = _ratings[rowIndex] == rating;
    final cell = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        selected ? '/' : '',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
    if (widget.readOnly) return cell;
    return InkWell(
      onTap: () => setState(() => _ratings[rowIndex] = rating),
      child: cell,
    );
  }
}

class _BiFormList extends StatelessWidget {
  const _BiFormList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<BiFormEntry> entries;
  final void Function(BiFormEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(BiFormEntry) onPrint;
  final Future<void> Function(BiFormEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Applicant', flex: 2.2),
      RspRecordsColumn('Respondent', flex: 2.2),
      RspRecordsColumn('Relationship', flex: 1.4),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, e.applicantName, bold: true),
              rspRecordsTextCell(context, e.respondentName, bold: true),
              rspRecordsTextCell(context, e.respondentRelationship),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'BI form â€” ${e.applicantName}',
                  subtitle:
                      '${e.respondentName} Â· ${e.respondentRelationship}',
                  previewBuilder: () => _BiFormEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 920,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete BI entry?',
              ),
            ],
          )
          .toList(),
    );
  }
}

/// RSP: Applicants Profile Ã¢â‚¬â€ job vacancy details + list of applicants.
class _RspApplicantsProfileSection extends StatefulWidget {
  const _RspApplicantsProfileSection();

  @override
  State<_RspApplicantsProfileSection> createState() =>
      _RspApplicantsProfileSectionState();
}

class _RspApplicantsProfileSectionState
    extends State<_RspApplicantsProfileSection> {
  List<ApplicantsProfileEntry> _entries = [];
  bool _loading = true;
  ApplicantsProfileEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _norm(String? s) => (s ?? '').trim().toLowerCase();

  static bool _samePosition(String? a, String? b) {
    final na = _norm(a);
    final nb = _norm(b);
    return na.isNotEmpty && na == nb;
  }

  static String _dateYmd(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String? _requirementsFromVacancy(JobVacancyItem? vacancy) {
    if (vacancy == null) return null;
    final lines = <String>[];
    void addLine(String label, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) lines.add('$label: $v');
    }

    addLine('Education', vacancy.education);
    addLine('Experience', vacancy.experience);
    addLine('Training', vacancy.training);
    if (lines.isNotEmpty) return lines.join('\n');
    final body = vacancy.body?.trim();
    return (body == null || body.isEmpty) ? null : body;
  }

  ApplicantsProfileEntry _buildAutoPrefilledProfile(
    JobVacancyAnnouncement announcement,
    List<RecruitmentApplication> applications, {
    String? preferredPosition,
  }) {
    final pipelineApps = applications
        .where((a) => a.isActiveInPipeline)
        .toList();
    final sourceApps = pipelineApps.isNotEmpty ? pipelineApps : applications;
    final preferred = preferredPosition?.trim();

    JobVacancyItem? selectedVacancy;
    if (preferred != null && preferred.isNotEmpty) {
      for (final v in announcement.vacancies) {
        final key = v.positionKey?.trim();
        if (key != null && key.isNotEmpty && _samePosition(key, preferred)) {
          selectedVacancy = v;
          break;
        }
      }
    }
    selectedVacancy ??= () {
      for (final v in announcement.vacancies) {
        final key = v.positionKey?.trim();
        if (key == null || key.isEmpty) continue;
        final hasMatches = sourceApps.any(
          (a) => _samePosition(a.positionAppliedFor, key),
        );
        if (hasMatches) return v;
      }
      return null;
    }();
    selectedVacancy ??= announcement.vacancies.isNotEmpty
        ? announcement.vacancies.first
        : null;

    String? selectedPosition = preferred;
    if (selectedPosition == null || selectedPosition.isEmpty) {
      selectedPosition = selectedVacancy?.positionKey?.trim();
    }
    if (selectedPosition == null || selectedPosition.isEmpty) {
      for (final a in sourceApps) {
        final p = a.positionAppliedFor?.trim();
        if (p != null && p.isNotEmpty) {
          selectedPosition = p;
          break;
        }
      }
    }

    final matchedApps = selectedPosition == null || selectedPosition.isEmpty
        ? sourceApps
        : sourceApps
              .where(
                (a) => _samePosition(a.positionAppliedFor, selectedPosition),
              )
              .toList();
    matchedApps.sort((a, b) => _norm(a.fullName).compareTo(_norm(b.fullName)));

    DateTime? postingDate;
    final withCreatedAt =
        matchedApps
            .where((a) => a.createdAt != null)
            .map((a) => a.createdAt!)
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (withCreatedAt.isNotEmpty) {
      postingDate = withCreatedAt.first;
    } else {
      postingDate = announcement.updatedAt;
    }

    return ApplicantsProfileEntry(
      positionAppliedFor: (selectedPosition == null || selectedPosition.isEmpty)
          ? null
          : selectedPosition,
      minimumRequirements: _requirementsFromVacancy(selectedVacancy),
      dateOfPosting: postingDate == null ? null : _dateYmd(postingDate),
      closingDate: selectedVacancy?.closingDate == null
          ? null
          : _dateYmd(selectedVacancy!.closingDate!),
      applicants: matchedApps
          .map(
            (a) => ApplicantsProfileApplicant(
              name: a.fullName.trim().isEmpty ? null : a.fullName.trim(),
              course: a.course?.trim().isEmpty == true
                  ? null
                  : a.course?.trim(),
              address: a.address?.trim().isEmpty == true
                  ? null
                  : a.address?.trim(),
              sex: a.sex?.trim().isEmpty == true ? null : a.sex?.trim(),
              age: a.age?.trim().isEmpty == true ? null : a.age?.trim(),
              civilStatus: a.civilStatus?.trim().isEmpty == true
                  ? null
                  : a.civilStatus?.trim(),
            ),
          )
          .toList(),
    );
  }

  List<String> _autofillPositions(
    JobVacancyAnnouncement announcement,
    List<RecruitmentApplication> applications,
  ) {
    final ordered = <String>[];
    void addPosition(String? raw) {
      final p = raw?.trim();
      if (p == null || p.isEmpty) return;
      if (!ordered.any((existing) => _samePosition(existing, p))) {
        ordered.add(p);
      }
    }

    for (final v in announcement.vacancies) {
      addPosition(v.positionKey);
    }

    final pipelineApps = applications
        .where((a) => a.isActiveInPipeline)
        .toList();
    final sourceApps = pipelineApps.isNotEmpty ? pipelineApps : applications;
    for (final app in sourceApps) {
      addPosition(app.positionAppliedFor);
    }

    return ordered;
  }

  /// Returned by [_pickAutofillPosition] when the user explicitly closes the
  /// dialog (X button or tapping outside) instead of choosing an option.
  static const String _cancelledChoice =
      '__cancelled_applicants_profile_pick__';

  Future<String?> _pickAutofillPosition(
    List<String> positions,
    List<RecruitmentApplication> applications,
  ) async {
    if (positions.length <= 1)
      return positions.isEmpty ? null : positions.first;
    final pipelineApps = applications
        .where((a) => a.isActiveInPipeline)
        .toList();
    final sourceApps = pipelineApps.isNotEmpty ? pipelineApps : applications;

    int countFor(String position) => sourceApps
        .where((a) => _samePosition(a.positionAppliedFor, position))
        .length;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final hairline = AppTheme.dashHairlineOf(ctx);
        final primary = AppTheme.dashTextPrimaryOf(ctx);
        final secondary = AppTheme.dashTextSecondaryOf(ctx);
        final panel = AppTheme.dashPanelOf(ctx);

        String initialsFor(String position) {
          final parts = position.trim().split(RegExp(r'\s+'));
          var initials = '';
          if (parts.isNotEmpty && parts.first.isNotEmpty) {
            initials += parts.first[0].toUpperCase();
          }
          if (parts.length > 1 && parts.last.isNotEmpty) {
            initials += parts.last[0].toUpperCase();
          }
          return initials.isEmpty ? '?' : initials;
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 28,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: Material(
              color: panel,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              elevation: 12,
              shadowColor: Colors.black26,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryNavy,
                          AppTheme.primaryNavyLight,
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.work_outline_rounded,
                            color: AppTheme.primaryNavy,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select position',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose which vacancy to autofill into the applicants profile.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.close_rounded, color: secondary),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      itemCount: positions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final position = positions[i];
                        final count = countFor(position);
                        final countLabel = count == 1
                            ? '1 applicant'
                            : '$count applicants';
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(position),
                            borderRadius: BorderRadius.circular(14),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: AppTheme.dashMutedSurfaceOf(ctx),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: hairline),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.primaryNavy,
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(14),
                                          bottomLeft: Radius.circular(14),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        14,
                                        12,
                                      ),
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              AppTheme.primaryNavy.withValues(
                                                alpha: 0.18,
                                              ),
                                              AppTheme.primaryNavyLight
                                                  .withValues(alpha: 0.1),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: AppTheme.primaryNavy
                                                .withValues(alpha: 0.22),
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          initialsFor(position),
                                          style: const TextStyle(
                                            color: AppTheme.primaryNavy,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              position,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: primary,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryNavy
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: AppTheme.primaryNavy
                                                      .withValues(alpha: 0.22),
                                                ),
                                              ),
                                              child: Text(
                                                countLabel,
                                                style: const TextStyle(
                                                  color: AppTheme.primaryNavy,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(_blankFormChoice),
                      icon: const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 18,
                      ),
                      label: const Text('Start with a blank form (no data)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                        side: BorderSide(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.4),
                        ),
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? _cancelledChoice;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApplicantsProfileRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  /// Sentinel returned by [_pickAutofillPosition] when the user chooses
  /// "Start with a blank form" instead of a vacancy to autofill from.
  static const String _blankFormChoice = '__blank_applicants_profile_form__';

  Future<void> _startNew() async {
    try {
      final announcement = await JobVacancyAnnouncementRepo.instance.fetch();
      final applications = await RecruitmentRepo.instance.listApplications();
      if (!mounted) return;
      final positions = _autofillPositions(announcement, applications);
      final selectedPosition = await _pickAutofillPosition(
        positions,
        applications,
      );
      if (!mounted) return;
      if (selectedPosition == _cancelledChoice) {
        return;
      }
      if (selectedPosition == _blankFormChoice) {
        setState(() => _editing = const ApplicantsProfileEntry());
        return;
      }
      setState(
        () => _editing = _buildAutoPrefilledProfile(
          announcement,
          applications,
          preferredPosition: selectedPosition,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _editing = const ApplicantsProfileEntry());
    }
  }

  void _edit(ApplicantsProfileEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ApplicantsProfileEntry entry) async {
    try {
      if (entry.id == null) {
        await ApplicantsProfileRepo.instance.insert(entry);
      } else {
        await ApplicantsProfileRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Applicants profile saved.')),
        );
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
      }
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await ApplicantsProfileRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Applicants profile deleted.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printProfile(ApplicantsProfileEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildApplicantsProfilePdf(entry),
        filename: 'Applicants_Profile.pdf',
        format: FormPdf.pageLongLandscape,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadProfile(ApplicantsProfileEntry entry) async {
    try {
      final doc = await FormPdf.buildApplicantsProfilePdf(entry);
      await FormPdf.sharePdf(doc, name: 'Applicants_Profile.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved applicants profiles',
      emptyMessage: 'No profiles yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = (e.positionAppliedFor?.trim().isNotEmpty ?? false)
            ? e.positionAppliedFor!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle:
              '${e.applicants.length} applicant(s) Â· Posted ${e.dateOfPosting ?? "â€”"}',
          detailDialogTitle: 'Applicants profile â€” $pos',
          previewContentWidth: 960,
          previewBuilder: () => _ApplicantsProfileFormEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printProfile(e),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RSP',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            Text(
              'Applicants Profile',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Applicants Profile',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _ApplicantsProfileFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printProfile,
            onDownloadPdf: _downloadProfile,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add profile'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _loading ? null : _openSavedRecordsBrowser,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
              label: const Text('View records'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          const RspFormEmptyState(
            message:
                'No applicants profiles yet. Tap "Add profile" to add one.',
            icon: Icons.people_outline,
          )
        else
          _ApplicantsProfileList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printProfile,
            onDownloadPdf: _downloadProfile,
          ),
      ],
    );
  }
}

class _ApplicantsProfileFormEditor extends StatefulWidget {
  const _ApplicantsProfileFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final ApplicantsProfileEntry entry;
  final bool readOnly;
  final void Function(ApplicantsProfileEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ApplicantsProfileEntry) onPrint;
  final Future<void> Function(ApplicantsProfileEntry) onDownloadPdf;

  @override
  State<_ApplicantsProfileFormEditor> createState() =>
      _ApplicantsProfileFormEditorState();
}

class _ApplicantsProfileFormEditorState
    extends State<_ApplicantsProfileFormEditor> {
  static const _kApplicantsPerPage =
      ApplicantsProfileEntry.applicantsPerFormPage;

  late TextEditingController _positionApplied;
  late TextEditingController _minRequirements;
  late TextEditingController _datePosting;
  late TextEditingController _closingDate;
  late TextEditingController _preparedBy;
  late TextEditingController _checkedBy;
  late TextEditingController _searchCtrl;
  late List<Map<String, TextEditingController>> _applicantRows;
  int _currentFormPage = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _positionApplied = TextEditingController(text: e.positionAppliedFor ?? '');
    _minRequirements = TextEditingController(text: e.minimumRequirements ?? '');
    _datePosting = TextEditingController(text: e.dateOfPosting ?? '');
    _closingDate = TextEditingController(text: e.closingDate ?? '');
    _preparedBy = TextEditingController(text: e.preparedBy ?? '');
    _checkedBy = TextEditingController(text: e.checkedBy ?? '');
    _searchCtrl = TextEditingController();
    _applicantRows = e.applicants.isEmpty
        ? <Map<String, TextEditingController>>[]
        : e.applicants
              .map(
                (a) => _applicantRow(
                  a.name ?? '',
                  a.course ?? '',
                  formatStoredAddressForDisplay(a.address),
                  a.sex ?? '',
                  a.age ?? '',
                  a.civilStatus ?? '',
                  a.remarkDisability ?? '',
                ),
              )
              .toList();
    _positionApplied.addListener(_onTitleFieldChanged);
  }

  void _onTitleFieldChanged() => setState(() {});

  Map<String, TextEditingController> _applicantRow(
    String name,
    String course,
    String address,
    String sex,
    String age,
    String civil,
    String remark,
  ) {
    return {
      'name': TextEditingController(text: name),
      'course': TextEditingController(text: course),
      'address': TextEditingController(text: address),
      'sex': TextEditingController(text: sex),
      'age': TextEditingController(text: age),
      'civil_status': TextEditingController(text: civil),
      'remark_disability': TextEditingController(text: remark),
    };
  }

  @override
  void dispose() {
    _positionApplied.removeListener(_onTitleFieldChanged);
    _positionApplied.dispose();
    _minRequirements.dispose();
    _datePosting.dispose();
    _closingDate.dispose();
    _preparedBy.dispose();
    _checkedBy.dispose();
    _searchCtrl.dispose();
    for (final row in _applicantRows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  int get _formPageCount {
    final n = _applicantRows.length;
    return n == 0 ? 1 : ((n - 1) ~/ _kApplicantsPerPage) + 1;
  }

  int get _currentPageStart => _currentFormPage * _kApplicantsPerPage;

  int get _currentPageEnd =>
      (_currentPageStart + _kApplicantsPerPage).clamp(0, _applicantRows.length);

  List<Map<String, TextEditingController>> get _currentPageRows =>
      _applicantRows.sublist(_currentPageStart, _currentPageEnd);

  Future<void> _openAddApplicantDialog() async {
    if (widget.readOnly) return;
    final result = await showDialog<_ApplicantDialogResult>(
      context: context,
      builder: (_) => const _ApplicantDialog(isEditing: false),
    );
    if (result == null || !mounted) return;
    setState(() {
      _applicantRows.add(
        _applicantRow(
          result.name,
          result.course,
          result.address,
          result.sex,
          result.age,
          result.civilStatus,
          result.remark,
        ),
      );
      _currentFormPage = (_applicantRows.length - 1) ~/ _kApplicantsPerPage;
    });
  }

  Future<void> _openEditApplicantDialog(int globalIndex) async {
    if (widget.readOnly) return;
    final row = _applicantRows[globalIndex];
    final initial = _ApplicantDialogResult(
      name: row['name']!.text,
      course: row['course']!.text,
      address: row['address']!.text,
      sex: row['sex']!.text,
      age: row['age']!.text,
      civilStatus: row['civil_status']!.text,
      remark: row['remark_disability']!.text,
    );
    final result = await showDialog<_ApplicantDialogResult>(
      context: context,
      builder: (_) => _ApplicantDialog(isEditing: true, initial: initial),
    );
    if (result == null || !mounted) return;
    setState(() {
      row['name']!.text = result.name;
      row['course']!.text = result.course;
      row['address']!.text = result.address;
      row['sex']!.text = result.sex;
      row['age']!.text = result.age;
      row['civil_status']!.text = result.civilStatus;
      row['remark_disability']!.text = result.remark;
    });
  }

  void _removeApplicant(int pageLocalIndex) {
    if (widget.readOnly) return;
    if (_applicantRows.isEmpty) return;
    final globalIndex = _currentPageStart + pageLocalIndex;
    if (globalIndex < 0 || globalIndex >= _applicantRows.length) return;
    setState(() {
      for (final c in _applicantRows[globalIndex].values) {
        c.dispose();
      }
      _applicantRows.removeAt(globalIndex);
      final maxPage = _formPageCount - 1;
      if (_currentFormPage > maxPage) {
        _currentFormPage = maxPage.clamp(0, maxPage);
      }
    });
  }

  void _goToFormPage(int page) {
    final maxPage = _formPageCount - 1;
    setState(() => _currentFormPage = page.clamp(0, maxPage));
  }

  ApplicantsProfileEntry _buildCurrentEntry() {
    final applicants = _applicantRows
        .map(
          (r) => ApplicantsProfileApplicant(
            name: r['name']!.text.trim().isEmpty
                ? null
                : r['name']!.text.trim(),
            course: r['course']!.text.trim().isEmpty
                ? null
                : r['course']!.text.trim(),
            address: r['address']!.text.trim().isEmpty
                ? null
                : r['address']!.text.trim(),
            sex: r['sex']!.text.trim().isEmpty ? null : r['sex']!.text.trim(),
            age: r['age']!.text.trim().isEmpty ? null : r['age']!.text.trim(),
            civilStatus: r['civil_status']!.text.trim().isEmpty
                ? null
                : r['civil_status']!.text.trim(),
            remarkDisability: r['remark_disability']!.text.trim().isEmpty
                ? null
                : r['remark_disability']!.text.trim(),
          ),
        )
        .toList();
    return ApplicantsProfileEntry(
      id: widget.entry.id,
      positionAppliedFor: _positionApplied.text.trim().isEmpty
          ? null
          : _positionApplied.text.trim(),
      minimumRequirements: _minRequirements.text.trim().isEmpty
          ? null
          : _minRequirements.text.trim(),
      dateOfPosting: _datePosting.text.trim().isEmpty
          ? null
          : _datePosting.text.trim(),
      closingDate: _closingDate.text.trim().isEmpty
          ? null
          : _closingDate.text.trim(),
      applicants: applicants,
      preparedBy: _preparedBy.text.trim().isEmpty
          ? null
          : _preparedBy.text.trim(),
      checkedBy: _checkedBy.text.trim().isEmpty ? null : _checkedBy.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  static String _dash(String v) => v.trim().isEmpty ? '—' : v.trim();

  static String _initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _statusChip(String label) {
    final Color color = label == 'Draft'
        ? const Color(0xFFB26A00)
        : label == 'Read-only preview'
        ? Colors.blueGrey
        : const Color(0xFF2E7D32);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _editorHeaderBar(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final position = _positionApplied.text.trim();
    final title = position.isEmpty ? 'New Applicants Profile' : position;
    final statusLabel = ro
        ? 'Read-only preview'
        : (widget.entry.id == null ? 'Draft' : 'Saved');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statusChip(statusLabel),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Vacancy details and applicant list for this posting.',
                  style: TextStyle(fontSize: 12.5, color: secondary),
                ),
              ],
            ),
          ),
          if (!ro)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Print',
                  style: rspLdRecordIconButtonStyle(),
                  onPressed: () => widget.onPrint(_buildCurrentEntry()),
                  icon: const Icon(Icons.print_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Download PDF',
                  style: rspLdRecordIconButtonStyle(),
                  onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                ),
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static const _kDateFieldLabels = {'Date of Posting', 'Closing Date'};

  static String _formatPickedDate(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickVacancyDate(TextEditingController c) async {
    final now = DateTime.now();
    final parsed = DateTime.tryParse(c.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() => c.text = _formatPickedDate(picked));
  }

  Widget _vacancyField(TextEditingController c, String label, bool ro) {
    final isDateField = _kDateFieldLabels.contains(label);
    return TextFormField(
      controller: c,
      readOnly: ro || isDateField,
      minLines: 1,
      maxLines: label == 'Minimum Requirements' ? 3 : 1,
      onTap: (!ro && isDateField) ? () => _pickVacancyDate(c) : null,
      decoration: AppTheme.dashInputDecoration(
        context,
        labelText: label,
        suffixIcon: (isDateField && !ro)
            ? IconButton(
                tooltip: 'Pick a date',
                icon: const Icon(Icons.calendar_month_outlined, size: 20),
                onPressed: () => _pickVacancyDate(c),
              )
            : null,
      ),
    );
  }

  Widget _vacancyInfoCard(BuildContext context, bool ro) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VACANCY INFORMATION',
            style: AppTheme.dashSectionTitle(context),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 640;
              Widget pair(
                TextEditingController a,
                String labelA,
                TextEditingController b,
                String labelB,
              ) {
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _vacancyField(a, labelA, ro)),
                      const SizedBox(width: 14),
                      Expanded(child: _vacancyField(b, labelB, ro)),
                    ],
                  );
                }
                return Column(
                  children: [
                    _vacancyField(a, labelA, ro),
                    const SizedBox(height: 14),
                    _vacancyField(b, labelB, ro),
                  ],
                );
              }

              return Column(
                children: [
                  pair(
                    _positionApplied,
                    'Position Applied For',
                    _minRequirements,
                    'Minimum Requirements',
                  ),
                  const SizedBox(height: 14),
                  pair(
                    _datePosting,
                    'Date of Posting',
                    _closingDate,
                    'Closing Date',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _applicantsSectionHeader(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final onPage = _currentPageRows.length;
    final fraction = (onPage / _kApplicantsPerPage).clamp(0.0, 1.0);
    final isFull = onPage >= _kApplicantsPerPage;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      runSpacing: 12,
      spacing: 16,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Applicants',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$onPage / $_kApplicantsPerPage',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  width: 160,
                  height: 6,
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: AppTheme.dashHairlineOf(context),
                    color: AppTheme.primaryNavy,
                  ),
                ),
              ),
              if (isFull) ...[
                const SizedBox(height: 6),
                Text(
                  'Form is full. Adding one more opens the next form automatically.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: secondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!ro)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim().toLowerCase()),
                  decoration:
                      AppTheme.dashInputDecoration(
                        context,
                        hintText: 'Search applicants...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      ).copyWith(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                ),
              ),
              FilledButton.icon(
                onPressed: _openAddApplicantDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Applicant'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _formPagePill(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous form',
          onPressed: _currentFormPage > 0
              ? () => _goToFormPage(_currentFormPage - 1)
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            'Form ${_currentFormPage + 1} of $_formPageCount',
            style: const TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next form',
          onPressed: _currentFormPage < _formPageCount - 1
              ? () => _goToFormPage(_currentFormPage + 1)
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        const SizedBox(width: 8),
        Text(
          _applicantRows.isEmpty
              ? 'No applicants yet'
              : 'Rows ${_currentPageStart + 1}–$_currentPageEnd of ${_applicantRows.length}',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _applicantsTable(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final rows = _currentPageRows;
    final q = _searchQuery;

    final visible = <int>[];
    for (var i = 0; i < rows.length; i++) {
      if (q.isEmpty) {
        visible.add(i);
        continue;
      }
      final r = rows[i];
      final hay = [
        r['name']!.text,
        r['course']!.text,
        r['address']!.text,
      ].join(' ').toLowerCase();
      if (hay.contains(q)) visible.add(i);
    }

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline),
        ),
        child: Text(
          'No applicants yet. Tap "Add Applicant" to add one.',
          style: TextStyle(color: secondary),
        ),
      );
    }

    if (visible.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hairline),
        ),
        child: Text(
          'No applicants match your search.',
          style: TextStyle(color: secondary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              AppTheme.dashMutedSurfaceOf(context),
            ),
            dataRowMinHeight: 52,
            dataRowMaxHeight: 64,
            columnSpacing: 20,
            horizontalMargin: 16,
            headingTextStyle: TextStyle(
              color: secondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
            dataTextStyle: TextStyle(color: primary, fontSize: 13),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('NAME')),
              DataColumn(label: Text('COURSE')),
              DataColumn(label: Text('ADDRESS')),
              DataColumn(label: Text('SEX')),
              DataColumn(label: Text('AGE')),
              DataColumn(label: Text('CIVIL STATUS')),
              DataColumn(label: Text('REMARK')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: visible.map((i) {
              final r = rows[i];
              final globalIndex = _currentPageStart + i;
              final name = r['name']!.text.trim();
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      '${globalIndex + 1}',
                      style: TextStyle(color: secondary),
                    ),
                  ),
                  DataCell(
                    Text(
                      name.isEmpty ? '—' : name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(Text(_dash(r['course']!.text))),
                  DataCell(
                    SizedBox(
                      width: 200,
                      child: Text(
                        _dash(r['address']!.text),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                  DataCell(Text(_dash(r['sex']!.text))),
                  DataCell(Text(_dash(r['age']!.text))),
                  DataCell(Text(_dash(r['civil_status']!.text))),
                  DataCell(Text(_dash(r['remark_disability']!.text))),
                  DataCell(
                    ro
                        ? const SizedBox(width: 8)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                style: rspLdRecordIconButtonStyle(),
                                onPressed: () =>
                                    _openEditApplicantDialog(globalIndex),
                                icon: const Icon(Icons.edit_rounded, size: 18),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Remove',
                                style: rspLdRecordIconButtonStyle(
                                  foreground: const Color(0xFFC62828),
                                ),
                                onPressed: () => _removeApplicant(i),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Blank strip with a bottom rule, sized for a physical pen signature above
  /// the printed name (mirrors the space added in the PDF output).
  Widget _signatureSpace(BuildContext context) {
    return Container(
      height: 30,
      margin: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
    );
  }

  Widget _preparedByCard(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.14),
            child: Text(
              _initialsOf(_preparedBy.text),
              style: const TextStyle(
                color: AppTheme.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PREPARED BY', style: AppTheme.dashSectionTitle(context)),
                const SizedBox(height: 6),
                _signatureSpace(context),
                ro
                    ? Text(
                        _preparedBy.text.trim().isEmpty
                            ? '—'
                            : _preparedBy.text.trim(),
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : TextFormField(
                        controller: _preparedBy,
                        decoration: AppTheme.dashInputDecoration(
                          context,
                          hintText: 'Full name, position',
                        ),
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkedByCard(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blueGrey.withValues(alpha: 0.14),
            child: Icon(
              Icons.verified_user_outlined,
              size: 18,
              color: Colors.blueGrey.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CHECKED BY', style: AppTheme.dashSectionTitle(context)),
                const SizedBox(height: 6),
                _signatureSpace(context),
                ro
                    ? Text(
                        _checkedBy.text.trim().isEmpty
                            ? '—'
                            : _checkedBy.text.trim(),
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : TextFormField(
                        controller: _checkedBy,
                        decoration: AppTheme.dashInputDecoration(
                          context,
                          hintText: 'HRMDO officer name, position',
                        ),
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Container(
      decoration: AppTheme.dashSurfaceCard(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editorHeaderBar(context, ro),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _vacancyInfoCard(context, ro),
                const SizedBox(height: 24),
                _applicantsSectionHeader(context, ro),
                const SizedBox(height: 12),
                if (_formPageCount > 1) ...[
                  _formPagePill(context),
                  const SizedBox(height: 12),
                ],
                _applicantsTable(context, ro),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 640;
                    final prepared = _preparedByCard(context, ro);
                    final checked = _checkedByCard(context, ro);
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: prepared),
                          const SizedBox(width: 16),
                          Expanded(child: checked),
                        ],
                      );
                    }
                    return Column(
                      children: [prepared, const SizedBox(height: 16), checked],
                    );
                  },
                ),
                if (ro) ...[
                  const SizedBox(height: 16),
                  if (widget.entry.createdAt != null)
                    Text(
                      'Created: ${widget.entry.createdAt!.toLocal()}',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  if (widget.entry.updatedAt != null)
                    Text(
                      'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Values collected by [_ApplicantDialog] for one applicant row.
class _ApplicantDialogResult {
  const _ApplicantDialogResult({
    required this.name,
    required this.course,
    required this.address,
    required this.sex,
    required this.age,
    required this.civilStatus,
    required this.remark,
  });

  final String name;
  final String course;
  final String address;
  final String sex;
  final String age;
  final String civilStatus;
  final String remark;
}

/// Modal used by the Applicants section for both "Add Applicant" and "Edit Applicant".
class _ApplicantDialog extends StatefulWidget {
  const _ApplicantDialog({required this.isEditing, this.initial});

  final bool isEditing;
  final _ApplicantDialogResult? initial;

  @override
  State<_ApplicantDialog> createState() => _ApplicantDialogState();
}

class _ApplicantDialogState extends State<_ApplicantDialog> {
  static const _sexOptions = ['Male', 'Female'];
  static const _civilStatusOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
  ];

  final _formKey = GlobalKey<FormState>();
  final _addressFormKey = GlobalKey<StructuredAddressFormState>();
  late TextEditingController _name;
  late TextEditingController _course;
  late TextEditingController _street;
  late TextEditingController _age;
  late TextEditingController _remark;
  String? _sex;
  String? _civilStatus;
  String? _initialRawAddress;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _course = TextEditingController(text: i?.course ?? '');
    _street = TextEditingController();
    _age = TextEditingController(text: i?.age ?? '');
    _remark = TextEditingController(text: i?.remark ?? '');
    _sex = _sexOptions.contains(i?.sex) ? i!.sex : null;
    _civilStatus = _civilStatusOptions.contains(i?.civilStatus)
        ? i!.civilStatus
        : null;
    _initialRawAddress = i?.address;
  }

  @override
  void dispose() {
    _name.dispose();
    _course.dispose();
    _street.dispose();
    _age.dispose();
    _remark.dispose();
    super.dispose();
  }

  InputDecoration _fieldDec(String hint) =>
      AppTheme.dashInputDecoration(context, labelText: hint);

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final encoded =
        _addressFormKey.currentState?.composeEncoded() ??
        _street.text.trim();
    Navigator.of(context).pop(
      _ApplicantDialogResult(
        name: _name.text.trim(),
        course: _course.text.trim(),
        address: encoded,
        sex: _sex ?? '',
        age: _age.text.trim(),
        civilStatus: _civilStatus ?? '',
        remark: _remark.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final dialogH = (screenH * 0.88).clamp(480.0, 720.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 640,
        height: dialogH,
        child: Material(
          color: panel,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          elevation: 10,
          shadowColor: Colors.black26,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.isEditing
                              ? Icons.edit_outlined
                              : Icons.person_add_alt_1_rounded,
                          size: 20,
                          color: AppTheme.primaryNavy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isEditing
                                  ? 'Edit Applicant'
                                  : 'Add Applicant',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Enter applicant details for this profile.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: secondary),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: hairline),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PERSONAL INFORMATION',
                          style: AppTheme.dashSectionTitle(context),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth > 480;
                            final nameField = TextFormField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              decoration: AppTheme.dashInputDecoration(
                                context,
                                labelText: 'Full Name',
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            );
                            final courseField = TextFormField(
                              controller: _course,
                              decoration: AppTheme.dashInputDecoration(
                                context,
                                labelText: 'Course / Degree',
                              ),
                            );
                            if (!wide) {
                              return Column(
                                children: [
                                  nameField,
                                  const SizedBox(height: 12),
                                  courseField,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: nameField),
                                const SizedBox(width: 12),
                                Expanded(child: courseField),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth > 480;
                            final sexField = DropdownButtonFormField<String>(
                              initialValue: _sex,
                              decoration: AppTheme.dashInputDecoration(
                                context,
                                labelText: 'Sex',
                              ),
                              items: _sexOptions
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => _sex = v),
                            );
                            final ageField = TextFormField(
                              controller: _age,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: AppTheme.dashInputDecoration(
                                context,
                                labelText: 'Age',
                              ),
                            );
                            final civilField =
                                DropdownButtonFormField<String>(
                                  initialValue: _civilStatus,
                                  decoration: AppTheme.dashInputDecoration(
                                    context,
                                    labelText: 'Civil Status',
                                  ),
                                  items: _civilStatusOptions
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _civilStatus = v),
                                );
                            if (!wide) {
                              return Column(
                                children: [
                                  sexField,
                                  const SizedBox(height: 12),
                                  ageField,
                                  const SizedBox(height: 12),
                                  civilField,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: sexField),
                                const SizedBox(width: 12),
                                Expanded(child: ageField),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: civilField),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _remark,
                          minLines: 1,
                          maxLines: 2,
                          decoration: AppTheme.dashInputDecoration(
                            context,
                            labelText: 'Remark / Disability (optional)',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.dashMutedSurfaceOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: hairline),
                          ),
                          child: StructuredAddressForm(
                            key: _addressFormKey,
                            streetController: _street,
                            initialRawAddress: _initialRawAddress,
                            inputDecoration: _fieldDec,
                            sectionLabel: 'ADDRESS',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: hairline),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        icon: Icon(
                          widget.isEditing
                              ? Icons.check_rounded
                              : Icons.person_add_alt_1_rounded,
                          size: 18,
                        ),
                        label: Text(
                          widget.isEditing ? 'Save Changes' : 'Add Applicant',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplicantsProfileList extends StatelessWidget {
  const _ApplicantsProfileList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<ApplicantsProfileEntry> entries;
  final void Function(ApplicantsProfileEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ApplicantsProfileEntry) onPrint;
  final Future<void> Function(ApplicantsProfileEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Position applied for', flex: 2.8),
      RspRecordsColumn('Posting date', flex: 1.4),
      RspRecordsColumn('Applicants', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(
                context,
                e.positionAppliedFor ?? '',
                bold: true,
              ),
              rspRecordsTextCell(context, e.dateOfPosting ?? ''),
              rspRecordsTextCell(
                context,
                '${e.applicants.length}',
                align: TextAlign.center,
                bold: true,
              ),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Applicants profile',
                  subtitle: e.positionAppliedFor ?? '',
                  previewBuilder: () => _ApplicantsProfileFormEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 1000,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete applicants profile?',
              ),
            ],
          )
          .toList(),
    );
  }
}

class _RspSelectionLineupSection extends StatefulWidget {
  const _RspSelectionLineupSection();

  @override
  State<_RspSelectionLineupSection> createState() =>
      _RspSelectionLineupSectionState();
}

class _RspSelectionLineupSectionState
    extends State<_RspSelectionLineupSection> {
  List<SelectionLineupEntry> _entries = [];
  bool _loading = true;
  SelectionLineupEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await SelectionLineupRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _startNew() => setState(() => _editing = const SelectionLineupEntry());
  void _edit(SelectionLineupEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(SelectionLineupEntry entry) async {
    try {
      if (entry.id == null) {
        await SelectionLineupRepo.instance.insert(entry);
      } else {
        await SelectionLineupRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selection line-up saved.')),
        );
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
      }
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await SelectionLineupRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printSl(SelectionLineupEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildSelectionLineupPdf(entry),
        filename: 'Selection_Lineup.pdf',
        format: FormPdf.pageLetterLandscape,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadSl(SelectionLineupEntry entry) async {
    try {
      final doc = await FormPdf.buildSelectionLineupPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Selection_Lineup.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved selection line-ups',
      emptyMessage: 'No line-ups yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.vacantPosition?.trim().isNotEmpty == true
            ? e.vacantPosition!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle: '${e.date ?? "â€”"} Â· ${e.applicants.length} applicant(s)',
          detailDialogTitle: 'Selection line-up â€” $pos',
          previewContentWidth: 1000,
          previewBuilder: () => _SelectionLineupEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printSl(e),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RSP',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            Text(
              'Selection Line-Up',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Selection Line-up',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage the vacant position, item no., and applicant list for this line-up. Printing keeps the official Selection Line-Up format.',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _SelectionLineupEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printSl,
            onDownloadPdf: _downloadSl,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add line-up'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _loading ? null : _openSavedRecordsBrowser,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
              label: const Text('View records'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          const RspFormEmptyState(
            message: 'No selection line-ups yet. Tap "Add line-up" to add one.',
            icon: Icons.list_alt_rounded,
          )
        else
          _SelectionLineupList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printSl,
            onDownloadPdf: _downloadSl,
          ),
      ],
    );
  }
}

class _SelectionLineupEditor extends StatefulWidget {
  const _SelectionLineupEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final SelectionLineupEntry entry;
  final bool readOnly;
  final void Function(SelectionLineupEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(SelectionLineupEntry) onPrint;
  final Future<void> Function(SelectionLineupEntry) onDownloadPdf;

  @override
  State<_SelectionLineupEditor> createState() => _SelectionLineupEditorState();
}

class _SelectionLineupEditorState extends State<_SelectionLineupEditor> {
  late TextEditingController _date;
  late TextEditingController _agency;
  late TextEditingController _position;
  late TextEditingController _itemNo;
  late TextEditingController _preparedName;
  late TextEditingController _preparedTitle;
  late TextEditingController _searchCtrl;
  late List<Map<String, TextEditingController>> _rows;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _date = TextEditingController(text: e.date ?? '');
    _agency = TextEditingController(text: e.nameOfAgencyOffice ?? '');
    _position = TextEditingController(text: e.vacantPosition ?? '');
    _itemNo = TextEditingController(text: e.itemNo ?? '');
    _preparedName = TextEditingController(text: e.preparedByName ?? '');
    _preparedTitle = TextEditingController(text: e.preparedByTitle ?? '');
    _searchCtrl = TextEditingController();
    _rows = e.applicants.isEmpty
        ? <Map<String, TextEditingController>>[]
        : e.applicants
              .map(
                (a) => _slRow(
                  a.name ?? '',
                  a.education ?? '',
                  a.experience ?? '',
                  a.training ?? '',
                  a.eligibility ?? '',
                ),
              )
              .toList();
    _position.addListener(_onTitleFieldChanged);
  }

  void _onTitleFieldChanged() => setState(() {});

  Map<String, TextEditingController> _slRow(
    String name,
    String edu,
    String exp,
    String train,
    String elig,
  ) {
    return {
      'name': TextEditingController(text: name),
      'education': TextEditingController(text: edu),
      'experience': TextEditingController(text: exp),
      'training': TextEditingController(text: train),
      'eligibility': TextEditingController(text: elig),
    };
  }

  @override
  void dispose() {
    _position.removeListener(_onTitleFieldChanged);
    _date.dispose();
    _agency.dispose();
    _position.dispose();
    _itemNo.dispose();
    _preparedName.dispose();
    _preparedTitle.dispose();
    _searchCtrl.dispose();
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  static String _formatPickedDate(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickDate() async {
    if (widget.readOnly) return;
    final now = DateTime.now();
    final parsed = DateTime.tryParse(_date.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      helpText: 'Select date',
    );
    if (picked == null || !mounted) return;
    setState(() => _date.text = _formatPickedDate(picked));
  }

  Future<void> _pickVacantPosition() async {
    if (widget.readOnly) return;
    try {
      final announcement = await JobVacancyAnnouncementRepo.instance.fetch();
      final positions = <String>[];
      for (final v in announcement.vacancies) {
        final key = v.positionKey?.trim();
        if (key != null && key.isNotEmpty && !positions.contains(key)) {
          positions.add(key);
        }
      }
      if (!mounted) return;
      if (positions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No job vacancies found to select from.'),
          ),
        );
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final primary = AppTheme.dashTextPrimaryOf(ctx);
          final secondary = AppTheme.dashTextSecondaryOf(ctx);
          final panel = AppTheme.dashPanelOf(ctx);
          final hairline = AppTheme.dashHairlineOf(ctx);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 28,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 480),
              child: Material(
                color: panel,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                elevation: 10,
                shadowColor: Colors.black26,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select vacant position',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: primary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: Icon(Icons.close_rounded, color: secondary),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: positions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = positions[i];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(ctx).pop(p),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.dashMutedSurfaceOf(ctx),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: hairline),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: primary,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (selected != null && mounted) {
        setState(() => _position.text = selected);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load job vacancies.')),
      );
    }
  }

  Future<void> _openAddApplicantDialog() async {
    if (widget.readOnly) return;
    final result = await showDialog<_SlApplicantDialogResult>(
      context: context,
      builder: (_) => const _SlApplicantDialog(isEditing: false),
    );
    if (result == null || !mounted) return;
    setState(() {
      _rows.add(
        _slRow(
          result.name,
          result.education,
          result.experience,
          result.training,
          result.eligibility,
        ),
      );
    });
  }

  Future<void> _openEditApplicantDialog(int index) async {
    if (widget.readOnly) return;
    final row = _rows[index];
    final initial = _SlApplicantDialogResult(
      name: row['name']!.text,
      education: row['education']!.text,
      experience: row['experience']!.text,
      training: row['training']!.text,
      eligibility: row['eligibility']!.text,
    );
    final result = await showDialog<_SlApplicantDialogResult>(
      context: context,
      builder: (_) => _SlApplicantDialog(isEditing: true, initial: initial),
    );
    if (result == null || !mounted) return;
    setState(() {
      row['name']!.text = result.name;
      row['education']!.text = result.education;
      row['experience']!.text = result.experience;
      row['training']!.text = result.training;
      row['eligibility']!.text = result.eligibility;
    });
  }

  void _removeRow(int i) {
    if (widget.readOnly) return;
    if (i < 0 || i >= _rows.length) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  SelectionLineupEntry _buildCurrentEntry() {
    final applicants = _rows
        .map(
          (r) => SelectionLineupApplicant(
            name: r['name']!.text.trim().isEmpty
                ? null
                : r['name']!.text.trim(),
            education: r['education']!.text.trim().isEmpty
                ? null
                : r['education']!.text.trim(),
            experience: r['experience']!.text.trim().isEmpty
                ? null
                : r['experience']!.text.trim(),
            training: r['training']!.text.trim().isEmpty
                ? null
                : r['training']!.text.trim(),
            eligibility: r['eligibility']!.text.trim().isEmpty
                ? null
                : r['eligibility']!.text.trim(),
          ),
        )
        .toList();
    return SelectionLineupEntry(
      id: widget.entry.id,
      date: _date.text.trim().isEmpty ? null : _date.text.trim(),
      nameOfAgencyOffice: _agency.text.trim().isEmpty
          ? null
          : _agency.text.trim(),
      vacantPosition: _position.text.trim().isEmpty
          ? null
          : _position.text.trim(),
      itemNo: _itemNo.text.trim().isEmpty ? null : _itemNo.text.trim(),
      applicants: applicants,
      preparedByName: _preparedName.text.trim().isEmpty
          ? null
          : _preparedName.text.trim(),
      preparedByTitle: _preparedTitle.text.trim().isEmpty
          ? null
          : _preparedTitle.text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerBar(context, ro),
          Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _vacancyInfoCard(context, ro),
                const SizedBox(height: 24),
                _applicantsSectionHeader(context, ro),
                const SizedBox(height: 12),
                _applicantsTable(context, ro),
                const SizedBox(height: 24),
                _preparedByCard(context, ro),
                if (ro) ...[
                  const SizedBox(height: 16),
                  if (widget.entry.createdAt != null)
                    Text(
                      'Created: ${widget.entry.createdAt!.toLocal()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  if (widget.entry.updatedAt != null)
                    Text(
                      'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBar(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final position = _position.text.trim();
    final itemNo = _itemNo.text.trim();
    final title = position.isEmpty ? 'New Selection Line-Up' : position;
    final statusLabel = ro
        ? 'Read-only preview'
        : (widget.entry.id == null ? 'Draft' : 'Saved');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statusChip(statusLabel),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  itemNo.isEmpty
                      ? 'Vacant position, item no., and applicant list.'
                      : 'Item No. $itemNo',
                  style: TextStyle(fontSize: 12.5, color: secondary),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Print',
                style: rspLdRecordIconButtonStyle(),
                onPressed: () => widget.onPrint(_buildCurrentEntry()),
                icon: const Icon(Icons.print_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Download PDF',
                style: rspLdRecordIconButtonStyle(),
                onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              ),
              if (!ro) ...[
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label) {
    final Color color = label == 'Draft'
        ? const Color(0xFFB26A00)
        : label == 'Read-only preview'
        ? Colors.blueGrey
        : const Color(0xFF2E7D32);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _vacancyInfoCard(BuildContext context, bool ro) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VACANCY INFORMATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 640;
              final agencyField = TextFormField(
                controller: _agency,
                readOnly: ro,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'Agency / Office',
                ),
              );
              final dateField = TextFormField(
                controller: _date,
                readOnly: ro,
                onTap: ro ? null : _pickDate,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'Date',
                  suffixIcon: ro
                      ? null
                      : IconButton(
                          tooltip: 'Pick a date',
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 20,
                          ),
                          onPressed: _pickDate,
                        ),
                ),
              );
              final positionField = TextFormField(
                controller: _position,
                readOnly: ro,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'Vacant Position',
                  suffixIcon: ro
                      ? null
                      : IconButton(
                          tooltip: 'Pick from job vacancies',
                          icon: const Icon(
                            Icons.playlist_add_check_rounded,
                            size: 20,
                          ),
                          onPressed: _pickVacantPosition,
                        ),
                ),
              );
              final itemNoField = TextFormField(
                controller: _itemNo,
                readOnly: ro,
                decoration: AppTheme.dashInputDecoration(
                  context,
                  labelText: 'Item No.',
                ),
              );

              Widget pair(Widget a, Widget b) {
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: a),
                      const SizedBox(width: 14),
                      Expanded(child: b),
                    ],
                  );
                }
                return Column(
                  children: [a, const SizedBox(height: 14), b],
                );
              }

              return Column(
                children: [
                  pair(agencyField, dateField),
                  const SizedBox(height: 14),
                  pair(positionField, itemNoField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _applicantsSectionHeader(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      spacing: 16,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Applicants',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_rows.length}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryNavy,
                ),
              ),
            ),
          ],
        ),
        if (!ro)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim().toLowerCase()),
                  decoration: AppTheme.dashInputDecoration(
                    context,
                    hintText: 'Search applicants...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _openAddApplicantDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Applicant'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _applicantsTable(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final q = _searchQuery;
    final visible = <int>[];
    for (var i = 0; i < _rows.length; i++) {
      if (q.isEmpty) {
        visible.add(i);
        continue;
      }
      final r = _rows[i];
      final hay = [
        r['name']!.text,
        r['education']!.text,
        r['experience']!.text,
        r['training']!.text,
        r['eligibility']!.text,
      ].join(' ').toLowerCase();
      if (hay.contains(q)) visible.add(i);
    }

    if (_rows.isEmpty) {
      return _emptyBox(
        context,
        'No applicants yet. Tap "Add Applicant" to add one.',
      );
    }
    if (visible.isEmpty) {
      return _emptyBox(context, 'No applicants match your search.');
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              AppTheme.dashMutedSurfaceOf(context),
            ),
            dataRowMinHeight: 52,
            dataRowMaxHeight: 64,
            columnSpacing: 20,
            horizontalMargin: 16,
            headingTextStyle: TextStyle(
              color: secondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
            dataTextStyle: TextStyle(color: primary, fontSize: 13),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('APPLICANT')),
              DataColumn(label: Text('EDUCATION')),
              DataColumn(label: Text('EXPERIENCE')),
              DataColumn(label: Text('TRAINING')),
              DataColumn(label: Text('ELIGIBILITY')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: visible.map((i) {
              final r = _rows[i];
              final name = r['name']!.text.trim();
              return DataRow(
                cells: [
                  DataCell(
                    Text('${i + 1}', style: TextStyle(color: secondary)),
                  ),
                  DataCell(
                    Text(
                      name.isEmpty ? '\u2014' : name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(Text(_dash(r['education']!.text))),
                  DataCell(Text(_dash(r['experience']!.text))),
                  DataCell(Text(_dash(r['training']!.text))),
                  DataCell(Text(_dash(r['eligibility']!.text))),
                  DataCell(
                    ro
                        ? const SizedBox(width: 8)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                style: rspLdRecordIconButtonStyle(),
                                onPressed: () => _openEditApplicantDialog(i),
                                icon: const Icon(
                                  Icons.edit_rounded,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Remove',
                                style: rspLdRecordIconButtonStyle(
                                  foreground: const Color(0xFFC62828),
                                ),
                                onPressed: () => _removeRow(i),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _emptyBox(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(
        message,
        style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
      ),
    );
  }

  static String _dash(String v) => v.trim().isEmpty ? '\u2014' : v.trim();

  /// Blank strip with a bottom rule, sized for a physical pen signature above
  /// the printed name (mirrors the space added in the PDF output).
  Widget _signatureSpace(BuildContext context) {
    return Container(
      height: 30,
      margin: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
      ),
    );
  }

  Widget _preparedByCard(BuildContext context, bool ro) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.14),
            child: const Icon(
              Icons.badge_outlined,
              size: 18,
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREPARED BY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                _signatureSpace(context),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 420;
                    final nameField = ro
                        ? Text(
                            _preparedName.text.trim().isEmpty
                                ? '\u2014'
                                : _preparedName.text.trim(),
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : TextFormField(
                            controller: _preparedName,
                            decoration: AppTheme.dashInputDecoration(
                              context,
                              hintText: 'Full name',
                            ),
                          );
                    final titleField = ro
                        ? Text(
                            _preparedTitle.text.trim().isEmpty
                                ? '\u2014'
                                : _preparedTitle.text.trim(),
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                            ),
                          )
                        : TextFormField(
                            controller: _preparedTitle,
                            decoration: AppTheme.dashInputDecoration(
                              context,
                              hintText: 'Position / title',
                            ),
                          );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: nameField),
                          const SizedBox(width: 12),
                          Expanded(child: titleField),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        nameField,
                        const SizedBox(height: 10),
                        titleField,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlApplicantDialogResult {
  const _SlApplicantDialogResult({
    required this.name,
    required this.education,
    required this.experience,
    required this.training,
    required this.eligibility,
  });

  final String name;
  final String education;
  final String experience;
  final String training;
  final String eligibility;
}

class _SlApplicantDialog extends StatefulWidget {
  const _SlApplicantDialog({required this.isEditing, this.initial});

  final bool isEditing;
  final _SlApplicantDialogResult? initial;

  @override
  State<_SlApplicantDialog> createState() => _SlApplicantDialogState();
}

class _SlApplicantDialogState extends State<_SlApplicantDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _education;
  late TextEditingController _experience;
  late TextEditingController _training;
  late TextEditingController _eligibility;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(text: i?.name ?? '');
    _education = TextEditingController(text: i?.education ?? '');
    _experience = TextEditingController(text: i?.experience ?? '');
    _training = TextEditingController(text: i?.training ?? '');
    _eligibility = TextEditingController(text: i?.eligibility ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _education.dispose();
    _experience.dispose();
    _training.dispose();
    _eligibility.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _SlApplicantDialogResult(
        name: _name.text.trim(),
        education: _education.text.trim(),
        experience: _experience.text.trim(),
        training: _training.text.trim(),
        eligibility: _eligibility.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: AppTheme.dashPanelOf(context),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          elevation: 10,
          shadowColor: Colors.black26,
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.isEditing
                              ? 'Edit Applicant'
                              : 'Add Applicant',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: secondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Applicant Name',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _education,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Education',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _experience,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Experience',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _training,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Training',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _eligibility,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Eligibility',
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                        ),
                        child: Text(
                          widget.isEditing ? 'Save Changes' : 'Add Applicant',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionLineupList extends StatelessWidget {
  const _SelectionLineupList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<SelectionLineupEntry> entries;
  final void Function(SelectionLineupEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(SelectionLineupEntry) onPrint;
  final Future<void> Function(SelectionLineupEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Vacant position', flex: 2.6),
      RspRecordsColumn('Date', flex: 1.4),
      RspRecordsColumn('Applicants', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, e.vacantPosition ?? '', bold: true),
              rspRecordsTextCell(context, e.date ?? ''),
              rspRecordsTextCell(
                context,
                '${e.applicants.length}',
                align: TextAlign.center,
                bold: true,
              ),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Selection line-up',
                  subtitle: e.vacantPosition ?? '',
                  previewBuilder: () => _SelectionLineupEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 1000,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete line-up?',
              ),
            ],
          )
          .toList(),
    );
  }
}

/// RSP: Turn-Around Time Ã¢â‚¬â€ position, office, dates, applicant tracking table. Form only, no pre-filled names.

class _RspTurnAroundTimeSection extends StatefulWidget {
  const _RspTurnAroundTimeSection();

  @override
  State<_RspTurnAroundTimeSection> createState() =>
      _RspTurnAroundTimeSectionState();
}

class _RspTurnAroundTimeSectionState extends State<_RspTurnAroundTimeSection> {
  List<TurnAroundTimeEntry> _entries = [];
  bool _loading = true;
  TurnAroundTimeEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await TurnAroundTimeRepo.instance.list();
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _startNew() => setState(() => _editing = const TurnAroundTimeEntry());
  void _edit(TurnAroundTimeEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(TurnAroundTimeEntry entry) async {
    try {
      if (entry.id == null) {
        await TurnAroundTimeRepo.instance.insert(entry);
      } else {
        await TurnAroundTimeRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn-around time saved.')),
        );
        setState(() => _editing = null);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save. ${userFacingApiError(e)}')),
        );
      }
    }
  }

  Future<void> _onDelete(String id) async {
    try {
      await TurnAroundTimeRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Deleted.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _printTat(TurnAroundTimeEntry entry) async {
    try {
      await FormPdf.printForm(
        context: context,
        buildDocument: () => FormPdf.buildTurnAroundTimePdf(entry),
        filename: 'Turn_Around_Time.pdf',
        format: FormPdf.pageLongLandscape,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (_) {}
  }

  Future<void> _downloadTat(TurnAroundTimeEntry entry) async {
    try {
      final doc = await FormPdf.buildTurnAroundTimePdf(entry);
      await FormPdf.sharePdf(doc, name: 'Turn_Around_Time.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF ready to save or share.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved turn-around time records',
      emptyMessage: 'No entries yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.position?.trim().isNotEmpty == true
            ? e.position!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle:
              '${e.office ?? "â€”"} Â· ${e.applicants.length} applicant(s)',
          detailDialogTitle: 'Turn-around time â€” $pos',
          previewContentWidth: 1200,
          previewBuilder: () => _TurnAroundTimeEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printTat(e),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Turn-Around Time',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Position, office, dates, and applicant tracking (assessment, exam, deliberation, job offer, assumption, cost). Form onlyÃ¢â‚¬â€no pre-filled names.',
          style: TextStyle(
            color: AppTheme.dashTextSecondaryOf(context),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _TurnAroundTimeEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printTat,
            onDownloadPdf: _downloadTat,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add turn-around time'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _loading ? null : _openSavedRecordsBrowser,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
              label: const Text('View records'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          const RspFormEmptyState(
            message:
                'No turn-around time entries yet. Tap "Add turn-around time" to add one.',
            icon: Icons.schedule_rounded,
          )
        else
          _TurnAroundTimeList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printTat,
            onDownloadPdf: _downloadTat,
          ),
      ],
    );
  }
}

class _TurnAroundTimeEditor extends StatefulWidget {
  const _TurnAroundTimeEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final TurnAroundTimeEntry entry;
  final bool readOnly;
  final void Function(TurnAroundTimeEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(TurnAroundTimeEntry) onPrint;
  final Future<void> Function(TurnAroundTimeEntry) onDownloadPdf;

  @override
  State<_TurnAroundTimeEditor> createState() => _TurnAroundTimeEditorState();
}

class _TurnAroundTimeEditorState extends State<_TurnAroundTimeEditor> {
  late List<TextEditingController> _header;
  late List<TextEditingController> _signatory;
  late List<Map<String, TextEditingController>> _rows;
  final ScrollController _applicantsTableHScroll = ScrollController();

  static const List<String> _rowKeys = [
    'name',
    'date_initial_assessment',
    'date_contract_exam',
    'skills_trade_exam_result',
    'date_deliberation',
    'date_job_offer',
    'acceptance_date',
    'date_assumption_to_duty',
    'no_of_days_to_fill_up',
    'overall_cost_per_hire',
  ];

  Map<String, TextEditingController> _tatRow(Map<String, String> values) {
    return Map.fromEntries(
      _rowKeys.map(
        (k) => MapEntry(k, TextEditingController(text: values[k] ?? '')),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _header = [
      TextEditingController(text: e.position ?? ''),
      TextEditingController(text: e.office ?? ''),
      TextEditingController(text: e.noOfVacantPosition ?? ''),
      TextEditingController(text: e.dateOfPublication ?? ''),
      TextEditingController(text: e.endSearch ?? ''),
      TextEditingController(text: e.qs ?? ''),
    ];
    _signatory = [
      TextEditingController(text: e.preparedByName ?? ''),
      TextEditingController(text: e.preparedByTitle ?? ''),
      TextEditingController(text: e.notedByName ?? ''),
      TextEditingController(text: e.notedByTitle ?? ''),
    ];
    _rows = e.applicants.isEmpty
        ? [_tatRow({})]
        : e.applicants
              .map(
                (a) => _tatRow({
                  'name': a.name ?? '',
                  'date_initial_assessment': a.dateInitialAssessment ?? '',
                  'date_contract_exam': a.dateContractExam ?? '',
                  'skills_trade_exam_result': a.skillsTradeExamResult ?? '',
                  'date_deliberation': a.dateDeliberation ?? '',
                  'date_job_offer': a.dateJobOffer ?? '',
                  'acceptance_date': a.acceptanceDate ?? '',
                  'date_assumption_to_duty': a.dateAssumptionToDuty ?? '',
                  'no_of_days_to_fill_up': a.noOfDaysToFillUp ?? '',
                  'overall_cost_per_hire': a.overallCostPerHire ?? '',
                }),
              )
              .toList();
  }

  @override
  void dispose() {
    for (final c in _header) {
      c.dispose();
    }
    for (final c in _signatory) {
      c.dispose();
    }
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_tatRow({})));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  TurnAroundTimeEntry _buildCurrentEntry() {
    final applicants = _rows
        .map(
          (r) => TurnAroundTimeApplicant(
            name: r['name']!.text.trim().isEmpty
                ? null
                : r['name']!.text.trim(),
            dateInitialAssessment:
                r['date_initial_assessment']!.text.trim().isEmpty
                ? null
                : r['date_initial_assessment']!.text.trim(),
            dateContractExam: r['date_contract_exam']!.text.trim().isEmpty
                ? null
                : r['date_contract_exam']!.text.trim(),
            skillsTradeExamResult:
                r['skills_trade_exam_result']!.text.trim().isEmpty
                ? null
                : r['skills_trade_exam_result']!.text.trim(),
            dateDeliberation: r['date_deliberation']!.text.trim().isEmpty
                ? null
                : r['date_deliberation']!.text.trim(),
            dateJobOffer: r['date_job_offer']!.text.trim().isEmpty
                ? null
                : r['date_job_offer']!.text.trim(),
            acceptanceDate: r['acceptance_date']!.text.trim().isEmpty
                ? null
                : r['acceptance_date']!.text.trim(),
            dateAssumptionToDuty:
                r['date_assumption_to_duty']!.text.trim().isEmpty
                ? null
                : r['date_assumption_to_duty']!.text.trim(),
            noOfDaysToFillUp: r['no_of_days_to_fill_up']!.text.trim().isEmpty
                ? null
                : r['no_of_days_to_fill_up']!.text.trim(),
            overallCostPerHire: r['overall_cost_per_hire']!.text.trim().isEmpty
                ? null
                : r['overall_cost_per_hire']!.text.trim(),
          ),
        )
        .toList();
    return TurnAroundTimeEntry(
      id: widget.entry.id,
      position: _header[0].text.trim().isEmpty ? null : _header[0].text.trim(),
      office: _header[1].text.trim().isEmpty ? null : _header[1].text.trim(),
      noOfVacantPosition: _header[2].text.trim().isEmpty
          ? null
          : _header[2].text.trim(),
      dateOfPublication: _header[3].text.trim().isEmpty
          ? null
          : _header[3].text.trim(),
      endSearch: _header[4].text.trim().isEmpty ? null : _header[4].text.trim(),
      qs: _header[5].text.trim().isEmpty ? null : _header[5].text.trim(),
      applicants: applicants,
      preparedByName: _signatory[0].text.trim().isEmpty
          ? null
          : _signatory[0].text.trim(),
      preparedByTitle: _signatory[1].text.trim().isEmpty
          ? null
          : _signatory[1].text.trim(),
      notedByName: _signatory[2].text.trim().isEmpty
          ? null
          : _signatory[2].text.trim(),
      notedByTitle: _signatory[3].text.trim().isEmpty
          ? null
          : _signatory[3].text.trim(),
      createdAt: widget.entry.createdAt,
      updatedAt: widget.entry.updatedAt,
    );
  }

  void _save() {
    if (widget.readOnly) return;
    widget.onSave(_buildCurrentEntry());
  }

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    const labels = [
      'Name of Applicant',
      'Date of Initial Assesment',
      'Date of Contract for trade and written exam',
      'Skills Trade/ Exam Result',
      'Date of Deliberation',
      'Date of Job Offer',
      'Acceptance date of Job Offer',
      'Date of Assumption to Duty',
      'No. of Days to Fill-Up Position',
      'Overall Cost per hire',
    ];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const RspFormHeaderBoard(
              formTitle: 'TURN-AROUND TIME',
              officeName: 'MGO-Plaridel, Misamis Occidental',
            ),
            Center(
              child: SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Position:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _header[0],
                        readOnly: ro,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                    Text(
                      'Office:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _header[1],
                        readOnly: ro,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                    Text(
                      'No. of Vacant Position:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _header[2],
                        readOnly: ro,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                    Text(
                      'Date of Publication:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _header[3],
                        readOnly: ro,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                    Text(
                      'End Search:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _header[4],
                        readOnly: ro,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                    Text(
                      'Q.S.:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.dashTextPrimaryOf(context),
                        fontSize: 13,
                      ),
                    ),
                    RspSpacedOutlineField(
                      child: TextFormField(
                        controller: _header[5],
                        readOnly: ro,
                        decoration: rspUnderlinedField(''),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Applicants (turn-around tracking)',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!ro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add applicant'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Scroll horizontally to see all columns.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.dashTextSecondaryOf(context),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  child: ScrollConfiguration(
                    behavior: const MaterialScrollBehavior().copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: Scrollbar(
                      controller: _applicantsTableHScroll,
                      thumbVisibility: true,
                      trackVisibility: kIsWeb,
                      thickness: kIsWeb ? 8 : null,
                      radius: const Radius.circular(4),
                      child: SingleChildScrollView(
                        controller: _applicantsTableHScroll,
                        scrollDirection: Axis.horizontal,
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        child: DataTable(
                          horizontalMargin: 12,
                          columnSpacing: 16,
                          columns: [
                            for (var i = 0; i < _rowKeys.length; i++)
                              DataColumn(
                                label: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 100,
                                    maxWidth: 140,
                                  ),
                                  child: Text(
                                    labels[i],
                                    style: const TextStyle(fontSize: 11),
                                    softWrap: true,
                                    maxLines: 3,
                                    overflow: TextOverflow.fade,
                                  ),
                                ),
                              ),
                            const DataColumn(label: Text('')),
                          ],
                          rows: List.generate(_rows.length, (i) {
                            final r = _rows[i];
                            return DataRow(
                              cells: [
                                for (final k in _rowKeys)
                                  DataCell(
                                    SizedBox(
                                      width: 104,
                                      child: TextFormField(
                                        controller: r[k],
                                        readOnly: ro,
                                        decoration: rspTableCellField(),
                                      ),
                                    ),
                                  ),
                                DataCell(
                                  ro
                                      ? const SizedBox(width: 40)
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 20,
                                          ),
                                          onPressed: _rows.length > 1
                                              ? () => _removeRow(i)
                                              : null,
                                        ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Prepared by / Noted by',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            _f(_signatory[0], 'Prepared by (name)'),
            _f(_signatory[1], 'Prepared by (title)'),
            _f(_signatory[2], 'Noted by (name)'),
            _f(_signatory[3], 'Noted by (title)'),
            const SizedBox(height: 16),
            if (!ro) ...[
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => widget.onPrint(_buildCurrentEntry()),
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Print',
                  ),
                  IconButton(
                    onPressed: () => widget.onDownloadPdf(_buildCurrentEntry()),
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Download PDF',
                  ),
                ],
              ),
            ] else ...[
              if (widget.entry.createdAt != null)
                Text(
                  'Created: ${widget.entry.createdAt!.toLocal()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _f(TextEditingController c, String label) {
    return RspSpacedOutlineField(
      child: TextFormField(
        controller: c,
        readOnly: widget.readOnly,
        decoration: rspUnderlinedField(label),
      ),
    );
  }
}

class _TurnAroundTimeList extends StatelessWidget {
  const _TurnAroundTimeList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<TurnAroundTimeEntry> entries;
  final void Function(TurnAroundTimeEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(TurnAroundTimeEntry) onPrint;
  final Future<void> Function(TurnAroundTimeEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    const columns = [
      RspRecordsColumn('Position', flex: 2.4),
      RspRecordsColumn('Office', flex: 2),
      RspRecordsColumn('Applicants', flex: 1, align: TextAlign.center),
      RspRecordsColumn('Actions', flex: 2.4, align: TextAlign.center),
    ];
    return RspRecordsListTable(
      columns: columns,
      rows: entries
          .map(
            (e) => [
              rspRecordsTextCell(context, e.position ?? '', bold: true),
              rspRecordsTextCell(context, e.office ?? ''),
              rspRecordsTextCell(
                context,
                '${e.applicants.length}',
                align: TextAlign.center,
                bold: true,
              ),
              RspRecordsCrudActions(
                onView: () => showReadOnlySavedEntryDialog(
                  context,
                  title: 'Turn-around time',
                  subtitle: '${e.position ?? ''} Â· ${e.office ?? ''}',
                  previewBuilder: () => _TurnAroundTimeEditor(
                    readOnly: true,
                    entry: e,
                    onSave: (_) {},
                    onCancel: () {},
                    onPrint: (_) async {},
                    onDownloadPdf: (_) async {},
                  ),
                  contentWidth: 1200,
                  onPrint: () => onPrint(e),
                ),
                onEdit: () => onEdit(e),
                onPrint: () => onPrint(e),
                onDownloadPdf: () => onDownloadPdf(e),
                onDelete: () async {
                  if (e.id != null) onDelete(e.id!);
                },
                deleteDialogTitle: 'Delete entry?',
              ),
            ],
          )
          .toList(),
    );
  }
}

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
  void dispose() {
    headline.dispose();
    education.dispose();
    experience.dispose();
    training.dispose();
    closingDate.dispose();
    maxApplicants.dispose();
  }
}

/// RSP: Job Vacancies announcement form for the landing page. Supports multiple job vacancy entries.
class _RspJobVacanciesForm extends StatefulWidget {
  const _RspJobVacanciesForm();

  @override
  State<_RspJobVacanciesForm> createState() => _RspJobVacanciesFormState();
}

class _RspJobVacanciesFormState extends State<_RspJobVacanciesForm> {
  bool _loading = true;
  bool _hasVacancies = true;
  final List<_VacancyFormItem> _vacancies = [];

  /// Parallel to [_vacancies]: when false, only the header row is shown.
  final List<bool> _vacancyExpanded = [];
  bool _saving = false;
  bool _savingToggle = false;

  /// Fingerprint of vacancy entries last saved to the server (not including hiring toggle).
  String _savedVacanciesFingerprint = '';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Landing page is now open for hiring.'
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
      return h.length > 52 ? '${h.substring(0, 52)}â€¦' : h;
    }
    final parts = <String>[
      v.education.text.trim(),
      v.experience.text.trim(),
      v.training.text.trim(),
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      final joined = parts.join(' Â· ');
      return joined.length > 64 ? '${joined.substring(0, 64)}â€¦' : joined;
    }
    final m = v.maxApplicants.text.trim();
    if (m.isNotEmpty) return 'Max applicants: $m';
    return 'No headline yet â€” expand to edit';
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Vacancy entries saved. Landing page will show the updated positions.',
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

  InputDecoration _vacancyInput(
    BuildContext context, {
    required String hint,
    Widget? suffixIcon,
  }) {
    return AppTheme.dashInputDecoration(
      context,
      hintText: hint,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _vacancyFieldLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppTheme.dashTextSecondaryOf(context),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.65,
          height: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);

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
                    AppTheme.primaryNavy.withValues(alpha: 0.14),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                Icons.work_outline_rounded,
                color: AppTheme.dashIsDark(context)
                    ? AppTheme.primaryNavyLight
                    : AppTheme.primaryNavy,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Job Vacancies Announcement',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Control what appears in the Job Vacancies section on the landing page. Add multiple entries when you have more than one position.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hairline),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: muted,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _hasVacancies
                                    ? AppTheme.primaryNavy.withValues(
                                        alpha: 0.28,
                                      )
                                    : hairline,
                                width: _hasVacancies ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: panel,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: hairline),
                                  ),
                                  child: Icon(
                                    _hasVacancies
                                        ? Icons.campaign_rounded
                                        : Icons.pause_circle_outline_rounded,
                                    color: _hasVacancies
                                        ? AppTheme.primaryNavy
                                        : AppTheme.dashTextSecondaryOf(context),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Accepting applications',
                                              style: TextStyle(
                                                color:
                                                    AppTheme.dashTextPrimaryOf(
                                                      context,
                                                    ),
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: -0.15,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _hasVacancies
                                                  ? AppTheme.primaryNavy
                                                        .withValues(alpha: 0.12)
                                                  : AppTheme.dashTextSecondaryOf(
                                                      context,
                                                    ).withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _hasVacancies
                                                  ? 'Hiring'
                                                  : 'Closed',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.3,
                                                color: _hasVacancies
                                                    ? (AppTheme.dashIsDark(
                                                            context,
                                                          )
                                                          ? AppTheme
                                                                .primaryNavyLight
                                                          : AppTheme
                                                                .primaryNavy)
                                                    : AppTheme.dashTextSecondaryOf(
                                                        context,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'When ON, the landing page shows that you are hiring. When OFF, it shows no vacancies. This saves immediately.',
                                        style: TextStyle(
                                          color: AppTheme.dashTextSecondaryOf(
                                            context,
                                          ),
                                          fontSize: 13,
                                          height: 1.45,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_savingToggle)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                Switch(
                                  value: _hasVacancies,
                                  onChanged: _savingToggle
                                      ? null
                                      : _onHasVacanciesChanged,
                                  activeTrackColor: AppTheme.primaryNavy
                                      .withValues(alpha: 0.45),
                                  activeThumbColor: AppTheme.primaryNavy,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Divider(height: 1, color: hairline),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stackHeader = constraints.maxWidth < 520;
                              final headerTitle = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Job vacancy entries',
                                    style: TextStyle(
                                      color: AppTheme.dashTextPrimaryOf(
                                        context,
                                      ),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.25,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_vacancies.length}',
                                      style: TextStyle(
                                        color: AppTheme.dashIsDark(context)
                                            ? AppTheme.primaryNavyLight
                                            : AppTheme.primaryNavy,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                              final addBtn = FilledButton.icon(
                                onPressed: _addVacancy,
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text('Add new vacancy'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                              if (stackHeader) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    headerTitle,
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: addBtn,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: headerTitle),
                                  addBtn,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tap a row to expand or collapse fields. Delete is available when there is more than one entry.',
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(
                                context,
                              ).withValues(alpha: 0.9),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ...List.generate(_vacancies.length, (i) {
                            final v = _vacancies[i];
                            final expanded = i < _vacancyExpanded.length
                                ? _vacancyExpanded[i]
                                : true;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: panel,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: expanded
                                        ? AppTheme.primaryNavy.withValues(
                                            alpha: 0.22,
                                          )
                                        : hairline,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.035,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Material(
                                      color: expanded
                                          ? AppTheme.primaryNavy.withValues(
                                              alpha: 0.04,
                                            )
                                          : Colors.transparent,
                                      child: InkWell(
                                        onTap: () => setState(() {
                                          if (i < _vacancyExpanded.length) {
                                            _vacancyExpanded[i] =
                                                !_vacancyExpanded[i];
                                          }
                                        }),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            14,
                                            14,
                                            12,
                                            14,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      AppTheme.primaryNavy
                                                          .withValues(
                                                            alpha: 0.9,
                                                          ),
                                                      AppTheme.primaryNavyLight
                                                          .withValues(
                                                            alpha: 0.75,
                                                          ),
                                                    ],
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '${i + 1}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Position ${i + 1}',
                                                      style: TextStyle(
                                                        color:
                                                            AppTheme.dashTextPrimaryOf(
                                                              context,
                                                            ),
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        letterSpacing: -0.2,
                                                      ),
                                                    ),
                                                    if (!expanded) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        _vacancyEntrySummary(v),
                                                        style: TextStyle(
                                                          color:
                                                              AppTheme.dashTextSecondaryOf(
                                                                context,
                                                              ).withValues(
                                                                alpha: 0.92,
                                                              ),
                                                          fontSize: 12.5,
                                                          height: 1.4,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: panel,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: hairline,
                                                  ),
                                                ),
                                                child: Icon(
                                                  expanded
                                                      ? Icons
                                                            .expand_less_rounded
                                                      : Icons
                                                            .expand_more_rounded,
                                                  size: 22,
                                                  color:
                                                      AppTheme.dashTextSecondaryOf(
                                                        context,
                                                      ),
                                                ),
                                              ),
                                              if (_vacancies.length > 1) ...[
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  onPressed: () =>
                                                      _confirmDeleteVacancy(
                                                        context,
                                                        i,
                                                      ),
                                                  icon: Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 20,
                                                    color: Colors.red.shade700,
                                                  ),
                                                  tooltip: 'Delete',
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        AppTheme.dashIsDark(
                                                          context,
                                                        )
                                                        ? Colors.red.shade900
                                                              .withValues(
                                                                alpha: 0.35,
                                                              )
                                                        : Colors.red.shade50,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeInOut,
                                      alignment: Alignment.topCenter,
                                      child: expanded
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    14,
                                                    0,
                                                    14,
                                                    14,
                                                  ),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  18,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: muted,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: hairline,
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    _vacancyFieldLabel(
                                                      context,
                                                      'Headline',
                                                    ),
                                                    TextField(
                                                      controller: v.headline,
                                                      onChanged: (_) =>
                                                          setState(() {}),
                                                      decoration: _vacancyInput(
                                                        context,
                                                        hint:
                                                            'e.g. Now Hiring: Human Resource Assistant',
                                                      ),
                                                      maxLines: 1,
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _vacancyFieldLabel(
                                                      context,
                                                      'Education',
                                                    ),
                                                    TextField(
                                                      controller: v.education,
                                                      onChanged: (_) =>
                                                          setState(() {}),
                                                      decoration: _vacancyInput(
                                                        context,
                                                        hint:
                                                            'e.g. Bachelor\'s degree in relevant field',
                                                      ),
                                                      maxLines: 3,
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _vacancyFieldLabel(
                                                      context,
                                                      'Experience',
                                                    ),
                                                    TextField(
                                                      controller: v.experience,
                                                      onChanged: (_) =>
                                                          setState(() {}),
                                                      decoration: _vacancyInput(
                                                        context,
                                                        hint:
                                                            'e.g. 2 years in HR or local government',
                                                      ),
                                                      maxLines: 3,
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _vacancyFieldLabel(
                                                      context,
                                                      'Training',
                                                    ),
                                                    TextField(
                                                      controller: v.training,
                                                      onChanged: (_) =>
                                                          setState(() {}),
                                                      decoration: _vacancyInput(
                                                        context,
                                                        hint:
                                                            'e.g. Civil service eligibility, seminars',
                                                      ),
                                                      maxLines: 3,
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _vacancyFieldLabel(
                                                      context,
                                                      'Due date (auto-close)',
                                                    ),
                                                    Text(
                                                      'Automatically closes 15 days after the position is posted. The system will stop accepting applicants on this date.',
                                                      style: TextStyle(
                                                        color:
                                                            AppTheme.dashTextSecondaryOf(
                                                              context,
                                                            ).withValues(
                                                              alpha: 0.9,
                                                            ),
                                                        fontSize: 12,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 16,
                                                            vertical: 13,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppTheme.dashMutedSurfaceOf(
                                                              context,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              14,
                                                            ),
                                                        border: Border.all(
                                                          color:
                                                              AppTheme.dashHairlineOf(
                                                                context,
                                                              ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.event_rounded,
                                                            size: 20,
                                                            color:
                                                                AppTheme.dashTextSecondaryOf(
                                                                  context,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              v
                                                                      .closingDate
                                                                      .text
                                                                      .isNotEmpty
                                                                  ? v
                                                                        .closingDate
                                                                        .text
                                                                  : _autoCloseDate(),
                                                              style: TextStyle(
                                                                color:
                                                                    AppTheme.dashTextPrimaryOf(
                                                                      context,
                                                                    ),
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                          TextButton.icon(
                                                            onPressed: () =>
                                                                setState(() {
                                                                  v.closingDate.text =
                                                                      _autoCloseDate();
                                                                }),
                                                            icon: const Icon(
                                                              Icons
                                                                  .refresh_rounded,
                                                              size: 16,
                                                            ),
                                                            label: const Text(
                                                              'Reset',
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                            style: TextButton.styleFrom(
                                                              foregroundColor:
                                                                  AppTheme
                                                                      .primaryNavy,
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 6,
                                                                  ),
                                                              minimumSize:
                                                                  Size.zero,
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(height: 18),
                                                    _vacancyFieldLabel(
                                                      context,
                                                      'Max applicants',
                                                    ),
                                                    Text(
                                                      'Landing page shows slots in use (pipeline only). Hired (registered), declined documents, failed exam, or failed final interview do not count toward the limit.',
                                                      style: TextStyle(
                                                        color:
                                                            AppTheme.dashTextSecondaryOf(
                                                              context,
                                                            ).withValues(
                                                              alpha: 0.9,
                                                            ),
                                                        fontSize: 12,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    TextField(
                                                      controller:
                                                          v.maxApplicants,
                                                      onChanged: (_) =>
                                                          setState(() {}),
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration: _vacancyInput(
                                                        context,
                                                        hint:
                                                            'Leave blank for no limit (e.g. 50)',
                                                      ),
                                                      maxLines: 1,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : const SizedBox(
                                              width: double.infinity,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          Divider(height: 1, color: hairline),
                          const SizedBox(height: 20),
                          if (!_vacanciesDirty && !_saving) ...[
                            Text(
                              'Hiring on/off saves automatically. Use the button below only after you change positions, add vacancies, or edit vacancy details.',
                              style: TextStyle(
                                color: AppTheme.dashTextSecondaryOf(context),
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: _vacanciesDirty
                                    ? const [
                                        AppTheme.primaryNavy,
                                        AppTheme.primaryNavyLight,
                                      ]
                                    : [
                                        AppTheme.dashTextSecondaryOf(
                                          context,
                                        ).withValues(alpha: 0.35),
                                        AppTheme.dashTextSecondaryOf(
                                          context,
                                        ).withValues(alpha: 0.25),
                                      ],
                              ),
                              boxShadow: _vacanciesDirty
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryNavy.withValues(
                                          alpha: 0.28,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: (_saving || !_vacanciesDirty)
                                    ? null
                                    : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded, size: 20),
                                label: Text(
                                  _saving
                                      ? 'Saving...'
                                      : _vacanciesDirty
                                      ? 'Save vacancy entries on landing page'
                                      : 'No vacancy changes to save',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _RspMonitorView { applications, examResults }

/// RSP: Applications monitor or exam-results monitor (shared data loader).
class _RspApplicationsMonitor extends StatefulWidget {
  const _RspApplicationsMonitor({required this.view});

  final _RspMonitorView view;

  @override
  State<_RspApplicationsMonitor> createState() =>
      _RspApplicationsMonitorState();
}

class _RspApplicationsMonitorState extends State<_RspApplicationsMonitor> {
  List<RecruitmentApplication> _applications = [];
  Map<String, RecruitmentExamResult> _examResults = {};
  String? _selectedPositionFilter;
  DateTime? _selectedAppliedDate;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool _loading = true;
  bool _syncing = false;
  bool _exportingReport = false;
  String? _adminPassingApplicantId;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _scoreBreakdownVScrollController = ScrollController();

  Set<String> get _positionFilterOptions {
    final out = <String>{};
    for (final app in _applications) {
      final p = (app.positionAppliedFor ?? '').trim();
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
    return _applications.where((app) {
      final position = (app.positionAppliedFor ?? '').trim();
      if (_selectedPositionFilter != null &&
          _selectedPositionFilter!.isNotEmpty &&
          position != _selectedPositionFilter) {
        return false;
      }
      if (_selectedAppliedDate != null) {
        final createdAt = app.createdAt;
        if (createdAt == null ||
            !_isSameLocalDate(createdAt, _selectedAppliedDate!)) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final hay =
            '${app.applicantNumber ?? ''} ${app.fullName} ${app.email} ${app.phone ?? ''} ${app.positionAppliedFor ?? ''}'
                .toLowerCase();
        if (!hay.contains(_searchQuery)) return false;
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

  static Map<String, dynamic>? _examAnswersSubsection(
    Map<String, dynamic>? answersJson,
    String key,
  ) {
    if (answersJson == null) return null;
    final v = answersJson[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  double? _sectionScorePercent(
    Map<String, dynamic>? answersJson,
    String sectionKey,
  ) {
    final section = _examAnswersSubsection(answersJson, sectionKey);
    if (section == null) return null;
    return RspScreeningScores.mcqSectionPercent(section);
  }

  double? _beiSectionScorePercent(Map<String, dynamic>? answersJson) {
    final bei = _examAnswersSubsection(answersJson, 'bei');
    if (bei == null) return null;
    return RspScreeningScores.beiSectionPercent(bei);
  }

  bool _hasBeiAnswers(RecruitmentExamResult exam) {
    final bei = _examAnswersSubsection(exam.answersJson, 'bei');
    final a = bei?['answers'];
    return a is List && a.isNotEmpty;
  }

  Future<void> _confirmAndAdminPassExam(
    RecruitmentApplication app,
    RecruitmentExamResult? existing,
  ) async {
    if (_adminPassingApplicantId != null) return;
    final choice = await _AdminExamBypassDialog.show(
      context,
      app: app,
      existing: existing,
    );
    if (choice == null || !mounted) return;
    await _adminPassExamWithChoice(app, choice);
  }

  Future<void> _adminPassExamWithChoice(
    RecruitmentApplication app,
    _AdminPassChoice choice,
  ) async {
    setState(() => _adminPassingApplicantId = app.id.toLowerCase());
    try {
      var beiCount = 8;
      try {
        final beiQs = await RecruitmentRepo.instance.getExamQuestions('bei');
        if (beiQs.isNotEmpty) beiCount = beiQs.length;
      } catch (_) {}

      final bool usePerfect = choice.mode == _AdminPassScoreMode.perfect;
      final answersJson = usePerfect
          ? RspScreeningScores.buildAdminExamBypassAnswersJson(
              beiQuestionCount: beiCount,
            )
          : RspScreeningScores.buildAdminExamOverrideAnswersJson(
              generalScore: choice.generalScore,
              mathScore: choice.mathScore,
              generalInfoScore: choice.generalInfoScore,
              beiScore: choice.beiScore,
              beiQuestionCount: beiCount,
            );
      final overall = usePerfect
          ? 100.0
          : RspScreeningScores.roundOverall(
              (choice.generalScore +
                      choice.mathScore +
                      choice.generalInfoScore +
                      choice.beiScore) /
                  4.0,
            );

      await RecruitmentRepo.instance.submitExamResult(
        applicationId: app.id,
        scorePercent: overall,
        passed: true,
        answersJson: answersJson,
      );

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usePerfect
                ? '${app.fullName.trim().isEmpty ? 'Applicant' : app.fullName.trim()} marked passed - 100% on all four exams.'
                : '${app.fullName.trim().isEmpty ? 'Applicant' : app.fullName.trim()} marked passed with custom scores.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not mark as passed. ${userFacingApiError(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _adminPassingApplicantId = null);
    }
  }

  static const Color _kPassBg = Color(0xFFE8F5E9);
  static const Color _kPassFg = Color(0xFF1B5E20);
  static const Color _kPassBorder = Color(0xFF43A047);
  static const Color _kFailBg = Color(0xFFFFEBEE);
  static const Color _kFailFg = Color(0xFFB71C1C);
  static const Color _kFailBorder = Color(0xFFE57373);

  static TextStyle _scoreBreakdownScoreStyle(
    BuildContext context, {
    required bool isNA,
    double? value,
  }) {
    final tabular = [const FontFeature.tabularFigures()];
    if (isNA) {
      return TextStyle(
        fontSize: 13,
        fontFeatures: tabular,
        color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.85),
        fontStyle: FontStyle.italic,
      );
    }
    final passSection = value != null && value >= 60;
    final dark = AppTheme.dashIsDark(context);
    final passFg = dark ? const Color(0xFF81C784) : _kPassFg;
    final failFg = dark ? const Color(0xFFEF9A9A) : _kFailFg;
    return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      fontFeatures: tabular,
      color: passSection ? passFg : failFg,
    );
  }

  static Widget _scoreBreakdownStatusPill(
    BuildContext context, {
    required RecruitmentExamResult? exam,
  }) {
    if (exam == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Text(
          'No exam',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.dashTextSecondaryOf(context).withValues(alpha: 0.9),
          ),
        ),
      );
    }
    final pass = exam.passed;
    final dark = AppTheme.dashIsDark(context);
    final passBg = dark ? const Color(0xFF1E3A24) : _kPassBg;
    final failBg = dark ? const Color(0xFF3A2020) : _kFailBg;
    final passFg = dark ? const Color(0xFF81C784) : _kPassFg;
    final failFg = dark ? const Color(0xFFEF9A9A) : _kFailFg;
    final passBorder = dark ? const Color(0xFF81C784) : _kPassBorder;
    final failBorder = dark ? const Color(0xFFEF9A9A) : _kFailBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: pass ? passBg : failBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pass ? passBorder : failBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pass ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16,
            color: pass ? passFg : failFg,
          ),
          const SizedBox(width: 6),
          Text(
            pass ? 'Passed' : 'Failed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: pass ? passFg : failFg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _examResultColumnCell(
    BuildContext context, {
    required RecruitmentApplication app,
    required RecruitmentExamResult? exam,
    required bool isPassing,
  }) {
    if (isPassing) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (exam?.passed == true) {
      return _scoreBreakdownStatusPill(context, exam: exam);
    }

    return Tooltip(
      message: 'Admin pass: choose perfect 100% or encode custom scores',
      child: FilledButton.tonal(
        onPressed: () => _confirmAndAdminPassExam(app, exam),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
          foregroundColor: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          exam == null ? 'Mark passed' : 'Override pass',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _scoreBreakdownHeaderCell(
    BuildContext context,
    String label, {
    TextAlign align = TextAlign.start,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      child: Text(
        label,
        textAlign: align,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.letterheadNavy,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          letterSpacing: 0.45,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _scoreBreakdownBodyCell(
    Widget child, {
    Color? background,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 6,
      vertical: 12,
    ),
  }) {
    return ColoredBox(
      color: background ?? Colors.transparent,
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _buildScoreBreakdownDataTable(BuildContext dialogContext) {
    final borderColor = AppTheme.dashHairlineOf(dialogContext);
    final headerBg = AppTheme.primaryNavy.withValues(alpha: 0.09);
    final bodyText = AppTheme.dashTextPrimaryOf(dialogContext);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth;
        final narrow = tableWidth < 720;
        final gradeW = narrow ? 64.0 : 72.0;
        final resultW = narrow ? 96.0 : 108.0;
        final genInfoLabel = narrow ? 'Gen.' : 'Gen. info';

        // Flex columns expand to fill width; Grade/Result stay fixed.
        final columnWidths = <int, TableColumnWidth>{
          0: const FlexColumnWidth(2.1),
          1: const FlexColumnWidth(2.6),
          2: const FlexColumnWidth(1.05),
          3: const FlexColumnWidth(1.05),
          4: const FlexColumnWidth(1.15),
          5: const FlexColumnWidth(1.05),
          6: FixedColumnWidth(gradeW),
          7: FixedColumnWidth(resultW),
        };

        final rows = <TableRow>[
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: [
              _scoreBreakdownHeaderCell(dialogContext, 'Applicant'),
              _scoreBreakdownHeaderCell(dialogContext, 'Position'),
              _scoreBreakdownHeaderCell(
                dialogContext,
                'General',
                align: TextAlign.end,
              ),
              _scoreBreakdownHeaderCell(
                dialogContext,
                'Math',
                align: TextAlign.end,
              ),
              _scoreBreakdownHeaderCell(
                dialogContext,
                genInfoLabel,
                align: TextAlign.end,
              ),
              _scoreBreakdownHeaderCell(
                dialogContext,
                'BEI',
                align: TextAlign.end,
              ),
              _scoreBreakdownHeaderCell(
                dialogContext,
                'Grade BEI',
                align: TextAlign.center,
              ),
              _scoreBreakdownHeaderCell(
                dialogContext,
                'Result',
                align: TextAlign.center,
              ),
            ],
          ),
          ..._filteredApplications.asMap().entries.map((entry) {
            final index = entry.key;
            final app = entry.value;
            final exam = _examResults[app.id.toLowerCase()];
            double? generalScore;
            double? mathScore;
            double? infoScore;
            double? beiScore;
            final answersJson = exam?.answersJson;
            if (answersJson != null) {
              generalScore = _sectionScorePercent(answersJson, 'general');
              mathScore = _sectionScorePercent(answersJson, 'math');
              infoScore = _sectionScorePercent(answersJson, 'general_info');
              beiScore = _beiSectionScorePercent(answersJson);
            }

            String scoreLabel(double? v) =>
                v == null ? _kNa : '${v.toStringAsFixed(0)}%';

            final canGradeBei = exam != null && _hasBeiAnswers(exam);
            final rowBg = index.isOdd
                ? AppTheme.dashMutedSurfaceOf(dialogContext)
                : AppTheme.dashPanelOf(dialogContext);

            Widget scoreCell(double? value) => Text(
              scoreLabel(value),
              textAlign: TextAlign.end,
              style: _scoreBreakdownScoreStyle(
                dialogContext,
                isNA: value == null,
                value: value,
              ),
            );

            final isPassingThis =
                _adminPassingApplicantId == app.id.toLowerCase();
            final isExamView = widget.view == _RspMonitorView.examResults;

            return TableRow(
              decoration: BoxDecoration(color: rowBg),
              children: [
                _scoreBreakdownBodyCell(
                  Text(
                    app.fullName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: bodyText,
                    ),
                  ),
                  background: rowBg,
                ),
                _scoreBreakdownBodyCell(
                  Text(
                    _displayOrNa(app.positionAppliedFor),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.dashTextSecondaryOf(
                        dialogContext,
                      ).withValues(alpha: 0.95),
                    ),
                  ),
                  background: rowBg,
                ),
                _scoreBreakdownBodyCell(
                  scoreCell(generalScore),
                  background: rowBg,
                ),
                _scoreBreakdownBodyCell(
                  scoreCell(mathScore),
                  background: rowBg,
                ),
                _scoreBreakdownBodyCell(
                  scoreCell(infoScore),
                  background: rowBg,
                ),
                _scoreBreakdownBodyCell(scoreCell(beiScore), background: rowBg),
                _scoreBreakdownBodyCell(
                  Center(
                    child: canGradeBei
                        ? IconButton.filled(
                            tooltip: 'Grade BEI',
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.primaryNavy.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor:
                                  AppTheme.dashIsDark(dialogContext)
                                  ? AppTheme.primaryNavyLight
                                  : AppTheme.primaryNavy,
                              padding: const EdgeInsets.all(8),
                              minimumSize: const Size(40, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.rate_review_rounded,
                              size: 20,
                            ),
                            onPressed: () {
                              showRspBeiGradingDialog(
                                context: dialogContext,
                                applicant: app,
                                exam: exam,
                                onSaved: _load,
                              );
                            },
                          )
                        : Tooltip(
                            message: 'No BEI answers on file',
                            child: Icon(
                              Icons.remove_rounded,
                              size: 18,
                              color: AppTheme.dashTextSecondaryOf(
                                dialogContext,
                              ).withValues(alpha: 0.35),
                            ),
                          ),
                  ),
                  background: rowBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                ),
                _scoreBreakdownBodyCell(
                  Align(
                    alignment: Alignment.center,
                    child: isExamView
                        ? _examResultColumnCell(
                            dialogContext,
                            app: app,
                            exam: exam,
                            isPassing: isPassingThis,
                          )
                        : _scoreBreakdownStatusPill(dialogContext, exam: exam),
                  ),
                  background: rowBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                ),
              ],
            );
          }),
        ];

        return Scrollbar(
          controller: _scoreBreakdownVScrollController,
          thickness: 8,
          radius: const Radius.circular(8),
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _scoreBreakdownVScrollController,
            primary: false,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: tableWidth,
                child: Table(
                  columnWidths: columnWidths,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                    horizontalInside: BorderSide(color: borderColor),
                    verticalInside: BorderSide.none,
                  ),
                  children: rows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _scoreBreakdownVScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final apps = await RecruitmentRepo.instance.listApplications();
      final results = await RecruitmentRepo.instance
          .getExamResultsByApplication();
      if (mounted) {
        setState(() {
          _applications = apps;
          _examResults = results;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteApplicant(String applicationId) async {
    // Optimistic UI: remove the row immediately.
    if (!mounted) return;
    setState(() {
      _applications.removeWhere((a) => a.id == applicationId);
      _examResults.remove(applicationId.toLowerCase());
    });

    try {
      await RecruitmentRepo.instance.deleteApplication(applicationId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Applicant deleted.')));
    } catch (e) {
      if (!mounted) return;
      // Roll back by reloading from backend.
      setState(() => {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      await _load();
    }
  }

  Future<void> _confirmDeleteApplicantRow(
    BuildContext context,
    RecruitmentApplication app,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete applicant?'),
          content: Text(
            'This will permanently remove ${app.fullName} and their exam results.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _deleteApplicant(app.id);
  }

  Future<void> _showEditApplicantDialog(RecruitmentApplication app) async {
    final result =
        await showDialog<({String fullName, String email, String? phone})?>(
          context: context,
          builder: (ctx) => _EditApplicantBasicDialog(app: app),
        );
    if (result == null || !mounted) return;
    try {
      final updated = await RecruitmentRepo.instance.updateApplicationBasicInfo(
        app.id,
        fullName: result.fullName,
        email: result.email,
        phone: result.phone,
      );
      if (!mounted) return;
      setState(() {
        final i = _applications.indexWhere((a) => a.id == app.id);
        if (i >= 0) _applications[i] = updated;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Applicant details saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  String _reportFilterSummary() {
    final parts = <String>[];
    if (_selectedPositionFilter != null &&
        _selectedPositionFilter!.trim().isNotEmpty) {
      parts.add('Position: ${_selectedPositionFilter!.trim()}');
    }
    if (_selectedAppliedDate != null) {
      parts.add('Applied date: ${_formatDateShort(_selectedAppliedDate!)}');
    }
    if (parts.isEmpty) return 'Filters: none (all applications)';
    return 'Filters: ${parts.join(' Â· ')}';
  }

  List<RspApplicationsReportRow> _reportRows() {
    return _filteredApplications
        .map(
          (app) => RspApplicationsReportRow.fromApplication(
            app: app,
            exam: _examResults[app.id.toLowerCase()],
          ),
        )
        .toList();
  }

  Future<void> _showGenerateReportDialog() async {
    final apps = _filteredApplications;
    if (apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No applicants match the current filters. Adjust filters or refresh data.',
          ),
        ),
      );
      return;
    }

    var withExam = 0;
    var passed = 0;
    for (final app in apps) {
      final exam = _examResults[app.id.toLowerCase()];
      if (exam != null) {
        withExam++;
        if (exam.passed) passed++;
      }
    }

    final choice = await RspGenerateReportDialog.showApplications(
      context,
      applicantCount: apps.length,
      filterSummary: _reportFilterSummary(),
      withExamCount: withExam,
      passedCount: passed,
    );
    if (choice == null || !mounted) return;

    final rows = _reportRows();
    final summary = _reportFilterSummary();

    if (choice == RspReportExportChoice.preview) {
      await RspApplicationsReportPreviewScreen.open(
        context,
        rows: rows,
        filterSummary: summary,
      );
      return;
    }

    setState(() => _exportingReport = true);
    try {
      switch (choice) {
        case RspReportExportChoice.preview:
          break; // opened before export switch
        case RspReportExportChoice.csv:
          await RspApplicationsReportExport.shareCsv(
            rows: rows,
            filterSummary: summary,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'CSV report downloaded (${rows.length} applicants).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        case RspReportExportChoice.pdf:
          await RspApplicationsReportExport.sharePdf(
            rows: rows,
            filterSummary: summary,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF report downloaded (${rows.length} applicants).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        case RspReportExportChoice.print:
          await RspApplicationsReportExport.printPdf(
            context: context,
            rows: rows,
            filterSummary: summary,
          );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report failed. ${userFacingApiError(e)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingReport = false);
    }
  }

  /// Lists storage paths; retries when the API returns 429 (rate limited).
  Future<List<Map<String, String>>> _listStoragePathsWithRetry() async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
      try {
        return await RecruitmentRepo.instance.listStorageAttachmentPaths();
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt < maxAttempts - 1) {
          continue;
        }
        rethrow;
      }
    }
    return RecruitmentRepo.instance.listStorageAttachmentPaths();
  }

  /// Sync attachment paths from server disk into DB for applications missing paths.
  Future<void> _syncAttachmentsFromStorage() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final entries = await _listStoragePathsWithRetry();
      debugPrint(
        'Sync attachments: listed ${entries.length} file(s) on server.',
      );
      int linked = 0;
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final fileName = e['fileName']!;
        final kind = RspApplicationDocKind.fromStorageFileName(fileName);
        final finalReqKind = RspFinalRequirementDocKind.fromStorageFileName(
          fileName,
        );
        final bool ok;
        if (kind != null) {
          ok = await RecruitmentRepo.instance
              .setApplicationTypedAttachmentIfMissing(
                e['applicationId']!,
                e['path']!,
                fileName,
                kind,
              );
        } else if (finalReqKind != null) {
          ok = await RecruitmentRepo.instance
              .setApplicationFinalRequirementIfMissing(
                e['applicationId']!,
                e['path']!,
                fileName,
                finalReqKind,
              );
        } else {
          ok = await RecruitmentRepo.instance.setApplicationAttachmentIfMissing(
            e['applicationId']!,
            e['path']!,
            fileName,
          );
        }
        if (ok) linked++;
        if (i > 0 && i % 5 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      if (mounted) {
        await _load();
        if (!mounted) return;
        setState(() => _syncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              linked > 0
                  ? 'Linked $linked attachment(s) from storage. You can now view and download them.'
                  : entries.isEmpty
                  ? 'No files found in storage (bucket may be empty or path structure is applicationId/filename).'
                  : 'No applications were missing attachment paths; already linked or no matching application IDs.',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Sync attachments failed: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() => _syncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed. ${userFacingApiError(e)}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static const _kNa = 'N/A';

  ({String city, String barangay, String street}) _appAddressParts(
    RecruitmentApplication app,
  ) {
    final p = parseStoredAddress(app.address);
    return (city: p.city, barangay: p.barangay, street: p.street);
  }

  String _displayOrNa(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return _kNa;
    final lower = v.toLowerCase();
    if (lower == 'none' || lower == 'null') return _kNa;
    if (v == '\u2014' || v == '\u2013' || v == '-') return _kNa;
    if (v.contains('\u00e2\u20ac')) return _kNa;
    return v;
  }

  Widget _tableCell(double width, Widget child) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  String _applicationDisplayStatus(RecruitmentApplication app) {
    if (app.hiredUserId != null || app.status == 'registered') return 'Hired';
    if (app.hrAccountSetupDone) return 'Account setup done';
    if (app.orientationAttended == true) return 'Orientation attended';
    if (app.orientationAttended == false) return 'Orientation missed';
    if (app.orientationAt != null) return 'Orientation scheduled';
    if (app.finalRequirementsApproved) return 'Final requirements approved';
    if (app.finalInterviewPassed == true) return 'Final interview passed';
    if (app.finalInterviewPassed == false) return 'Final interview failed';

    switch (app.status) {
      case 'submitted':
        return 'Pending review';
      case 'document_approved':
        return 'Docs approved';
      case 'document_declined':
        return 'Docs declined';
      case 'exam_taken':
        return 'Exam taken';
      case 'passed':
        return 'Passed exam';
      case 'failed':
        return 'Failed exam';
      default:
        return app.status;
    }
  }

  /// Readable status pill with color by outcome (tooltip shows raw value).
  Widget _applicationStatusBadge(BuildContext context, String status) {
    final raw = status.trim();
    final s = raw.toLowerCase();
    final dark = AppTheme.dashIsDark(context);
    late Color bg;
    late Color fg;
    late IconData icon;
    if (s.contains('passed') ||
        s == 'registered' ||
        s.contains('approved') ||
        s.contains('hire')) {
      bg = dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9);
      fg = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      icon = Icons.check_circle_outline_rounded;
    } else if (s.contains('declined') ||
        s.contains('failed') ||
        s.contains('reject')) {
      bg = dark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE);
      fg = dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
      icon = Icons.cancel_outlined;
    } else if (s.contains('pending') ||
        s.contains('submitted') ||
        s.contains('review') ||
        s.contains('exam')) {
      bg = AppTheme.primaryNavy.withValues(alpha: dark ? 0.22 : 0.12);
      fg = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavyDark;
      icon = Icons.schedule_rounded;
    } else {
      bg = AppTheme.dashMutedSurfaceOf(context);
      fg = AppTheme.dashTextSecondaryOf(context);
      icon = Icons.label_outline_rounded;
    }
    final display = raw.isEmpty ? _kNa : raw.replaceAll('_', ' ');
    return Tooltip(
      message: raw.isEmpty ? '' : raw,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 158),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: fg.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    display,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExamView = widget.view == _RspMonitorView.examResults;
    final isApplicationsView = !isExamView;
    final pageTitle = isExamView ? 'Exam Results' : 'Applications';
    final pageSubtitle = isExamView
        ? 'Section scores and pass/fail below. Use Mark passed in the Result column to choose perfect 100% or encode custom pass scores. Use Grade BEI to score real BEI responses.'
        : 'Monitor applicant submissions, attachments, and document review status.';
    final pageIcon = isExamView
        ? Icons.fact_check_outlined
        : Icons.assignment_outlined;
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final tableHeaderStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
      letterSpacing: 0.35,
      color: AppTheme.dashIsDark(context)
          ? AppTheme.primaryNavyLight
          : AppTheme.letterheadNavy,
    );
    final filteredApplications = _filteredApplications;

    final generateReportBtn = Tooltip(
      message:
          'Export the filtered applicant list and exam scores (CSV or PDF).',
      child: OutlinedButton.icon(
        onPressed: (_loading || _exportingReport)
            ? null
            : _showGenerateReportDialog,
        icon: _exportingReport
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.summarize_outlined, size: 18),
        label: Text(_exportingReport ? 'Generating…' : 'Generate report'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
          side: BorderSide(
            color: AppTheme.primaryNavy.withValues(
              alpha: AppTheme.dashIsDark(context) ? 0.45 : 0.35,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );

    final syncBtn = Tooltip(
      message:
          'Link files already in storage to applications that show "No file" (e.g. after fixing RLS).',
      child: TextButton.icon(
        onPressed: (_loading || _syncing) ? null : _syncAttachmentsFromStorage,
        icon: _syncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync_rounded, size: 20),
        label: Text(_syncing ? 'Syncing...' : 'Sync attachments from storage'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
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
                    AppTheme.primaryNavy.withValues(alpha: 0.14),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                pageIcon,
                size: 26,
                color: AppTheme.dashIsDark(context)
                    ? AppTheme.primaryNavyLight
                    : AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pageTitle,
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.15,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: hairline),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 22),
                          onPressed: _loading ? null : _load,
                          tooltip: 'Refresh',
                          style: IconButton.styleFrom(
                            foregroundColor: AppTheme.dashIsDark(context)
                                ? AppTheme.primaryNavyLight
                                : AppTheme.primaryNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pageSubtitle,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: muted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hairline),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 640) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    generateReportBtn,
                    if (isApplicationsView) const SizedBox(height: 10),
                    if (isApplicationsView) syncBtn,
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPositionFilter,
                      decoration: InputDecoration(
                        labelText: 'Filter position',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All positions'),
                        ),
                        ...(_positionFilterOptions.toList()..sort(
                              (a, b) =>
                                  a.toLowerCase().compareTo(b.toLowerCase()),
                            ))
                            .map(
                              (p) => DropdownMenuItem<String>(
                                value: p,
                                child: Text(p),
                              ),
                            ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) {
                              setState(() => _selectedPositionFilter = value);
                            },
                    ),
                    const SizedBox(height: 10),
                    dateFilterBtn,
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => setState(
                                  () => _selectedAppliedDate = DateTime.now(),
                                ),
                          icon: const Icon(Icons.today_outlined, size: 18),
                          label: const Text('Today'),
                        ),
                        TextButton.icon(
                          onPressed:
                              (_loading ||
                                  (_selectedPositionFilter == null &&
                                      _selectedAppliedDate == null &&
                                      _searchQuery.isEmpty))
                              ? null
                              : () {
                                  setState(() {
                                    _selectedPositionFilter = null;
                                    _selectedAppliedDate = null;
                                    _searchController.clear();
                                  });
                                },
                          icon: const Icon(Icons.clear_all_rounded, size: 18),
                          label: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [generateReportBtn, if (isApplicationsView) syncBtn],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchController,
                enabled: !_loading,
                decoration: InputDecoration(
                  labelText: 'Search applicant ID, name, email…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 320,
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
            dateFilterBtn,
            TextButton.icon(
              onPressed: _loading
                  ? null
                  : () => setState(() => _selectedAppliedDate = DateTime.now()),
              icon: const Icon(Icons.today_outlined, size: 18),
              label: const Text('Today'),
            ),
            TextButton.icon(
              onPressed:
                  (_loading ||
                      (_selectedPositionFilter == null &&
                          _selectedAppliedDate == null &&
                          _searchQuery.isEmpty))
                  ? null
                  : () {
                      setState(() {
                        _selectedPositionFilter = null;
                        _selectedAppliedDate = null;
                        _searchController.clear();
                      });
                    },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear filters'),
            ),
            Text(
              '${filteredApplications.length} shown',
              style: TextStyle(
                color: secondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hairline),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_applications.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No applications yet. Applicants will appear here after they submit Step 1 from the recruitment flow.',
                      style: TextStyle(
                        color: secondary.withValues(alpha: 0.92),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              else if (filteredApplications.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No applicants match the selected filters. Try another position or date.',
                      style: TextStyle(
                        color: secondary.withValues(alpha: 0.92),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              else if (isExamView)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _buildScoreBreakdownDataTable(context),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scrollWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    const fixedTableWidth = 3510.0;
                    final tableWidth = scrollWidth > fixedTableWidth
                        ? scrollWidth
                        : fixedTableWidth;
                    return SizedBox(
                      width: scrollWidth,
                      child: Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: tableWidth),
                              child: Table(
                                columnWidths: {
                                  0: const FixedColumnWidth(
                                    160,
                                  ), // Applicant ID
                                  1: const FixedColumnWidth(140), // First
                                  2: const FixedColumnWidth(140), // Middle
                                  3: const FixedColumnWidth(140), // Last
                                  4: const FixedColumnWidth(90), // Suffix
                                  5: const FixedColumnWidth(90), // Gender
                                  6: const FixedColumnWidth(150), // Course
                                  7: const FixedColumnWidth(70), // Age
                                  8: const FixedColumnWidth(
                                    140,
                                  ), // Civil status
                                  9: const FixedColumnWidth(
                                    170,
                                  ), // City / Municipality
                                  10: const FixedColumnWidth(150), // Barangay
                                  11: const FixedColumnWidth(180), // Street
                                  12: const FixedColumnWidth(260), // Email
                                  13: const FixedColumnWidth(140), // Phone
                                  14: const FixedColumnWidth(
                                    200,
                                  ), // Position applied
                                  15: const FixedColumnWidth(170), // Status
                                  16: const FixedColumnWidth(
                                    188,
                                  ), // Application letter
                                  17: const FixedColumnWidth(188), // Resume
                                  18: const FixedColumnWidth(188), // TOR
                                  19: const FixedColumnWidth(
                                    200,
                                  ), // Eligibility/trainings
                                  20: const FixedColumnWidth(
                                    248,
                                  ), // Document review
                                  21: const FixedColumnWidth(108), // Actions
                                },
                                defaultVerticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                border: TableBorder.symmetric(
                                  inside: BorderSide(color: hairline),
                                ),
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.08,
                                      ),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppTheme.primaryNavy
                                              .withValues(alpha: 0.2),
                                        ),
                                      ),
                                    ),
                                    children: [
                                      _tableCell(
                                        160,
                                        Text(
                                          'Applicant ID',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        140,
                                        Text(
                                          'First name',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        140,
                                        Text(
                                          'Middle name',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        140,
                                        Text(
                                          'Last name',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        90,
                                        Text('Suffix', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        90,
                                        Text('Gender', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        150,
                                        Text('Course', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        70,
                                        Text('Age', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        140,
                                        Text(
                                          'Civil status',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        170,
                                        Text(
                                          'City / Municipality',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        150,
                                        Text(
                                          'Barangay',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        180,
                                        Text('Street', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        260,
                                        Text('Email', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        140,
                                        Text('Phone', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        200,
                                        Text(
                                          'Position applied',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        170,
                                        Text('Status', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        188,
                                        Text(
                                          'Application letter',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        188,
                                        Text('Resume', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        188,
                                        Text('TOR', style: tableHeaderStyle),
                                      ),
                                      _tableCell(
                                        200,
                                        Text(
                                          'Eligibility / trainings (prelim.)',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        248,
                                        Text(
                                          'Document review',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                      _tableCell(
                                        108,
                                        Text(
                                          'Actions',
                                          style: tableHeaderStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...List.generate(filteredApplications.length, (
                                    ri,
                                  ) {
                                    final app = filteredApplications[ri];
                                    final textStyle = TextStyle(
                                      fontSize: 13,
                                      color: primary,
                                      fontWeight: FontWeight.w500,
                                    );

                                    final full = app.fullName.trim();
                                    final parts = full
                                        .split(RegExp(r'\s+'))
                                        .where((p) => p.trim().isNotEmpty)
                                        .toList();
                                    final firstName = _displayOrNa(
                                      (app.firstName ?? '').trim().isNotEmpty
                                          ? app.firstName
                                          : (parts.isNotEmpty
                                                ? parts.first
                                                : null),
                                    );
                                    final middleName = _displayOrNa(
                                      app.middleName,
                                    );
                                    final lastName = _displayOrNa(
                                      (app.lastName ?? '').trim().isNotEmpty
                                          ? app.lastName
                                          : (parts.length >= 2
                                                ? parts.last
                                                : null),
                                    );
                                    final suffix = _displayOrNa(app.suffix);
                                    final gender = _displayOrNa(app.sex);
                                    final course = _displayOrNa(app.course);
                                    final age = _displayOrNa(app.age);
                                    final civilStatus = _displayOrNa(
                                      app.civilStatus,
                                    );
                                    final addr = _appAddressParts(app);
                                    final city = _displayOrNa(
                                      addr.city.isEmpty ? null : addr.city,
                                    );
                                    final barangay = _displayOrNa(
                                      addr.barangay.isEmpty
                                          ? null
                                          : addr.barangay,
                                    );
                                    final street = _displayOrNa(
                                      addr.street.isEmpty ? null : addr.street,
                                    );
                                    final applicantId = _displayOrNa(
                                      app.applicantNumber,
                                    );

                                    return TableRow(
                                      decoration: ri.isOdd
                                          ? BoxDecoration(
                                              color: AppTheme.sectionAltOf(
                                                context,
                                              ).withValues(alpha: 0.45),
                                            )
                                          : null,
                                      children: [
                                        _tableCell(
                                          160,
                                          SelectableText(
                                            applicantId,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: const Color(0xFFE85D04),
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          140,
                                          Tooltip(
                                            message: app.fullName,
                                            child: Text(
                                              firstName,
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          140,
                                          Text(
                                            middleName,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                            softWrap: true,
                                          ),
                                        ),
                                        _tableCell(
                                          140,
                                          Text(
                                            lastName,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                            softWrap: true,
                                          ),
                                        ),
                                        _tableCell(
                                          90,
                                          Text(
                                            suffix,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
                                        _tableCell(
                                          90,
                                          Text(
                                            gender,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
                                        _tableCell(
                                          150,
                                          Tooltip(
                                            message: course,
                                            child: Text(
                                              course,
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          70,
                                          Text(
                                            age,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        _tableCell(
                                          140,
                                          Text(
                                            civilStatus,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                            softWrap: true,
                                          ),
                                        ),
                                        _tableCell(
                                          170,
                                          Tooltip(
                                            message: city,
                                            child: Text(
                                              city,
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          150,
                                          Tooltip(
                                            message: barangay,
                                            child: Text(
                                              barangay,
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          180,
                                          Tooltip(
                                            message: street,
                                            child: Text(
                                              street,
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          260,
                                          Tooltip(
                                            message: app.email,
                                            child: Text(
                                              app.email,
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          140,
                                          Text(
                                            _displayOrNa(app.phone),
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        _tableCell(
                                          200,
                                          Tooltip(
                                            message: _displayOrNa(
                                              app.positionAppliedFor,
                                            ),
                                            child: Text(
                                              _displayOrNa(
                                                app.positionAppliedFor,
                                              ),
                                              style: textStyle,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              softWrap: true,
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          170,
                                          _applicationStatusBadge(
                                            context,
                                            _applicationDisplayStatus(app),
                                          ),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            child: _TypedDocAdminCell(
                                              app: app,
                                              kind: RspApplicationDocKind
                                                  .applicationLetter,
                                              onFileRemoved: _load,
                                            ),
                                          ),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            child: _TypedDocAdminCell(
                                              app: app,
                                              kind:
                                                  RspApplicationDocKind.resume,
                                              onFileRemoved: _load,
                                            ),
                                          ),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            child: _TypedDocAdminCell(
                                              app: app,
                                              kind: RspApplicationDocKind.tor,
                                              onFileRemoved: _load,
                                            ),
                                          ),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            child: _TypedDocAdminCell(
                                              app: app,
                                              kind: RspApplicationDocKind
                                                  .eligibilityTrainings,
                                              onFileRemoved: _load,
                                            ),
                                          ),
                                        ),
                                        TableCell(
                                          verticalAlignment:
                                              TableCellVerticalAlignment.middle,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            child: SizedBox(
                                              width: 248,
                                              child: _DocumentReviewCell(
                                                app: app,
                                                onUpdated: _load,
                                                onDeleteApplicant:
                                                    _deleteApplicant,
                                              ),
                                            ),
                                          ),
                                        ),
                                        _tableCell(
                                          108,
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                onPressed: () =>
                                                    _showEditApplicantDialog(
                                                      app,
                                                    ),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 20,
                                                ),
                                                tooltip:
                                                    'Edit name, email, phone',
                                                style: IconButton.styleFrom(
                                                  foregroundColor:
                                                      AppTheme.dashIsDark(
                                                        context,
                                                      )
                                                      ? AppTheme
                                                            .primaryNavyLight
                                                      : AppTheme.primaryNavy,
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  minimumSize: const Size(
                                                    32,
                                                    32,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () =>
                                                    _confirmDeleteApplicantRow(
                                                      context,
                                                      app,
                                                    ),
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 20,
                                                ),
                                                tooltip: 'Delete applicant',
                                                style: IconButton.styleFrom(
                                                  foregroundColor: const Color(
                                                    0xFFC62828,
                                                  ),
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  minimumSize: const Size(
                                                    32,
                                                    32,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _AdminPassScoreMode { perfect, custom }

class _AdminPassChoice {
  const _AdminPassChoice.perfect()
    : mode = _AdminPassScoreMode.perfect,
      generalScore = 100,
      mathScore = 100,
      generalInfoScore = 100,
      beiScore = 100;

  const _AdminPassChoice.custom({
    required this.generalScore,
    required this.mathScore,
    required this.generalInfoScore,
    required this.beiScore,
  }) : mode = _AdminPassScoreMode.custom;

  final _AdminPassScoreMode mode;
  final double generalScore;
  final double mathScore;
  final double generalInfoScore;
  final double beiScore;
}

class _AdminExamBypassDialog extends StatefulWidget {
  const _AdminExamBypassDialog({required this.app, required this.existing});

  final RecruitmentApplication app;
  final RecruitmentExamResult? existing;

  static Future<_AdminPassChoice?> show(
    BuildContext context, {
    required RecruitmentApplication app,
    required RecruitmentExamResult? existing,
  }) {
    return showDialog<_AdminPassChoice>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (ctx) => _AdminExamBypassDialog(app: app, existing: existing),
    );
  }

  @override
  State<_AdminExamBypassDialog> createState() => _AdminExamBypassDialogState();
}

class _AdminExamBypassDialogState extends State<_AdminExamBypassDialog> {
  _AdminPassScoreMode _mode = _AdminPassScoreMode.perfect;
  final _generalController = TextEditingController(text: '100');
  final _mathController = TextEditingController(text: '100');
  final _infoController = TextEditingController(text: '100');
  final _beiController = TextEditingController(text: '100');

  @override
  void dispose() {
    _generalController.dispose();
    _mathController.dispose();
    _infoController.dispose();
    _beiController.dispose();
    super.dispose();
  }

  double? _parseScore(TextEditingController c) {
    final s = c.text.trim();
    if (s.isEmpty) return null;
    final v = double.tryParse(s);
    if (v == null) return null;
    if (v < 60 || v > 100) return null;
    return v;
  }

  _AdminPassChoice? _buildChoiceOrShowError() {
    if (_mode == _AdminPassScoreMode.perfect) {
      return const _AdminPassChoice.perfect();
    }
    final g = _parseScore(_generalController);
    final m = _parseScore(_mathController);
    final i = _parseScore(_infoController);
    final b = _parseScore(_beiController);
    if (g == null || m == null || i == null || b == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter valid scores from 60 to 100 for General, Math, Gen. info, and BEI.',
          ),
        ),
      );
      return null;
    }
    return _AdminPassChoice.custom(
      generalScore: g,
      mathScore: m,
      generalInfoScore: i,
      beiScore: b,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final muted = AppTheme.dashMutedSurfaceOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    final alreadyPassed = widget.existing?.passed == true;
    final hasExam = widget.existing != null;
    final name = widget.app.fullName.trim().isEmpty
        ? 'Unnamed applicant'
        : widget.app.fullName.trim();
    final position = (widget.app.positionAppliedFor ?? '').trim();
    final email = widget.app.email.trim();

    String statusLabel;
    Color statusBg;
    Color statusFg;
    IconData statusIcon;
    if (alreadyPassed) {
      statusLabel = 'Currently passed';
      statusBg = dark ? const Color(0xFF1E3A24) : const Color(0xFFE8F5E9);
      statusFg = dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (hasExam) {
      statusLabel = 'Failed exam';
      statusBg = dark ? const Color(0xFF3A2020) : const Color(0xFFFFEBEE);
      statusFg = dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
      statusIcon = Icons.cancel_outlined;
    } else {
      statusLabel = 'No exam yet';
      statusBg = muted;
      statusFg = secondary;
      statusIcon = Icons.hourglass_empty_rounded;
    }

    final parts = name.split(RegExp(r'\s+'));
    var initials = '';
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      initials += parts.first[0].toUpperCase();
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      initials += parts.last[0].toUpperCase();
    }
    if (initials.isEmpty) initials = '?';

    return Dialog(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 14, 0),
              child: Row(
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
                          accent.withValues(alpha: 0.18),
                          accent.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(color: accent.withValues(alpha: 0.22)),
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alreadyPassed
                              ? 'Replace exam result?'
                              : 'Admin exam bypass',
                          style: TextStyle(
                            color: primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.35,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          alreadyPassed
                              ? 'Overwrite the current passing record with perfect scores on all four screening sections.'
                              : 'Record this applicant as passed with 100% on every exam section — even without taking the screening exam.',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: secondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: muted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hairline),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: accent.withValues(alpha: 0.14),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              color: primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: TextStyle(
                                color: secondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if (position.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              position,
                              style: TextStyle(
                                color: accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusFg.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusFg),
                          const SizedBox(width: 5),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusFg,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Text(
                'SCORING MODE',
                style: TextStyle(
                  color: secondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: muted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioListTile<_AdminPassScoreMode>(
                      value: _AdminPassScoreMode.perfect,
                      groupValue: _mode,
                      onChanged: (v) => setState(() => _mode = v!),
                      title: const Text('Perfect score (100% on all sections)'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<_AdminPassScoreMode>(
                      value: _AdminPassScoreMode.custom,
                      groupValue: _mode,
                      onChanged: (v) => setState(() => _mode = v!),
                      title: const Text(
                        'Custom scores (admin manually encodes section scores)',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_mode == _AdminPassScoreMode.custom) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Allowed range: 60 to 100 (Mark passed mode).',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _generalController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'General',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _mathController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Math',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _infoController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Gen. info',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _beiController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'BEI',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFFFF8E1,
                  ).withValues(alpha: dark ? 0.22 : 1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: dark
                          ? const Color(0xFFFFD54F)
                          : const Color(0xFFF57F17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is an HR admin override. The applicant is marked passed and the chosen scores are saved to the screening result.',
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFFFE082)
                              : const Color(0xFF6D4C41),
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: hairline),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.primaryNavy,
                            AppTheme.primaryNavyLight,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: () {
                          final choice = _buildChoiceOrShowError();
                          if (choice == null) return;
                          Navigator.of(context).pop(choice);
                        },
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          alreadyPassed ? 'Replace result' : 'Mark passed',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
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

class _AdminBypassExamChip extends StatelessWidget {
  const _AdminBypassExamChip({required this.label, required this.score});

  final String label;
  final String score;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final accent = dark ? AppTheme.primaryNavyLight : AppTheme.primaryNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            score,
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditApplicantBasicDialog extends StatefulWidget {
  const _EditApplicantBasicDialog({required this.app});

  final RecruitmentApplication app;

  @override
  State<_EditApplicantBasicDialog> createState() =>
      _EditApplicantBasicDialogState();
}

class _EditApplicantBasicDialogState extends State<_EditApplicantBasicDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.app.fullName);
    _email = TextEditingController(text: widget.app.email);
    _phone = TextEditingController(text: widget.app.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ph = _phone.text.trim();
    Navigator.of(context).pop((
      fullName: _name.text.trim(),
      email: _email.text.trim(),
      phone: ph.isEmpty ? null : ph,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit applicant'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One required document slot in the admin table (DB path + optional legacy resume).
class _TypedDocAdminCell extends StatelessWidget {
  const _TypedDocAdminCell({
    required this.app,
    required this.kind,
    this.onFileRemoved,
  });

  final RecruitmentApplication app;
  final RspApplicationDocKind kind;
  final VoidCallback? onFileRemoved;

  /// Display name for storage files like "1736123456_0_Resume.pdf" -> "Resume.pdf"
  static String displayName(String pathOrName) {
    final name = pathOrName.contains('/')
        ? pathOrName.split('/').last
        : pathOrName;
    final parts = name.split('_');
    if (parts.length >= 3 &&
        int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null) {
      return parts.sublist(2).join('_');
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    var path = app.docPath(kind);
    var name = app.docDisplayName(kind);
    if (path == null &&
        name == null &&
        kind == RspApplicationDocKind.resume &&
        app.attachmentPath != null &&
        app.attachmentName != null) {
      path = app.attachmentPath;
      name = app.attachmentName;
    }
    if (path != null && name != null && path.isNotEmpty) {
      final p = path;
      final n = name;
      return _AttachmentRow(
        path: p,
        fileName: displayName(n),
        onRemove: onFileRemoved != null
            ? () => _removeFile(context, p, onFileRemoved!)
            : null,
      );
    }
    return Tooltip(
      message:
          'No file for this document type. Use "Sync attachments from storage" if uploads exist only in the bucket.',
      child: Text(
        'No file',
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 12,
        ),
      ),
    );
  }

  static Future<void> _removeFile(
    BuildContext context,
    String path,
    VoidCallback onRefresh,
  ) async {
    try {
      await RecruitmentRepo.instance.deleteAttachment(path);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File removed.')));
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove file: $e')));
      }
    }
  }
}

/// One attachment: download button + optional remove (admin).
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.path,
    required this.fileName,
    this.onRemove,
  });

  final String path;
  final String fileName;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: _AttachmentActions(path: path, fileName: fileName),
        ),
        if (onRemove != null)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: 'Remove file',
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(28, 28),
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class _DocumentReviewCell extends StatelessWidget {
  const _DocumentReviewCell({
    required this.app,
    required this.onUpdated,
    required this.onDeleteApplicant,
  });

  final RecruitmentApplication app;
  final VoidCallback onUpdated;
  final Future<void> Function(String applicationId) onDeleteApplicant;

  Future<void> _approve(BuildContext context) async {
    try {
      await RecruitmentRepo.instance.updateApplicationStatus(
        app.id,
        'document_approved',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Document approved. Applicant can now take the exam.',
            ),
          ),
        );
        onUpdated();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _decline(BuildContext context) async {
    try {
      await RecruitmentRepo.instance.updateApplicationStatus(
        app.id,
        'document_declined',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Document declined.')));
        onUpdated();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteApplicant(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete applicant?'),
          content: Text(
            'This will remove ${app.fullName} and their exam results.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await onDeleteApplicant(app.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (app.status == 'submitted') {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.icon(
            onPressed: () => _approve(context),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Approve'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(100, 38),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _decline(context),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Decline'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(100, 38),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _deleteApplicant(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828), width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(100, 38),
            ),
          ),
        ],
      );
    }
    if (app.status == 'document_approved') {
      final dark = AppTheme.dashIsDark(context);
      final approvedFg = dark ? const Color(0xFF81C784) : Colors.green.shade700;
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 20, color: approvedFg),
              const SizedBox(width: 6),
              Text(
                'Approved',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: approvedFg,
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => _deleteApplicant(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828), width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(100, 38),
            ),
          ),
        ],
      );
    }
    if (app.status == 'document_declined') {
      final dark = AppTheme.dashIsDark(context);
      final declinedFg = dark ? const Color(0xFFEF9A9A) : Colors.red.shade700;
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel, size: 20, color: declinedFg),
              const SizedBox(width: 6),
              Text(
                'Declined',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: declinedFg,
                ),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () => _deleteApplicant(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFC62828), width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(100, 38),
            ),
          ),
        ],
      );
    }
    return Text(
      app.status,
      style: TextStyle(
        fontSize: 13,
        color: AppTheme.dashTextSecondaryOf(context),
      ),
    );
  }
}

/// Preview (opens dialog on web) + explicit Download for applicant files.
class _AttachmentActions extends StatelessWidget {
  const _AttachmentActions({required this.path, required this.fileName});

  final String path;
  final String fileName;

  Future<String?> _resolveUrl() => RecruitmentRepo.instance
      .getAttachmentDownloadUrl(path, fileName: fileName);

  Future<void> _preview(BuildContext context) async {
    final url = await _resolveUrl();
    if (url != null && context.mounted) {
      if (kIsWeb) {
        showRspAttachmentPreviewDialog(
          context,
          url: url,
          fileName: fileName,
          objectPath: path,
        );
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create attachment link. Restart the API and verify '
            'storage configuration.',
          ),
        ),
      );
    }
  }

  Future<void> _download(BuildContext context) async {
    final url = await _resolveUrl();
    if (url != null && context.mounted) {
      final uri = Uri.parse(url).replace(
        queryParameters: {...Uri.parse(url).queryParameters, 'download': '1'},
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get download link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkColor = AppTheme.dashIsDark(context)
        ? AppTheme.primaryNavyLight
        : AppTheme.primaryNavy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Tooltip(
            message: 'Preview â€” $fileName',
            child: TextButton.icon(
              onPressed: () => _preview(context),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: SizedBox(
                width: 200,
                child: Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: linkColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Download / open in new tab',
          onPressed: () => _download(context),
          icon: const Icon(Icons.download_rounded, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: linkColor,
            padding: const EdgeInsets.all(4),
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );
  }
}
