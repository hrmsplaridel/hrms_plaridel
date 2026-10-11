import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/bi_form.dart';
import 'package:hrms_plaridel/features/learning_development/models/ojt_work_immersion_evaluation.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/pages/rsp_admin_screen.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/ojt_work_immersion_evaluation_section.dart';

/// Applicant completion of the one form HR assigned after document approval.
class ApplicantRequiredFormPage extends StatefulWidget {
  const ApplicantRequiredFormPage({super.key, required this.applicationId});

  final String applicationId;

  @override
  State<ApplicantRequiredFormPage> createState() =>
      _ApplicantRequiredFormPageState();
}

class _ApplicantRequiredFormPageState extends State<ApplicantRequiredFormPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _formType;
  String? _status;
  Map<String, dynamic>? _entry;

  bool get _readOnly =>
      _status == 'submitted_for_review' ||
      _status == 'resubmitted_for_review' ||
      _status == 'approved';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await RecruitmentRepo.instance.getMyRequiredForm(
        widget.applicationId,
      );
      final assignment = payload['assignment'];
      final entry = payload['entry'];
      if (!mounted) return;
      setState(() {
        _formType = assignment is Map
            ? assignment['formType']?.toString()
            : null;
        _status = assignment is Map ? assignment['status']?.toString() : null;
        _entry = entry is Map ? Map<String, dynamic>.from(entry) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _persistBi(BiFormEntry entry) async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.saveRequiredFormDraft(
        widget.applicationId,
        entry.toJson(),
      );
      _status = 'in_progress';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitBi(BiFormEntry entry) async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.submitRequiredForm(
        widget.applicationId,
        entry.toJson(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
      }
    }
  }

  Future<void> _submitOjt(OjtWorkImmersionEvaluation entry) async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.submitRequiredForm(
        widget.applicationId,
        <String, dynamic>{
          'ojt_immersion': entry.ojtImmersion,
          'school': entry.school,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        title: Text(
          _formType == 'ojt'
              ? 'OJT / Work Immersion Evaluation'
              : 'Background Investigation',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _formType == 'ojt'
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: OjtWorkImmersionEvaluationEditor(
                entry: OjtWorkImmersionEvaluation.fromJson(_entry ?? {}),
                readOnly: _readOnly,
                applicantOnly: true,
                onSave: _submitOjt,
                onCancel: () => Navigator.of(context).pop(false),
                onPrint: (_) async {},
                onDownloadPdf: (_) async {},
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ApplicantBiFormHost(
                entry: BiFormEntry.fromJson(_entry ?? {}),
                readOnly: _readOnly,
                onPersist: _persistBi,
                onSubmitToHr: _submitBi,
              ),
            ),
    );
  }
}
