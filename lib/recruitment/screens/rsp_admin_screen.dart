import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'package:url_launcher/url_launcher.dart';
import '../../data/applicants_profile.dart';
import '../../data/bi_form.dart';
import '../../data/comparative_assessment.dart';
import '../../data/individual_development_plan.dart';
import '../../data/job_vacancy_announcement.dart';
import '../../data/performance_evaluation_form.dart';
import '../../data/promotion_certification.dart';
import '../../data/recruitment_application.dart';
import '../../data/rsp_screening_scores.dart';
import '../../data/selection_lineup.dart';
import '../../data/turn_around_time.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../utils/form_pdf.dart';
import '../../widgets/feature_card.dart';
import '../../widgets/read_only_saved_entry_dialog.dart';
import '../../widgets/rsp_form_header_footer.dart';
import '../../widgets/rsp_ld_saved_records_browser.dart';
import '../widgets/rsp_bei_grading_dialog.dart';
import '../widgets/rsp_final_interview_scheduler.dart';
import '../../api/user_facing_api_error.dart';

/// RSP module: hub with buttons for each RSP feature (Job Vacancies, Applications & Exam Results).
class RspAdminContent extends StatefulWidget {
  const RspAdminContent({super.key, this.onNavigateToSidebarIndex});

  /// Switch admin sidebar tab (e.g. index `5` = Create Account below DocuTracker).
  final ValueChanged<int>? onNavigateToSidebarIndex;

  @override
  State<RspAdminContent> createState() => _RspAdminContentState();
}

