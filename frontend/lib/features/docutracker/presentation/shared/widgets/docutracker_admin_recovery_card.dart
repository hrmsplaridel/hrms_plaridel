import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_admin_recovery.dart';

/// Attention notice for a native document that needs reviewer reassignment.
class DocuTrackerAdminRecoveryCard extends StatelessWidget {
  const DocuTrackerAdminRecoveryCard({
    super.key,
    required this.showAction,
    required this.documentNumber,
    required this.documentTitle,
    required this.stepLabel,
    required this.currentReviewer,
    this.reason,
    this.loadOptions,
    this.onSubmit,
  });

  final bool showAction;
  final String documentNumber;
  final String documentTitle;
  final String stepLabel;
  final String currentReviewer;
  final String? reason;
  final Future<DocuTrackerRecoveryOptions> Function()? loadOptions;
  final Future<String?> Function(
    DocuTrackerRecoveryCandidate candidate,
    String remarks,
  )?
  onSubmit;

  @override
  Widget build(BuildContext context) {
    final tone = DocuTrackerTokens.toneOf(context, const Color(0xFFB45309));
    return Container(
      key: const ValueKey('docutracker-admin-recovery-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.isDark(context)
            ? DocuTrackerTokens.insetOf(context)
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.admin_panel_settings_outlined, size: 20, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Admin attention required',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This document needs a reviewer reassignment before the workflow can continue.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: DocuTrackerTokens.textSecondaryOf(context),
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 8),
            Text(
              reason!,
              key: const ValueKey('docutracker-admin-recovery-reason'),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
          ],
          if (showAction && loadOptions != null && onSubmit != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('docutracker-admin-recovery-action'),
                onPressed: () => _openDialog(context),
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('Recover Assignment'),
                style: FilledButton.styleFrom(
                  backgroundColor: DocuTrackerTokens.brand,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    final recovered = await showDialog<DocuTrackerRecoveryCandidate>(
      context: context,
      builder: (dialogContext) => DocuTrackerAdminRecoveryDialog(
        documentNumber: documentNumber,
        documentTitle: documentTitle,
        stepLabel: stepLabel,
        currentReviewer: currentReviewer,
        loadOptions: loadOptions!,
        onSubmit: onSubmit!,
      ),
    );
    if (recovered == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Assignment recovered. ${recovered.name} is now the active reviewer.',
        ),
      ),
    );
  }
}

class DocuTrackerAdminRecoveryDialog extends StatefulWidget {
  const DocuTrackerAdminRecoveryDialog({
    super.key,
    required this.documentNumber,
    required this.documentTitle,
    required this.stepLabel,
    required this.currentReviewer,
    required this.loadOptions,
    required this.onSubmit,
  });

  final String documentNumber;
  final String documentTitle;
  final String stepLabel;
  final String currentReviewer;
  final Future<DocuTrackerRecoveryOptions> Function() loadOptions;
  final Future<String?> Function(
    DocuTrackerRecoveryCandidate candidate,
    String remarks,
  )
  onSubmit;

  @override
  State<DocuTrackerAdminRecoveryDialog> createState() =>
      _DocuTrackerAdminRecoveryDialogState();
}

class _DocuTrackerAdminRecoveryDialogState
    extends State<DocuTrackerAdminRecoveryDialog> {
  final _remarks = TextEditingController();
  DocuTrackerRecoveryOptions? _options;
  String? _selectedId;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _remarks.addListener(_onRemarksChanged);
    _load();
  }

  @override
  void dispose() {
    _remarks.removeListener(_onRemarksChanged);
    _remarks.dispose();
    super.dispose();
  }

