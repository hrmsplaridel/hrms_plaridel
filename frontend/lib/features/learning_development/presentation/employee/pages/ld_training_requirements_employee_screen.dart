import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _savingTitle = false;
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
    setState(() => _savingTitle = true);
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
    } finally {
      if (mounted) setState(() => _savingTitle = false);
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

  Future<void> _previewDoc(LdTrainingRequirementDocKind kind) async {
    final r = _record;
    if (r == null) return;
    final path = r.docPath(kind);
    final name = r.docDisplayName(kind);
    if (path == null || path.isEmpty) return;
    final url = await LdTrainingRequirementRepo.instance.getAttachmentDownloadUrl(
      path,
      fileName: name,
    );
    if (url == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this document.')),
        );
      }
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _removePicked(LdTrainingRequirementDocKind kind) {
    setState(() => _picked.remove(kind));
  }

  int _uploadedCount(
    LdTrainingRequirementRecord record,
    List<LdTrainingRequirementDocKind> kinds,
  ) {
    var n = 0;
    for (final k in kinds) {
      final p = record.docPath(k);
      if (p != null && p.trim().isNotEmpty) n++;
    }
    return n;
  }

  _PhaseStatus _phaseStatus({
    required LdTrainingRequirementRecord record,
    required List<LdTrainingRequirementDocKind> kinds,
    required bool approved,
    required bool locked,
    required bool isPreTraining,
  }) {
    if (locked) return _PhaseStatus.locked;
    if (approved) return _PhaseStatus.approved;
    final uploaded = _uploadedCount(record, kinds);
    if (uploaded >= kinds.length) return _PhaseStatus.awaitingReview;
    if (uploaded > 0) return _PhaseStatus.inProgress;
    return isPreTraining ? _PhaseStatus.actionNeeded : _PhaseStatus.actionNeeded;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = _record;
    if (r == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
              const SizedBox(height: 12),
              const Text('Could not load training requirements.'),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final hPad = wide ? 32.0 : 20.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: EdgeInsets.all(wide ? 28 : 22),
                    decoration: EmployeeDashUi.welcomeBanner(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EmployeeSectionHeader(
                          title: 'Training Requirements',
                          icon: Icons.fact_check_outlined,
                          subtitle:
                              'Submit pre-training documents before travel and post-training '
                              'documents after completing your training.',
                        ),
                        const SizedBox(height: 20),
                        _ProgressSteps(record: r),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _TrainingTitleCard(
                    controller: _trainingTitleController,
                    saving: _savingTitle,
                    savedTitle: r.trainingTitle,
                    onSave: _saveTrainingTitle,
                  ),
                  const SizedBox(height: 20),
                  _PhaseCard(
                    step: 1,
                    title: 'Pre-training requirements',
                    description:
                        'Upload your invitation letter for training travel, approved by the mayor. '
                        'HR must approve this before you can submit post-training documents.',
                    kinds: const [LdTrainingRequirementDocKind.invitationLetter],
                    record: r,
                    status: _phaseStatus(
                      record: r,
                      kinds: const [LdTrainingRequirementDocKind.invitationLetter],
                      approved: r.preRequirementsApproved,
                      locked: false,
                      isPreTraining: true,
                    ),
                    locked: false,
                    wide: wide,
                    picked: _picked,
                    uploading: _uploading,
                    onPick: _pick,
                    onRemove: _removePicked,
                    onUpload: _uploadKind,
                    onPreview: _previewDoc,
                  ),
                  const SizedBox(height: 16),
                  _PhaseCard(
                    step: 2,
                    title: 'Post-training requirements',
                    description:
                        'After training, upload your Learning Application Plan (LAP) and training certificates.',
                    kinds: const [
                      LdTrainingRequirementDocKind.lap,
                      LdTrainingRequirementDocKind.trainingCertificate,
                    ],
                    record: r,
                    status: _phaseStatus(
                      record: r,
                      kinds: const [
                        LdTrainingRequirementDocKind.lap,
                        LdTrainingRequirementDocKind.trainingCertificate,
                      ],
                      approved: r.postRequirementsApproved,
                      locked: !r.preRequirementsApproved,
                      isPreTraining: false,
                    ),
                    locked: !r.preRequirementsApproved,
                    lockedMessage:
                        'Available after HR approves your pre-training requirements.',
                    wide: wide,
                    picked: _picked,
                    uploading: _uploading,
                    onPick: _pick,
                    onRemove: _removePicked,
                    onUpload: _uploadKind,
                    onPreview: _previewDoc,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _PhaseStatus {
  locked,
  actionNeeded,
  inProgress,
  awaitingReview,
  approved,
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.record});

  final LdTrainingRequirementRecord record;

  static const _accent = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final preDone = record.preRequirementsApproved;
    final postDone = record.postRequirementsApproved;
    final preActive = !preDone;
    final postActive = preDone && !postDone;

    Widget step(String label, bool done, bool active) {
      final color = done
          ? const Color(0xFF2E7D32)
          : active
          ? _accent
          : secondary.withValues(alpha: 0.45);
      return Expanded(
        child: Column(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done
                    ? const Color(0xFFE8F5E9)
                    : active
                    ? _accent.withValues(alpha: 0.14)
                    : AppTheme.dashMutedSurfaceOf(context),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(
                done ? Icons.check_rounded : Icons.circle,
                size: done ? 16 : 8,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: done || active ? AppTheme.dashTextPrimaryOf(context) : secondary,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        step('Pre-training', preDone, preActive),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Divider(
              color: preDone
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.35)
                  : AppTheme.dashHairlineOf(context),
            ),
          ),
        ),
        step('Post-training', postDone, postActive),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Divider(color: AppTheme.dashHairlineOf(context)),
          ),
        ),
        step('Complete', postDone, false),
      ],
    );
  }
}

