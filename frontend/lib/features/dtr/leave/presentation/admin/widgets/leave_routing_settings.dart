import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employment_type_field.dart';

class LeaveRoutingSettings extends StatefulWidget {
  const LeaveRoutingSettings({super.key, this.leaveTypeId, this.onChanged});
  final String? leaveTypeId;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  @override
  State<LeaveRoutingSettings> createState() => _State();
}

class _State extends State<LeaveRoutingSettings> {
  String route = 'hr';
  List<String>? types;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
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
    setState(() => busy = true);
    try {
      await ApiClient.instance.post(
        '/api/leave/routing/types/${widget.leaveTypeId}',
        data: {'approval_route': route, 'mayor_employment_types': types},
      );
      if (mounted) {
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
        items: const [
          DropdownMenuItem(value: 'hr', child: Text('Department → Final HR')),
          DropdownMenuItem(value: 'mayor', child: Text('Department approval → Manual Mayor signing')),
        ],
        onChanged: busy
            ? null
            : (v) {
                setState(() {
                  route = v!;
                  types = route == 'mayor'
                      ? ['job_order', 'contract_of_service']
                      : null;
                });
                changed();
              },
      ),
      if (route == 'mayor') ...[
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            title: const Text(
              'Apply manual Mayor signing only to selected employment types',
            ),
            value: types != null,
            onChanged: busy
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
          Wrap(
            spacing: 8,
            children: employmentTypeLabels.entries
                .map(
                  (e) => FilterChip(
                    label: Text(e.value),
                    selected: types!.contains(e.key),
                    onSelected: busy
                        ? null
                        : (selected) {
                            setState(() {
                              final next = [...types!];
                              if (selected) {
                                next.add(e.key);
                              } else {
                                next.remove(e.key);
                              }
                              types = next;
                            });
                            changed();
                          },
                  ),
                )
                .toList(),
          ),
        const Text(
          'Selected types are approved in the system by the department reviewer. The Mayor signs the printed form manually. Other types keep Department Review → Final HR.',
        ),
      ],
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      if (widget.leaveTypeId != null)
        FilledButton(
          onPressed: busy ? _disabled : () => _save(),
          child: const Text('Save routing'),
        ),
      if (error != null)
        TextButton(onPressed: _load, child: const Text('Retry')),
      const SizedBox(height: 20),
    ],
  );
  VoidCallback? get _disabled => null;
}
