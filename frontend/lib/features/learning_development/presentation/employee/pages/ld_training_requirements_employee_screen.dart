import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/utils/input_rules.dart';
import 'package:hrms_plaridel/features/learning_development/models/ld_training_requirements.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/employee/widgets/ld_employee_layout.dart';

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
  List<LdTrainingRequirementRecord> _history = const [];
  bool _loading = true;
  bool _refreshing = false;
  final Set<LdTrainingRequirementDocKind> _uploadingKinds = {};
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

  Future<void> _load({bool silent = false}) async {
    if (_loading && silent) return;
    if (_refreshing) return;
    setState(() {
      if (silent) {
        _refreshing = true;
      } else {
        _loading = true;
      }
    });
    try {
      final mine = await LdTrainingRequirementRepo.instance.loadMine();
      if (!mounted) return;
      setState(() {
        _record = mine.current;
        _history = mine.history;
        _trainingTitleController.text = mine.current?.trainingTitle ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiError(e))));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refreshRequirements() => _load(silent: true);

  bool _hasTitle(LdTrainingRequirementRecord r) =>
      (r.trainingTitle ?? '').trim().isNotEmpty;

  Future<void> _saveTrainingTitle() async {
    final title = _trainingTitleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the training or seminar you will attend.'),
        ),
      );
      return;
    }
    if (title.length > InputRules.trainingRequirementTitleMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Training title must be at most ${InputRules.trainingRequirementTitleMax} characters.',
          ),
        ),
      );
      return;
    }
    setState(() => _savingTitle = true);
    try {
      final declared = _record != null && _hasTitle(_record!);
      final repo = LdTrainingRequirementRepo.instance;
      final r = declared
          ? await repo.updateMyTrainingTitle(title)
          : await repo.declareTraining(title);
      if (!mounted) return;
      setState(() => _record = r);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            declared
                ? 'Training title saved.'
                : 'Training declared. You can now submit your requirements.',
          ),
        ),
      );
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
    final size = f.size > 0 ? f.size : (f.bytes?.length ?? 0);
    if (!InputRules.isWithinMaxBytes(
      size,
      InputRules.trainingRequirementPdfMaxBytes,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF must be at most ${InputRules.formatBytesLabel(InputRules.trainingRequirementPdfMaxBytes)}.',
          ),
        ),
      );
      return;
    }
    setState(() => _picked[kind] = f);
  }

  Future<void> _uploadKind(LdTrainingRequirementDocKind kind) async {
    final r = _record;
    final f = _picked[kind];
    if (r == null || f == null || f.bytes == null) return;
    if (_uploadingKinds.contains(kind)) return;
    setState(() => _uploadingKinds.add(kind));
    try {
      await LdTrainingRequirementRepo.instance.uploadDocument(
        r.id,
        kind,
        f.bytes!,
        f.name,
      );
      if (!mounted) return;
      setState(() => _picked.remove(kind));
      await _load(silent: true);
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
      if (mounted) setState(() => _uploadingKinds.remove(kind));
    }
  }

  Future<void> _previewDoc(LdTrainingRequirementDocKind kind) async {
    final r = _record;
    if (r == null) return;
    await _previewRecordDoc(r, kind);
  }

  Future<void> _previewRecordDoc(
    LdTrainingRequirementRecord r,
    LdTrainingRequirementDocKind kind,
  ) async {
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
  }) {
    if (locked) return _PhaseStatus.locked;
    if (approved) return _PhaseStatus.approved;
    if (kinds.any(record.isDocRejected)) return _PhaseStatus.needsRevision;
    final uploaded = _uploadedCount(record, kinds);
    if (uploaded >= kinds.length) return _PhaseStatus.awaitingReview;
    if (uploaded > 0) return _PhaseStatus.inProgress;
    return _PhaseStatus.actionNeeded;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final current = _record;
    // Requirements can only be submitted for a declared training/seminar.
    final declared = current != null && _hasTitle(current);
    final r =
        current ?? const LdTrainingRequirementRecord(id: '', employeeId: '');

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
        final width = constraints.maxWidth;
        final twoCol = LdEmployeeLayout.isTwoCol(width);
        final compact = LdEmployeeLayout.isPhone(width) || width < 768;
        final phoneNarrow = LdEmployeeLayout.isPhoneNarrow(width);
        final gap = LdEmployeeLayout.sectionGap(width);

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
            locked: !declared,
          ),
          locked: !declared,
          lockedTitle: 'Declare your training first',
          lockedMessage:
              'Enter the training or seminar you will attend above to start submitting requirements.',
          compact: compact,
          phoneNarrow: phoneNarrow,
          picked: _picked,
          uploadingKinds: _uploadingKinds,
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
            locked: !declared || !r.preRequirementsApproved,
          ),
          locked: !declared || !r.preRequirementsApproved,
          lockedTitle: declared
              ? 'Waiting for HR approval'
              : 'Declare your training first',
          lockedMessage: declared
              ? 'Post-training requirements will become available after HR approves your pre-training documents.'
              : 'Enter the training or seminar you will attend above to start.',
          compact: compact,
          phoneNarrow: phoneNarrow,
          picked: _picked,
          uploadingKinds: _uploadingKinds,
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
              child: _RequirementsHero(
                record: r,
                compact: compact,
                phoneNarrow: phoneNarrow,
                refreshing: _refreshing,
                onRefresh: _refreshRequirements,
              ),
            ),
            SizedBox(height: gap),
            KeyedSubtree(
              key: widget.tutorialProgramKey,
              child: _TrainingTitleCard(
                controller: _trainingTitleController,
                saving: _savingTitle,
                savedTitle: r.trainingTitle,
                declared: declared,
                titleLocked: declared && r.preRequirementsApproved,
                justCompleted: !declared && _history.isNotEmpty,
                compact: compact,
                phoneNarrow: phoneNarrow,
                onSave: _saveTrainingTitle,
                historyAction: _history.isEmpty
                    ? null
                    : _historyButton(context, fullWidth: compact),
              ),
            ),
            SizedBox(height: gap),
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
              SizedBox(height: gap),
              postCard,
            ],
          ],
        );
      },
    );
  }

  Widget _historyButton(BuildContext context, {required bool fullWidth}) {
    final button = OutlinedButton.icon(
      onPressed: _openTrainingHistory,
      icon: const Icon(Icons.history_rounded, size: 18),
      label: Text('Training history (${_history.length})'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryNavy,
        backgroundColor: AppTheme.dashPanelOf(context),
        side: BorderSide(
          color: AppTheme.primaryNavy.withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
    if (!fullWidth) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  Future<void> _openTrainingHistory() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close training history',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, __) {
        final mq = MediaQuery.of(dialogContext);
        final panel = LdEmployeeLayout.sidePanelMetrics(mq);
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              panel.top,
              panel.right,
              panel.bottom,
            ),
            child: Material(
              color: AppTheme.dashPanelOf(dialogContext),
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.horizontal(
                left: const Radius.circular(18),
                right: panel.fullBleed
                    ? Radius.zero
                    : const Radius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: panel.width,
                height: mq.size.height - panel.top - panel.bottom,
                child: _CompletedTrainings(
                  records: _history,
                  onClose: () => Navigator.of(dialogContext).pop(),
                  onPreview: _previewRecordDoc,
                ),
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
}

enum _PhaseStatus {
  locked,
  actionNeeded,
  needsRevision,
  inProgress,
  awaitingReview,
  approved,
}

class _RequirementsHero extends StatelessWidget {
  const _RequirementsHero({
    required this.record,
    required this.compact,
    this.phoneNarrow = false,
    required this.refreshing,
    required this.onRefresh,
  });

  final LdTrainingRequirementRecord record;
  final bool compact;
  final bool phoneNarrow;
  final bool refreshing;
  final VoidCallback onRefresh;

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

    final pad = phoneNarrow
        ? const EdgeInsets.fromLTRB(12, 12, 8, 12)
        : EdgeInsets.fromLTRB(
            compact ? 14 : 22,
            compact ? 14 : 18,
            compact ? 10 : 22,
            compact ? 12 : 16,
          );
    final iconSize = phoneNarrow ? 40.0 : (compact ? 44.0 : 50.0);
    final titleSize = phoneNarrow ? 17.0 : (compact ? 19.0 : 28.0);
    final bodySize = phoneNarrow ? 12.5 : (compact ? 13.0 : 14.0);

    return Container(
      padding: pad,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  color: AppTheme.primaryNavy,
                  size: phoneNarrow ? 20 : (compact ? 22 : 26),
                ),
              ),
              SizedBox(width: phoneNarrow ? 10 : (compact ? 12 : 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMPLOYEE TRAINING',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.primaryNavy,
                        fontSize: phoneNarrow ? 10 : 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: compact ? 0.5 : 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Training Requirements',
                      maxLines: 2,
                      style: TextStyle(
                        color: primary,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phoneNarrow
                          ? 'Submit and track your training documents.'
                          : 'Submit and track your required pre-training and post-training documents.',
                      style: TextStyle(
                        color: secondary,
                        fontSize: bodySize,
                        height: 1.4,
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Current stage: $_currentStage',
                        style: TextStyle(
                          color: primary,
                          fontSize: phoneNarrow ? 12 : 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: refreshing
                    ? 'Refreshing requirements'
                    : 'Refresh requirements',
                visualDensity: phoneNarrow
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                constraints: phoneNarrow
                    ? const BoxConstraints(minWidth: 40, minHeight: 40)
                    : null,
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
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
          _ProgressSteps(
            record: record,
            compact: compact,
            phoneNarrow: phoneNarrow,
          ),
        ],
      ),
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({
    required this.record,
    required this.compact,
    this.phoneNarrow = false,
  });

  final LdTrainingRequirementRecord record;
  final bool compact;
  final bool phoneNarrow;

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
        Expanded(
          flex: 3,
          child: _StepNode(
            number: 1,
            label: phoneNarrow
                ? 'Pre'
                : (compact ? 'Pre' : 'Pre-training'),
            done: preDone,
            active: preActive,
            locked: false,
            compact: compact,
          ),
        ),
        connector(preDone),
        Expanded(
          flex: 3,
          child: _StepNode(
            number: 2,
            label: phoneNarrow
                ? 'Post'
                : (compact ? 'Post' : 'Post-training'),
            done: postDone,
            active: postActive,
            locked: postLocked,
            compact: compact,
          ),
        ),
        connector(postDone),
        Expanded(
          flex: 3,
          child: _StepNode(
            number: 3,
            label: phoneNarrow
                ? 'Done'
                : (compact ? 'Done' : 'Complete'),
            done: postDone,
            active: false,
            locked: false,
            compact: compact,
          ),
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
    this.compact = false,
  });

  final int number;
  final String label;
  final bool done;
  final bool active;
  final bool locked;
  final bool compact;

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

    final nodeSize = compact ? 26.0 : 28.0;
    return Column(
      children: [
        Container(
          width: nodeSize,
          height: nodeSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 1.4),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: compact ? 14 : 16, color: Colors.white)
              : locked
              ? Icon(Icons.lock_rounded, size: compact ? 12 : 13, color: fg)
              : Text(
                  '$number',
                  style: TextStyle(
                    color: fg,
                    fontSize: compact ? 11 : 12,
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
            fontSize: compact ? 10.5 : 11,
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
    required this.declared,
    required this.titleLocked,
    required this.justCompleted,
    required this.compact,
    this.phoneNarrow = false,
    required this.onSave,
    this.historyAction,
  });

  final TextEditingController controller;
  final bool saving;
  final String? savedTitle;

  /// A training/seminar is already declared for the current submission.
  final bool declared;

  /// HR approved the pre-training documents, so the title can't change.
  final bool titleLocked;

  /// The previous training was completed; the next one is not declared yet.
  final bool justCompleted;
  final bool compact;
  final bool phoneNarrow;
  final VoidCallback onSave;
  final Widget? historyAction;

  static const _accent = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final dark = AppTheme.dashIsDark(context);

    final heading = declared
        ? 'Training Program'
        : 'Declare Training / Seminar';
    final subheading = declared
        ? (titleLocked
              ? 'Locked after HR approved your pre-training documents.'
              : 'Identify the training/program associated with these requirements.')
        : (justCompleted
              ? 'Previous training is complete. Declare the next one before submitting new requirements.'
              : 'Declare the training or seminar you will attend before submitting any requirements.');

    final input = TextField(
      controller: controller,
      enabled: !titleLocked,
      textInputAction: TextInputAction.done,
      maxLength: InputRules.trainingRequirementTitleMax,
      inputFormatters: InputRules.plainTextFormatters(
        maxLength: InputRules.trainingRequirementTitleMax,
        allowNewlines: false,
      ),
      decoration:
          AppTheme.dashInputDecoration(
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
            counterText: '',
          ),
      onSubmitted: (_) => onSave(),
    );

    final saveBtn = FilledButton.icon(
      onPressed: (saving || titleLocked) ? null : onSave,
      icon: saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(
              declared ? Icons.save_outlined : Icons.add_circle_outline,
              size: 18,
            ),
      label: Text(
        saving
            ? 'Saving…'
            : declared
            ? 'Save Title'
            : 'Declare Training',
      ),
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
        phoneNarrow ? 12 : (compact ? 14 : 20),
        phoneNarrow ? 12 : (compact ? 14 : 16),
        phoneNarrow ? 12 : (compact ? 14 : 20),
        phoneNarrow ? 12 : (compact ? 14 : 16),
      ),
      decoration: _panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _programIcon(),
              SizedBox(width: phoneNarrow ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      heading,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: phoneNarrow ? 14 : 15,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subheading,
                      style: TextStyle(
                        fontSize: phoneNarrow ? 12.5 : 13,
                        color: secondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact && historyAction != null) ...[
                const SizedBox(width: 12),
                historyAction!,
              ],
            ],
          ),
          if (compact && historyAction != null) ...[
            const SizedBox(height: 12),
            historyAction!,
          ],
          const SizedBox(height: 14),
          if (compact) ...[
            input,
            const SizedBox(height: 10),
            saveBtn,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: input),
                const SizedBox(width: 12),
                saveBtn,
              ],
            ),
          if (declared &&
              savedTitle != null &&
              savedTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Saved: ${savedTitle!.trim()}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: secondary, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _programIcon() {
    final size = phoneNarrow ? 32.0 : 36.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.edit_note_rounded,
        color: _accent,
        size: phoneNarrow ? 18 : 20,
      ),
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
    this.phoneNarrow = false,
    required this.picked,
    required this.uploadingKinds,
    required this.onPick,
    required this.onRemove,
    required this.onUpload,
    required this.onPreview,
    this.lockedMessage,
    this.lockedTitle = 'Waiting for HR approval',
  });

  final String lockedTitle;
  final int step;
  final String title;
  final String description;
  final List<LdTrainingRequirementDocKind> kinds;
  final LdTrainingRequirementRecord record;
  final _PhaseStatus status;
  final bool locked;
  final String? lockedMessage;
  final bool compact;
  final bool phoneNarrow;
  final Map<LdTrainingRequirementDocKind, PlatformFile> picked;
  final Set<LdTrainingRequirementDocKind> uploadingKinds;
  final ValueChanged<LdTrainingRequirementDocKind> onPick;
  final ValueChanged<LdTrainingRequirementDocKind> onRemove;
  final ValueChanged<LdTrainingRequirementDocKind> onUpload;
  final ValueChanged<LdTrainingRequirementDocKind> onPreview;

  static const _accent = Color(0xFFE85D04);

  int get _uploaded => kinds.where((k) {
    final p = record.docPath(k);
    return p != null && p.trim().isNotEmpty;
  }).length;

  bool _isUploading(LdTrainingRequirementDocKind kind) =>
      uploadingKinds.contains(kind);

  bool _isDocLocked(LdTrainingRequirementDocKind kind) {
    if (kind.isPreTraining) return record.preRequirementsApproved;
    return record.postRequirementsApproved;
  }

  bool get _approved => step == 1
      ? record.preRequirementsApproved
      : record.postRequirementsApproved;

  String _docReadyLabel(LdTrainingRequirementDocKind kind) {
    if (record.isDocRejected(kind)) return 'Not approved';
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
      _PhaseStatus.needsRevision => const Color(0xFFC62828),
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
        !_isUploading(kinds.first);

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
          phoneNarrow ? 12 : (compact ? 14 : 20),
          phoneNarrow ? 12 : (compact ? 14 : 20),
          phoneNarrow ? 12 : (compact ? 14 : 20),
          phoneNarrow ? 12 : (compact ? 14 : 18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: phoneNarrow ? 28 : 32,
                  height: phoneNarrow ? 28 : 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: locked
                      ? Icon(
                          Icons.lock_rounded,
                          size: phoneNarrow ? 13 : 15,
                          color: accentColor,
                        )
                      : Text(
                          '$step',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: phoneNarrow ? 12 : 14,
                            color: accentColor,
                          ),
                        ),
                ),
                SizedBox(width: phoneNarrow ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: phoneNarrow ? 14 : (compact ? 15 : 16),
                          color: primary,
                          height: 1.25,
                        ),
                      ),
                      if (compact) ...[
                        const SizedBox(height: 6),
                        _StatusBadge(status: status),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: secondary,
                          height: 1.4,
                          fontSize: phoneNarrow ? 12.5 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  _StatusBadge(status: status),
                ],
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
                            lockedTitle,
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
                final sideBySide =
                    !compact && kinds.length > 1 && inner.maxWidth >= 420;
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
                            disabled:
                                locked ||
                                _isDocLocked(kinds[i]) ||
                                _isUploading(kinds[i]),
                            picked: picked[kinds[i]],
                            uploading: _isUploading(kinds[i]),
                            showUploadButton: !singleKind,
                            phoneNarrow: phoneNarrow,
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
                        disabled:
                            locked ||
                            _isDocLocked(kinds[i]) ||
                            _isUploading(kinds[i]),
                        picked: picked[kinds[i]],
                        uploading: _isUploading(kinds[i]),
                        showUploadButton: !singleKind,
                        phoneNarrow: phoneNarrow,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _DocTile.shortLabel(k),
                        style: TextStyle(
                          fontSize: phoneNarrow ? 12.5 : 13,
                          color: primary,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                    icon: _isUploading(kinds.first)
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
                      _isUploading(kinds.first)
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

/// Trainings/seminars HR has already fully approved.
class _CompletedTrainings extends StatefulWidget {
  const _CompletedTrainings({
    required this.records,
    required this.onClose,
    required this.onPreview,
  });

  final List<LdTrainingRequirementRecord> records;
  final VoidCallback onClose;
  final void Function(
    LdTrainingRequirementRecord record,
    LdTrainingRequirementDocKind kind,
  )
  onPreview;

  @override
  State<_CompletedTrainings> createState() => _CompletedTrainingsState();
}

class _CompletedTrainingsState extends State<_CompletedTrainings> {
  final Set<String> _openRecords = {};

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final count = widget.records.length;
    final phone = LdEmployeeLayout.isPhone(MediaQuery.sizeOf(context).width);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 3, color: AppTheme.primaryNavy),
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? 14 : 18, 16, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: phone ? 32 : 36,
                height: phone ? 32 : 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: phone ? 18 : 20,
                  color: AppTheme.primaryNavy,
                ),
              ),
              SizedBox(width: phone ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Training history',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: phone ? 15 : 16,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count completed ${count == 1 ? 'training' : 'trainings'}',
                      style: TextStyle(
                        fontSize: phone ? 12 : 12.5,
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                visualDensity:
                    phone ? VisualDensity.compact : VisualDensity.standard,
                onPressed: widget.onClose,
                icon: Icon(Icons.close_rounded, color: secondary),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              phone ? 14 : 16,
              14,
              phone ? 14 : 16,
              16 + bottomSafe,
            ),
            children: [
              for (final r in widget.records) _recordTile(r, primary, secondary),
            ],
          ),
        ),
      ],
    );
  }

  String? _completedLabel(LdTrainingRequirementRecord r) {
    final at = (r.updatedAt ?? r.createdAt)?.toLocal();
    if (at == null) return null;
    return 'Completed ${MaterialLocalizations.of(context).formatMediumDate(at)}';
  }

  Widget _recordTile(
    LdTrainingRequirementRecord r,
    Color primary,
    Color secondary,
  ) {
    final expanded = _openRecords.contains(r.id);
    final title = (r.trainingTitle ?? '').trim().isEmpty
        ? 'Untitled training'
        : r.trainingTitle!.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              if (!_openRecords.remove(r.id)) _openRecords.add(r.id);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 18,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRAINING / SEMINAR',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                        if (_completedLabel(r) != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _completedLabel(r)!,
                            style: TextStyle(fontSize: 11.5, color: secondary),
                          ),
                        ],
                        const SizedBox(height: 2),
                        const Text(
                          'Approved',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: secondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  _phaseSection(
                    r,
                    step: 1,
                    label: 'Pre-training requirements',
                    kinds: const [
                      LdTrainingRequirementDocKind.invitationLetter,
                      LdTrainingRequirementDocKind.travelOrder,
                    ],
                    primary: primary,
                    secondary: secondary,
                  ),
                  const SizedBox(height: 8),
                  _phaseSection(
                    r,
                    step: 2,
                    label: 'Post-training requirements',
                    kinds: const [
                      LdTrainingRequirementDocKind.lap,
                      LdTrainingRequirementDocKind.trainingCertificate,
                    ],
                    primary: primary,
                    secondary: secondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _phaseSection(
    LdTrainingRequirementRecord r, {
    required int step,
    required String label,
    required List<LdTrainingRequirementDocKind> kinds,
    required Color primary,
    required Color secondary,
  }) {
    const green = Color(0xFF2E7D32);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: green,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Approved',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: green,
                  ),
                ),
              ),
            ],
          ),
          for (final k in kinds) _docRow(r, k, primary, secondary),
        ],
      ),
    );
  }

  Widget _docRow(
    LdTrainingRequirementRecord r,
    LdTrainingRequirementDocKind kind,
    Color primary,
    Color secondary,
  ) {
    final path = r.docPath(kind);
    final has = path != null && path.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            Icons.picture_as_pdf_rounded,
            size: 16,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              has
                  ? '${_DocTile.shortLabel(kind)}: ${r.docDisplayName(kind) ?? 'Uploaded'}'
                  : '${_DocTile.shortLabel(kind)}: not submitted',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: has ? primary : secondary,
              ),
            ),
          ),
          if (has)
            TextButton(
              onPressed: () => widget.onPreview(r, kind),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('View'),
            ),
        ],
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
        Text('HR Review', style: TextStyle(fontSize: 13, color: secondary)),
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
      _PhaseStatus.needsRevision => (
        'Not approved',
        const Color(0xFFC62828),
        Icons.cancel_rounded,
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
    this.phoneNarrow = false,
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
  final bool phoneNarrow;
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
    final rejected = record.isDocRejected(kind);
    final rejectReason = record.docRejectReason(kind)?.trim();
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final navy = AppTheme.primaryNavy;
    const rejectColor = Color(0xFFC62828);

    return Container(
      padding: EdgeInsets.all(phoneNarrow ? 12 : 14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rejected
              ? rejectColor.withValues(alpha: 0.35)
              : hasStored
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
                padding: EdgeInsets.all(phoneNarrow ? 6 : 7),
                decoration: BoxDecoration(
                  color: (rejected ? rejectColor : AppTheme.primaryNavy)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  rejected ? Icons.cancel_rounded : _kindIcon(kind),
                  size: phoneNarrow ? 16 : 18,
                  color: rejected ? rejectColor : navy,
                ),
              ),
              SizedBox(width: phoneNarrow ? 8 : 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortLabel(kind),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: phoneNarrow ? 12.5 : 13,
                        height: 1.25,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rejected
                          ? 'HR marked this document not approved. Please upload a new PDF.'
                          : _kindSubtitle(kind),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: phoneNarrow ? 11 : 11.5,
                        height: 1.35,
                        color: rejected ? rejectColor : secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
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
          if (rejected && rejectReason != null && rejectReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: rejectColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: rejectColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                rejectReason,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: primary,
                ),
              ),
            ),
          ],
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
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'PDF only • Max 15 MB',
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
            TextButton(
              onPressed: onView,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('View'),
            ),
          if (onRemove != null)
            TextButton(
              onPressed: onRemove,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(44, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Remove'),
            ),
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
