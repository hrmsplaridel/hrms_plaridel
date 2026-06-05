import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/ld_training_requirements.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/employee/shared/widgets/employee_dash_ui.dart';

class LdTrainingRequirementsEmployeeScreen extends StatefulWidget {
  const LdTrainingRequirementsEmployeeScreen({super.key});

  @override
  State<LdTrainingRequirementsEmployeeScreen> createState() =>
      _LdTrainingRequirementsEmployeeScreenState();
}

class _LdTrainingRequirementsEmployeeScreenState
    extends State<LdTrainingRequirementsEmployeeScreen> {
  LdTrainingRequirementRecord? _record;
  bool _loading = true;
  bool _uploading = false;
  final _trainingTitleController = TextEditingController();
  final Map<LdTrainingRequirementDocKind, PlatformFile> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trainingTitleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await LdTrainingRequirementRepo.instance.loadMine();
      if (!mounted) return;
      setState(() {
        _record = r;
        _trainingTitleController.text = r.trainingTitle ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    }
  }

  Future<void> _saveTrainingTitle() async {
    final title = _trainingTitleController.text.trim();
    if (title.isEmpty) return;
    try {
      final r = await LdTrainingRequirementRepo.instance.updateMyTrainingTitle(
        title,
      );
      if (!mounted) return;
      setState(() => _record = r);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Training title saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    }
  }

  Future<void> _pick(LdTrainingRequirementDocKind kind) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    if (f.bytes == null || f.name.isEmpty) return;
    setState(() => _picked[kind] = f);
  }

  Future<void> _uploadKind(LdTrainingRequirementDocKind kind) async {
    final r = _record;
    final f = _picked[kind];
    if (r == null || f == null || f.bytes == null) return;
    setState(() => _uploading = true);
    try {
      await LdTrainingRequirementRepo.instance.uploadDocument(
        r.id,
        kind,
        f.bytes!,
        f.name,
      );
      if (!mounted) return;
      setState(() => _picked.remove(kind));
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document uploaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static String _kindLabel(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return 'Invitation letter for training travel (approved by the mayor)';
      case LdTrainingRequirementDocKind.lap:
        return 'Learning Application Plan (LAP)';
      case LdTrainingRequirementDocKind.trainingCertificate:
        return 'Training certificate';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = _record;
    if (r == null) {
      return const Center(child: Text('Could not load training requirements.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: EmployeeDashUi.welcomeBanner(context),
            child: const EmployeeSectionHeader(
              title: 'Training Requirements',
              icon: Icons.fact_check_outlined,
              subtitle:
                  'Submit pre-training documents before travel and post-training '
                  'documents after completing your training.',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _trainingTitleController,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Training / program title (optional)',
              hintText: 'e.g. Leadership Enhancement Program 2026',
            ),
            onSubmitted: (_) => _saveTrainingTitle(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _saveTrainingTitle,
              child: const Text('Save training title'),
            ),
          ),
          const SizedBox(height: 24),
          _phaseCard(
            title: 'Pre-training requirements',
            description:
                'Upload your invitation letter for training travel, approved by the mayor. '
                'HR must approve this before you can submit post-training documents.',
            kinds: const [LdTrainingRequirementDocKind.invitationLetter],
            record: r,
            approved: r.preRequirementsApproved,
            locked: false,
          ),
          const SizedBox(height: 16),
          _phaseCard(
            title: 'Post-training requirements',
            description:
                'After training, upload your Learning Application Plan (LAP) and training certificates.',
            kinds: const [
              LdTrainingRequirementDocKind.lap,
              LdTrainingRequirementDocKind.trainingCertificate,
            ],
            record: r,
            approved: r.postRequirementsApproved,
            locked: !r.preRequirementsApproved,
            lockedMessage:
                'Available after HR approves your pre-training requirements.',
          ),
        ],
      ),
    );
  }

  Widget _phaseCard({
    required String title,
    required String description,
    required List<LdTrainingRequirementDocKind> kinds,
    required LdTrainingRequirementRecord record,
    required bool approved,
    required bool locked,
    String? lockedMessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (approved)
                _statusPill('Approved', const Color(0xFF2E7D32))
              else if (locked)
                _statusPill('Locked', Colors.grey.shade700)
              else
                _statusPill('Submit documents', Colors.orange.shade800),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: AppTheme.dashTextSecondaryOf(context),
              height: 1.45,
            ),
          ),
          if (locked && lockedMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              lockedMessage,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...kinds.map(
            (k) => _docRow(
              kind: k,
              record: record,
              disabled: locked || approved || _uploading,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _docRow({
    required LdTrainingRequirementDocKind kind,
    required LdTrainingRequirementRecord record,
    required bool disabled,
  }) {
    final storedPath = record.docPath(kind);
    final storedName = record.docDisplayName(kind);
    final hasStored = storedPath != null && storedPath.isNotEmpty;
    final picked = _picked[kind];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.dashMutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _kindLabel(kind),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (hasStored)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      storedName ?? 'Uploaded',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else if (picked != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(picked.name, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    onPressed: disabled ? null : () => setState(() => _picked.remove(kind)),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: disabled ? null : () => _uploadKind(kind),
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('Upload PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                ),
              ),
            ]
            else
              FilledButton.tonalIcon(
                onPressed: disabled ? null : () => _pick(kind),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Choose PDF'),
              ),
          ],
        ),
      ),
    );
  }
}
