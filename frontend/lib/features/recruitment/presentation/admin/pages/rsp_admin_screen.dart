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
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/rsp_job_vacancies_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/computation_of_points_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/work_experience_sheet_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/turn_around_time_section.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/ojt_work_immersion_evaluation_section.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_applications_report_export.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_generate_report_dialog.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_applications_report_preview_screen.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_attachment_actions.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_records_list_table.dart';
import 'package:hrms_plaridel/shared/widgets/rsp_ld_record_actions.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_admin_hub.dart';
import 'package:hrms_plaridel/features/forms/presentation/admin/pages/form_background_upload_page.dart';
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
                const RspJobVacanciesSection()
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

/// RSP: "Exams" hub â€” pick which exam to view/edit (BEI, General, Math, General Info).
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
  _RspExamPickerItem(
    examKey: 'ojt_work_immersion',
    title: 'OJT / Work Immersion Evaluation',
    subtitle: 'Interview scoring form.',
    icon: Icons.school_outlined,
    format: 'Evaluation form',
  ),
];

/// RSP: "Forms" hub â€” pick which form to view/edit.
class _RspFormsSection extends StatefulWidget {
  const _RspFormsSection({required this.onBackToRsp});

  final VoidCallback onBackToRsp;

  @override
  State<_RspFormsSection> createState() => _RspFormsSectionState();
}

class _RspFormsSectionState extends State<_RspFormsSection> {
  _RspExamPickerItem? _selected;
  bool _showPrintBackground = false;

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
        return const RspTurnAroundTimeSection();
      case 'ojt_work_immersion':
        return const RspOjtWorkImmersionEvaluationSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBreadcrumb() {
    final navy = AppTheme.primaryNavy;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final selectedItem = _selected;
    final inBackground = _showPrintBackground;
    return Row(
      children: [
        TextButton.icon(
          onPressed: selectedItem == null && !inBackground
              ? widget.onBackToRsp
              : () => setState(() {
                  _selected = null;
                  _showPrintBackground = false;
                }),
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
            color: selectedItem == null && !inBackground ? navy : secondary,
            fontSize: 13,
            fontWeight: selectedItem == null && !inBackground
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
        if (inBackground) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
          const SizedBox(width: 2),
          const Flexible(
            child: Text(
              'Print background',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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
    if (_showPrintBackground) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 12),
          FormBackgroundUploadPage(
            module: 'rsp',
            embedded: true,
            onBack: () => setState(() => _showPrintBackground = false),
          ),
        ],
      );
    }

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
                      'Select a form or set a print background.',
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
        FormsPrintBackgroundEntry(
          onOpen: () => setState(() => _showPrintBackground = true),
        ),
        const SizedBox(height: 16),
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
                    hintText: 'Question textÃ¢â‚¬Â¦',
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
                // ignore: deprecated_member_use
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

/// RSP: Background Investigation (BI) Form ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â list entries and add/edit form.
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
              subtitle: '${e.respondentName} Ã‚Â· ${e.respondentRelationship}',
              detailDialogTitle: 'BI form Ã¢â‚¬â€ ${e.applicantName}',
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
        printModule: 'rsp',
        printFormKey: 'bi',
      );
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
                        // ignore: deprecated_member_use
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
                'Page 2 Ã¢â‚¬â€ Functional areas & performance',
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
                'Page 3 Ã¢â‚¬â€ Other relevant information',
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
                  title: 'BI form Ã¢â‚¬â€ ${e.applicantName}',
                  subtitle:
                      '${e.respondentName} Ã‚Â· ${e.respondentRelationship}',
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

/// RSP: Applicants Profile ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â job vacancy details + list of applicants.
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
        printModule: 'rsp',
        printFormKey: 'applicants_profile',
      );
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
              '${e.applicants.length} applicant(s) Ã‚Â· Posted ${e.dateOfPosting ?? "Ã¢â‚¬â€"}',
          detailDialogTitle: 'Applicants profile Ã¢â‚¬â€ $pos',
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

  static String _dash(String v) => v.trim().isEmpty ? 'â€”' : v.trim();

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
              : 'Rows ${_currentPageStart + 1}â€“$_currentPageEnd of ${_applicantRows.length}',
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
                      name.isEmpty ? 'â€”' : name,
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
                            ? 'â€”'
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
                            ? 'â€”'
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
        printModule: 'rsp',
        printFormKey: 'selection_lineup',
      );
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
          subtitle: '${e.date ?? "Ã¢â‚¬â€"} Ã‚Â· ${e.applicants.length} applicant(s)',
          detailDialogTitle: 'Selection line-up Ã¢â‚¬â€ $pos',
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

