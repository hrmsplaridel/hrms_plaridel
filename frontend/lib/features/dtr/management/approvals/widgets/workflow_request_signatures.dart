import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';
import 'approval_workflow_summary.dart';

/// Shows only the active reviewer's signature control. Saved applicant and
/// previous reviewer ink remains available to form preview and printing.
class WorkflowRequestSignatures extends StatefulWidget {
  const WorkflowRequestSignatures({
    super.key,
    required this.sourceTable,
    required this.requestId,
    this.canReview = false,
    this.stepLabel,
    this.showWorkflowSummary = false,
    this.initialBundle,
    this.onChanged,
  });

  final String sourceTable;
  final String requestId;
  final bool canReview;
  final String? stepLabel;
  final bool showWorkflowSummary;
  final DocuTrackerSourceSignatureBundle? initialBundle;
  final ValueChanged<DocuTrackerSourceSignatureBundle>? onChanged;

  @override
  State<WorkflowRequestSignatures> createState() =>
      _WorkflowRequestSignaturesState();
}

class _WorkflowRequestSignaturesState extends State<WorkflowRequestSignatures> {
  DocuTrackerSourceSignatureBundle? _bundle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bundle = widget.initialBundle;
    if (_bundle == null && (widget.canReview || widget.showWorkflowSummary)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    final provider = context.read<DocuTrackerProvider>();
    final bundle = await provider.loadSourceSignatures(
      sourceModule: 'dtr',
      sourceTable: widget.sourceTable,
      sourceRecordId: widget.requestId,
    );
    if (!mounted) return;
    if (bundle == null) {
      setState(
        () =>
            _error = provider.sourceSignatureError ?? 'Signatures unavailable',
      );
      return;
    }
    _accept(bundle);
  }

  void _accept(DocuTrackerSourceSignatureBundle bundle) {
    if (!mounted) return;
    setState(() => _bundle = bundle);
    widget.onChanged?.call(bundle);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canReview && !widget.showWorkflowSummary) {
      return const SizedBox.shrink();
    }
    final bundle = _bundle;
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!)),
          IconButton(
            onPressed: _load,
            tooltip: 'Retry signatures',
            icon: const Icon(Icons.refresh),
          ),
        ],
      );
    }
    if (bundle == null) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showWorkflowSummary)
          ApprovalWorkflowSummary(snapshot: bundle.workflowSnapshot),
        if (widget.canReview)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DocuTrackerSourceSignatureCard(
              key: const ValueKey('hr_approver'),
              sourceModule: 'dtr',
              sourceTable: widget.sourceTable,
              sourceRecordId: widget.requestId,
              slotKey: 'hr_approver',
              title: '${widget.stepLabel ?? 'Current reviewer'} signature',
              initialBundle: bundle,
              unsignedMessage: 'No reviewer signature yet',
              waitingMessage: 'Waiting for this step’s reviewer to sign.',
              onChanged: _accept,
            ),
          ),
      ],
    );
  }
}
