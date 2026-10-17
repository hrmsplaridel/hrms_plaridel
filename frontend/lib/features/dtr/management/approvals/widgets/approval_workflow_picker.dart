import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';

const approvalStepLabels = <String, String>{
  'department': 'Department Review',
  'hr': 'HR Review',
  'mayor': 'Mayor Approval',
  'manual_mayor': 'Manual Mayor Signing',
};
String approvalStepsLabel(dynamic steps) => (steps as List? ?? const [])
    .map(
      (step) => step is Map
          ? step['label']?.toString() ?? 'Review'
          : approvalStepLabels[step] ?? step.toString(),
    )
    .join(' → ');

class ApprovalWorkflowPicker extends StatefulWidget {
  const ApprovalWorkflowPicker({
    super.key,
    this.initialWorkflowId,
    this.leaveTypeId,
    this.enabled = true,
    required this.onChanged,
    this.onSaved,
  });
  final String? initialWorkflowId;
  final String? leaveTypeId;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback? onSaved;
  @override
  State<ApprovalWorkflowPicker> createState() => _ApprovalWorkflowPickerState();
}

class _ApprovalWorkflowPickerState extends State<ApprovalWorkflowPicker> {
  List<Map<String, dynamic>> _items = [];
  String? _selected, _error;
  bool _loading = true, _saving = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _selected = widget.initialWorkflowId;
    _load();
  }

  @override
  void didUpdateWidget(covariant ApprovalWorkflowPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leaveTypeId != widget.leaveTypeId ||
        (oldWidget.initialWorkflowId != widget.initialWorkflowId &&
            _selected != widget.initialWorkflowId)) {
      _selected = widget.initialWorkflowId;
      _load();
    }
  }

  Map<String, dynamic>? get _workflow =>
      _items.where((w) => w['id'] == _selected).firstOrNull;
  Map<String, dynamic> get _payload => {
    'approval_workflow_id': _selected,
    'approval_route': 'hr',
    'mayor_employment_types': null,
    'workflow_steps': _workflow?['steps'],
  };
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await ApiClient.instance.get<List<dynamic>>(
        '/api/approval-workflows',
      );
      String? selected = widget.initialWorkflowId;
      if (widget.leaveTypeId != null) {
        final settings = await ApiClient.instance.get<Map<String, dynamic>>(
          '/api/leave/routing/types/${widget.leaveTypeId}',
        );
        selected = settings.data?['approval_workflow_id'] as String?;
      }
      if (!mounted || generation != _generation) return;
      final items = (catalog.data ?? [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      final defaultWorkflow = selected == null && widget.leaveTypeId == null
          ? items
                .where(
                  (w) =>
                      w['is_active'] == true &&
                      w['employment_types'] == null &&
                      w['steps'] is List &&
                      (w['steps'] as List).length == 2 &&
                      (w['steps'] as List)[0] == 'department' &&
                      (w['steps'] as List)[1] == 'hr',
                )
                .firstOrNull
          : null;
      selected ??= defaultWorkflow?['id'] as String?;
      if (selected != null && !items.any((w) => w['id'] == selected)) {
        throw const FormatException('Selected workflow is unavailable.');
      }
      setState(() {
        _items = items;
        _selected = selected;
        _loading = false;
      });
      if (defaultWorkflow != null) widget.onChanged(_payload);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'Could not load workflow. Please retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_selected == null || _loading || _saving || !widget.enabled) return;
    final generation = _generation;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post(
        '/api/leave/routing/types/${widget.leaveTypeId}',
        data: _payload,
      );
      if (!mounted || generation != _generation) return;
      widget.onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workflow saved for future submissions.')),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _workflow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Approval workflow',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        DropdownButtonFormField<String>(
          key: ValueKey('workflow-$_selected-$_generation'),
          initialValue: selected?['id'] as String?,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Select workflow',
            hintText: 'Choose an approval workflow',
          ),
          items: _items
              .where((w) => w['is_active'] == true || w['id'] == _selected)
              .map(
                (w) => DropdownMenuItem<String>(
                  value: w['id'] as String,
                  enabled: w['is_active'] == true,
                  child: Text(
                    '${w['name']} · v${w['current_version']}${w['is_active'] == false ? ' (inactive)' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: !widget.enabled || _loading || _saving || _error != null
              ? null
              : (id) {
                  setState(() => _selected = id);
                  widget.onChanged(_payload);
                },
        ),
        const SizedBox(height: 8),
        if (selected != null) Text(approvalStepsLabel(selected['steps'])),
        if (selected?['employment_types'] != null)
          Text(
            'Applies to: ${(selected!['employment_types'] as List).join(', ')}. Other employment types: Department Review → HR Review.',
          ),
        const SizedBox(height: 8),
        const Text(
          'Manage workflows in Approvals & Signatories → Workflows. Filed requests keep their saved workflow version.',
        ),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
        if (widget.leaveTypeId != null)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed:
                  !widget.enabled ||
                      _loading ||
                      _saving ||
                      _selected == null ||
                      selected?['is_active'] != true ||
                      _error != null
                  ? null
                  : _save,
              child: Text(_saving ? 'Saving…' : 'Save workflow'),
            ),
          ),
      ],
    );
  }
}
