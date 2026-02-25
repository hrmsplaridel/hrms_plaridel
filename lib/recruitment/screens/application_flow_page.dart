import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/recruitment_application.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../login/screens/login_page.dart';

/// Default BEI questions when DB has none (admin can edit and save from RSP).
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

/// Multi-step recruitment flow: Basic Info → Exam → Result → Registration (if passed) → Interview info.
class ApplicationFlowPage extends StatefulWidget {
  const ApplicationFlowPage({super.key});

  @override
  State<ApplicationFlowPage> createState() => _ApplicationFlowPageState();
}

class _ApplicationFlowPageState extends State<ApplicationFlowPage> {
  int _step = 1;
  String? _applicationId;
  /// When loaded via "Continue application" or after Step 1: submitted | document_approved | document_declined
  String? _applicationStatus;
  bool _examPassed = false;
  double _examScore = 0;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _continueEmailController = TextEditingController();
  PlatformFile? _pickedFile;
  List<String>? _beiQuestionsLoaded;
  List<TextEditingController> _beiControllers = [];
  bool _submitting = false;
  bool _continueLoading = false;
  bool _beiLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _continueEmailController.dispose();
    for (final c in _beiControllers) c.dispose();
    super.dispose();
  }

  Future<void> _loadBeiQuestions() async {
    if (_beiLoading || _beiQuestionsLoaded != null) return;
    _beiLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestions('bei');
      final questions = list.isNotEmpty ? list : _defaultBeiQuestions;
      if (mounted) {
        for (final c in _beiControllers) c.dispose();
        _beiControllers = questions.map((_) => TextEditingController()).toList();
        _beiQuestionsLoaded = questions;
        _beiLoading = false;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        for (final c in _beiControllers) c.dispose();
        _beiControllers = _defaultBeiQuestions.map((_) => TextEditingController()).toList();
        _beiQuestionsLoaded = _defaultBeiQuestions;
        _beiLoading = false;
        setState(() {});
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, type: FileType.any);
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _submitStep1() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter full name and email.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final id = await RecruitmentRepo.instance.insertApplication(RecruitmentApplication(
        id: '',
        fullName: name,
        email: email,
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        resumeNotes: null,
        status: 'submitted',
      ));
      if (_pickedFile != null && (_pickedFile!.bytes != null) && _pickedFile!.name.isNotEmpty && mounted) {
        try {
          await RecruitmentRepo.instance.uploadAttachment(id, _pickedFile!.bytes!, _pickedFile!.name);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Application saved but file upload failed: $e')));
        }
      }
      if (mounted) {
        setState(() {
          _applicationId = id;
          _applicationStatus = 'submitted';
          _step = 2;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    }
  }

  void _submitBeiExam() {
    if (_beiQuestionsLoaded == null || _beiControllers.isEmpty) return;
    final answers = _beiControllers.map((c) => c.text.trim()).toList();
    final allFilled = answers.every((a) => a.isNotEmpty);
    if (!allFilled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide an answer for each question.')));
      return;
    }
    _beiAnswersForSubmit = answers;
    setState(() => _step = 4);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGeneralQuestions());
  }

  List<String>? _beiAnswersForSubmit;

  List<Map<String, dynamic>>? _generalQuestionsLoaded;
  List<int> _generalSelected = [];
  bool _generalLoading = false;

  Future<void> _loadGeneralQuestions() async {
    if (_generalLoading || _generalQuestionsLoaded != null) return;
    _generalLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions('general');
      if (mounted) {
        _generalQuestionsLoaded = list;
        _generalSelected = List.filled(list.length, -1);
        _generalLoading = false;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _generalQuestionsLoaded = [];
        _generalSelected = [];
        _generalLoading = false;
        setState(() {});
      }
    }
  }

  void _submitGeneralExam() {
    if (_generalQuestionsLoaded == null || _generalQuestionsLoaded!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No General Exam questions loaded.')));
      return;
    }
    if (_generalSelected.any((s) => s < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please answer all questions.')));
      return;
    }
    setState(() => _step = 5);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMathQuestions());
  }

  List<Map<String, dynamic>>? _mathQuestionsLoaded;
  List<int> _mathSelected = [];
  bool _mathLoading = false;
  List<Map<String, dynamic>>? _generalInfoQuestionsLoaded;
  List<int> _generalInfoSelected = [];
  bool _generalInfoLoading = false;

  Future<void> _loadMathQuestions() async {
    if (_mathLoading || _mathQuestionsLoaded != null) return;
    _mathLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions('math');
      if (mounted) {
        _mathQuestionsLoaded = list;
        _mathSelected = List.filled(list.length, -1);
        _mathLoading = false;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _mathQuestionsLoaded = [];
        _mathSelected = [];
        _mathLoading = false;
        setState(() {});
      }
    }
  }

  Future<void> _loadGeneralInfoQuestions() async {
    if (_generalInfoLoading || _generalInfoQuestionsLoaded != null) return;
    _generalInfoLoading = true;
    if (mounted) setState(() {});
    try {
      final list = await RecruitmentRepo.instance.getExamQuestionsWithOptions('general_info');
      if (mounted) {
        _generalInfoQuestionsLoaded = list;
        _generalInfoSelected = List.filled(list.length, -1);
        _generalInfoLoading = false;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _generalInfoQuestionsLoaded = [];
        _generalInfoSelected = [];
        _generalInfoLoading = false;
        setState(() {});
      }
    }
  }

  void _submitMathExam() {
    if (_mathQuestionsLoaded == null || _mathQuestionsLoaded!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Mathematics Exam questions loaded.')));
      return;
    }
    if (_mathSelected.any((s) => s < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please answer all questions.')));
      return;
    }
    setState(() => _step = 6);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGeneralInfoQuestions());
  }

  void _submitGeneralInfoExam() {
    if (_generalInfoQuestionsLoaded == null || _generalInfoQuestionsLoaded!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No General Information Exam questions loaded.')));
      return;
    }
    if (_generalInfoSelected.any((s) => s < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please answer all questions.')));
      return;
    }
    int correct = 0;
    for (int i = 0; i < _generalInfoQuestionsLoaded!.length; i++) {
      if (_generalInfoSelected[i] == (_generalInfoQuestionsLoaded![i]['correct'] as int)) correct++;
    }
    final total = _generalInfoQuestionsLoaded!.length;
    final double score = total > 0 ? (correct / total) * 100.0 : 0.0;
    final passed = score >= 60;
    setState(() {
      _examScore = score;
      _examPassed = passed;
      _step = 7;
    });
    if (_applicationId != null) {
      final answersJson = <String, dynamic>{
        'general': _generalQuestionsLoaded != null
            ? {
                'questions': _generalQuestionsLoaded!.map((q) => q['question_text']).toList(),
                'options': _generalQuestionsLoaded!.map((q) => q['options']).toList(),
                'correct': _generalQuestionsLoaded!.map((q) => q['correct']).toList(),
                'selected': _generalSelected,
              }
            : null,
        'math': _mathQuestionsLoaded != null
            ? {
                'questions': _mathQuestionsLoaded!.map((q) => q['question_text']).toList(),
                'options': _mathQuestionsLoaded!.map((q) => q['options']).toList(),
                'correct': _mathQuestionsLoaded!.map((q) => q['correct']).toList(),
                'selected': _mathSelected,
              }
            : null,
        'general_info': {
          'questions': _generalInfoQuestionsLoaded!.map((q) => q['question_text']).toList(),
          'options': _generalInfoQuestionsLoaded!.map((q) => q['options']).toList(),
          'correct': _generalInfoQuestionsLoaded!.map((q) => q['correct']).toList(),
          'selected': _generalInfoSelected,
          'score': score,
          'passed': passed,
        },
      };
      if (_beiAnswersForSubmit != null && _beiQuestionsLoaded != null) {
        answersJson['bei'] = {'questions': _beiQuestionsLoaded, 'answers': _beiAnswersForSubmit};
      }
      if (answersJson['general'] == null) answersJson.remove('general');
      if (answersJson['math'] == null) answersJson.remove('math');
      RecruitmentRepo.instance.submitExamResult(
        applicationId: _applicationId!,
        scorePercent: score,
        passed: passed,
        answersJson: answersJson,
      );
    }
  }

  Future<void> _continueApplication() async {
    final email = _continueEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your email to continue.')));
      return;
    }
    setState(() => _continueLoading = true);
    try {
      final app = await RecruitmentRepo.instance.getApplicationByEmail(email);
      if (!mounted) return;
      if (app == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No application found for this email.')));
        setState(() => _continueLoading = false);
        return;
      }
      setState(() {
        _applicationId = app.id;
        _applicationStatus = app.status;
        _continueLoading = false;
      });
      if (app.status == 'document_approved') {
        setState(() => _step = 3);
      } else if (app.status == 'document_declined') {
        setState(() => _step = 2);
      } else {
        setState(() => _step = 2);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
        setState(() => _continueLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      appBar: AppBar(
        title: const Text('Recruitment Application'),
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepIndicator(),
                const SizedBox(height: 32),
                if (_step == 1) _buildStep1BasicInfo(),
                if (_step == 2) _buildStep2PendingReview(),
                if (_step == 3) _buildStep3BeiExam(),
                if (_step == 4) _buildStep4GeneralExam(),
                if (_step == 5) _buildStep5MathExam(),
                if (_step == 6) _buildStep6GeneralInfoExam(),
                if (_step == 7) _buildStep7Result(),
                if (_step == 8) _buildStep8Registration(),
                if (_step == 9) _buildStep9Interview(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(9, (i) {
        final n = i + 1;
        final active = n == _step;
        final done = n < _step;
        return Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: active ? AppTheme.primaryNavy : (done ? AppTheme.primaryNavy.withOpacity(0.5) : AppTheme.lightGray),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('$n', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10)),
            ),
            if (n < 9) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.arrow_forward, size: 12, color: AppTheme.textSecondary)),
          ],
        );
      }),
    );
  }

  Widget _buildStep1BasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.2))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Already applied?', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Enter your email to continue and take the exam once your documents are approved.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _continueEmailController,
                decoration: _dec('Email to continue'),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _continueLoading ? null : _continueApplication,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
              child: _continueLoading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Continue'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(height: 24),
        const SizedBox(height: 8),
        Text('Step 1: Submit Basic Information', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Provide your details. HR will review your documents before you can take the exam.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        TextField(controller: _nameController, decoration: _dec('Full Name'), textCapitalization: TextCapitalization.words),
        const SizedBox(height: 16),
        TextField(controller: _emailController, decoration: _dec('Email'), keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        TextField(controller: _phoneController, decoration: _dec('Phone (optional)'), keyboardType: TextInputType.phone),
        const SizedBox(height: 16),
        Text('Attach file (resume, document)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _pickFile,
          icon: const Icon(Icons.attach_file, size: 20),
          label: Text(_pickedFile != null ? _pickedFile!.name : 'Choose file (optional)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryNavy,
            side: const BorderSide(color: AppTheme.primaryNavy),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            alignment: Alignment.centerLeft,
          ),
        ),
        if (_pickedFile != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(_pickedFile!.name, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis)),
              TextButton(
                onPressed: _submitting ? null : () => setState(() => _pickedFile = null),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submitStep1,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _submitting ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit application'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2PendingReview() {
    final isDeclined = _applicationStatus == 'document_declined';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 2: Document review', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        if (!isDeclined) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primaryNavy.withOpacity(0.2))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _continueEmailController,
                    decoration: _dec('Your email to take the exam'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _continueLoading ? null : _continueApplication,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                  child: _continueLoading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Continue to exam'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDeclined ? Colors.red.shade50 : AppTheme.primaryNavy.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDeclined ? Colors.red.shade200 : AppTheme.primaryNavy.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(isDeclined ? Icons.cancel : Icons.hourglass_top_rounded, size: 56, color: isDeclined ? Colors.red.shade700 : AppTheme.primaryNavy),
              const SizedBox(height: 16),
              Text(
                isDeclined ? 'Application not approved' : 'Under review',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                isDeclined
                    ? 'Your application was not approved. You cannot proceed to the exam. If you have questions, please contact HR.'
                    : 'HR is reviewing your documents. Once approved, you can take the screening exam. Use "Continue application" above and enter your email to take the exam when ready.',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (!isDeclined)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Return to this page later and click "Continue" with your email to take the exam.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }

  Widget _buildStep3BeiExam() {
    if (_beiQuestionsLoaded == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBeiQuestions());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 3: 8 Behavioral Event Interview (BEI)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        ],
      );
    }
    final questions = _beiQuestionsLoaded!;
    if (questions.isEmpty || _beiControllers.length != questions.length) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 3: 8 Behavioral Event Interview (BEI)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('For New Applicant/s and Promotion/s. Please answer each question in the space provided.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        ...List.generate(questions.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${questions[i]}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  controller: _beiControllers[i],
                  onChanged: (_) => setState(() {}),
                  maxLines: 5,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Type your answer here...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: AppTheme.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '"Make you MOVE". Your Answer is an Extension of Yourself. Make one that\'s Truly you.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitBeiExam,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Submit BEI Answers'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4GeneralExam() {
    if (_generalQuestionsLoaded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 4: General Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        ],
      );
    }
    final questions = _generalQuestionsLoaded!;
    if (questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 4: General Exam for LGU-Plaridel Applicants', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('No questions configured. Please try again later.', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 4: General Exam for LGU-Plaridel Applicants', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Answer each question. You need 60% or higher to pass.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        ...List.generate(questions.length, (i) {
          final q = questions[i];
          final options = q['options'] as List<dynamic>? ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${q['question_text']}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...List.generate(options.length, (j) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioListTile<int>(
                      value: j,
                      groupValue: _generalSelected[i],
                      onChanged: (v) => setState(() => _generalSelected[i] = v ?? -1),
                      title: Text(options[j].toString(), style: const TextStyle(fontSize: 14)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitGeneralExam,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Submit General Exam'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep5MathExam() {
    if (_mathQuestionsLoaded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 5: Mathematics Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        ],
      );
    }
    final questions = _mathQuestionsLoaded!;
    if (questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 5: Mathematics Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('No questions configured. Please try again later.', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 5: Mathematics Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Instruction: Encircle the letter of your choice. You need 60% or higher to pass.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        ...List.generate(questions.length, (i) {
          final q = questions[i];
          final options = q['options'] as List<dynamic>? ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${q['question_text']}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...List.generate(options.length, (j) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioListTile<int>(
                      value: j,
                      groupValue: _mathSelected[i],
                      onChanged: (v) => setState(() => _mathSelected[i] = v ?? -1),
                      title: Text('${String.fromCharCode(97 + j)}. ${options[j]}', style: const TextStyle(fontSize: 14)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitMathExam,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Submit Mathematics Exam'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep6GeneralInfoExam() {
    if (_generalInfoQuestionsLoaded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 6: General Information Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        ],
      );
    }
    final questions = _generalInfoQuestionsLoaded!;
    if (questions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 6: General Information Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('No questions configured. Please try again later.', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 6: General Information Exam', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Instruction: Encircle the letter of your choice. You have ten (10) minutes to answer. You need 60% or higher to pass.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        ...List.generate(questions.length, (i) {
          final q = questions[i];
          final options = q['options'] as List<dynamic>? ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i + 1}. ${q['question_text']}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...List.generate(options.length, (j) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioListTile<int>(
                      value: j,
                      groupValue: _generalInfoSelected[i],
                      onChanged: (v) => setState(() => _generalInfoSelected[i] = v ?? -1),
                      title: Text('${String.fromCharCode(97 + j)}. ${options[j]}', style: const TextStyle(fontSize: 14)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitGeneralInfoExam,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Submit General Information Exam'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep7Result() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 7: View Exam Result', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _examPassed ? AppTheme.primaryNavy.withOpacity(0.08) : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _examPassed ? AppTheme.primaryNavy.withOpacity(0.3) : Colors.orange.shade200),
          ),
          child: Column(
            children: [
              Icon(_examPassed ? Icons.check_circle : Icons.cancel, size: 56, color: _examPassed ? const Color(0xFFE85D04) : Colors.deepOrange.shade700),
              const SizedBox(height: 16),
              Text(_examPassed ? 'Passed' : 'Not passed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text('Score: ${_examScore.toStringAsFixed(0)}%', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
              if (!_examPassed) ...[const SizedBox(height: 12), Text('You need 60% or higher. You may try again by starting a new application.', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary), textAlign: TextAlign.center)],
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (_examPassed)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _step = 8),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Continue to Registration'),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Back to recruitment'),
            ),
          ),
      ],
    );
  }

  Widget _buildStep8Registration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 8: Complete Registration (only if passed)', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Text('Create your account to access the employee portal. Use the same email you used in this application.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LoginPage()));
            },
            icon: const Icon(Icons.how_to_reg, size: 22),
            label: const Text('Go to Login / Create Account'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => setState(() => _step = 9),
            child: const Text('Next: Interview & Final Hiring'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep9Interview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step 9: Interview & Final Hiring', style: TextStyle(color: AppTheme.primaryNavy, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.lightGray)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What happens next:', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              Text('• Complete your account registration if you haven’t already.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              Text('• HR will review your application and exam result.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              Text('• If shortlisted, you will be contacted for an interview.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              Text('• Final hiring decision will be communicated by the HR office.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: AppTheme.white,
    );
  }
}