class _TrainingTitleCard extends StatelessWidget {
  const _TrainingTitleCard({
    required this.controller,
    required this.saving,
    required this.savedTitle,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final String? savedTitle;
  final VoidCallback onSave;

  static const _accent = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: EmployeeDashUi.elevatedPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note_rounded, color: _accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Training program',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            decoration: AppTheme.dashInputDecoration(
              context,
              labelText: 'Training / program title (optional)',
              hintText: 'e.g. Leadership Enhancement Program 2026',
              prefixIcon: const Icon(Icons.school_outlined, size: 20),
            ),
            onSubmitted: (_) => onSave(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (savedTitle != null && savedTitle!.trim().isNotEmpty)
                Expanded(
                  child: Text(
                    'Saved: ${savedTitle!.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'Helps HR identify your training on their review list.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(saving ? 'Saving…' : 'Save title'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.step,
    required this.title,
    required this.description,
    required this.kinds,
    required this.record,
    required this.status,
    required this.locked,
    required this.wide,
    required this.picked,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
    required this.onUpload,
    required this.onPreview,
    this.lockedMessage,
  });

  final int step;
  final String title;
  final String description;
  final List<LdTrainingRequirementDocKind> kinds;
  final LdTrainingRequirementRecord record;
  final _PhaseStatus status;
  final bool locked;
  final String? lockedMessage;
  final bool wide;
  final Map<LdTrainingRequirementDocKind, PlatformFile> picked;
  final bool uploading;
  final ValueChanged<LdTrainingRequirementDocKind> onPick;
  final ValueChanged<LdTrainingRequirementDocKind> onRemove;
  final ValueChanged<LdTrainingRequirementDocKind> onUpload;
  final ValueChanged<LdTrainingRequirementDocKind> onPreview;

  static const _accent = Color(0xFFE85D04);

  int get _uploaded =>
      kinds.where((k) {
        final p = record.docPath(k);
        return p != null && p.trim().isNotEmpty;
      }).length;

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (status) {
      _PhaseStatus.approved => const Color(0xFF2E7D32),
      _PhaseStatus.awaitingReview => const Color(0xFF1565C0),
      _PhaseStatus.inProgress => _accent,
      _PhaseStatus.actionNeeded => _accent,
      _PhaseStatus.locked => Colors.grey.shade600,
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$step',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: locked
                          ? AppTheme.dashTextSecondaryOf(context)
                          : AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      height: 1.45,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(status: status),
          ],
        ),
        if (!locked && kinds.length > 1) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: kinds.isEmpty ? 0 : _uploaded / kinds.length,
              minHeight: 6,
              backgroundColor: AppTheme.dashMutedSurfaceOf(context),
              color: accentColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_uploaded of ${kinds.length} documents uploaded',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
          ),
        ],
        if (locked && lockedMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lockedMessage!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.dashTextSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (wide && kinds.length > 1)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: kinds
                .map(
                  (k) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: k != kinds.last ? 10 : 0,
                      ),
                      child: _DocTile(
                        kind: k,
                        record: record,
                        disabled: locked || _isDocLocked(k) || uploading,
                        picked: picked[k],
                        uploading: uploading,
                        onPick: () => onPick(k),
                        onRemove: () => onRemove(k),
                        onUpload: () => onUpload(k),
                        onPreview: () => onPreview(k),
                      ),
                    ),
                  ),
                )
                .toList(),
          )
        else
          ...kinds.map(
            (k) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DocTile(
                kind: k,
                record: record,
                disabled: locked || _isDocLocked(k) || uploading,
                picked: picked[k],
                uploading: uploading,
                onPick: () => onPick(k),
                onRemove: () => onRemove(k),
                onUpload: () => onUpload(k),
                onPreview: () => onPreview(k),
              ),
            ),
          ),
      ],
    );

    return Container(
      decoration: EmployeeDashUi.elevatedPanel(context).copyWith(
        border: Border.all(
          color: accentColor.withValues(alpha: locked ? 0.12 : 0.22),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: accentColor.withValues(alpha: locked ? 0.25 : 0.85)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: locked
                ? Opacity(opacity: 0.55, child: content)
                : content,
          ),
        ],
      ),
    );
  }

  bool _isDocLocked(LdTrainingRequirementDocKind kind) {
    if (kind.isPreTraining) return record.preRequirementsApproved;
    return record.postRequirementsApproved;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _PhaseStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      _PhaseStatus.locked => ('Locked', Colors.grey.shade700, Icons.lock_rounded),
      _PhaseStatus.approved => (
        'Approved',
        const Color(0xFF2E7D32),
        Icons.verified_rounded,
      ),
      _PhaseStatus.awaitingReview => (
        'Awaiting HR',
        const Color(0xFF1565C0),
        Icons.hourglass_top_rounded,
      ),
      _PhaseStatus.inProgress => (
        'In progress',
        const Color(0xFFE85D04),
        Icons.upload_file_rounded,
      ),
      _PhaseStatus.actionNeeded => (
        'Submit documents',
        const Color(0xFFE85D04),
        Icons.upload_file_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.kind,
    required this.record,
    required this.disabled,
    required this.picked,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
    required this.onUpload,
    required this.onPreview,
  });

  final LdTrainingRequirementDocKind kind;
  final LdTrainingRequirementRecord record;
  final bool disabled;
  final PlatformFile? picked;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onUpload;
  final VoidCallback onPreview;

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

  static IconData _kindIcon(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return Icons.mail_outline_rounded;
      case LdTrainingRequirementDocKind.lap:
        return Icons.menu_book_outlined;
      case LdTrainingRequirementDocKind.trainingCertificate:
        return Icons.workspace_premium_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final storedPath = record.docPath(kind);
    final storedName = record.docDisplayName(kind);
    final hasStored = storedPath != null && storedPath.isNotEmpty;
    final navy = AppTheme.primaryNavy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasStored
              ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
              : AppTheme.dashHairlineOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_kindIcon(kind), size: 20, color: navy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _kindLabel(kind),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasStored)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9).withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: Colors.green.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      storedName ?? 'Uploaded',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'View PDF',
                    onPressed: disabled ? null : onPreview,
                    icon: Icon(Icons.visibility_outlined, color: navy),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            )
          else if (picked != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFE85D04).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      picked!.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: disabled ? null : onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: disabled ? null : onUpload,
              icon: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(uploading ? 'Uploading…' : 'Upload PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]
          else
            OutlinedButton.icon(
              onPressed: disabled ? null : onPick,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Choose PDF'),
              style: OutlinedButton.styleFrom(
                foregroundColor: navy,
                side: BorderSide(color: navy.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}
