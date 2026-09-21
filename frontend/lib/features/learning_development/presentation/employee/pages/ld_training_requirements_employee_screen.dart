import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/ld_training_requirements.dart';

class LdTrainingRequirementsEmployeeScreen extends StatefulWidget {
  const LdTrainingRequirementsEmployeeScreen({
    super.key,
    this.tutorialHeaderKey,
    this.tutorialProgramKey,
    this.tutorialPreTrainingKey,
    this.tutorialPostTrainingKey,
  });

  final GlobalKey? tutorialHeaderKey;
  final GlobalKey? tutorialProgramKey;
  final GlobalKey? tutorialPreTrainingKey;
  final GlobalKey? tutorialPostTrainingKey;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Training title saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document uploaded.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
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
    final url = await LdTrainingRequirementRepo.instance
        .getAttachmentDownloadUrl(path, fileName: name);
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
    return isPreTraining
        ? _PhaseStatus.actionNeeded
        : _PhaseStatus.actionNeeded;
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

    const preKinds = [
      LdTrainingRequirementDocKind.invitationLetter,
      LdTrainingRequirementDocKind.travelOrder,
    ];
    const postKinds = [
      LdTrainingRequirementDocKind.lap,
      LdTrainingRequirementDocKind.trainingCertificate,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 900;
        final compact = constraints.maxWidth < 768;

        final preCard = _PhaseCard(
          key: widget.tutorialPreTrainingKey,
          step: 1,
          title: 'Pre-training requirements',
          description:
              'Upload your invitation letter (mayor-approved) and Travel Order for training travel.',
          kinds: preKinds,
          record: r,
          status: _phaseStatus(
            record: r,
            kinds: preKinds,
            approved: r.preRequirementsApproved,
            locked: false,
            isPreTraining: true,
          ),
          locked: false,
          compact: compact,
          picked: _picked,
          uploading: _uploading,
          onPick: _pick,
          onRemove: _removePicked,
          onUpload: _uploadKind,
          onPreview: _previewDoc,
        );
        final postCard = _PhaseCard(
          key: widget.tutorialPostTrainingKey,
          step: 2,
          title: 'Post-training requirements',
          description:
              'After training, upload your Learning Application Plan (LAP) and training certificate.',
          kinds: postKinds,
          record: r,
          status: _phaseStatus(
            record: r,
            kinds: postKinds,
            approved: r.postRequirementsApproved,
            locked: !r.preRequirementsApproved,
            isPreTraining: false,
          ),
          locked: !r.preRequirementsApproved,
          lockedMessage:
              'Post-training requirements will become available after HR approves your pre-training documents.',
          compact: compact,
          picked: _picked,
          uploading: _uploading,
          onPick: _pick,
          onRemove: _removePicked,
          onUpload: _uploadKind,
          onPreview: _previewDoc,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: widget.tutorialHeaderKey,
              child: _RequirementsHero(record: r, compact: compact),
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: widget.tutorialProgramKey,
              child: _TrainingTitleCard(
                controller: _trainingTitleController,
                saving: _savingTitle,
                savedTitle: r.trainingTitle,
                compact: compact,
                onSave: _saveTrainingTitle,
              ),
            ),
            const SizedBox(height: 16),
            if (twoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: preCard),
                  const SizedBox(width: 20),
                  Expanded(child: postCard),
                ],
              )
            else ...[
              preCard,
              const SizedBox(height: 16),
              postCard,
            ],
          ],
        );
      },
    );
  }
}

enum _PhaseStatus { locked, actionNeeded, inProgress, awaitingReview, approved }

class _RequirementsHero extends StatelessWidget {
  const _RequirementsHero({required this.record, required this.compact});

  final LdTrainingRequirementRecord record;
  final bool compact;

