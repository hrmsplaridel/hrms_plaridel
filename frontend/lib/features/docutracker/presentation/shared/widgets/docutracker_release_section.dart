import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_release.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_document_detail_ui.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

typedef DocuTrackerReleaseOptionsLoader =
    Future<DocuTrackerReleaseOptions> Function(String documentId);

typedef DocuTrackerReleaseSubmitter =
    Future<DocuTrackerResult<DocuTrackerDocument>> Function({
      required String documentId,
      required String departmentId,
      String? remarks,
      String? idempotencyKey,
    });

/// Release stage of an approved document, shown apart from the workflow.
class DocuTrackerReleaseSection extends StatelessWidget {
  const DocuTrackerReleaseSection({
    super.key,
    required this.document,
    this.onRelease,
  });

  final DocuTrackerDocument document;

  /// Shown only when the backend allows the viewer to release now.
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    if (!document.releaseRequired) return const SizedBox.shrink();
    final released = document.isReleased;
    final muted = DocuTrackerTokens.textMutedOf(context);
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final department = document.releasedToDepartmentName?.trim();
    final releasedBy = docuTrackerReleasedByLine(document);
    final remarks = document.releaseRemarks?.trim();

    return DocuTrackerDetailSectionCard(
      key: const ValueKey('docutracker-release-section'),
      icon: released ? Icons.outbox_rounded : Icons.schedule_send_outlined,
      title: released ? 'Released' : 'Approved · Awaiting release',
      subtitle: released
          ? 'Distributed after final approval'
          : 'Final approval is complete; not yet distributed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (released) ...[
            Text(
              department == null || department.isEmpty
                  ? 'Released to department'
                  : 'Released to $department',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
            if (releasedBy != null) ...[
              const SizedBox(height: 4),
              Text(releasedBy, style: TextStyle(fontSize: 13, color: muted)),
            ],
            if (remarks != null && remarks.isNotEmpty) ...[
              const SizedBox(height: 12),
              DocuTrackerPeachDashedBox(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  remarks,
                  style: TextStyle(fontSize: 13, height: 1.4, color: primary),
                ),
              ),
            ],
          ] else ...[
            Text(
              'The receiving department cannot see this document until an '
              'authorized user releases it.',
              style: TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
            if (onRelease != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('docutracker-release-button'),
                onPressed: onRelease,
                icon: const Icon(Icons.outbox_rounded),
                label: const Text('Release Document'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Opens the release dialog. Returns the released document, or null when the
/// dialog was dismissed.
Future<DocuTrackerDocument?> showDocuTrackerReleaseDialog(
  BuildContext context, {
  required DocuTrackerDocument document,
  DocuTrackerReleaseOptionsLoader? loadOptions,
  DocuTrackerReleaseSubmitter? submit,
}) {
  final repository = DocuTrackerRepository.instance;
  return showDialog<DocuTrackerDocument>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DocuTrackerReleaseDialog(
      document: document,
      loadOptions: loadOptions ?? repository.getReleaseOptions,
      submit: submit ?? repository.releaseDocument,
    ),
  );
}

class DocuTrackerReleaseDialog extends StatefulWidget {
  const DocuTrackerReleaseDialog({
    super.key,
    required this.document,
    required this.loadOptions,
    required this.submit,
  });

  final DocuTrackerDocument document;
  final DocuTrackerReleaseOptionsLoader loadOptions;
  final DocuTrackerReleaseSubmitter submit;

  @override
  State<DocuTrackerReleaseDialog> createState() =>
      _DocuTrackerReleaseDialogState();
}

class _DocuTrackerReleaseDialogState extends State<DocuTrackerReleaseDialog> {
  final _remarksController = TextEditingController();

  /// One key per dialog, so a retried confirm cannot release twice.
  late final String _idempotencyKey =
      'release-${widget.document.id}-${DateTime.now().microsecondsSinceEpoch}'
      '-${Random().nextInt(1 << 32)}';

  DocuTrackerReleaseOptions? _options;
  String? _departmentId;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final options = await widget.loadOptions(widget.document.id!);
      if (!mounted) return;
      final suggested = options.suggestedDepartmentId;
      setState(() {
        _options = options;
        _departmentId =
            suggested != null &&
                options.departments.any((d) => d.id == suggested)
            ? suggested
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String? get _departmentName => _options?.departments
      .where((d) => d.id == _departmentId)
      .firstOrNull
      ?.name;

  Future<void> _confirm() async {
    final departmentId = _departmentId;
    if (departmentId == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.submit(
      documentId: widget.document.id!,
      departmentId: departmentId,
      remarks: _remarksController.text,
      idempotencyKey: _idempotencyKey,
    );
    if (!mounted) return;
    switch (result) {
      case DocuTrackerSuccess(:final value):
        Navigator.of(context).pop(value);
      case DocuTrackerFailure(:final message):
        setState(() {
          _error = message;
          _submitting = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final canRelease = options?.canRelease == true;
    final typeName = documentTypeFromString(
      widget.document.documentType,
    ).displayName;
    final muted = DocuTrackerTokens.textMutedOf(context);
    final departmentName = _departmentName;

    return AlertDialog(
      title: const Text('Release Document'),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.document.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  if (options != null && !canRelease)
                    Text(
                      options.released
                          ? 'This document has already been released.'
                          : 'You are not authorized to release this document.',
                      style: TextStyle(color: muted),
                    )
                  else if (options != null) ...[
                    DropdownButtonFormField<String>(
                      key: const ValueKey('docutracker-release-department'),
                      initialValue: _departmentId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Release to Department',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final department in options.departments)
                          DropdownMenuItem(
                            value: department.id,
                            child: Text(
                              department.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _departmentId = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('docutracker-release-remarks'),
                      controller: _remarksController,
                      enabled: !_submitting,
                      maxLines: 3,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Text(
                      departmentName == null
                          ? 'Choose the department that should receive this '
                                '$typeName.'
                          : 'Members of $departmentName will be able to '
                                'open it (view only). A release cannot be '
                                'changed afterwards.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const ValueKey('docutracker-release-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('docutracker-release-confirm'),
          onPressed: canRelease && _departmentId != null && !_submitting
              ? _confirm
              : null,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm Release'),
        ),
      ],
    );
  }
}