  void _onRemarksChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool keepError = false}) async {
    try {
      final options = await widget.loadOptions();
      if (!mounted) return;
      final stillListed = options.candidates.any(
        (candidate) => candidate.userId == _selectedId,
      );
      setState(() {
        _options = options;
        _loading = false;
        if (!keepError) _error = null;
        if (!stillListed) {
          _selectedId = options.candidates.length == 1
              ? options.candidates.single.userId
              : null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _selectedId = null;
        _options = DocuTrackerRecoveryOptions(
          candidates: const [],
          message: error.toString(),
        );
      });
    }
  }

  bool get _canConfirm {
    final options = _options;
    if (_loading || _submitting || options?.canSelect != true) return false;
    if (_remarks.text.trim().isEmpty) return false;
    return options!.candidates.any(
      (candidate) => candidate.userId == _selectedId,
    );
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    final options = _options!;
    DocuTrackerRecoveryCandidate? selected;
    for (final candidate in options.candidates) {
      if (candidate.userId == _selectedId) {
        selected = candidate;
        break;
      }
    }
    if (selected == null) return;
    final remarks = _remarks.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.onSubmit(selected, remarks);
    if (!mounted) return;
    if (error != null && error.isNotEmpty) {
      setState(() {
        _submitting = false;
        _error = error;
        _loading = true;
      });
      await _load(keepError: true);
      return;
    }
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return AlertDialog(
      key: const ValueKey('docutracker-admin-recovery-dialog'),
      title: const Text('Recover Assignment'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Fact(label: 'Document', value: _documentLabel()),
              _Fact(label: 'Current step', value: _stepLabel(options)),
              _Fact(label: 'Current reviewer', value: _reviewerLabel(options)),
              if ((options?.departmentName ?? '').isNotEmpty)
                _Fact(label: 'Department', value: options!.departmentName!),
              const SizedBox(height: 12),
              Text(
                'Eligible replacement reviewers',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: DocuTrackerTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else if (options == null || !options.canSelect)
                Text(
                  options?.message ?? docuTrackerNoReplacementReviewerMessage,
                  key: const ValueKey('docutracker-admin-recovery-empty'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: DocuTrackerTokens.textPrimaryOf(context),
                  ),
                )
              else
                RadioGroup<String>(
                  groupValue: _selectedId,
                  onChanged: _submitting
                      ? (_) {}
                      : (value) => setState(() => _selectedId = value),
                  child: Column(
                    children: [
                      for (final candidate in options.candidates)
                        RadioListTile<String>(
                          key: ValueKey(
                            'docutracker-recovery-candidate-${candidate.userId}',
                          ),
                          value: candidate.userId,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            candidate.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(candidate.roleLabel),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('docutracker-admin-recovery-remarks'),
                controller: _remarks,
                minLines: 2,
                maxLines: 4,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Reason for reassignment',
                  helperText: docuTrackerRecoveryRemarksRequired,
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const ValueKey('docutracker-admin-recovery-error'),
                  style: TextStyle(
                    color: DocuTrackerTokens.toneOf(
                      context,
                      const Color(0xFFB91C1C),
                    ),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('docutracker-admin-recovery-confirm'),
          onPressed: _canConfirm ? _confirm : null,
          child: Text(_submitting ? 'Recovering…' : 'Confirm'),
        ),
      ],
    );
  }

  String _documentLabel() {
    final number = widget.documentNumber.trim();
    final title = widget.documentTitle.trim();
    if (number.isEmpty) return title.isEmpty ? 'Document' : title;
    if (title.isEmpty) return number;
    return '$number · $title';
  }

  String _stepLabel(DocuTrackerRecoveryOptions? options) {
    final name = options?.stepLabel?.trim() ?? '';
    final step = options?.currentStep;
    if (name.isEmpty) return widget.stepLabel;
    if (step == null || step < 1) return name;
    return 'Step $step · $name';
  }

  String _reviewerLabel(DocuTrackerRecoveryOptions? options) {
    final name = options?.currentReviewerName?.trim() ?? '';
    if (name.isEmpty) return widget.currentReviewer;
    return name;
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textMutedOf(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DocuTrackerTokens.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