  String get _currentStage {
    if (record.postRequirementsApproved) return 'Complete';
    if (record.preRequirementsApproved) return 'Post-training';
    return 'Pre-training';
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        compact ? 16 : 18,
        compact ? 16 : 22,
        compact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: dark
              ? [AppTheme.dashPanelOf(context), const Color(0xFF2A241E)]
              : const [Colors.white, Color(0xFFFFF6EE)],
        ),
        border: Border.all(
          color: dark
              ? AppTheme.dashHairlineOf(context)
              : AppTheme.primaryNavy.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 44 : 50,
                height: compact ? 44 : 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  color: AppTheme.primaryNavy,
                  size: compact ? 22 : 26,
                ),
              ),
              SizedBox(width: compact ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMPLOYEE TRAINING',
                      style: TextStyle(
                        color: AppTheme.primaryNavy,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Training Requirements',
                      style: TextStyle(
                        color: primary,
                        fontSize: compact ? 22 : 28,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Submit and track your required pre-training and post-training documents.',
                      style: TextStyle(
                        color: secondary,
                        fontSize: compact ? 13 : 14,
                        height: 1.35,
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Current stage: $_currentStage',
                        style: TextStyle(
                          color: primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dashPanelOf(context).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dashHairlineOf(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Current Stage',
                        style: TextStyle(
                          color: secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentStage,
                        style: TextStyle(
                          color: primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _ProgressSteps(record: record, compact: compact),
        ],
      ),
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.record, required this.compact});

  final LdTrainingRequirementRecord record;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final preDone = record.preRequirementsApproved;
    final postDone = record.postRequirementsApproved;
    final preActive = !preDone;
    final postActive = preDone && !postDone;
    final postLocked = !preDone;

    Widget connector(bool complete) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            height: 2,
            color: complete
                ? const Color(0xFF2E7D32).withValues(alpha: 0.45)
                : AppTheme.dashHairlineOf(context),
          ),
        ),
      );
    }

    return Row(
      children: [
        _StepNode(
          number: 1,
          label: compact ? 'Pre' : 'Pre-training',
          done: preDone,
          active: preActive,
          locked: false,
        ),
        connector(preDone),
        _StepNode(
          number: 2,
          label: compact ? 'Post' : 'Post-training',
          done: postDone,
          active: postActive,
          locked: postLocked,
        ),
        connector(postDone),
        _StepNode(
          number: 3,
          label: 'Complete',
          done: postDone,
          active: false,
          locked: false,
        ),
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
    required this.locked,
  });

  final int number;
  final String label;
  final bool done;
  final bool active;
  final bool locked;

  static const _accent = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final Color ring;
    final Color fill;
    final Color fg;
    if (done) {
      ring = const Color(0xFF2E7D32);
      fill = const Color(0xFF2E7D32);
      fg = Colors.white;
    } else if (active) {
      ring = _accent;
      fill = _accent;
      fg = Colors.white;
    } else {
      ring = secondary.withValues(alpha: 0.35);
      fill = AppTheme.dashMutedSurfaceOf(context);
      fg = secondary;
    }

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 1.4),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : locked
              ? Icon(Icons.lock_rounded, size: 13, color: fg)
              : Text(
                  '$number',
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: done || active ? primary : secondary,
          ),
        ),
      ],
    );
  }
}