/// RSP: Turn-Around Time -- moved to turn_around_time_section.dart (RspTurnAroundTimeSection).

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
  String? _statusFilter;
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
      if (_statusFilter != null && _statusFilter!.isNotEmpty) {
        if (_applicationDisplayStatus(app) != _statusFilter) return false;
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
    if (_statusFilter != null && _statusFilter!.trim().isNotEmpty) {
      parts.add('Status: ${_statusFilter!.trim()}');
    }
    if (_searchQuery.isNotEmpty) {
      parts.add('Search: $_searchQuery');
    }
    if (parts.isEmpty) return 'Filters: none (all applications)';
    return 'Filters: ${parts.join(' · ')}';
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

  ({String province, String city, String barangay, String street})
  _appAddressParts(RecruitmentApplication app) {
    final p = parseStoredAddress(app.address);
    return (
      province: p.province,
      city: p.city,
      barangay: p.barangay,
      street: p.street,
    );
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
          constraints: const BoxConstraints(maxWidth: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: fg.withValues(alpha: 0.22)),
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
                  maxLines: 1,
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

  bool get _hasActiveFilters =>
      _selectedPositionFilter != null ||
      _selectedAppliedDate != null ||
      _statusFilter != null ||
      _searchQuery.isNotEmpty;

  void _clearAllFilters() {
    setState(() {
      _selectedPositionFilter = null;
      _selectedAppliedDate = null;
      _statusFilter = null;
      _searchController.clear();
    });
  }

  Widget _filterDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    required Color hairline,
    double width = 220,
  }) {
    return Semantics(
      label: label,
      child: SizedBox(
        width: width,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: value,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
                borderRadius: BorderRadius.circular(10),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Set<String> get _statusFilterOptions {
    final out = <String>{};
    for (final app in _applications) {
      out.add(_applicationDisplayStatus(app));
    }
    return out;
  }

  bool _isHiredApp(RecruitmentApplication app) =>
      app.hiredUserId != null || app.status == 'registered';

  int get _summaryTotal => _applications.length;

  int get _summaryForReview =>
      _applications.where((a) => a.status == 'submitted').length;

  int get _summaryHired => _applications.where(_isHiredApp).length;

  int get _summaryPassed => _applications.where((a) {
    if (_isHiredApp(a)) return false;
    return a.status == 'passed' || a.finalInterviewPassed == true;
  }).length;

  int get _summaryInProgress => _applications.where((a) {
    if (_isHiredApp(a)) return false;
    if (a.status == 'submitted') return false;
    if (a.status == 'failed' || a.status == 'document_declined') return false;
    if (a.finalInterviewPassed == false) return false;
    if (a.status == 'passed' || a.finalInterviewPassed == true) return false;
    return true;
  }).length;

  int _docsSubmittedCount(RecruitmentApplication app) {
    var n = 0;
    for (final kind in RspApplicationDocKind.values) {
      var path = app.docPath(kind);
      if (path == null &&
          kind == RspApplicationDocKind.resume &&
          app.attachmentPath != null) {
        path = app.attachmentPath;
      }
      if (path != null && path.trim().isNotEmpty) n++;
    }
    return n;
  }

  Future<void> _confirmSyncAttachments() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync attachments from storage?'),
        content: const Text(
          'Link files already in storage to applications that show “No file”. This does not delete or overwrite existing linked documents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy),
            child: const Text('Sync'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _syncAttachmentsFromStorage();
  }

  Future<void> _openApplicantDetails(
    RecruitmentApplication app, {
    int initialTab = 0,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Applicant details',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: AppTheme.dashPanelOf(ctx),
            elevation: 12,
            child: SizedBox(
              width: MediaQuery.sizeOf(ctx).width < 720
                  ? MediaQuery.sizeOf(ctx).width
                  : 560,
              height: MediaQuery.sizeOf(ctx).height,
              child: _ApplicantDetailsDrawer(
                app: app,
                exam: _examResults[app.id.toLowerCase()],
                initialTab: initialTab,
                statusBadge: _applicationStatusBadge(
                  ctx,
                  _applicationDisplayStatus(app),
                ),
                formatDate: _formatDateShort,
                displayOrNa: _displayOrNa,
                addressParts: _appAddressParts,
                sectionScore: _sectionScorePercent,
                beiScore: _beiSectionScorePercent,
                onEdit: () {
                  Navigator.of(ctx).pop();
                  _showEditApplicantDialog(app);
                },
                onDelete: () {
                  Navigator.of(ctx).pop();
                  _confirmDeleteApplicantRow(context, app);
                },
                onUpdated: _load,
                onDeleteApplicant: _deleteApplicant,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  Widget _summaryCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
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

  Widget _summaryRow({required bool compact}) {
    final tiles = [
      _summaryCard(
        label: 'Total Applicants',
        value: _summaryTotal,
        icon: Icons.people_outline_rounded,
        color: AppTheme.primaryNavy,
      ),
      _summaryCard(
        label: 'In Progress',
        value: _summaryInProgress,
        icon: Icons.timelapse_rounded,
        color: AppTheme.primaryNavy,
      ),
      _summaryCard(
        label: 'For Review',
        value: _summaryForReview,
        icon: Icons.fact_check_outlined,
        color: const Color(0xFF1565C0),
      ),
      _summaryCard(
        label: 'Passed',
        value: _summaryPassed,
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF2E7D32),
      ),
      _summaryCard(
        label: 'Hired',
        value: _summaryHired,
        icon: Icons.badge_outlined,
        color: const Color(0xFF6A1B9A),
      ),
    ];
    if (compact) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 8),
              Expanded(child: tiles[1]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: tiles[2]),
              const SizedBox(width: 8),
              Expanded(child: tiles[3]),
            ],
          ),
          const SizedBox(height: 8),
          tiles[4],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  Widget _docsSummaryChip(RecruitmentApplication app) {
    final have = _docsSubmittedCount(app);
    const total = 4;
    final complete = have >= total;
    final color = complete ? const Color(0xFF2E7D32) : AppTheme.primaryNavy;
    return InkWell(
      onTap: () => _openApplicantDetails(app, initialTab: 1),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                complete ? '$have / $total Complete' : '$have / $total Submitted',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _applicantActionsMenu(RecruitmentApplication app) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _showEditApplicantDialog(app);
          case 'delete':
            _confirmDeleteApplicantRow(context, app);
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(
          value: 'delete',
          child: Text(
            'Delete',
            style: TextStyle(color: Color(0xFFC62828)),
          ),
        ),
      ],
    );
  }

  Widget _buildApplicationsDirectory(
    BuildContext context,
    List<RecruitmentApplication> apps,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final mobile = w < 768;
        final tablet = w >= 768 && w < 1024;
        if (mobile) {
          return Column(
            children: [
              for (final app in apps) ...[
                _applicantMobileCard(context, app),
                const SizedBox(height: 10),
              ],
            ],
          );
        }
        return _applicantDesktopTable(
          context,
          apps,
          showContactAndDate: !tablet,
        );
      },
    );
  }

  Widget _applicantMobileCard(
    BuildContext context,
    RecruitmentApplication app,
  ) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openApplicantDetails(app),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
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
                          app.fullName.trim().isEmpty
                              ? 'Unnamed applicant'
                              : app.fullName.trim(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayOrNa(app.applicantNumber),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _applicantActionsMenu(app),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (app.positionAppliedFor ?? '').trim().isEmpty
                    ? '—'
                    : app.positionAppliedFor!.trim(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
              const SizedBox(height: 8),
              _applicationStatusBadge(context, _applicationDisplayStatus(app)),
              const SizedBox(height: 8),
              Text(
                app.email,
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
              if ((app.phone ?? '').trim().isNotEmpty)
                Text(
                  app.phone!.trim(),
                  style: TextStyle(fontSize: 12.5, color: secondary),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _docsSummaryChip(app),
                  const Spacer(),
                  Text(
                    app.createdAt == null
                        ? '—'
                        : _formatDateShort(app.createdAt!),
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _openApplicantDetails(app),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('View Applicant'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _applicantDesktopTable(
    BuildContext context,
    List<RecruitmentApplication> apps, {
    required bool showContactAndDate,
  }) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
      letterSpacing: 0.3,
      color: AppTheme.dashIsDark(context)
          ? AppTheme.primaryNavyLight
          : AppTheme.letterheadNavy,
    );

    Widget header(String t, {int flex = 2}) => Expanded(
      flex: flex,
      child: Text(t, style: headerStyle),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            border: Border(bottom: BorderSide(color: hairline)),
          ),
          child: Row(
            children: [
              header('Applicant', flex: 3),
              header('Position', flex: 2),
              if (showContactAndDate) header('Contact', flex: 3),
              if (showContactAndDate) header('Applied', flex: 2),
              header('Status', flex: 2),
              header('Documents', flex: 2),
              const SizedBox(
                width: 96,
                child: Text('Actions', textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        ...List.generate(apps.length, (i) {
          final app = apps[i];
          return Material(
            color: i.isOdd
                ? AppTheme.sectionAltOf(context).withValues(alpha: 0.4)
                : Colors.transparent,
            child: InkWell(
              onTap: () => _openApplicantDetails(app),
              hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.04),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: hairline)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.fullName.trim().isEmpty
                                ? 'Unnamed applicant'
                                : app.fullName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _displayOrNa(app.applicantNumber),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE85D04),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        (app.positionAppliedFor ?? '').trim().isEmpty
                            ? '—'
                            : app.positionAppliedFor!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: primary),
                      ),
                    ),
                    if (showContactAndDate)
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: primary),
                            ),
                            if ((app.phone ?? '').trim().isNotEmpty)
                              Text(
                                app.phone!.trim(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondary,
                  ),
                ),
              ],
            ),
                      ),
                    if (showContactAndDate)
                      Expanded(
                        flex: 2,
                        child: Text(
                          app.createdAt == null
                              ? '—'
                              : _formatDateShort(app.createdAt!),
                          style: TextStyle(fontSize: 12.5, color: primary),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: _applicationStatusBadge(
                        context,
                        _applicationDisplayStatus(app),
                      ),
                    ),
                    Expanded(flex: 2, child: _docsSummaryChip(app)),
                    SizedBox(
                      width: 96,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'View applicant',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () => _openApplicantDetails(app),
                            icon: const Icon(Icons.visibility_outlined, size: 20),
                          ),
                          _applicantActionsMenu(app),
                        ],
                      ),
                    ),
                  ],
          ),
        ),
      ),
          );
        }),
      ],
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
    final secondary = AppTheme.dashTextSecondaryOf(context);
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

    final dateFilterLabel = _selectedAppliedDate == null
        ? 'Applied date'
        : _formatDateShort(_selectedAppliedDate!);
    final dateFilterBtn = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(color: hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_outlined,
            size: 18,
            color: AppTheme.dashTextPrimaryOf(context),
          ),
          const SizedBox(width: 8),
          Text(
            dateFilterLabel,
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: 22,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ],
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
                  Text(
                          pageTitle,
                          style: TextStyle(
                            color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.15,
                          ),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    pageSubtitle,
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
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
                  children: [
                    generateReportBtn,
                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dashTextPrimaryOf(context),
                    side: BorderSide(color: hairline),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                          vertical: 12,
                        ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (isApplicationsView)
                  PopupMenuButton<String>(
                    tooltip: 'More actions',
                    onSelected: (v) {
                      if (v == 'sync') _confirmSyncAttachments();
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'sync',
                        enabled: !_loading && !_syncing,
                        child: Text(
                          _syncing
                              ? 'Syncing attachments…'
                              : 'Sync attachments from storage',
                              ),
                            ),
                      ],
                        ),
                      ],
                    ),
                  ],
        ),
        if (isApplicationsView && !_loading) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) =>
                _summaryRow(compact: c.maxWidth < 900),
          ),
        ],
        const SizedBox(height: 14),
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
                  hintText: 'Search applicants...',
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
            _filterDropdown(
              label: 'Position',
              value: _selectedPositionFilter,
              width: 260,
              hairline: hairline,
              items: [
                  const DropdownMenuItem<String>(
                    value: null,
                  child: Text(
                    'All positions',
                    overflow: TextOverflow.ellipsis,
                  ),
                  ),
                  ...(_positionFilterOptions.toList()..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      ))
                      .map(
                      (p) => DropdownMenuItem<String>(
                        value: p,
                        child: Text(p, overflow: TextOverflow.ellipsis),
                      ),
                      ),
                ],
                onChanged: _loading
                    ? null
                  : (value) => setState(() => _selectedPositionFilter = value),
            ),
            _filterDropdown(
              label: 'Status',
              value: _statusFilter,
              width: 200,
              hairline: hairline,
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    'All statuses',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...(_statusFilterOptions.toList()..sort()).map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _statusFilter = value),
            ),
            PopupMenuButton<String>(
              tooltip: 'Applied date',
              enabled: !_loading,
              onSelected: (v) async {
                if (v == 'today') {
                  setState(() => _selectedAppliedDate = DateTime.now());
                  return;
                }
                if (v == 'clear') {
                  setState(() => _selectedAppliedDate = null);
                  return;
                }
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
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'today', child: Text('Today')),
                PopupMenuItem(value: 'pick', child: Text('Choose date…')),
                PopupMenuItem(value: 'clear', child: Text('Clear date')),
              ],
              child: dateFilterBtn,
            ),
            TextButton.icon(
              onPressed: (_loading || !_hasActiveFilters)
                  ? null
                  : _clearAllFilters,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear filters'),
            ),
            Text(
              '${filteredApplications.length} applicant${filteredApplications.length == 1 ? '' : 's'}',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: _buildApplicationsDirectory(
                    context,
                    filteredApplications,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApplicantDetailsDrawer extends StatelessWidget {
  const _ApplicantDetailsDrawer({
    required this.app,
    required this.exam,
    required this.initialTab,
    required this.statusBadge,
    required this.formatDate,
    required this.displayOrNa,
    required this.addressParts,
    required this.sectionScore,
    required this.beiScore,
    required this.onEdit,
    required this.onDelete,
    required this.onUpdated,
    required this.onDeleteApplicant,
  });

  final RecruitmentApplication app;
  final RecruitmentExamResult? exam;
  final int initialTab;
  final Widget statusBadge;
  final String Function(DateTime) formatDate;
  final String Function(String?) displayOrNa;
  final ({String province, String city, String barangay, String street})
  Function(RecruitmentApplication)
  addressParts;
  final double? Function(Map<String, dynamic>?, String) sectionScore;
  final double? Function(Map<String, dynamic>?) beiScore;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onUpdated;
  final Future<void> Function(String) onDeleteApplicant;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final hairline = AppTheme.dashHairlineOf(context);
    final compactActions = MediaQuery.sizeOf(context).width < 420;
    final name = app.fullName.trim().isEmpty
        ? 'Unnamed applicant'
        : app.fullName.trim();
    final position = (app.positionAppliedFor ?? '').trim().isEmpty
        ? '—'
        : app.positionAppliedFor!.trim();

    return DefaultTabController(
      length: 4,
      initialIndex: initialTab.clamp(0, 3),
      child: ColoredBox(
        color: AppTheme.dashCanvasOf(context),
        child: SafeArea(
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
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Applicant details',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: primary,
                        ),
                      ),
                    ),
                    if (compactActions) ...[
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: const Color(0xFFC62828),
                      ),
                    ] else ...[
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        style: TextButton.styleFrom(
                          foregroundColor: primary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFC62828),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  decoration: BoxDecoration(
                    color: AppTheme.dashPanelOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: hairline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _initialsAvatar(context, name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                                        Text(
                              name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                color: primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    displayOrNa(app.applicantNumber),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11.5,
                                      letterSpacing: 0.3,
                                      color: Color(0xFFE85D04),
                                    ),
                                  ),
                                ),
                                        Text(
                                  position,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            statusBadge,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Material(
                color: AppTheme.dashPanelOf(context),
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Documents'),
                    Tab(text: 'Assessment'),
                    Tab(text: 'Hiring Progress'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _overviewTab(context),
                    _documentsTab(context),
                    _assessmentTab(context),
                    _progressTab(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initialsOf(String name) {
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

  Widget _initialsAvatar(BuildContext context, String name) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: 0.22),
        ),
      ),
      alignment: Alignment.center,
                                            child: Text(
        _initialsOf(name),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: AppTheme.dashIsDark(context)
              ? AppTheme.primaryNavyLight
              : AppTheme.primaryNavy,
        ),
      ),
    );
  }

  Widget _sectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryNavy),
              const SizedBox(width: 8),
                                          Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _infoField(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                                          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 3),
                                          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoGrid(BuildContext context, List<(String, String)> fields) {
    final wide = MediaQuery.sizeOf(context).width >= 520;
    final cells = fields
        .map((f) => _infoField(context, f.$1, f.$2))
        .toList();
    if (!wide) return Column(children: cells);
    return Column(
      children: [
        for (var i = 0; i < cells.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[i]),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < cells.length ? cells[i + 1] : const SizedBox(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _overviewTab(BuildContext context) {
    final addr = addressParts(app);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _sectionCard(
          context: context,
          title: 'Personal information',
          icon: Icons.person_outline_rounded,
          children: [
            _infoGrid(context, [
              ('Complete name', displayOrNa(app.fullName)),
              ('Gender', displayOrNa(app.sex)),
              ('Age', displayOrNa(app.age)),
              ('Civil status', displayOrNa(app.civilStatus)),
              ('Course', displayOrNa(app.course)),
            ]),
          ],
        ),
        _sectionCard(
          context: context,
          title: 'Contact information',
          icon: Icons.contact_mail_outlined,
          children: [
            _infoGrid(context, [
              ('Email', displayOrNa(app.email)),
              ('Phone', displayOrNa(app.phone)),
            ]),
          ],
        ),
        _sectionCard(
          context: context,
          title: 'Address',
          icon: Icons.location_on_outlined,
          children: [
            _infoGrid(context, [
              ('Province', displayOrNa(addr.province)),
              ('City / Municipality', displayOrNa(addr.city)),
              ('Barangay', displayOrNa(addr.barangay)),
              ('Street', displayOrNa(addr.street)),
            ]),
          ],
        ),
        _sectionCard(
          context: context,
          title: 'Application information',
          icon: Icons.work_outline_rounded,
          children: [
            _infoGrid(context, [
              ('Position applied', displayOrNa(app.positionAppliedFor)),
              (
                'Applied date',
                app.createdAt == null ? '—' : formatDate(app.createdAt!),
              ),
              ('Applicant ID', displayOrNa(app.applicantNumber)),
            ]),
          ],
        ),
      ],
    );
  }

  Widget _documentsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        for (final kind in RspApplicationDocKind.values)
          _sectionCard(
            context: context,
            title: switch (kind) {
              RspApplicationDocKind.applicationLetter => 'Application Letter',
              RspApplicationDocKind.resume => 'Resume',
              RspApplicationDocKind.tor => 'TOR',
              RspApplicationDocKind.eligibilityTrainings =>
                'Eligibility / Trainings',
            },
            icon: Icons.description_outlined,
            children: [
              _TypedDocAdminCell(
                app: app,
                kind: kind,
                onFileRemoved: onUpdated,
              ),
            ],
          ),
        _sectionCard(
          context: context,
          title: 'Document review',
          icon: Icons.fact_check_outlined,
          children: [
            _DocumentReviewCell(
              app: app,
              onUpdated: onUpdated,
              onDeleteApplicant: onDeleteApplicant,
            ),
          ],
        ),
      ],
    );
  }

  Widget _scoreTile(
    BuildContext context, {
    required String label,
    required String value,
    Color? accent,
  }) {
    final color = accent ?? AppTheme.dashTextPrimaryOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _assessmentTab(BuildContext context) {
    final e = exam;
    if (e == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 36,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 10),
                                          Text(
                'No exam recorded yet',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.dashTextPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scores will appear here after the applicant takes the examination.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
    final passed = e.passed;
    final resultColor = passed
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: resultColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: resultColor.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(
                passed
                    ? Icons.check_circle_outline_rounded
                    : Icons.cancel_outlined,
                color: resultColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passed ? 'Passed' : 'Failed',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: resultColor,
                      ),
                    ),
                    Text(
                      'Overall ${e.scorePercent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _scoreTile(
                context,
                label: 'Overall',
                value: '${e.scorePercent.toStringAsFixed(1)}%',
                accent: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _scoreTile(
                context,
                label: 'General',
                value: pct(sectionScore(e.answersJson, 'general')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _scoreTile(
                context,
                label: 'Math',
                value: pct(sectionScore(e.answersJson, 'math')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _scoreTile(
                context,
                label: 'Information',
                value: pct(sectionScore(e.answersJson, 'general_info')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _scoreTile(
          context,
          label: 'BEI',
          value: pct(beiScore(e.answersJson)),
        ),
      ],
    );
  }

  Widget _progressTab(BuildContext context) {
    final steps = _hiringPipelineSteps(context);
    final doneCount = steps.where((s) => s.status == _PipelineTone.done).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppTheme.dashPanelOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                                            children: [
                  const Icon(
                    Icons.flag_outlined,
                    size: 16,
                    color: AppTheme.primaryNavy,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Hiring progress',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$doneCount of ${steps.length} complete',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < steps.length; i++)
                _progressStep(
                                                      context,
                  label: steps[i].label,
                  detail: steps[i].detail,
                  status: steps[i].status,
                  isLast: i == steps.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _pipelineHired =>
      app.status == 'registered' ||
      (app.hiredUserId != null && app.hiredUserId!.trim().isNotEmpty);

  bool get _pipelineBeiPending =>
      exam != null && !exam!.beiGradingComplete;

  bool get _pipelineExamPassed =>
      !_pipelineBeiPending &&
      ((exam?.passed ?? false) ||
          app.status == 'passed' ||
          app.status == 'registered' ||
          _pipelineHired);

  bool get _pipelineExamFailed =>
      !_pipelineBeiPending &&
      ((exam?.passed == false) || app.status == 'failed');

  String _pipelineWhen(BuildContext context, DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '${formatDate(local)} · $time';
  }

  List<({String label, String detail, _PipelineTone status})>
  _hiringPipelineSteps(BuildContext context) {
    final status = app.status;
    final hasExam = exam != null;

    late final _PipelineTone docsTone;
    late final String docsDetail;
    if (status == 'document_declined') {
      docsTone = _PipelineTone.failed;
      docsDetail = 'Documents declined.';
    } else if (status == 'submitted' && !hasExam) {
      docsTone = _PipelineTone.current;
      docsDetail = 'Awaiting HR document approval.';
    } else if (status == 'document_approved' ||
        status == 'exam_taken' ||
        status == 'passed' ||
        status == 'failed' ||
        status == 'registered' ||
        hasExam ||
        _pipelineHired) {
      docsTone = _PipelineTone.done;
      docsDetail = 'Documents approved.';
    } else {
      docsTone = _PipelineTone.pending;
      docsDetail = 'Waiting for document review.';
    }

    late final _PipelineTone examTone;
    late final String examDetail;
    if (_pipelineBeiPending) {
      examTone = _PipelineTone.current;
      examDetail = 'Written exam submitted. BEI grading in progress.';
    } else if (hasExam ||
        status == 'passed' ||
        status == 'failed' ||
        status == 'registered' ||
        _pipelineHired) {
      examTone = _PipelineTone.done;
      examDetail = 'Screening exam completed.';
    } else if (status == 'document_approved' || status == 'exam_taken') {
      examTone = _PipelineTone.current;
      examDetail = status == 'exam_taken'
          ? 'Exam taken. Waiting for recorded result.'
          : 'Eligible to take the screening exam.';
    } else {
      examTone = _PipelineTone.pending;
      examDetail = 'Available after documents are approved.';
    }

    late final _PipelineTone resultTone;
    late final String resultDetail;
    if (_pipelineBeiPending) {
      resultTone = _PipelineTone.current;
      resultDetail = 'BEI scores are not complete yet.';
    } else if (_pipelineExamPassed) {
      resultTone = _PipelineTone.done;
      resultDetail = 'Passed the screening exam.';
    } else if (_pipelineExamFailed) {
      resultTone = _PipelineTone.failed;
      resultDetail = 'Did not pass the screening exam.';
    } else {
      resultTone = _PipelineTone.pending;
      resultDetail = 'Result appears after the exam is completed and graded.';
    }

    late final _PipelineTone interviewTone;
    late final String interviewDetail;
    if (_pipelineHired || app.finalInterviewPassed == true) {
      interviewTone = _PipelineTone.done;
      interviewDetail = 'Passed deliberation / final interview.';
    } else if (app.finalInterviewPassed == false) {
      interviewTone = _PipelineTone.failed;
      interviewDetail = 'Did not pass the final interview.';
    } else if (!_pipelineExamPassed) {
      interviewTone = _PipelineTone.pending;
      interviewDetail = 'Available after the applicant passes the exam.';
    } else if (app.finalInterviewAt != null) {
      interviewTone = _PipelineTone.current;
      interviewDetail =
          'Scheduled: ${_pipelineWhen(context, app.finalInterviewAt)}. Waiting for result.';
    } else {
      interviewTone = _PipelineTone.current;
      interviewDetail = 'Exam passed. Waiting for deliberation schedule.';
    }

    late final _PipelineTone reqTone;
    late final String reqDetail;
    if (_pipelineHired || app.finalRequirementsApproved) {
      reqTone = _PipelineTone.done;
      reqDetail = 'Medical certificate, drug test, and NBI clearance approved.';
    } else if (app.finalInterviewPassed == false) {
      reqTone = _PipelineTone.failed;
      reqDetail = 'Not applicable — final interview was not passed.';
    } else if (app.finalInterviewPassed != true) {
      reqTone = _PipelineTone.pending;
      reqDetail = 'Available after the applicant passes deliberation.';
    } else if (app.hasRejectedFinalRequirement) {
      reqTone = _PipelineTone.current;
      reqDetail = 'A final requirement was rejected and needs re-upload.';
    } else if (app.hasAllFinalRequirementsUploaded) {
      reqTone = _PipelineTone.current;
      reqDetail = 'All three documents uploaded. Awaiting HR review.';
    } else {
      reqTone = _PipelineTone.current;
      reqDetail = 'Waiting for medical certificate, drug test, and NBI clearance.';
    }

    late final _PipelineTone orientTone;
    late final String orientDetail;
    if (_pipelineHired || app.orientationAttended == true) {
      orientTone = _PipelineTone.done;
      orientDetail = 'Orientation attendance confirmed.';
    } else if (!app.finalRequirementsApproved) {
      orientTone = _PipelineTone.pending;
      orientDetail = 'Available after final requirements are approved.';
    } else if (app.orientationAttended == false) {
      orientTone = _PipelineTone.failed;
      orientDetail = 'Recorded as missed / did not attend.';
    } else if (app.orientationAt != null) {
      orientTone = _PipelineTone.current;
      orientDetail =
          'Scheduled: ${_pipelineWhen(context, app.orientationAt)}. Waiting for attendance.';
    } else {
      orientTone = _PipelineTone.current;
      orientDetail = 'Final requirements approved. Waiting for orientation schedule.';
    }

    late final _PipelineTone accountTone;
    late final String accountDetail;
    if (_pipelineHired || app.hrAccountSetupDone) {
      accountTone = _PipelineTone.done;
      accountDetail = _pipelineHired
          ? 'Employee account is linked.'
          : 'HR marked account setup as done.';
    } else if (app.finalInterviewPassed == false || _pipelineExamFailed) {
      accountTone = _PipelineTone.failed;
      accountDetail = 'Not applicable — applicant did not continue to hiring.';
    } else if (app.orientationAttended == true) {
      accountTone = _PipelineTone.current;
      accountDetail = 'Orientation done. Waiting for employee account setup.';
    } else if (_pipelineExamPassed && app.finalInterviewPassed == true) {
      accountTone = _PipelineTone.pending;
      accountDetail = 'Available after orientation is completed.';
    } else {
      accountTone = _PipelineTone.pending;
      accountDetail = 'Available after the applicant is cleared for hiring.';
    }

    return [
      (
        label: 'Application submitted',
        detail: 'Application and initial documents received.',
        status: _PipelineTone.done,
      ),
      (
        label: 'Document review',
        detail: docsDetail,
        status: docsTone,
      ),
      (
        label: 'Screening exams',
        detail: examDetail,
        status: examTone,
      ),
      (
        label: 'Exam result',
        detail: resultDetail,
        status: resultTone,
      ),
      (
        label: 'Deliberation',
        detail: interviewDetail,
        status: interviewTone,
      ),
      (
        label: 'Final requirements',
        detail: reqDetail,
        status: reqTone,
      ),
      (
        label: 'Orientation',
        detail: orientDetail,
        status: orientTone,
      ),
      (
        label: 'Account setup',
        detail: accountDetail,
        status: accountTone,
      ),
    ];
  }

  Widget _progressStep(
    BuildContext context, {
    required String label,
    required String detail,
    required _PipelineTone status,
    required bool isLast,
  }) {
    final Color iconColor;
    final IconData icon;
    switch (status) {
      case _PipelineTone.done:
        icon = Icons.check_circle_rounded;
        iconColor = const Color(0xFF2E7D32);
      case _PipelineTone.current:
        icon = Icons.timelapse_rounded;
        iconColor = AppTheme.primaryNavy;
      case _PipelineTone.failed:
        icon = Icons.cancel_rounded;
        iconColor = const Color(0xFFC62828);
      case _PipelineTone.pending:
        icon = Icons.radio_button_unchecked_rounded;
        iconColor = AppTheme.dashTextSecondaryOf(context);
    }
    final lineColor = status == _PipelineTone.done
        ? const Color(0xFF2E7D32)
        : status == _PipelineTone.failed
        ? const Color(0xFFC62828)
        : AppTheme.dashHairlineOf(context);
    final titleColor = status == _PipelineTone.pending
        ? AppTheme.dashTextSecondaryOf(context)
        : AppTheme.dashTextPrimaryOf(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(icon, size: 20, color: iconColor),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppTheme.dashTextSecondaryOf(context),
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

enum _PipelineTone { pending, current, done, failed }

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
                              : 'Record this applicant as passed with 100% on every exam section â€” even without taking the screening exam.',
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
                    // ignore: deprecated_member_use
                    RadioListTile<_AdminPassScoreMode>(
                      value: _AdminPassScoreMode.perfect,
                      groupValue: _mode,
                      onChanged: (v) => setState(() => _mode = v!),
                      title: const Text('Perfect score (100% on all sections)'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    // ignore: deprecated_member_use
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

// _AdminBypassExamChip was removed because it was not referenced anywhere.

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
            message: 'Preview Ã¢â‚¬â€ $fileName',
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
