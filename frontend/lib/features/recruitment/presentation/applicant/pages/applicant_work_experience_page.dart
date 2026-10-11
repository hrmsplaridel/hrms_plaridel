import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/sections/work_experience_sheet_section.dart';

/// Applicant completion of the Work Experience Sheet assigned for deliberation.
class ApplicantWorkExperiencePage extends StatefulWidget {
  const ApplicantWorkExperiencePage({super.key, required this.applicationId});

  final String applicationId;

  @override
  State<ApplicantWorkExperiencePage> createState() =>
      _ApplicantWorkExperiencePageState();
}

class _ApplicantWorkExperiencePageState
    extends State<ApplicantWorkExperiencePage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _status;
  String? _comment;
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
      final payload = await RecruitmentRepo.instance.getMyWorkExperience(
        widget.applicationId,
      );
      final tracking = payload['tracking'];
      final entry = payload['wes'];
      if (!mounted) return;
      setState(() {
        _status = tracking is Map ? tracking['wesStatus']?.toString() : null;
        _comment = tracking is Map
            ? tracking['wesReviewComment']?.toString()
            : null;
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

  Future<void> _save(WorkExperienceSheetEntry entry, {required bool submit}) async {
    if (_saving || _readOnly) return;
    setState(() => _saving = true);
    try {
      if (submit) {
        await RecruitmentRepo.instance.submitWorkExperience(
          widget.applicationId,
          entry.toJson(),
        );
      } else {
        await RecruitmentRepo.instance.saveWorkExperienceDraft(
          widget.applicationId,
          entry.toJson(),
        );
      }
      if (!mounted) return;
      if (submit) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _saving = false;
        _status = 'in_progress';
        _entry = entry.toJson();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(title: const Text('Work Experience Sheet')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _entry == null
          ? const Center(
              child: Text('HR has not assigned the Work Experience Sheet yet.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if ((_comment ?? '').trim().isNotEmpty &&
                    _status == 'needs_revision')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('HR asked for a revision: ${_comment!.trim()}'),
                  ),
                WorkExperienceSheetEditor(
                  entry: WorkExperienceSheetEntry.fromJson(_entry!),
                  readOnly: _readOnly || _saving,
                  applicantWorkflow: true,
                  onSave: (entry) => _save(entry, submit: false),
                  onSubmitToHr: (entry) => _save(entry, submit: true),
                  onCancel: () => Navigator.of(context).pop(),
                  onPrint: (_) async {},
                  onDownloadPdf: (_) async {},
                ),
              ],
            ),
    );
  }
}