class _TrainingTitleCard extends StatelessWidget {
  const _TrainingTitleCard({
    required this.controller,
    required this.saving,
    required this.savedTitle,
    required this.compact,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final String? savedTitle;
  final bool compact;
  final VoidCallback onSave;

  static const _accent = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);

    final input = TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      decoration: AppTheme.dashInputDecoration(
        context,
        hintText: 'e.g. Leadership Enhancement Program 2026',
        prefixIcon: const Icon(Icons.school_outlined, size: 20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        radius: 11,
      ).copyWith(
        filled: true,
        fillColor: dark
            ? AppTheme.dashMutedSurfaceOf(context)
            : const Color(0xFFF7F8FA),
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      onSubmitted: (_) => onSave(),
    );

    final saveBtn = FilledButton.icon(
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
      label: Text(saving ? 'Saving…' : 'Save Title'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryNavy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.primaryNavy.withValues(alpha: 0.45),
        minimumSize: Size(compact ? double.infinity : 132, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 20,
        compact ? 14 : 16,
        compact ? 16 : 20,
        compact ? 14 : 16,
      ),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            Row(
              children: [
                _programIcon(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Training Program',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: primary,
                        ),
                      ),
                      Text(
                        'Identify the training/program associated with these requirements.',
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            input,
            const SizedBox(height: 10),
            saveBtn,
          ] else
            Row(
              children: [
                _programIcon(),
                const SizedBox(width: 12),
                SizedBox(
                  width: 168,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Training Program',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: primary,
                        ),
                      ),
                      Text(
                        'Identify the training/program associated with these requirements.',
                        style: TextStyle(fontSize: 11.5, color: secondary, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: input),
                const SizedBox(width: 12),
                saveBtn,
              ],
            ),
          if (savedTitle != null && savedTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Saved: ${savedTitle!.trim()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _programIcon() {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.edit_note_rounded, color: _accent, size: 20),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    super.key,
    required this.step,
    required this.title,
    required this.description,
    required this.kinds,
    required this.record,
    required this.status,
    required this.locked,
    required this.compact,
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
  final bool compact;
  final Map<LdTrainingRequirementDocKind, PlatformFile> picked;
  final bool uploading;
  final ValueChanged<LdTrainingRequirementDocKind> onPick;
  final ValueChanged<LdTrainingRequirementDocKind> onRemove;
  final ValueChanged<LdTrainingRequirementDocKind> onUpload;
  final ValueChanged<LdTrainingRequirementDocKind> onPreview;

  static const _accent = Color(0xFFE85D04);

  int get _uploaded => kinds.where((k) {
    final p = record.docPath(k);
    return p != null && p.trim().isNotEmpty;
  }).length;

  bool _isDocLocked(LdTrainingRequirementDocKind kind) {
    if (kind.isPreTraining) return record.preRequirementsApproved;
    return record.postRequirementsApproved;
  }

  bool get _approved =>
      step == 1 ? record.preRequirementsApproved : record.postRequirementsApproved;

  String _docReadyLabel(LdTrainingRequirementDocKind kind) {
    final path = record.docPath(kind);
    if (path != null && path.trim().isNotEmpty) return 'Uploaded';
    if (picked[kind] != null) return 'Ready';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final accentColor = switch (status) {
      _PhaseStatus.approved => const Color(0xFF2E7D32),
      _PhaseStatus.awaitingReview => const Color(0xFF1565C0),
      _PhaseStatus.inProgress => _accent,
      _PhaseStatus.actionNeeded => _accent,
      _PhaseStatus.locked => Colors.grey.shade600,
    };

    final singleKind = kinds.length == 1;
    final pickedSingle = singleKind ? picked[kinds.first] : null;
    final storedSingle = singleKind
        ? (record.docPath(kinds.first)?.trim().isNotEmpty ?? false)
        : false;
    final canSubmitSingle =
        singleKind &&
        pickedSingle != null &&
        !locked &&
        !_isDocLocked(kinds.first) &&
        !uploading;

    return Container(
      decoration: _panelDecoration(context).copyWith(
        color: locked
            ? (AppTheme.dashIsDark(context)
                  ? AppTheme.dashMutedSurfaceOf(context)
                  : const Color(0xFFF7F8FA))
            : AppTheme.dashPanelOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 20,
          compact ? 16 : 20,
          compact ? 16 : 20,
          compact ? 16 : 18,
        ),
        child: Column(
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
                  child: locked
                      ? Icon(
                          Icons.lock_rounded,
                          size: 15,
                          color: accentColor,
                        )
                      : Text(
                          '$step',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: secondary,
                          height: 1.4,
                          fontSize: 13,
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
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: kinds.isEmpty ? 0 : _uploaded / kinds.length,
                  minHeight: 5,
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
                  color: secondary,
                ),
              ),
            ],
            if (locked && lockedMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: AppTheme.primaryNavy,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Waiting for HR approval',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lockedMessage!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: secondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, inner) {
                final sideBySide = !compact && kinds.length > 1 && inner.maxWidth >= 420;
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < kinds.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _DocTile(
                            kind: kinds[i],
                            record: record,
                            disabled: locked || _isDocLocked(kinds[i]) || uploading,
                            picked: picked[kinds[i]],
                            uploading: uploading,
                            showUploadButton: !singleKind,
                            onPick: () => onPick(kinds[i]),
                            onRemove: () => onRemove(kinds[i]),
                            onUpload: () => onUpload(kinds[i]),
                            onPreview: () => onPreview(kinds[i]),
                          ),
                        ),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < kinds.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _DocTile(
                        kind: kinds[i],
                        record: record,
                        disabled: locked || _isDocLocked(kinds[i]) || uploading,
                        picked: picked[kinds[i]],
                        uploading: uploading,
                        showUploadButton: !singleKind,
                        onPick: () => onPick(kinds[i]),
                        onRemove: () => onRemove(kinds[i]),
                        onUpload: () => onUpload(kinds[i]),
                        onPreview: () => onPreview(kinds[i]),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            const SizedBox(height: 12),
            Text(
              'Document status',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: secondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final k in kinds)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _DocTile.shortLabel(k),
                        style: TextStyle(fontSize: 13, color: primary),
                      ),
                    ),
                    Text(
                      _docReadyLabel(k),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _HrReviewRow(approved: _approved, locked: locked),
            if (singleKind) ...[
              const SizedBox(height: 12),
              Align(
                alignment: compact ? Alignment.center : Alignment.centerRight,
                child: SizedBox(
                  width: compact ? double.infinity : 190,
                  child: FilledButton.icon(
                    onPressed: canSubmitSingle
                        ? () => onUpload(kinds.first)
                        : null,
                    icon: uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      uploading
                          ? 'Submitting…'
                          : storedSingle
                          ? 'Submitted'
                          : 'Submit Documents',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryNavy.withValues(
                        alpha: 0.35,
                      ),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HrReviewRow extends StatelessWidget {
  const _HrReviewRow({required this.approved, required this.locked});

  final bool approved;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final label = locked
        ? 'Waiting'
        : approved
        ? 'Approved'
        : 'Pending';
    final color = approved
        ? const Color(0xFF2E7D32)
        : locked
        ? Colors.grey.shade700
        : const Color(0xFFE85D04);
    return Row(
      children: [
        Text(
          'HR Review',
          style: TextStyle(fontSize: 13, color: secondary),
        ),
        const Spacer(),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _PhaseStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      _PhaseStatus.locked => (
        'Locked',
        Colors.grey.shade700,
        Icons.lock_rounded,
      ),
      _PhaseStatus.approved => (
        'Approved',
        const Color(0xFF2E7D32),
        Icons.verified_rounded,
      ),
      _PhaseStatus.awaitingReview => (
        'Under Review',
        const Color(0xFF1565C0),
        Icons.hourglass_top_rounded,
      ),
      _PhaseStatus.inProgress => (
        'Submitted',
        const Color(0xFF1565C0),
        Icons.upload_file_rounded,
      ),
      _PhaseStatus.actionNeeded => (
        'Pending',
        const Color(0xFFE85D04),
        Icons.upload_file_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
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
    required this.showUploadButton,
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
  final bool showUploadButton;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onUpload;
  final VoidCallback onPreview;

  static String shortLabel(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return 'Invitation Letter';
      case LdTrainingRequirementDocKind.travelOrder:
        return 'Travel Order';
      case LdTrainingRequirementDocKind.lap:
        return 'Learning Application Plan (LAP)';
      case LdTrainingRequirementDocKind.trainingCertificate:
        return 'Training Certificate';
    }
  }

  static String _kindSubtitle(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return 'For training travel • Mayor-approved document';
      case LdTrainingRequirementDocKind.travelOrder:
        return 'Official travel order for the training';
      case LdTrainingRequirementDocKind.lap:
        return 'Required after training completion';
      case LdTrainingRequirementDocKind.trainingCertificate:
        return 'Official proof of training attendance';
    }
  }

  static IconData _kindIcon(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return Icons.mail_outline_rounded;
      case LdTrainingRequirementDocKind.travelOrder:
        return Icons.airplane_ticket_outlined;
      case LdTrainingRequirementDocKind.lap:
        return Icons.menu_book_outlined;
      case LdTrainingRequirementDocKind.trainingCertificate:
        return Icons.workspace_premium_outlined;
    }
  }

  static String _fileSizeLabel(PlatformFile file) {
    final bytes = file.size;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final storedPath = record.docPath(kind);
    final storedName = record.docDisplayName(kind);
    final hasStored = storedPath != null && storedPath.isNotEmpty;
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final navy = AppTheme.primaryNavy;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.55),
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
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_kindIcon(kind), size: 18, color: navy),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortLabel(kind),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: primary,
                      ),
                    ),
                    Text(
                      _kindSubtitle(kind),
                      style: TextStyle(fontSize: 11.5, color: secondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PDF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasStored)
            _FileRow(
              name: storedName ?? 'Uploaded',
              meta: 'PDF',
              onView: disabled ? null : onPreview,
            )
          else if (picked != null) ...[
            _FileRow(
              name: picked!.name,
              meta: 'PDF • ${_fileSizeLabel(picked!)}',
              onRemove: disabled ? null : onRemove,
            ),
            if (showUploadButton) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: disabled ? null : onUpload,
                icon: uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(uploading ? 'Uploading…' : 'Upload PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ] else
            CustomPaint(
              painter: _DashedRRectPainter(
                color: AppTheme.dashHairlineOf(context),
                radius: 12,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: disabled ? null : onPick,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 10,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 22,
                          color: disabled ? secondary : navy,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Drop your ${shortLabel(kind).toLowerCase()} here',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'PDF only',
                          style: TextStyle(fontSize: 11.5, color: secondary),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: disabled ? null : onPick,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: navy,
                            side: BorderSide(
                              color: navy.withValues(alpha: 0.4),
                            ),
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          child: const Text('Choose PDF'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.meta,
    this.onView,
    this.onRemove,
  });

  final String name;
  final String meta;
  final VoidCallback? onView;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.picture_as_pdf_rounded,
            size: 18,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                Text(meta, style: TextStyle(fontSize: 11, color: secondary)),
              ],
            ),
          ),
          if (onView != null)
            TextButton(onPressed: onView, child: const Text('View')),
          if (onRemove != null)
            TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration(BuildContext context, {double radius = 18}) {
  final dark = AppTheme.dashIsDark(context);
  return BoxDecoration(
    color: AppTheme.dashPanelOf(context),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppTheme.dashHairlineOf(context)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.18 : 0.04),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 6.0;
    const dashGap = 4.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