class _RspAdminContentState extends State<RspAdminContent> {
  /// 0 = menu, 1 = Job Vacancies, 2 = Applications, … 14 = Turn-Around Time, 15 = Final interview (passed exam)
  int _rspSectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_rspSectionIndex != 0) ...[
          TextButton.icon(
            onPressed: () => setState(() => _rspSectionIndex = 0),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text('Back to RSP'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryNavy),
          ),
          const SizedBox(height: 16),
        ],
        if (_rspSectionIndex == 0) ...[
          Text(
            'RSP',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recruitment, Selection, and Placement. Choose a feature below.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              FeatureCard(
                title: 'Job Vacancies (Landing Page)',
                subtitle: 'Edit the announcement shown on the landing page.',
                icon: Icons.work_rounded,
                onTap: () => setState(() => _rspSectionIndex = 1),
              ),
              FeatureCard(
                title: 'Applications & Exam Results',
                subtitle: 'View applicants, attachments, and exam results.',
                icon: Icons.assignment_rounded,
                onTap: () => setState(() => _rspSectionIndex = 2),
              ),
              FeatureCard(
                title: 'Final interview (passed exam)',
                subtitle:
                    'Set the final interview date and time for applicants who passed the screening exam.',
                icon: Icons.event_available_rounded,
                onTap: () => setState(() => _rspSectionIndex = 15),
              ),
              FeatureCard(
                title: 'BEI / Exam Questions',
                subtitle:
                    'View and edit the 8 Behavioral Event Interview questions applicants answer.',
                icon: Icons.quiz_rounded,
                onTap: () => setState(() => _rspSectionIndex = 3),
              ),
              FeatureCard(
                title: 'General Exam (LGU-Plaridel)',
                subtitle:
                    'View and edit the General Exam multiple-choice questions for applicants.',
                icon: Icons.assignment_turned_in_rounded,
                onTap: () => setState(() => _rspSectionIndex = 4),
              ),
              FeatureCard(
                title: 'Mathematics Exam',
                subtitle:
                    'View and edit the Mathematics exam questions for applicants.',
                icon: Icons.calculate_rounded,
                onTap: () => setState(() => _rspSectionIndex = 5),
              ),
              FeatureCard(
                title: 'General Information Exam',
                subtitle:
                    'View and edit the General Information exam questions for applicants.',
                icon: Icons.info_outline_rounded,
                onTap: () => setState(() => _rspSectionIndex = 6),
              ),
              FeatureCard(
                title: 'Background Investigation (BI) Form',
                subtitle:
                    'Record BI form entries: applicant, respondent, and competency ratings.',
                icon: Icons.verified_user_rounded,
                onTap: () => setState(() => _rspSectionIndex = 7),
              ),
              FeatureCard(
                title: 'Performance / Functional Evaluation',
                subtitle:
                    'Record functional areas and performance narratives for applicants.',
                icon: Icons.assessment_rounded,
                onTap: () => setState(() => _rspSectionIndex = 8),
              ),
              FeatureCard(
                title: 'Individual Development Plan (IDP)',
                subtitle:
                    'Record employee IDP: qualifications, succession analysis, development plan.',
                icon: Icons.trending_up_rounded,
                onTap: () => setState(() => _rspSectionIndex = 9),
              ),
              FeatureCard(
                title: 'Applicants Profile',
                subtitle:
                    'Job vacancy details and list of applicants (name, course, address, sex, age, civil status, remark).',
                icon: Icons.people_alt_rounded,
                onTap: () => setState(() => _rspSectionIndex = 10),
              ),
              FeatureCard(
                title: 'Comparative Assessment (Promotion)',
                subtitle:
                    'Merit Promotion Board: position, minimum requirements, and candidate comparison table. Form only, no pre-filled names.',
                icon: Icons.balance_rounded,
                onTap: () => setState(() => _rspSectionIndex = 11),
              ),
              FeatureCard(
                title: 'Promotion Certification / Screening',
                subtitle:
                    'Certification that candidates have been screened and found qualified. Form only, no pre-filled names.',
                icon: Icons.verified_rounded,
                onTap: () => setState(() => _rspSectionIndex = 12),
              ),
              FeatureCard(
                title: 'Selection Line-up',
                subtitle:
                    'Date, agency/office, vacant position, item no., and applicants table (name, education, experience, training, eligibility). Form only.',
                icon: Icons.format_list_numbered_rounded,
                onTap: () => setState(() => _rspSectionIndex = 13),
              ),
              FeatureCard(
                title: 'Turn-Around Time',
                subtitle:
                    'Merit Promotion Board: position, office, dates, and applicant tracking table (assessment, exam, deliberation, job offer, assumption, cost). Form only.',
                icon: Icons.schedule_rounded,
                onTap: () => setState(() => _rspSectionIndex = 14),
              ),
            ],
          ),
        ] else if (_rspSectionIndex == 1)
          const _RspJobVacanciesForm()
        else if (_rspSectionIndex == 2)
          _RspApplicationsMonitor()
        else if (_rspSectionIndex == 3)
          const _RspBeiQuestionsEditor()
        else if (_rspSectionIndex == 4)
          const _RspGeneralExamEditor()
        else if (_rspSectionIndex == 5)
          const _RspMathExamEditor()
        else if (_rspSectionIndex == 6)
          const _RspGeneralInfoExamEditor()
        else if (_rspSectionIndex == 7)
          const _RspBiFormSection()
        else if (_rspSectionIndex == 8)
          const _RspPerformanceEvaluationSection()
        else if (_rspSectionIndex == 9)
          const _RspIdpSection()
        else if (_rspSectionIndex == 10)
          const _RspApplicantsProfileSection()
        else if (_rspSectionIndex == 11)
          const _RspComparativeAssessmentSection()
        else if (_rspSectionIndex == 12)
          const _RspPromotionCertificationSection()
        else if (_rspSectionIndex == 13)
          const _RspSelectionLineupSection()
        else if (_rspSectionIndex == 14)
          const _RspTurnAroundTimeSection()
        else if (_rspSectionIndex == 15)
          RspFinalInterviewScheduler(
            onGoToCreateAccount: () => widget.onNavigateToSidebarIndex?.call(5),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

/// Default 8 BEI questions when DB has none (so admin can edit and save).
const _defaultBeiQuestions = [
  'Tell me about a time when you had to collaborate with a co-worker that you had a hard time getting along with?',
  'Describe for me a time when you were under a significant amount of pressure at work. How did you deal with it?',
  'Tell me about a time when you were ask to work on a task that you had never done before.',
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
        Text(
          '8 Behavioral Event Interview (BEI) Questions',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'For New Applicant/s and Promotion/s. Edit the questions below; applicants will see these when they take the exam.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...List.generate(_controllers.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}.',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _controllers[i],
                              onChanged: (_) => setState(() {}),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Question text...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: AppTheme.offWhite,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _controllers.length > 1
                            ? () {
                                _controllers[i].dispose();
                                _controllers.removeAt(i);
                                setState(() {});
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove question',
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  _controllers.add(TextEditingController());
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_saving ? 'Saving...' : 'Save BEI questions'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
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

/// Admin-only: minutes per MCQ exam (0 = no time limit for applicants).
class _RspExamTimeLimitEditor extends StatefulWidget {
  const _RspExamTimeLimitEditor({required this.examType});
  final String examType;

  @override
  State<_RspExamTimeLimitEditor> createState() => _RspExamTimeLimitEditorState();
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
          content: Text('Enter minutes between 0 (no limit) and 1440 (24 hours).'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time limit saved.')),
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

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.timer_outlined, color: AppTheme.primaryNavy, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Applicant time limit',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Minutes allowed for this exam (0 = no countdown). Applicants see a timer during the exam.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 88,
                          child: TextField(
                            controller: _minutesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Minutes',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: AppTheme.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonal(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save limit'),
                        ),
                      ],
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
        Text(
          'General Exam for LGU-Plaridel Applicants',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Multiple-choice questions. Edit below; set the correct option per question. Applicants will see these after the BEI.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        const _RspExamTimeLimitEditor(examType: 'general'),
        const SizedBox(height: 24),
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final optCount = item.optionControllers.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${i + 1}. Question',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: item.questionController,
                                  onChanged: (_) => setState(() {}),
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    hintText: 'Question text...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.offWhite,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Options (select correct one)',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...List.generate(optCount, (j) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Radio<int>(
                                          value: j,
                                          groupValue: item.correctIndex,
                                          onChanged: (v) => setState(
                                            () => item.correctIndex = v ?? 0,
                                          ),
                                        ),
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                item.optionControllers[j],
                                            onChanged: (_) => setState(() {}),
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Option ${String.fromCharCode(97 + j)}',
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              filled: true,
                                              fillColor: AppTheme.offWhite,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                if (optCount < 6)
                                  TextButton.icon(
                                    onPressed: () {
                                      item.optionControllers.add(
                                        TextEditingController(),
                                      );
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add option'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.primaryNavy,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_items.length > 1)
                            IconButton(
                              onPressed: () {
                                final removed = _items.removeAt(i);
                                removed.questionController.dispose();
                                for (final c in removed.optionControllers) {
                                  c.dispose();
                                }
                                setState(() {});
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: 'Remove question',
                              color: Colors.red.shade700,
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _items.add(_makeItem('', <String>['', '', '', ''], 0));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saving ? 'Saving...' : 'Save General Exam questions',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        Text(
          'Mathematics Exam',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Multiple-choice mathematics questions. Edit below; set the correct option per question. Applicants will see these after the General Exam.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        const _RspExamTimeLimitEditor(examType: 'math'),
        const SizedBox(height: 24),
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final optCount = item.optionControllers.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. Question',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: item.questionController,
                              onChanged: (_) => setState(() {}),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Question text...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: AppTheme.offWhite,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Options (select correct one)',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...List.generate(optCount, (j) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Radio<int>(
                                      value: j,
                                      groupValue: item.correctIndex,
                                      onChanged: (v) => setState(
                                        () => item.correctIndex = v ?? 0,
                                      ),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: item.optionControllers[j],
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Option ${String.fromCharCode(97 + j)}',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: AppTheme.offWhite,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (optCount < 6)
                              TextButton.icon(
                                onPressed: () {
                                  item.optionControllers.add(
                                    TextEditingController(),
                                  );
                                  setState(() {});
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add option'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primaryNavy,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_items.length > 1)
                        IconButton(
                          onPressed: () {
                            final removed = _items.removeAt(i);
                            removed.questionController.dispose();
                            for (final c in removed.optionControllers) {
                              c.dispose();
                            }
                            setState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove question',
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _items.add(_makeItem('', <String>['', '', '', ''], 0));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saving ? 'Saving...' : 'Save Mathematics Exam questions',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        Text(
          'General Information Exam',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Multiple-choice questions on general information (e.g. constitution, labor). Edit below; set the correct option per question.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        const _RspExamTimeLimitEditor(examType: 'general_info'),
        const SizedBox(height: 24),
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final optCount = item.optionControllers.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. Question',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: item.questionController,
                              onChanged: (_) => setState(() {}),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Question text...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: AppTheme.offWhite,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Options (select correct one)',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...List.generate(optCount, (j) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Radio<int>(
                                      value: j,
                                      groupValue: item.correctIndex,
                                      onChanged: (v) => setState(
                                        () => item.correctIndex = v ?? 0,
                                      ),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: item.optionControllers[j],
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Option ${String.fromCharCode(97 + j)}',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: AppTheme.offWhite,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (optCount < 6)
                              TextButton.icon(
                                onPressed: () {
                                  item.optionControllers.add(
                                    TextEditingController(),
                                  );
                                  setState(() {});
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add option'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primaryNavy,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_items.length > 1)
                        IconButton(
                          onPressed: () {
                            final removed = _items.removeAt(i);
                            removed.questionController.dispose();
                            for (final c in removed.optionControllers) {
                              c.dispose();
                            }
                            setState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove question',
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  _items.add(_makeItem('', <String>['', '', '', ''], 0));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add question'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : 'Save General Information Exam questions',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// RSP: Background Investigation (BI) Form â€” list entries and add/edit form.
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
              subtitle: '${e.respondentName} · ${e.respondentRelationship}',
              detailDialogTitle: 'BI form — ${e.applicantName}',
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
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Record BI evaluations: applicant and respondent details, plus competency ratings (1\u20135).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No BI entries yet. Tap "Add BI entry" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
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
      final doc = await FormPdf.buildBiFormPdf(entry);
      await FormPdf.printDocument(doc, name: 'BI_Form.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
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
  }

  @override
  void dispose() {
    _applicantName.dispose();
    _applicantDept.dispose();
    _applicantPosition.dispose();
    _positionApplied.dispose();
    _respondentName.dispose();
    _respondentPosition.dispose();
    super.dispose();
  }

  BiFormEntry _buildCurrentEntry() {
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
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
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
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
                            groupValue: _relationship,
                            onChanged: (v) =>
                                setState(() => _relationship = v!),
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
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Using the following rating guide please check (/) the appropriate box opposite each behavioral Indicator:',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
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
                      color: AppTheme.primaryNavy.withOpacity(0.08),
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                if (widget.entry.updatedAt != null)
                  Text(
                    'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Applicant')),
          DataColumn(label: Text('Respondent')),
          DataColumn(label: Text('Relationship')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(e.applicantName)),
              DataCell(Text(e.respondentName)),
              DataCell(Text(e.respondentRelationship)),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => showReadOnlySavedEntryDialog(
                        context,
                        title: 'Saved BI form',
                        previewBuilder: () => _BiFormEditor(
                          readOnly: true,
                          entry: e,
                          onSave: (_) {},
                          onCancel: () {},
                          onPrint: (_) async {},
                          onDownloadPdf: (_) async {},
                        ),
                        contentWidth: 920,
                      ),
                      child: const Text('View'),
                    ),
                    TextButton(
                      onPressed: () => onEdit(e),
                      child: const Text('Edit'),
                    ),
                    IconButton(
                      onPressed: () => onPrint(e),
                      icon: const Icon(Icons.print_rounded, size: 20),
                      tooltip: 'Print',
                    ),
                    IconButton(
                      onPressed: () => onDownloadPdf(e),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      tooltip: 'Download PDF',
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete BI entry?'),
                            content: const Text('This cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && e.id != null) onDelete(e.id!);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// RSP: Performance / Functional Evaluation â€” list entries and add/edit form.
class _RspPerformanceEvaluationSection extends StatefulWidget {
  const _RspPerformanceEvaluationSection();

  @override
  State<_RspPerformanceEvaluationSection> createState() =>
      _RspPerformanceEvaluationSectionState();
}

class _RspPerformanceEvaluationSectionState
    extends State<_RspPerformanceEvaluationSection> {
  List<PerformanceEvaluationEntry> _entries = [];
  bool _loading = true;
  PerformanceEvaluationEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await PerformanceEvaluationRepo.instance.list();
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
    setState(() => _editing = const PerformanceEvaluationEntry());
  }

  void _edit(PerformanceEvaluationEntry e) {
    setState(() => _editing = e);
  }

  void _cancelEdit() {
    setState(() => _editing = null);
  }

  void _openSavedRecordsBrowser() {
    showRspLdSavedRecordsBrowser(
      context,
      sheetTitle: 'Saved performance evaluations',
      emptyMessage: 'No evaluations yet.',
      loading: _loading,
      items: _entries.map((e) {
        final areas = e.functionalAreas.isEmpty
            ? '—'
            : e.functionalAreas.join(', ');
        final name = (e.applicantName?.trim().isNotEmpty ?? false)
            ? e.applicantName!
            : '(No name)';
        return SavedRecordListItem(
          title: name,
          subtitle: areas,
          detailDialogTitle: 'Performance evaluation — $name',
          previewContentWidth: 880,
          previewBuilder: () => _PerformanceFormEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printPerf(e),
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
          'Performance / Functional Evaluation',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Record functional areas and performance narratives for applicants.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _PerformanceFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSavePerf,
            onCancel: _cancelEdit,
            onPrint: _printPerf,
            onDownloadPdf: _downloadPerf,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add evaluation'),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No evaluations yet. Tap "Add evaluation" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          )
        else
          _PerformanceFormList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDeletePerf,
            onPrint: _printPerf,
            onDownloadPdf: _downloadPerf,
          ),
      ],
    );
  }

  Future<void> _onSavePerf(PerformanceEvaluationEntry entry) async {
    try {
      if (entry.id == null) {
        await PerformanceEvaluationRepo.instance.insert(entry);
      } else {
        await PerformanceEvaluationRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Evaluation saved.')));
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

  Future<void> _onDeletePerf(String id) async {
    try {
      await PerformanceEvaluationRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Evaluation deleted.')));
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

  Future<void> _printPerf(PerformanceEvaluationEntry entry) async {
    try {
      final doc = await FormPdf.buildPerformanceEvaluationPdf(entry);
      await FormPdf.printDocument(doc, name: 'Performance_Evaluation.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _downloadPerf(PerformanceEvaluationEntry entry) async {
    try {
      final doc = await FormPdf.buildPerformanceEvaluationPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Performance_Evaluation.pdf');
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

class _PerformanceFormEditor extends StatefulWidget {
  const _PerformanceFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final PerformanceEvaluationEntry entry;
  final bool readOnly;
  final void Function(PerformanceEvaluationEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(PerformanceEvaluationEntry) onPrint;
  final Future<void> Function(PerformanceEvaluationEntry) onDownloadPdf;

  @override
  State<_PerformanceFormEditor> createState() => _PerformanceFormEditorState();
}

class _PerformanceFormEditorState extends State<_PerformanceFormEditor> {
  late TextEditingController _applicantName;
  late TextEditingController _otherArea;
  late TextEditingController _perf3Years;
  late TextEditingController _challenges;
  late TextEditingController _compliance;
  late List<bool> _functionalChecks;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _applicantName = TextEditingController(text: e.applicantName ?? '');
    _otherArea = TextEditingController(text: e.otherFunctionalArea ?? '');
    _perf3Years = TextEditingController(text: e.performance3Years ?? '');
    _challenges = TextEditingController(text: e.challengesCoping ?? '');
    _compliance = TextEditingController(text: e.complianceAttendance ?? '');
    _functionalChecks = List.generate(
      PerformanceEvaluationEntry.functionalAreaOptions.length,
      (i) => e.functionalAreas.contains(
        PerformanceEvaluationEntry.functionalAreaOptions[i],
      ),
    );
  }

  @override
  void dispose() {
    _applicantName.dispose();
    _otherArea.dispose();
    _perf3Years.dispose();
    _challenges.dispose();
    _compliance.dispose();
    super.dispose();
  }

  PerformanceEvaluationEntry _buildCurrentEntry() {
    final areas = <String>[];
    for (var i = 0; i < _functionalChecks.length; i++) {
      if (_functionalChecks[i]) {
        areas.add(PerformanceEvaluationEntry.functionalAreaOptions[i]);
      }
    }
    return PerformanceEvaluationEntry(
      id: widget.entry.id,
      applicantName: _applicantName.text.trim().isEmpty
          ? null
          : _applicantName.text.trim(),
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
    const options = PerformanceEvaluationEntry.functionalAreaOptions;
    const leftCount = 6; // Left column: first 6; right column: rest + Other
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(
              formTitle: 'Performance / Functional Evaluation',
            ),
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < leftCount && i < options.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            options[i],
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
                      for (var i = leftCount; i < options.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            options[i],
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
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      RspSpacedOutlineField(
                        child: TextFormField(
                          controller: _otherArea,
                          readOnly: ro,
                          decoration: rspUnderlinedField(''),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PerformanceFormList extends StatelessWidget {
  const _PerformanceFormList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<PerformanceEvaluationEntry> entries;
  final void Function(PerformanceEvaluationEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(PerformanceEvaluationEntry) onPrint;
  final Future<void> Function(PerformanceEvaluationEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Applicant')),
          DataColumn(label: Text('Functional areas')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries.map((e) {
          return DataRow(
            cells: [
              DataCell(Text(e.applicantName ?? 'â€”')),
              DataCell(
                Text(
                  e.functionalAreas.isEmpty
                      ? 'â€”'
                      : e.functionalAreas.join(', '),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => showReadOnlySavedEntryDialog(
                        context,
                        title: 'Saved performance evaluation',
                        previewBuilder: () => _PerformanceFormEditor(
                          readOnly: true,
                          entry: e,
                          onSave: (_) {},
                          onCancel: () {},
                          onPrint: (_) async {},
                          onDownloadPdf: (_) async {},
                        ),
                        contentWidth: 880,
                      ),
                      child: const Text('View'),
                    ),
                    TextButton(
                      onPressed: () => onEdit(e),
                      child: const Text('Edit'),
                    ),
                    IconButton(
                      onPressed: () => onPrint(e),
                      icon: const Icon(Icons.print_rounded, size: 20),
                      tooltip: 'Print',
                    ),
                    IconButton(
                      onPressed: () => onDownloadPdf(e),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      tooltip: 'Download PDF',
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete evaluation?'),
                            content: const Text('This cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && e.id != null) onDelete(e.id!);
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// RSP: Individual Development Plan (IDP) â€” list entries and add/edit form.
class _RspIdpSection extends StatefulWidget {
  const _RspIdpSection();

  @override
  State<_RspIdpSection> createState() => _RspIdpSectionState();
}

class _RspIdpSectionState extends State<_RspIdpSection> {
  List<IdpEntry> _entries = [];
  bool _loading = true;
  IdpEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await IdpRepo.instance.list();
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

  void _startNew() => setState(() => _editing = const IdpEntry());
  void _edit(IdpEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(IdpEntry entry) async {
    try {
      if (entry.id == null) {
        await IdpRepo.instance.insert(entry);
      } else {
        await IdpRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IDP saved.')));
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
      await IdpRepo.instance.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IDP deleted.')));
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

  Future<void> _printIdp(IdpEntry entry) async {
    try {
      final doc = await FormPdf.buildIdpPdf(entry);
      await FormPdf.printDocument(doc, name: 'IDP.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _downloadIdp(IdpEntry entry) async {
    try {
      final doc = await FormPdf.buildIdpPdf(entry);
      await FormPdf.sharePdf(doc, name: 'IDP.pdf');
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
      sheetTitle: 'Saved IDP records',
      emptyMessage: 'No IDP entries yet.',
      loading: _loading,
      items: _entries.map((e) {
        final name = (e.name?.trim().isNotEmpty ?? false)
            ? e.name!
            : '(No name)';
        final sub = '${e.position ?? "—"} · ${e.department ?? "—"}';
        return SavedRecordListItem(
          title: name,
          subtitle: sub,
          detailDialogTitle: 'IDP — $name',
          previewContentWidth: 920,
          previewBuilder: () => _IdpFormEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printIdp(e),
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
          'Individual Development Plan (IDP)',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Record employee IDP: personal/position info, qualifications, succession analysis, and development plan rows.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _IdpFormEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printIdp,
            onDownloadPdf: _downloadIdp,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add IDP'),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No IDP entries yet. Tap "Add IDP" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          )
        else
          _IdpList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printIdp,
            onDownloadPdf: _downloadIdp,
          ),
      ],
    );
  }
}

class _IdpFormEditor extends StatefulWidget {
  const _IdpFormEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final IdpEntry entry;
  final bool readOnly;
  final void Function(IdpEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(IdpEntry) onPrint;
  final Future<void> Function(IdpEntry) onDownloadPdf;

  @override
  State<_IdpFormEditor> createState() => _IdpFormEditorState();
}

class _IdpFormEditorState extends State<_IdpFormEditor> {
  late List<TextEditingController> _controllers;
  late String? _performanceRating;
  late String? _competenceRating;
  late String? _successionPriorityRating;
  late List<Map<String, TextEditingController>> _planRows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _controllers = [
      TextEditingController(text: e.name ?? ''),
      TextEditingController(text: e.position ?? ''),
      TextEditingController(text: e.category ?? ''),
      TextEditingController(text: e.division ?? ''),
      TextEditingController(text: e.department ?? ''),
      TextEditingController(text: e.education ?? ''),
      TextEditingController(text: e.experience ?? ''),
      TextEditingController(text: e.training ?? ''),
      TextEditingController(text: e.eligibility ?? ''),
      TextEditingController(text: e.targetPosition1 ?? ''),
      TextEditingController(text: e.targetPosition2 ?? ''),
      TextEditingController(text: e.avgRating ?? ''),
      TextEditingController(text: e.opcr ?? ''),
      TextEditingController(text: e.ipcr ?? ''),
      TextEditingController(text: e.competencyDescription ?? ''),
      TextEditingController(text: e.successionPriorityScore ?? ''),
      TextEditingController(text: e.preparedBy ?? ''),
      TextEditingController(text: e.reviewedBy ?? ''),
      TextEditingController(text: e.notedBy ?? ''),
      TextEditingController(text: e.approvedBy ?? ''),
    ];
    _performanceRating = e.performanceRating;
    _competenceRating = e.competenceRating;
    _successionPriorityRating = e.successionPriorityRating;
    _planRows = e.developmentPlanRows.isEmpty
        ? [_rowControllers('', '', '', '')]
        : e.developmentPlanRows
              .map(
                (r) => _rowControllers(
                  r.objectives ?? '',
                  r.ldProgram ?? '',
                  r.requirements ?? '',
                  r.timeFrame ?? '',
                ),
              )
              .toList();
  }

  Map<String, TextEditingController> _rowControllers(
    String obj,
    String ld,
    String req,
    String tf,
  ) {
    return {
      'objectives': TextEditingController(text: obj),
      'ld_program': TextEditingController(text: ld),
      'requirements': TextEditingController(text: req),
      'time_frame': TextEditingController(text: tf),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final row in _planRows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addPlanRow() {
    if (widget.readOnly) return;
    setState(() => _planRows.add(_rowControllers('', '', '', '')));
  }

  void _removePlanRow(int index) {
    if (widget.readOnly) return;
    if (_planRows.length <= 1) return;
    setState(() {
      for (final c in _planRows[index].values) {
        c.dispose();
      }
      _planRows.removeAt(index);
    });
  }

  IdpEntry _buildCurrentEntry() {
    final rows = _planRows
        .map(
          (r) => IdpPlanRow(
            objectives: r['objectives']!.text.trim().isEmpty
                ? null
                : r['objectives']!.text.trim(),
            ldProgram: r['ld_program']!.text.trim().isEmpty
                ? null
                : r['ld_program']!.text.trim(),
            requirements: r['requirements']!.text.trim().isEmpty
                ? null
                : r['requirements']!.text.trim(),
            timeFrame: r['time_frame']!.text.trim().isEmpty
                ? null
                : r['time_frame']!.text.trim(),
          ),
        )
        .toList();
    return IdpEntry(
      id: widget.entry.id,
      name: _controllers[0].text.trim().isEmpty
          ? null
          : _controllers[0].text.trim(),
      position: _controllers[1].text.trim().isEmpty
          ? null
          : _controllers[1].text.trim(),
      category: _controllers[2].text.trim().isEmpty
          ? null
          : _controllers[2].text.trim(),
      division: _controllers[3].text.trim().isEmpty
          ? null
          : _controllers[3].text.trim(),
      department: _controllers[4].text.trim().isEmpty
          ? null
          : _controllers[4].text.trim(),
      education: _controllers[5].text.trim().isEmpty
          ? null
          : _controllers[5].text.trim(),
      experience: _controllers[6].text.trim().isEmpty
          ? null
          : _controllers[6].text.trim(),
      training: _controllers[7].text.trim().isEmpty
          ? null
          : _controllers[7].text.trim(),
      eligibility: _controllers[8].text.trim().isEmpty
          ? null
          : _controllers[8].text.trim(),
      targetPosition1: _controllers[9].text.trim().isEmpty
          ? null
          : _controllers[9].text.trim(),
      targetPosition2: _controllers[10].text.trim().isEmpty
          ? null
          : _controllers[10].text.trim(),
      avgRating: _controllers[11].text.trim().isEmpty
          ? null
          : _controllers[11].text.trim(),
      opcr: _controllers[12].text.trim().isEmpty
          ? null
          : _controllers[12].text.trim(),
      ipcr: _controllers[13].text.trim().isEmpty
          ? null
          : _controllers[13].text.trim(),
      performanceRating: _performanceRating,
      competencyDescription: _controllers[14].text.trim().isEmpty
          ? null
          : _controllers[14].text.trim(),
      competenceRating: _competenceRating,
      successionPriorityScore: _controllers[15].text.trim().isEmpty
          ? null
          : _controllers[15].text.trim(),
      successionPriorityRating: _successionPriorityRating,
      developmentPlanRows: rows,
      preparedBy: _controllers[16].text.trim().isEmpty
          ? null
          : _controllers[16].text.trim(),
      reviewedBy: _controllers[17].text.trim().isEmpty
          ? null
          : _controllers[17].text.trim(),
      notedBy: _controllers[18].text.trim().isEmpty
          ? null
          : _controllers[18].text.trim(),
      approvedBy: _controllers[19].text.trim().isEmpty
          ? null
          : _controllers[19].text.trim(),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(
              formTitle: 'INDIVIDUAL DEVELOPMENT PLAN',
              subtitle: 'LOCAL GOVERNMENT UNIT OF PLARIDEL',
            ),
            const SizedBox(height: 16),
            Text(
              'Personal & position',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Name', _controllers[0]),
            _field('Position', _controllers[1]),
            _field('Category', _controllers[2]),
            _field('Division', _controllers[3]),
            _field('Department', _controllers[4]),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Qualifications',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Education', _controllers[5]),
            _field('Experience', _controllers[6]),
            _field('Training', _controllers[7]),
            _field('Eligibility', _controllers[8]),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Succession analysis – target positions',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Target position 1', _controllers[9]),
            _field('Target position 2', _controllers[10]),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Performance (avg 2 latest SPMS-IPCR)',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Average rating', _controllers[11]),
            _field('OPCR', _controllers[12]),
            _field('IPCR', _controllers[13]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: IdpEntry.performanceRatingOptions
                  .map(
                    (v) => ChoiceChip(
                      label: Text(v.replaceAll('_', ' ')),
                      selected: _performanceRating == v,
                      onSelected: ro
                          ? null
                          : (_) => setState(() => _performanceRating = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Competence assessment',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Competency', _controllers[14]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: IdpEntry.competenceRatingOptions
                  .map(
                    (v) => ChoiceChip(
                      label: Text(v[0].toUpperCase() + v.substring(1)),
                      selected: _competenceRating == v,
                      onSelected: ro
                          ? null
                          : (_) => setState(() => _competenceRating = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Succession priority',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Total score', _controllers[15]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: IdpEntry.successionPriorityOptions
                  .map(
                    (v) => ChoiceChip(
                      label: Text(
                        v == 'priority_2'
                            ? 'Priority 2'
                            : v == 'priority_3'
                            ? 'Priority 3'
                            : 'Priority',
                      ),
                      selected: _successionPriorityRating == v,
                      onSelected: ro
                          ? null
                          : (_) =>
                                setState(() => _successionPriorityRating = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: rspFormSectionGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Development plan (objectives, L&D program, requirements, time frame)',
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
                    onPressed: _addPlanRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add row'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            ...List.generate(_planRows.length, (i) {
              final r = _planRows[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: rspFormFieldVerticalGap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: r['objectives'],
                        readOnly: ro,
                        decoration: rspUnderlinedField('Objectives'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: r['ld_program'],
                        readOnly: ro,
                        decoration: rspUnderlinedField('L&D program'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: r['requirements'],
                        readOnly: ro,
                        decoration: rspUnderlinedField('Requirements'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: r['time_frame'],
                        readOnly: ro,
                        decoration: rspUnderlinedField('Time frame'),
                      ),
                    ),
                    if (!ro)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _planRows.length > 1
                            ? () => _removePlanRow(i)
                            : null,
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Signatures (optional)',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field('Prepared by', _controllers[16]),
            _field('Reviewed by', _controllers[17]),
            _field('Noted by', _controllers[18]),
            _field('Approved by', _controllers[19]),
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return RspSpacedOutlineField(
      child: TextFormField(
        controller: c,
        readOnly: widget.readOnly,
        decoration: rspUnderlinedField(label),
      ),
    );
  }
}

class _IdpList extends StatelessWidget {
  const _IdpList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<IdpEntry> entries;
  final void Function(IdpEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(IdpEntry) onPrint;
  final Future<void> Function(IdpEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Department')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries
            .map(
              (e) => DataRow(
                cells: [
                  DataCell(Text(e.name ?? 'â€”')),
                  DataCell(Text(e.position ?? 'â€”')),
                  DataCell(Text(e.department ?? 'â€”')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => showReadOnlySavedEntryDialog(
                            context,
                            title: 'Saved IDP',
                            previewBuilder: () => _IdpFormEditor(
                              readOnly: true,
                              entry: e,
                              onSave: (_) {},
                              onCancel: () {},
                              onPrint: (_) async {},
                              onDownloadPdf: (_) async {},
                            ),
                            contentWidth: 920,
                          ),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => onEdit(e),
                          child: const Text('Edit'),
                        ),
                        IconButton(
                          onPressed: () => onPrint(e),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(e),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete IDP?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && e.id != null) onDelete(e.id!);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// RSP: Applicants Profile â€” job vacancy details + list of applicants.
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

  void _startNew() => setState(() => _editing = const ApplicantsProfileEntry());
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
      final doc = await FormPdf.buildApplicantsProfilePdf(entry);
      await FormPdf.printDocument(doc, name: 'Applicants_Profile.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
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
              '${e.applicants.length} applicant(s) · Posted ${e.dateOfPosting ?? "—"}',
          detailDialogTitle: 'Applicants profile — $pos',
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
        Text(
          'Applicants Profile',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Job vacancy details (position, requirements, dates) and list of applicants (name, course, address, sex, age, civil status, remark).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No applicants profiles yet. Tap "Add profile" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
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
  late TextEditingController _positionApplied;
  late TextEditingController _minRequirements;
  late TextEditingController _datePosting;
  late TextEditingController _closingDate;
  late TextEditingController _preparedBy;
  late TextEditingController _checkedBy;
  late List<Map<String, TextEditingController>> _applicantRows;

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
    _applicantRows = e.applicants.isEmpty
        ? [_applicantRow('', '', '', '', '', '', '')]
        : e.applicants
              .map(
                (a) => _applicantRow(
                  a.name ?? '',
                  a.course ?? '',
                  a.address ?? '',
                  a.sex ?? '',
                  a.age ?? '',
                  a.civilStatus ?? '',
                  a.remarkDisability ?? '',
                ),
              )
              .toList();
  }

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
    _positionApplied.dispose();
    _minRequirements.dispose();
    _datePosting.dispose();
    _closingDate.dispose();
    _preparedBy.dispose();
    _checkedBy.dispose();
    for (final row in _applicantRows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addApplicant() {
    if (widget.readOnly) return;
    setState(
      () => _applicantRows.add(_applicantRow('', '', '', '', '', '', '')),
    );
  }

  void _removeApplicant(int index) {
    if (widget.readOnly) return;
    if (_applicantRows.length <= 1) return;
    setState(() {
      for (final c in _applicantRows[index].values) {
        c.dispose();
      }
      _applicantRows.removeAt(index);
    });
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

  @override
  Widget build(BuildContext context) {
    final ro = widget.readOnly;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(formTitle: 'APPLICANTS PROFILE'),
            const SizedBox(height: 20),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _positionApplied,
                readOnly: ro,
                decoration: rspUnderlinedField('Position Applied for:'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _minRequirements,
                readOnly: ro,
                decoration: rspUnderlinedField('Minimum Requirements:'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _datePosting,
                readOnly: ro,
                decoration: rspUnderlinedField('Date of Posting:'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _closingDate,
                readOnly: ro,
                decoration: rspUnderlinedField('Closing Date:'),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Applicants',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!ro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addApplicant,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add applicant'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('NAME')),
                  DataColumn(label: Text('COURSE')),
                  DataColumn(label: Text('ADDRESS')),
                  DataColumn(label: Text('SEX')),
                  DataColumn(label: Text('AGE')),
                  DataColumn(label: Text('CIVIL STATUS')),
                  DataColumn(label: Text('REMARK (DISABILITY)')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_applicantRows.length, (i) {
                  final r = _applicantRows[i];
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['name'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            controller: r['course'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            controller: r['address'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 50,
                          child: TextFormField(
                            controller: r['sex'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 45,
                          child: TextFormField(
                            controller: r['age'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            controller: r['civil_status'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['remark_disability'],
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
                                onPressed: _applicantRows.length > 1
                                    ? () => _removeApplicant(i)
                                    : null,
                              ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prepared by:',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      RspSpacedOutlineField(
                        child: TextFormField(
                          controller: _preparedBy,
                          readOnly: ro,
                          decoration: rspUnderlinedField(''),
                        ),
                      ),
                      Text(
                        '(e.g. HRMDO Staff)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
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
                        'Checked by:',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      RspSpacedOutlineField(
                        child: TextFormField(
                          controller: _checkedBy,
                          readOnly: ro,
                          decoration: rspUnderlinedField(''),
                        ),
                      ),
                      Text(
                        '(e.g. HRMDO)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position applied for')),
          DataColumn(label: Text('Posting date')),
          DataColumn(label: Text('Applicants')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries
            .map(
              (e) => DataRow(
                cells: [
                  DataCell(Text(e.positionAppliedFor ?? 'â€”')),
                  DataCell(Text(e.dateOfPosting ?? 'â€”')),
                  DataCell(Text('${e.applicants.length}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => onEdit(e),
                          child: const Text('Edit'),
                        ),
                        IconButton(
                          onPressed: () => onPrint(e),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(e),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete applicants profile?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && e.id != null) onDelete(e.id!);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// RSP: Comparative Assessment of Candidates for Promotion â€” form only, no names/values pre-filled.
class _RspComparativeAssessmentSection extends StatefulWidget {
  const _RspComparativeAssessmentSection();

  @override
  State<_RspComparativeAssessmentSection> createState() =>
      _RspComparativeAssessmentSectionState();
}

class _RspComparativeAssessmentSectionState
    extends State<_RspComparativeAssessmentSection> {
  List<ComparativeAssessmentEntry> _entries = [];
  bool _loading = true;
  ComparativeAssessmentEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ComparativeAssessmentRepo.instance.list();
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

  void _startNew() =>
      setState(() => _editing = const ComparativeAssessmentEntry());
  void _edit(ComparativeAssessmentEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(ComparativeAssessmentEntry entry) async {
    try {
      if (entry.id == null) {
        await ComparativeAssessmentRepo.instance.insert(entry);
      } else {
        await ComparativeAssessmentRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comparative assessment saved.')),
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
      await ComparativeAssessmentRepo.instance.delete(id);
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

  Future<void> _printCa(ComparativeAssessmentEntry entry) async {
    try {
      final doc = await FormPdf.buildComparativeAssessmentPdf(entry);
      await FormPdf.printDocument(doc, name: 'Comparative_Assessment.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _downloadCa(ComparativeAssessmentEntry entry) async {
    try {
      final doc = await FormPdf.buildComparativeAssessmentPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Comparative_Assessment.pdf');
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
      sheetTitle: 'Saved comparative assessments',
      emptyMessage: 'No assessments yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.positionToBeFilled?.trim().isNotEmpty == true
            ? e.positionToBeFilled!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle: '${e.candidates.length} candidate(s)',
          detailDialogTitle: 'Comparative assessment — $pos',
          previewContentWidth: 960,
          previewBuilder: () => _ComparativeAssessmentEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printCa(e),
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
          'Comparative Assessment of Candidates for Promotion',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Position, minimum requirements, and candidate comparison table. Form only\u2014no names or values pre-filled.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _ComparativeAssessmentEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printCa,
            onDownloadPdf: _downloadCa,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add assessment'),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No assessments yet. Tap "Add assessment" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          )
        else
          _ComparativeAssessmentList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printCa,
            onDownloadPdf: _downloadCa,
          ),
      ],
    );
  }
}

class _ComparativeAssessmentEditor extends StatefulWidget {
  const _ComparativeAssessmentEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final ComparativeAssessmentEntry entry;
  final bool readOnly;
  final void Function(ComparativeAssessmentEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(ComparativeAssessmentEntry) onPrint;
  final Future<void> Function(ComparativeAssessmentEntry) onDownloadPdf;

  @override
  State<_ComparativeAssessmentEditor> createState() =>
      _ComparativeAssessmentEditorState();
}

class _ComparativeAssessmentEditorState
    extends State<_ComparativeAssessmentEditor> {
  late TextEditingController _position;
  late TextEditingController _edu;
  late TextEditingController _exp;
  late TextEditingController _elig;
  late TextEditingController _training;
  late List<Map<String, TextEditingController>> _rows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _position = TextEditingController(text: e.positionToBeFilled ?? '');
    _edu = TextEditingController(text: e.minReqEducation ?? '');
    _exp = TextEditingController(text: e.minReqExperience ?? '');
    _elig = TextEditingController(text: e.minReqEligibility ?? '');
    _training = TextEditingController(text: e.minReqTraining ?? '');
    _rows = e.candidates.isEmpty
        ? [_caRow('', '', '', '', '', '', '', '')]
        : e.candidates
              .map(
                (c) => _caRow(
                  c.candidateName ?? '',
                  c.presentPositionSalary ?? '',
                  c.education ?? '',
                  c.trainingHrs ?? '',
                  c.relatedExperience ?? '',
                  c.eligibility ?? '',
                  c.performanceRating ?? '',
                  c.remarks ?? '',
                ),
              )
              .toList();
  }

  Map<String, TextEditingController> _caRow(
    String n,
    String pos,
    String edu,
    String hrs,
    String rel,
    String elig,
    String perf,
    String rem,
  ) {
    return {
      'name': TextEditingController(text: n),
      'present_position_salary': TextEditingController(text: pos),
      'education': TextEditingController(text: edu),
      'training_hrs': TextEditingController(text: hrs),
      'related_experience': TextEditingController(text: rel),
      'eligibility': TextEditingController(text: elig),
      'performance_rating': TextEditingController(text: perf),
      'remarks': TextEditingController(text: rem),
    };
  }

  @override
  void dispose() {
    _position.dispose();
    _edu.dispose();
    _exp.dispose();
    _elig.dispose();
    _training.dispose();
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    if (widget.readOnly) return;
    setState(() => _rows.add(_caRow('', '', '', '', '', '', '', '')));
  }

  void _removeRow(int i) {
    if (widget.readOnly) return;
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  ComparativeAssessmentEntry _buildCurrentEntry() {
    final candidates = _rows
        .map(
          (r) => ComparativeAssessmentCandidate(
            candidateName: r['name']!.text.trim().isEmpty
                ? null
                : r['name']!.text.trim(),
            presentPositionSalary:
                r['present_position_salary']!.text.trim().isEmpty
                ? null
                : r['present_position_salary']!.text.trim(),
            education: r['education']!.text.trim().isEmpty
                ? null
                : r['education']!.text.trim(),
            trainingHrs: r['training_hrs']!.text.trim().isEmpty
                ? null
                : r['training_hrs']!.text.trim(),
            relatedExperience: r['related_experience']!.text.trim().isEmpty
                ? null
                : r['related_experience']!.text.trim(),
            eligibility: r['eligibility']!.text.trim().isEmpty
                ? null
                : r['eligibility']!.text.trim(),
            performanceRating: r['performance_rating']!.text.trim().isEmpty
                ? null
                : r['performance_rating']!.text.trim(),
            remarks: r['remarks']!.text.trim().isEmpty
                ? null
                : r['remarks']!.text.trim(),
          ),
        )
        .toList();
    return ComparativeAssessmentEntry(
      id: widget.entry.id,
      positionToBeFilled: _position.text.trim().isEmpty
          ? null
          : _position.text.trim(),
      minReqEducation: _edu.text.trim().isEmpty ? null : _edu.text.trim(),
      minReqExperience: _exp.text.trim().isEmpty ? null : _exp.text.trim(),
      minReqEligibility: _elig.text.trim().isEmpty ? null : _elig.text.trim(),
      minReqTraining: _training.text.trim().isEmpty
          ? null
          : _training.text.trim(),
      candidates: candidates,
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeaderBoard(
              formTitle: 'COMPARATIVE ASSESSMENT OF CANDIDATES FOR PROMOTION',
            ),
            Text(
              'POSITION TO BE FILLED:',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _position,
                readOnly: ro,
                decoration: rspUnderlinedField(''),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'MINIMUM REQUIREMENTS:',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _edu,
                readOnly: ro,
                decoration: rspUnderlinedField('EDUCATION :'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _exp,
                readOnly: ro,
                decoration: rspUnderlinedField('EXPERIENCE :'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _elig,
                readOnly: ro,
                decoration: rspUnderlinedField('ELIGIBILITY :'),
              ),
            ),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _training,
                readOnly: ro,
                decoration: rspUnderlinedField('TRAINING :'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Candidates',
                    style: TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!ro) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add row'),
                  ),
                ],
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('CANDIDATES')),
                  DataColumn(
                    label: Text('Present Position/Salary Grade/Monthly Salary'),
                  ),
                  DataColumn(label: Text('EDUCATION')),
                  DataColumn(label: Text('No. of hrs. Related Training')),
                  DataColumn(label: Text('Related Experienced')),
                  DataColumn(label: Text('Eligibility')),
                  DataColumn(label: Text('Performance Rating')),
                  DataColumn(label: Text('REMARKS')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['name'],
                            readOnly: ro,
                            decoration: rspTableCellField(hintText: 'Name'),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['present_position_salary'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            controller: r['education'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 70,
                          child: TextFormField(
                            controller: r['training_hrs'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['related_experience'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['eligibility'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['performance_rating'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            controller: r['remarks'],
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComparativeAssessmentList extends StatelessWidget {
  const _ComparativeAssessmentList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<ComparativeAssessmentEntry> entries;
  final void Function(ComparativeAssessmentEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(ComparativeAssessmentEntry) onPrint;
  final Future<void> Function(ComparativeAssessmentEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Candidates')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries
            .map(
              (e) => DataRow(
                cells: [
                  DataCell(Text(e.positionToBeFilled ?? 'â€”')),
                  DataCell(Text('${e.candidates.length}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => showReadOnlySavedEntryDialog(
                            context,
                            title: 'Saved comparative assessment',
                            previewBuilder: () => _ComparativeAssessmentEditor(
                              readOnly: true,
                              entry: e,
                              onSave: (_) {},
                              onCancel: () {},
                              onPrint: (_) async {},
                              onDownloadPdf: (_) async {},
                            ),
                            contentWidth: 960,
                          ),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => onEdit(e),
                          child: const Text('Edit'),
                        ),
                        IconButton(
                          onPressed: () => onPrint(e),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(e),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && e.id != null) onDelete(e.id!);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// RSP: Promotion Certification / Screening — form only, no names/values pre-filled.
class _RspPromotionCertificationSection extends StatefulWidget {
  const _RspPromotionCertificationSection();

  @override
  State<_RspPromotionCertificationSection> createState() =>
      _RspPromotionCertificationSectionState();
}

class _RspPromotionCertificationSectionState
    extends State<_RspPromotionCertificationSection> {
  List<PromotionCertificationEntry> _entries = [];
  bool _loading = true;
  PromotionCertificationEntry? _editing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await PromotionCertificationRepo.instance.list();
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

  void _startNew() =>
      setState(() => _editing = const PromotionCertificationEntry());
  void _edit(PromotionCertificationEntry e) => setState(() => _editing = e);
  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _onSave(PromotionCertificationEntry entry) async {
    try {
      if (entry.id == null) {
        await PromotionCertificationRepo.instance.insert(entry);
      } else {
        await PromotionCertificationRepo.instance.update(entry);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Promotion certification saved.')),
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
      await PromotionCertificationRepo.instance.delete(id);
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

  Future<void> _printPc(PromotionCertificationEntry entry) async {
    try {
      final doc = await FormPdf.buildPromotionCertificationPdf(entry);
      await FormPdf.printDocument(doc, name: 'Promotion_Certification.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _downloadPc(PromotionCertificationEntry entry) async {
    try {
      final doc = await FormPdf.buildPromotionCertificationPdf(entry);
      await FormPdf.sharePdf(doc, name: 'Promotion_Certification.pdf');
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
      sheetTitle: 'Saved promotion certifications',
      emptyMessage: 'No certifications yet.',
      loading: _loading,
      items: _entries.map((e) {
        final pos = e.positionForPromotion?.trim().isNotEmpty == true
            ? e.positionForPromotion!
            : '(No position)';
        return SavedRecordListItem(
          title: pos,
          subtitle: '${e.candidates.length} candidate(s)',
          detailDialogTitle: 'Promotion certification — $pos',
          previewContentWidth: 960,
          previewBuilder: () => _PromotionCertificationEditor(
            readOnly: true,
            entry: e,
            onSave: (_) {},
            onCancel: () {},
            onPrint: (_) async {},
            onDownloadPdf: (_) async {},
          ),
          onPrint: () => _printPc(e),
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
          'Promotion Certification / Screening',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Certification that candidate(s) have been screened and found qualified for promotion. Form only—no names or values pre-filled.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 24),
        if (_editing != null) ...[
          _PromotionCertificationEditor(
            key: ValueKey(_editing?.id ?? 'new'),
            entry: _editing!,
            onSave: _onSave,
            onCancel: _cancelEdit,
            onPrint: _printPc,
            onDownloadPdf: _downloadPc,
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _startNew,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add certification'),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No certifications yet. Tap "Add certification" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          )
        else
          _PromotionCertificationList(
            entries: _entries,
            onEdit: _edit,
            onDelete: _onDelete,
            onPrint: _printPc,
            onDownloadPdf: _downloadPc,
          ),
      ],
    );
  }
}

class _PromotionCertificationEditor extends StatefulWidget {
  const _PromotionCertificationEditor({
    super.key,
    required this.entry,
    this.readOnly = false,
    required this.onSave,
    required this.onCancel,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final PromotionCertificationEntry entry;
  final bool readOnly;
  final void Function(PromotionCertificationEntry) onSave;
  final VoidCallback onCancel;
  final Future<void> Function(PromotionCertificationEntry) onPrint;
  final Future<void> Function(PromotionCertificationEntry) onDownloadPdf;

  @override
  State<_PromotionCertificationEditor> createState() =>
      _PromotionCertificationEditorState();
}

class _PromotionCertificationEditorState
    extends State<_PromotionCertificationEditor> {
  late TextEditingController _position;
  late TextEditingController _day;
  late TextEditingController _month;
  late TextEditingController _year;
  late TextEditingController _signName;
  late TextEditingController _signTitle;
  late List<Map<String, TextEditingController>> _rows;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _position = TextEditingController(text: e.positionForPromotion ?? '');
    _day = TextEditingController(text: e.dateDay ?? '');
    _month = TextEditingController(text: e.dateMonth ?? '');
    _year = TextEditingController(text: e.dateYear ?? '');
    _signName = TextEditingController(text: e.signatoryName ?? '');
    _signTitle = TextEditingController(text: e.signatoryTitle ?? '');
    _rows = e.candidates.isEmpty
        ? [_pcRow('', '', '', '', '', '')]
        : e.candidates
              .map(
                (c) => _pcRow(
                  c.name ?? '',
                  c.col1 ?? '',
                  c.col2 ?? '',
                  c.col3 ?? '',
                  c.col4 ?? '',
                  c.col5 ?? '',
                ),
              )
              .toList();
  }

  Map<String, TextEditingController> _pcRow(
    String name,
    String c1,
    String c2,
    String c3,
    String c4,
    String c5,
  ) {
    return {
      'name': TextEditingController(text: name),
      'col1': TextEditingController(text: c1),
      'col2': TextEditingController(text: c2),
      'col3': TextEditingController(text: c3),
      'col4': TextEditingController(text: c4),
      'col5': TextEditingController(text: c5),
    };
  }

  @override
  void dispose() {
    _position.dispose();
    _day.dispose();
    _month.dispose();
    _year.dispose();
    _signName.dispose();
    _signTitle.dispose();
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    if (widget.readOnly) return;
    setState(() => _rows.add(_pcRow('', '', '', '', '', '')));
  }

  void _removeRow(int i) {
    if (widget.readOnly) return;
    if (_rows.length <= 1) return;
    setState(() {
      for (final c in _rows[i].values) {
        c.dispose();
      }
      _rows.removeAt(i);
    });
  }

  PromotionCertificationEntry _buildCurrentEntry() {
    final candidates = _rows
        .map(
          (r) => PromotionCertificationCandidate(
            name: r['name']!.text.trim().isEmpty
                ? null
                : r['name']!.text.trim(),
            col1: r['col1']!.text.trim().isEmpty
                ? null
                : r['col1']!.text.trim(),
            col2: r['col2']!.text.trim().isEmpty
                ? null
                : r['col2']!.text.trim(),
            col3: r['col3']!.text.trim().isEmpty
                ? null
                : r['col3']!.text.trim(),
            col4: r['col4']!.text.trim().isEmpty
                ? null
                : r['col4']!.text.trim(),
            col5: r['col5']!.text.trim().isEmpty
                ? null
                : r['col5']!.text.trim(),
          ),
        )
        .toList();
    return PromotionCertificationEntry(
      id: widget.entry.id,
      positionForPromotion: _position.text.trim().isEmpty
          ? null
          : _position.text.trim(),
      candidates: candidates,
      dateDay: _day.text.trim().isEmpty ? null : _day.text.trim(),
      dateMonth: _month.text.trim().isEmpty ? null : _month.text.trim(),
      dateYear: _year.text.trim().isEmpty ? null : _year.text.trim(),
      signatoryName: _signName.text.trim().isEmpty
          ? null
          : _signName.text.trim(),
      signatoryTitle: _signTitle.text.trim().isEmpty
          ? null
          : _signTitle.text.trim(),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(
              formTitle: 'Promotion Certification / Screening',
            ),
            const SizedBox(height: 16),
            Text(
              'Position for promotion:',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _position,
                readOnly: ro,
                decoration: rspUnderlinedField(''),
              ),
            ),
            const SizedBox(height: rspFormSectionGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Candidates (name + 5 columns)',
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
                    label: const Text('Add row'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('1')),
                  DataColumn(label: Text('2')),
                  DataColumn(label: Text('3')),
                  DataColumn(label: Text('4')),
                  DataColumn(label: Text('5')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['name'],
                            readOnly: ro,
                            decoration: rspTableCellField(hintText: 'Name'),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['col1'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['col2'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['col3'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['col4'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            controller: r['col5'],
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
            const SizedBox(height: rspFormSectionGap),
            const Text(
              'We hereby certify that the above candidate(s) have been screened and found to be qualified for promotion to the above position.',
              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, height: 1.45),
            ),
            const SizedBox(height: 20),
            Text(
              'Date of certification',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 12,
              children: [
                Text(
                  'Done this',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: TextFormField(
                    controller: _day,
                    readOnly: ro,
                    style: const TextStyle(fontSize: 14, height: 1.2),
                    decoration: rspInlineClauseField(hintText: 'day'),
                  ),
                ),
                Text(
                  'day of',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _month,
                    readOnly: ro,
                    style: const TextStyle(fontSize: 14, height: 1.2),
                    decoration: rspInlineClauseField(hintText: 'month'),
                  ),
                ),
                Text(
                  ',',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: TextFormField(
                    controller: _year,
                    readOnly: ro,
                    style: const TextStyle(fontSize: 14, height: 1.2),
                    decoration: rspInlineClauseField(hintText: 'year'),
                  ),
                ),
                Text(
                  '.',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Signatory (e.g. Secretariat)',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field(_signName, 'Name'),
            _field(_signTitle, 'Title'),
            const SizedBox(height: 24),
            if (!ro) ...[
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return RspSpacedOutlineField(
      child: TextFormField(
        controller: c,
        readOnly: widget.readOnly,
        decoration: rspUnderlinedField(label),
      ),
    );
  }
}

class _PromotionCertificationList extends StatelessWidget {
  const _PromotionCertificationList({
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    required this.onPrint,
    required this.onDownloadPdf,
  });

  final List<PromotionCertificationEntry> entries;
  final void Function(PromotionCertificationEntry) onEdit;
  final void Function(String id) onDelete;
  final Future<void> Function(PromotionCertificationEntry) onPrint;
  final Future<void> Function(PromotionCertificationEntry) onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Candidates')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries
            .map(
              (e) => DataRow(
                cells: [
                  DataCell(Text(e.positionForPromotion ?? 'â€”')),
                  DataCell(Text('${e.candidates.length}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => showReadOnlySavedEntryDialog(
                            context,
                            title: 'Saved promotion certification',
                            previewBuilder: () => _PromotionCertificationEditor(
                              readOnly: true,
                              entry: e,
                              onSave: (_) {},
                              onCancel: () {},
                              onPrint: (_) async {},
                              onDownloadPdf: (_) async {},
                            ),
                            contentWidth: 960,
                          ),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => onEdit(e),
                          child: const Text('Edit'),
                        ),
                        IconButton(
                          onPressed: () => onPrint(e),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(e),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && e.id != null) onDelete(e.id!);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// RSP: Selection Line-up â€” date, agency/office, vacant position, item no., applicants table. Form only, no pre-filled names.
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
      final doc = await FormPdf.buildSelectionLineupPdf(entry);
      await FormPdf.printDocument(doc, name: 'Selection_Lineup.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
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
          subtitle: '${e.date ?? "—"} · ${e.applicants.length} applicant(s)',
          detailDialogTitle: 'Selection line-up — $pos',
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
        Text(
          'Selection Line-up',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Date, name of agency/office, vacant position, item no., and applicants table (name, education, experience, training, eligibility). Form only\u2014no pre-filled names.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No selection line-ups yet. Tap "Add line-up" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
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
  late List<Map<String, TextEditingController>> _rows;

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
    _rows = e.applicants.isEmpty
        ? [_slRow('', '', '', '', '')]
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
  }

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
    _date.dispose();
    _agency.dispose();
    _position.dispose();
    _itemNo.dispose();
    _preparedName.dispose();
    _preparedTitle.dispose();
    for (final row in _rows) {
      for (final c in row.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_slRow('', '', '', '', '')));
  void _removeRow(int i) {
    if (_rows.length <= 1) return;
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RspFormHeader(formTitle: 'SELECTION LINE-UP'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 180,
                  child: RspSpacedOutlineField(
                    child: TextFormField(
                      controller: _date,
                      readOnly: ro,
                      decoration: rspUnderlinedField('Date'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Name of Agency/Office:',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _agency,
                readOnly: ro,
                decoration: rspUnderlinedField(''),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Vacant Position:',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _position,
                readOnly: ro,
                decoration: rspUnderlinedField(''),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Item No.:',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            RspSpacedOutlineField(
              child: TextFormField(
                controller: _itemNo,
                readOnly: ro,
                decoration: rspUnderlinedField(''),
              ),
            ),
            const SizedBox(height: rspFormSectionGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Name of applicants (table)',
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
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('NAME OF APPLICANTS')),
                  DataColumn(label: Text('EDUCATION')),
                  DataColumn(label: Text('EXPERIENCE')),
                  DataColumn(label: Text('TRAINING')),
                  DataColumn(label: Text('ELIGIBILITY')),
                  DataColumn(label: Text('')),
                ],
                rows: List.generate(_rows.length, (i) {
                  final r = _rows[i];
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: TextFormField(
                            controller: r['name'],
                            readOnly: ro,
                            decoration: rspTableCellField(hintText: 'Name'),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['education'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: r['experience'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['training'],
                            readOnly: ro,
                            decoration: rspTableCellField(),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: r['eligibility'],
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
            const SizedBox(height: rspFormSectionGap),
            Text(
              'Prepared by',
              style: TextStyle(
                color: AppTheme.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _field(_preparedName, 'Name'),
            _field(_preparedTitle, 'Title'),
            const SizedBox(height: 24),
            if (!ro) ...[
              Row(
                children: [
                  FilledButton(onPressed: _save, child: const Text('Save')),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label) {
    return RspSpacedOutlineField(
      child: TextFormField(
        controller: c,
        readOnly: widget.readOnly,
        decoration: rspUnderlinedField(label),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Vacant position')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Applicants')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries
            .map(
              (e) => DataRow(
                cells: [
                  DataCell(Text(e.vacantPosition ?? 'â€”')),
                  DataCell(Text(e.date ?? 'â€”')),
                  DataCell(Text('${e.applicants.length}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => showReadOnlySavedEntryDialog(
                            context,
                            title: 'Saved selection line-up',
                            previewBuilder: () => _SelectionLineupEditor(
                              readOnly: true,
                              entry: e,
                              onSave: (_) {},
                              onCancel: () {},
                              onPrint: (_) async {},
                              onDownloadPdf: (_) async {},
                            ),
                            contentWidth: 1000,
                          ),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => onEdit(e),
                          child: const Text('Edit'),
                        ),
                        IconButton(
                          onPressed: () => onPrint(e),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(e),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && e.id != null) onDelete(e.id!);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// RSP: Turn-Around Time â€” position, office, dates, applicant tracking table. Form only, no pre-filled names.
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
      final doc = await FormPdf.buildTurnAroundTimePdf(entry);
      await FormPdf.printDocument(doc, name: 'Turn_Around_Time.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Print dialog opened.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
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
          subtitle: '${e.office ?? "—"} · ${e.applicants.length} applicant(s)',
          detailDialogTitle: 'Turn-around time — $pos',
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
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Position, office, dates, and applicant tracking (assessment, exam, deliberation, job offer, assumption, cost). Form onlyâ€”no pre-filled names.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No turn-around time entries yet. Tap "Add turn-around time" to add one.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
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
        border: Border.all(color: Colors.black.withOpacity(0.06)),
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
                        color: AppTheme.textPrimary,
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
                        color: AppTheme.textPrimary,
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
                        color: AppTheme.textPrimary,
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
                        color: AppTheme.textPrimary,
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
                        color: AppTheme.textPrimary,
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
                        color: AppTheme.textPrimary,
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
                color: AppTheme.textSecondary,
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
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              if (widget.entry.updatedAt != null)
                Text(
                  'Last updated: ${widget.entry.updatedAt!.toLocal()}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Position')),
          DataColumn(label: Text('Office')),
          DataColumn(label: Text('Applicants')),
          DataColumn(label: Text('Actions')),
        ],
        rows: entries
            .map(
              (e) => DataRow(
                cells: [
                  DataCell(Text(e.position ?? 'â€”')),
                  DataCell(Text(e.office ?? 'â€”')),
                  DataCell(Text('${e.applicants.length}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => showReadOnlySavedEntryDialog(
                            context,
                            title: 'Saved turn-around time',
                            previewBuilder: () => _TurnAroundTimeEditor(
                              readOnly: true,
                              entry: e,
                              onSave: (_) {},
                              onCancel: () {},
                              onPrint: (_) async {},
                              onDownloadPdf: (_) async {},
                            ),
                            contentWidth: 1200,
                          ),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => onEdit(e),
                          child: const Text('Edit'),
                        ),
                        IconButton(
                          onPressed: () => onPrint(e),
                          icon: const Icon(Icons.print_rounded, size: 20),
                          tooltip: 'Print',
                        ),
                        IconButton(
                          onPressed: () => onDownloadPdf(e),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 20,
                          ),
                          tooltip: 'Download PDF',
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete?'),
                                content: const Text('This cannot be undone.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && e.id != null) onDelete(e.id!);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

/// One vacancy form entry (headline + body controllers).
class _VacancyFormItem {
  _VacancyFormItem()
    : headline = TextEditingController(),
      body = TextEditingController(),
      maxApplicants = TextEditingController();
  final TextEditingController headline;
  final TextEditingController body;
  final TextEditingController maxApplicants;
  void dispose() {
    headline.dispose();
    body.dispose();
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

  String _vacancyEntrySummary(_VacancyFormItem v) {
    final h = v.headline.text.trim();
    if (h.isNotEmpty) {
      return h.length > 52 ? '${h.substring(0, 52)}…' : h;
    }
    final b = v.body.text.trim();
    if (b.isNotEmpty) {
      return b.length > 64 ? '${b.substring(0, 64)}…' : b;
    }
    final m = v.maxApplicants.text.trim();
    if (m.isNotEmpty) return 'Max applicants: $m';
    return 'No headline yet — expand to edit';
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
          item.body.text = v.body ?? '';
          item.maxApplicants.text =
              v.maxApplicants != null ? '${v.maxApplicants}' : '';
          next.add(item);
        }
      } else {
        final item = _VacancyFormItem();
        item.headline.text = a.headline ?? '';
        item.body.text = a.body ?? '';
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

  void _addVacancy() {
    setState(() {
      _vacancies.add(_VacancyFormItem());
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
          'Remove "$title" from the list? Use this when the job hiring is done. You can add it again later if needed. Changes are saved when you tap "Save and display on landing page".',
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
      final list = _vacancies
          .map(
            (v) {
              final rawMax = v.maxApplicants.text.trim();
              int? maxParsed;
              if (rawMax.isNotEmpty) {
                maxParsed = int.tryParse(rawMax);
                if (maxParsed != null && maxParsed < 1) maxParsed = null;
              }
              return JobVacancyItem(
                headline: v.headline.text.trim().isEmpty
                    ? null
                    : v.headline.text.trim(),
                body: v.body.text.trim().isEmpty ? null : v.body.text.trim(),
                maxApplicants: maxParsed,
              );
            },
          )
          .toList();
      final a = JobVacancyAnnouncement(
        hasVacancies: _hasVacancies,
        headline: list.isNotEmpty ? list.first.headline : null,
        body: list.isNotEmpty ? list.first.body : null,
        vacancies: list,
      );
      await JobVacancyAnnouncementRepo.instance.update(a);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Job vacancy announcement saved. Landing page will show this.',
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Job Vacancies Announcement',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.35,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Control what appears in the Job Vacancies section on the landing page. Add multiple entries when you have more than one position.',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.95),
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy,
                      AppTheme.primaryNavyLight,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              14,
                              10,
                              14,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.sectionAlt,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.045,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Accepting applications',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: _hasVacancies,
                                      onChanged: (v) =>
                                          setState(() => _hasVacancies = v),
                                      activeTrackColor:
                                          AppTheme.primaryNavy.withValues(
                                        alpha: 0.45,
                                      ),
                                      activeThumbColor: AppTheme.primaryNavy,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'When ON, the landing page shows that you are hiring. When OFF, it shows no vacancies.',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.92,
                                    ),
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Job vacancy entries',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: _addVacancy,
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text('Add new vacancy'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap a row to expand or collapse fields. Delete is available when there is more than one entry.',
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.88,
                              ),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...List.generate(_vacancies.length, (i) {
                            final v = _vacancies[i];
                            final expanded = i < _vacancyExpanded.length
                                ? _vacancyExpanded[i]
                                : true;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.black.withValues(
                                      alpha: 0.08,
                                    ),
                                  ),
                                  boxShadow: AppTheme.cardShadow,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppTheme.primaryNavy.withValues(
                                              alpha: 0.85,
                                            ),
                                            AppTheme.primaryNavyLight
                                                .withValues(alpha: 0.5),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        2,
                                        8,
                                        2,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => setState(() {
                                                  if (i <
                                                      _vacancyExpanded
                                                          .length) {
                                                    _vacancyExpanded[i] =
                                                        !_vacancyExpanded[i];
                                                  }
                                                }),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 10,
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                        child: Icon(
                                                          expanded
                                                              ? Icons
                                                                  .expand_less_rounded
                                                              : Icons
                                                                  .expand_more_rounded,
                                                          color: AppTheme
                                                              .textSecondary
                                                              .withValues(
                                                            alpha: 0.75,
                                                          ),
                                                          size: 26,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'Position ${i + 1}',
                                                              style:
                                                                  const TextStyle(
                                                                color: AppTheme
                                                                    .textPrimary,
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                letterSpacing:
                                                                    -0.2,
                                                              ),
                                                            ),
                                                            if (!expanded) ...[
                                                              const SizedBox(
                                                                height: 6,
                                                              ),
                                                              Text(
                                                                _vacancyEntrySummary(
                                                                  v,
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  color: AppTheme
                                                                      .textSecondary
                                                                      .withValues(
                                                                    alpha:
                                                                        0.92,
                                                                  ),
                                                                  fontSize:
                                                                      12.5,
                                                                  height: 1.4,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_vacancies.length > 1)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _confirmDeleteVacancy(
                                                  context,
                                                  i,
                                                ),
                                                icon: Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: Colors.red.shade700,
                                                ),
                                                label: Text(
                                                  'Delete',
                                                  style: TextStyle(
                                                    color: Colors.red.shade700,
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.red.shade700,
                                                  side: BorderSide(
                                                    color: Colors.red.shade400,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                                  minimumSize: Size.zero,
                                                ),
                                              ),
                                            ),
                                        ],
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
                                                18,
                                                0,
                                                18,
                                                18,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Headline (optional)',
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .textSecondary,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  TextField(
                                                    controller: v.headline,
                                                    onChanged: (_) =>
                                                        setState(() {}),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'e.g. Now Hiring: Human Resource Assistant',
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 14,
                                                        vertical: 12,
                                                      ),
                                                    ),
                                                    maxLines: 1,
                                                  ),
                                                  const SizedBox(height: 14),
                                                  Text(
                                                    'Description (optional)',
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .textSecondary,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  TextField(
                                                    controller: v.body,
                                                    onChanged: (_) =>
                                                        setState(() {}),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'Short description for this position.',
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 14,
                                                        vertical: 12,
                                                      ),
                                                      alignLabelWithHint: true,
                                                    ),
                                                    maxLines: 3,
                                                  ),
                                                  const SizedBox(height: 14),
                                                  Text(
                                                    'Max applicants (optional)',
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .textSecondary,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Counts only applicants still in process. Document declined, exam failed, final interview failed, or hired (registered) frees a slot.',
                                                    style: TextStyle(
                                                      color: AppTheme
                                                          .textSecondary
                                                          .withValues(
                                                        alpha: 0.9,
                                                      ),
                                                      fontSize: 11.5,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  TextField(
                                                    controller:
                                                        v.maxApplicants,
                                                    onChanged: (_) =>
                                                        setState(() {}),
                                                    keyboardType:
                                                        TextInputType.number,
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'Leave blank for no limit (e.g. 50)',
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 14,
                                                        vertical: 12,
                                                      ),
                                                    ),
                                                    maxLines: 1,
                                                  ),
                                                ],
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
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 20),
                        label: Text(
                          _saving
                              ? 'Saving...'
                              : 'Save and display on landing page',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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

/// RSP: List of applications and exam results for admin monitoring.
class _RspApplicationsMonitor extends StatefulWidget {
  @override
  State<_RspApplicationsMonitor> createState() =>
      _RspApplicationsMonitorState();
}

class _RspApplicationsMonitorState extends State<_RspApplicationsMonitor> {
  List<RecruitmentApplication> _applications = [];
  Map<String, RecruitmentExamResult> _examResults = {};

  bool _loading = true;
  bool _syncing = false;
  final ScrollController _horizontalScrollController = ScrollController();

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

  Future<void> _openBeiGrading(
    BuildContext context,
    RecruitmentApplication app,
    RecruitmentExamResult exam,
  ) async {
    await showRspBeiGradingDialog(
      context: context,
      applicant: app,
      exam: exam,
      onSaved: _load,
    );
  }

  static const Color _kPassBg = Color(0xFFE8F5E9);
  static const Color _kPassFg = Color(0xFF1B5E20);
  static const Color _kPassBorder = Color(0xFF43A047);
  static const Color _kFailBg = Color(0xFFFFEBEE);
  static const Color _kFailFg = Color(0xFFB71C1C);
  static const Color _kFailBorder = Color(0xFFE57373);

  static TextStyle _scoreBreakdownScoreStyle({
    required bool isNA,
    double? value,
  }) {
    final tabular = [const FontFeature.tabularFigures()];
    if (isNA) {
      return TextStyle(
        fontSize: 13,
        fontFeatures: tabular,
        color: AppTheme.textSecondary.withValues(alpha: 0.85),
        fontStyle: FontStyle.italic,
      );
    }
    final passSection = value != null && value >= 60;
    return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      fontFeatures: tabular,
      color: passSection ? _kPassFg : _kFailFg,
    );
  }

  static Widget _scoreBreakdownStatusPill({
    required RecruitmentExamResult? exam,
  }) {
    if (exam == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.lightGray,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Text(
          'No exam',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary.withValues(alpha: 0.9),
          ),
        ),
      );
    }
    final pass = exam.passed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: pass ? _kPassBg : _kFailBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pass ? _kPassBorder : _kFailBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pass ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16,
            color: pass ? _kPassFg : _kFailFg,
          ),
          const SizedBox(width: 6),
          Text(
            pass ? 'Passed' : 'Failed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: pass ? _kPassFg : _kFailFg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreBreakdownGuideBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•',
            style: TextStyle(
              color: AppTheme.primaryNavy,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreBreakdownSidePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 22,
                color: AppTheme.primaryNavy,
              ),
              const SizedBox(width: 8),
              Text(
                'Scoring guide',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _scoreBreakdownGuideBullet(
            'General, Math, and General information columns are filled automatically from the applicant’s multiple-choice answers.',
          ),
          _scoreBreakdownGuideBullet(
            'BEI shows an average only after every behavioral question is scored (0–100). Use the grade icon in this table or Grade BEI on the main applications list.',
          ),
          _scoreBreakdownGuideBullet(
            'Overall screening % averages all sections that apply. Pass / fail uses a 60% cutoff on that overall value.',
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBreakdownDataTable(BuildContext dialogContext) {
    final borderColor = Colors.black.withValues(alpha: 0.08);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: DataTable(
                columnSpacing: 28,
                horizontalMargin: 16,
                headingRowHeight: 48,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 72,
                border: TableBorder(
                  top: BorderSide(color: borderColor),
                  bottom: BorderSide(color: borderColor),
                  horizontalInside: BorderSide(color: borderColor),
                ),
                dividerThickness: 0,
                headingRowColor: WidgetStateProperty.all(
                  AppTheme.primaryNavy.withValues(alpha: 0.08),
                ),
                headingTextStyle: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.2,
                ),
                dataTextStyle: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
                columns: [
                  const DataColumn(label: Text('Applicant')),
                  const DataColumn(label: Text('Position')),
                  const DataColumn(label: Text('General'), numeric: true),
                  const DataColumn(label: Text('Math'), numeric: true),
                  const DataColumn(label: Text('Gen. info'), numeric: true),
                  const DataColumn(label: Text('BEI'), numeric: true),
                  const DataColumn(
                    label: Text('Grade'),
                  ),
                  const DataColumn(label: Text('Result')),
                ],
                rows: _applications.map((app) {
                  final exam = _examResults[app.id.toLowerCase()];
                  double? generalScore;
                  double? mathScore;
                  double? infoScore;
                  double? beiScore;
                  final answersJson = exam?.answersJson;
                  if (answersJson != null) {
                    generalScore = _sectionScorePercent(answersJson, 'general');
                    mathScore = _sectionScorePercent(answersJson, 'math');
                    infoScore = _sectionScorePercent(
                      answersJson,
                      'general_info',
                    );
                    beiScore = _beiSectionScorePercent(answersJson);
                  }

                  String scoreLabel(double? v) =>
                      v == null ? '—' : '${v.toStringAsFixed(0)}%';

                  final canGradeBei =
                      exam != null && _hasBeiAnswers(exam);

                  return DataRow(
                    cells: [
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 150,
                            maxWidth: 220,
                          ),
                          child: Text(
                            app.fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 80,
                            maxWidth: 140,
                          ),
                          child: Text(
                            (app.positionAppliedFor != null &&
                                    app.positionAppliedFor!.trim().isNotEmpty)
                                ? app.positionAppliedFor!.trim()
                                : '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.95,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          scoreLabel(generalScore),
                          textAlign: TextAlign.end,
                          style: _scoreBreakdownScoreStyle(
                            isNA: generalScore == null,
                            value: generalScore,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          scoreLabel(mathScore),
                          textAlign: TextAlign.end,
                          style: _scoreBreakdownScoreStyle(
                            isNA: mathScore == null,
                            value: mathScore,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          scoreLabel(infoScore),
                          textAlign: TextAlign.end,
                          style: _scoreBreakdownScoreStyle(
                            isNA: infoScore == null,
                            value: infoScore,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          scoreLabel(beiScore),
                          textAlign: TextAlign.end,
                          style: _scoreBreakdownScoreStyle(
                            isNA: beiScore == null,
                            value: beiScore,
                          ),
                        ),
                      ),
                      DataCell(
                        Center(
                          child: canGradeBei
                              ? IconButton(
                                  tooltip: 'Grade BEI',
                                  icon: Icon(
                                    Icons.rate_review_outlined,
                                    color: AppTheme.primaryNavy,
                                    size: 22,
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
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.remove_rounded,
                                      size: 20,
                                      color: AppTheme.textSecondary
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      DataCell(
                        _scoreBreakdownStatusPill(exam: exam),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showApplicantScoreBreakdownDialog() async {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final hasData = _applications.isNotEmpty;
        final borderColor = Colors.black.withValues(alpha: 0.08);
        return AlertDialog(
          backgroundColor: AppTheme.offWhite,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Applicant score breakdown',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Summary of screening scores by section. Grade BEI from the icon column when answers exist.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
          content: hasData
              ? Builder(
                  builder: (_) {
                    final mq = MediaQuery.sizeOf(ctx);
                    final contentWidth = (mq.width - 48).clamp(280.0, 1120.0);
                    final contentHeight = (mq.height * 0.58).clamp(300.0, 560.0);
                    final useWide = contentWidth >= 760;
                    final table = _buildScoreBreakdownDataTable(ctx);
                    final side = _scoreBreakdownSidePanel();
                    return SizedBox(
                      width: contentWidth,
                      height: contentHeight,
                      child: useWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 13,
                                  child: table,
                                ),
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: borderColor,
                                ),
                                Expanded(
                                  flex: 9,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: side,
                                  ),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  table,
                                  const SizedBox(height: 16),
                                  side,
                                ],
                              ),
                            ),
                    );
                  },
                )
              : SizedBox(
                  width: 320,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No applicants yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: AppTheme.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Applicant details saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  /// Sync attachment paths from server disk into DB for applications missing paths.
  Future<void> _syncAttachmentsFromStorage() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final entries = await RecruitmentRepo.instance
          .listStorageAttachmentPaths();
      debugPrint(
        'Sync attachments: listed ${entries.length} file(s) on server.',
      );
      int linked = 0;
      for (final e in entries) {
        final fileName = e['fileName']!;
        final kind = RspApplicationDocKind.fromStorageFileName(fileName);
        final ok = kind != null
            ? await RecruitmentRepo.instance
                  .setApplicationTypedAttachmentIfMissing(
                    e['applicationId']!,
                    e['path']!,
                    fileName,
                    kind,
                  )
            : await RecruitmentRepo.instance.setApplicationAttachmentIfMissing(
                e['applicationId']!,
                e['path']!,
                fileName,
              );
        if (ok) linked++;
      }
      if (mounted) {
        await _load();
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
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $message'),
            backgroundColor: const Color(0xFFC62828),
          ),
        );
      }
    }
  }

  static const _kNa = 'N/A';

  Widget _tableCell(double width, Widget child) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: SizedBox(width: width, child: child),
      ),
    );
  }

  /// Readable status pill with color by outcome (tooltip shows raw value).
  Widget _applicationStatusBadge(String status) {
    final raw = status.trim();
    final s = raw.toLowerCase();
    late Color bg;
    late Color fg;
    late IconData icon;
    if (s.contains('passed') ||
        s == 'registered' ||
        s.contains('approved') ||
        s.contains('hire')) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
      icon = Icons.check_circle_outline_rounded;
    } else if (s.contains('declined') ||
        s.contains('failed') ||
        s.contains('reject')) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      icon = Icons.cancel_outlined;
    } else if (s.contains('pending') ||
        s.contains('submitted') ||
        s.contains('review') ||
        s.contains('exam')) {
      bg = AppTheme.primaryNavy.withValues(alpha: 0.12);
      fg = AppTheme.primaryNavyDark;
      icon = Icons.schedule_rounded;
    } else {
      bg = AppTheme.sectionAlt;
      fg = AppTheme.textSecondary;
      icon = Icons.label_outline_rounded;
    }
    final display =
        raw.isEmpty ? _kNa : raw.replaceAll('_', ' ');
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

  Widget _examOutcomeChip(bool passed) {
    final fg = passed ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final bg = passed ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        passed ? 'Passed' : 'Failed',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Applications & Exam Results',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.35,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: _loading ? null : _load,
              tooltip: 'Refresh',
              style: IconButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : _showApplicantScoreBreakdownDialog,
              icon: const Icon(Icons.assessment_rounded, size: 18),
              label: const Text('View Scores'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                side: BorderSide(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Tooltip(
              message:
                  'Link files already in storage to applications that show "No file" (e.g. after fixing RLS).',
              child: TextButton.icon(
                onPressed: (_loading || _syncing)
                    ? null
                    : _syncAttachmentsFromStorage,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
                label: Text(
                  _syncing ? 'Syncing...' : 'Sync attachments from storage',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Monitor all documents (basic info) and screening exam results from applicants.',
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.95),
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy,
                      AppTheme.primaryNavyLight,
                    ],
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
                        color: AppTheme.textSecondary.withValues(alpha: 0.92),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scrollWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    const fixedTableWidth = 2234.0;
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
                                  0: const FixedColumnWidth(160),
                                  1: const FixedColumnWidth(260),
                                  2: const FixedColumnWidth(140),
                                  3: const FixedColumnWidth(200),
                                  4: const FixedColumnWidth(170),
                                  5: const FixedColumnWidth(76),
                                  6: const FixedColumnWidth(108),
                                  7: const FixedColumnWidth(188),
                                  8: const FixedColumnWidth(188),
                                  9: const FixedColumnWidth(188),
                                  10: const FixedColumnWidth(200),
                                  11: const FixedColumnWidth(248),
                                  12: const FixedColumnWidth(108),
                                },
                                defaultVerticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                border: TableBorder.symmetric(
                                  inside: BorderSide(
                                    color: Colors.black.withValues(alpha: 0.07),
                                  ),
                                ),
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryNavy.withValues(
                                        alpha: 0.1,
                                      ),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppTheme.primaryNavy
                                              .withValues(alpha: 0.15),
                                        ),
                                      ),
                                    ),
                                    children: [
                                      _tableCell(
                                        160,
                                        const Text(
                                          'Name',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        260,
                                        const Text(
                                          'Email',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        140,
                                        const Text(
                                          'Phone',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        200,
                                        const Text(
                                          'Position applied',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        170,
                                        const Text(
                                          'Status',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        76,
                                        const Text(
                                          'Exam',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        108,
                                        const Text(
                                          'Score / BEI',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        188,
                                        const Text(
                                          'Application letter',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        188,
                                        const Text(
                                          'Resume',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        188,
                                        const Text(
                                          'TOR',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        200,
                                        const Text(
                                          'Eligibility / trainings (prelim.)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        248,
                                        const Text(
                                          'Document review',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      _tableCell(
                                        108,
                                        const Text(
                                          'Actions',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...List.generate(_applications.length, (ri) {
                                    final app = _applications[ri];
                                    final exam =
                                        _examResults[app.id.toLowerCase()];
                                    final textStyle = TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    );
                                    return TableRow(
                                      decoration: ri.isOdd
                                          ? BoxDecoration(
                                              color: AppTheme.sectionAlt
                                                  .withValues(alpha: 0.4),
                                            )
                                          : null,
                                      children: [
                                        _tableCell(
                                          160,
                                          Tooltip(
                                            message: app.fullName,
                                            child: Text(
                                              app.fullName,
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
                                            app.phone ?? _kNa,
                                            style: textStyle,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        _tableCell(
                                          200,
                                          Tooltip(
                                            message:
                                                app.positionAppliedFor ?? _kNa,
                                            child: Text(
                                              (app.positionAppliedFor != null &&
                                                      app.positionAppliedFor!
                                                          .trim()
                                                          .isNotEmpty)
                                                  ? app.positionAppliedFor!
                                                      .trim()
                                                  : _kNa,
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
                                            app.status,
                                          ),
                                        ),
                                        _tableCell(
                                          76,
                                          exam == null
                                              ? Text(
                                                  _kNa,
                                                  style: textStyle.copyWith(
                                                    color: AppTheme
                                                        .textSecondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                )
                                              : Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: _examOutcomeChip(
                                                    exam.passed,
                                                  ),
                                                ),
                                        ),
                                        _tableCell(
                                          108,
                                          exam == null
                                              ? Text(_kNa, style: textStyle)
                                              : Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${exam.scorePercent.toStringAsFixed(0)}%',
                                                      style: textStyle,
                                                    ),
                                                    if (_hasBeiAnswers(exam))
                                                      TextButton(
                                                        style: TextButton
                                                            .styleFrom(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          minimumSize:
                                                              Size.zero,
                                                          tapTargetSize:
                                                              MaterialTapTargetSize
                                                                  .shrinkWrap,
                                                          foregroundColor:
                                                              AppTheme
                                                                  .primaryNavy,
                                                        ),
                                                        onPressed: () =>
                                                            _openBeiGrading(
                                                          context,
                                                          app,
                                                          exam,
                                                        ),
                                                        child: const Text(
                                                          'Grade BEI',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
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
                                                tooltip: 'Edit name, email, phone',
                                                style: IconButton.styleFrom(
                                                  foregroundColor:
                                                      AppTheme.primaryNavy,
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  minimumSize:
                                                      const Size(32, 32),
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
                                                  foregroundColor:
                                                      const Color(0xFFC62828),
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  minimumSize:
                                                      const Size(32, 32),
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
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 20, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text(
                'Approved',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
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
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel, size: 20, color: Colors.red.shade700),
              const SizedBox(width: 6),
              Text(
                'Declined',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
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
    return Text(app.status);
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
        _showAttachmentPreviewDialog(
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
            'Could not create attachment link. Restart the API and set '
            'SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY, and run rsp-storage-attachment-policy.sql.',
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Tooltip(
            message: 'Preview — $fileName',
            child: TextButton.icon(
              onPressed: () => _preview(context),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: SizedBox(
                width: 200,
                child: Text(
                  fileName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
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
            foregroundColor: AppTheme.primaryNavy,
            padding: const EdgeInsets.all(4),
            minimumSize: const Size(32, 32),
          ),
        ),
      ],
    );
  }
}

bool _isImageExt(String ext) {
  return const <String>[
    'png',
    'jpg',
    'jpeg',
    'gif',
    'tif',
    'tiff',
    'webp',
    'bmp',
  ].contains(ext.toLowerCase());
}

String _extractExt(String fileName) {
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot == -1 || dot == lower.length - 1) return '';
  return lower.substring(dot + 1);
}

/// Same UX as L&D Training Daily Report attachment preview (Image.network + actions).
void _showAttachmentPreviewDialog(
  BuildContext context, {
  required String url,
  required String fileName,
  required String objectPath,
}) {
  // Prefer `fileName` (DB `attachment_name`), but if it has no extension,
  // fall back to the stored object key (e.g. `${applicationId}/${fileName}`).
  final ext = _extractExt(fileName).isNotEmpty
      ? _extractExt(fileName)
      : _extractExt(objectPath);
  final isImage = _isImageExt(ext);
  final isPdf = ext.toLowerCase() == 'pdf';
  final lowerExt = ext.toLowerCase();
  final isWord = <String>[
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
  ].contains(lowerExt);
  final downloadUri = Uri.parse(url).replace(
    queryParameters: {...Uri.parse(url).queryParameters, 'download': '1'},
  );

  showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attachment preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: isImage
                        ? InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Preview for this file type is not supported.',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () async {
                                        await launchUrl(
                                          Uri.parse(url),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Open in new tab'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : kIsWeb
                        ? (isPdf || isWord)
                              ? _WebIframePreview(
                                  url: isWord ? _withPreviewParam(url) : url,
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Preview for this file type is not supported.',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () async {
                                          await launchUrl(
                                            Uri.parse(url),
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Open in new tab'),
                                      ),
                                    ],
                                  ),
                                )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Preview for this file type is not supported.',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    await launchUrl(
                                      Uri.parse(url),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Open in new tab'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await launchUrl(
                          downloadUri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open file'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _officeViewerUrl(String fileUrl) {
  // Office Online viewer loads the file from `src` and renders it inline.
  // NOTE: `fileUrl` must be reachable by the browser (ideally from the same LAN).
  final encoded = Uri.encodeComponent(fileUrl);
  return 'https://view.officeapps.live.com/op/view.aspx?src=$encoded';
}

String _withPreviewParam(String url) {
  final uri = Uri.parse(url);
  final qp = <String, String>{...uri.queryParameters};
  qp['preview'] = '1';
  // Ensure we don't accidentally request download mode for inline preview.
  qp.remove('download');
  return uri.replace(queryParameters: qp).toString();
}

bool _isPrivateHost(String host) {
  final h = host.toLowerCase().trim();
  if (h.isEmpty) return true;
  if (h == 'localhost' || h == '127.0.0.1' || h == '0.0.0.0') return true;
  if (h.startsWith('10.') || h.startsWith('192.168.')) return true;
  if (h.startsWith('172.')) {
    // 172.16.0.0 - 172.31.255.255
    final parts = h.split('.');
    if (parts.length >= 2) {
      final second = int.tryParse(parts[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
  }
  if (h.endsWith('.local') || h.endsWith('.lan')) return true;
  return false;
}

/// Minimal web-only inline preview for PDFs/docs using an `<iframe>`.
/// Works best for `application/pdf` and many browsers will render it inline.
class _WebIframePreview extends StatefulWidget {
  const _WebIframePreview({required this.url});
  final String url;

  @override
  State<_WebIframePreview> createState() => _WebIframePreviewState();
}

class _WebIframePreviewState extends State<_WebIframePreview> {
  static int _counter = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'rsp-attachment-iframe-${_counter++}';

    // Register a one-off platform view factory.
    // ignore: avoid_web_libraries_in_flutter
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = widget.url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    // HtmlElementView sometimes ignores parent constraints; `SizedBox.expand`
    // ensures the iframe gets a non-zero height/width.
    return SizedBox.expand(child: HtmlElementView(viewType: _viewType));
  }
}
