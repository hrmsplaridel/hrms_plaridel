import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employment_type_field.dart';

class LeaveRoutingSettings extends StatefulWidget {
  const LeaveRoutingSettings({
    super.key,
    this.leaveTypeId,
    this.onChanged,
    this.onSaved,
    this.enabled = true,
    this.allowDirectMayor = false,
    this.initialRoute = 'hr',
    this.initialEmploymentTypes,
  });
  final bool allowDirectMayor;
  final String initialRoute;
  final List<String>? initialEmploymentTypes;
  final String? leaveTypeId;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final VoidCallback? onSaved;
  final bool enabled;
  @override
  State<LeaveRoutingSettings> createState() => _State();
}

class _State extends State<LeaveRoutingSettings> {
  String route = 'hr';
  List<String>? types;
  bool busy = false;
  String? error;
  bool get _blocked => busy || !widget.enabled;
  @override
  void initState() {
    super.initState();
    route = widget.initialRoute;
    types = widget.initialEmploymentTypes;
    if (widget.leaveTypeId != null) _load();
  }

  void changed() {
    widget.onChanged?.call({
      'approval_route': route,
      'mayor_employment_types': types,
    });
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/leave/routing/types/${widget.leaveTypeId}',
      );
      if (!mounted) return;
      setState(() {
        route = r.data!['approval_route']?.toString() ?? 'hr';
        types = (r.data!['mayor_employment_types'] as List?)?.cast<String>();
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load routing. Please retry.');
      }
    }
  }

  Future<void> _save() async {
    if (_blocked) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ApiClient.instance.post(
        '/api/leave/routing/types/${widget.leaveTypeId}',
        data: {'approval_route': route, 'mayor_employment_types': types},
      );
      if (mounted) {
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Routing saved for future submissions.'),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => error =
              (e.response?.data is Map ? e.response?.data['error'] : null)
                  ?.toString() ??
              'Could not save routing.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Approval routing',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey(route),
        initialValue: route,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Approval route'),
        items: [
          const DropdownMenuItem(
            value: 'hr',
            child: Text('Department → Final HR'),
          ),
          const DropdownMenuItem(
            value: 'mayor',
            child: Text('Department approval → Manual Mayor signing'),
          ),
          if (widget.allowDirectMayor)
            const DropdownMenuItem(
              value: 'mayor_direct',
              child: Text('Direct Mayor approval'),
            ),
        ],
        onChanged: _blocked
            ? null
            : (v) {
                setState(() {
                  route = v!;
                  types = route != 'hr'
                      ? ['job_order', 'contract_of_service']
                      : null;
                });
                changed();
              },
      ),
      if (route != 'hr') ...[
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Limit to employment types'),
            value: types != null,
            onChanged: _blocked
                ? null
                : (v) {
                    setState(
                      () => types = v
                          ? ['job_order', 'contract_of_service']
                          : null,
                    );
                    changed();
                  },
          ),
        ),
        if (types != null)
          InkWell(
            onTap: _blocked ? null : _selectTypes,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Employment types',
                suffixIcon: Icon(Icons.expand_more),
              ),
              child: Text(_selectionLabel),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          route == 'mayor_direct'
              ? 'Mayor approves in the app. Department and HR review are skipped.'
              : types == null
              ? 'Department approval for all types; Mayor signs the printed form.'
              : 'Selected types: department approval and manual Mayor signing. Others: Final HR.',
        ),
      ],
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      if (widget.leaveTypeId != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _blocked ? null : () => _save(),
              child: const Text('Save routing'),
            ),
          ),
        ),
      if (error != null)
        TextButton(onPressed: _blocked ? null : _load, child: const Text('Retry')),
    ],
  );

  String get _selectionLabel => types!.isEmpty
      ? 'Select employment types'
      : '${types!.map((type) => switch (type) {
          'job_order' => 'JO',
          'contract_of_service' => 'COS',
          _ => employmentTypeLabels[type] ?? type,
        }).join(', ')} selected';

  Future<void> _selectTypes() async {
    final selected = [...types!];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Employment types'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: employmentTypeLabels.entries
                    .map(
                      (entry) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.value),
                        value: selected.contains(entry.key),
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selected.add(entry.key);
                          } else {
                            selected.remove(entry.key);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, selected),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => types = result);
      changed();
    }
  }
}
