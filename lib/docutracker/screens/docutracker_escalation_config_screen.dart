import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';
import '../docutracker_api_result.dart';
import '../docutracker_repository.dart';
import '../docutracker_styles.dart';
import '../models/document_type.dart';
import '../models/escalation_config.dart';
import '../widgets/docutracker_error_banner.dart';
import '../widgets/docutracker_module_header.dart';
import '../widgets/docutracker_responsive_body.dart';

/// Admin UI for overdue escalation rules (per document type / department).
class DocuTrackerEscalationConfigScreen extends StatefulWidget {
  const DocuTrackerEscalationConfigScreen({super.key});

  @override
  State<DocuTrackerEscalationConfigScreen> createState() =>
      _DocuTrackerEscalationConfigScreenState();
}

class _DocuTrackerEscalationConfigScreenState
    extends State<DocuTrackerEscalationConfigScreen> {
  final _repo = DocuTrackerRepository.instance;
  List<EscalationConfig> _configs = const [];
  final Map<String, String> _departmentNameById = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final depts = await ApiClient.instance.get<List<dynamic>>(
        '/api/departments',
      );
      final map = <String, String>{};
      for (final e in depts.data ?? const []) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString();
        if (id != null && id.isNotEmpty) {
          map[id] = m['name']?.toString() ?? id;
        }
      }
      final configs = await _repo.listEscalationConfigs();
      if (!mounted) return;
      setState(() {
        _departmentNameById
          ..clear()
          ..addAll(map);
        _configs = configs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({EscalationConfig? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _EscalationConfigDialog(
        existing: existing,
        departmentNames: _departmentNameById,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DocuTrackerResponsiveBody(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DocuTrackerModuleHeader(
              title: 'Escalation rules',
              subtitle:
                  'Control automatic reassignment when deadlines are missed.',
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : () => _openEditor(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add rule'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When a review passes its deadline, the escalation worker reassigns the document '
              'using these rules. Department-specific rows take priority over global (no department).',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              DocuTrackerErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _configs.isEmpty
                  ? Center(
                      child: Text(
                        'No escalation rules yet. Add one to enable automatic escalation.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _configs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final c = _configs[i];
                        final deptLabel = c.departmentId == null
                            ? 'All departments'
                            : _departmentNameById[c.departmentId] ??
                                  c.departmentId!;
                        return Material(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              documentTypeFromString(
                                c.documentType,
                              ).displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '$deptLabel · escalate to ${c.escalationTargetRole ?? "—"}\n'
                              'After ${c.escalationDelayMinutes} min · max ${c.maxEscalationLevel} levels'
                              '${c.notifyOriginalSender ? " · notify sender" : ""}',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _openEditor(existing: c),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EscalationConfigDialog extends StatefulWidget {
  const _EscalationConfigDialog({this.existing, required this.departmentNames});

  final EscalationConfig? existing;
  final Map<String, String> departmentNames;

  @override
  State<_EscalationConfigDialog> createState() =>
      _EscalationConfigDialogState();
}

class _EscalationConfigDialogState extends State<_EscalationConfigDialog> {
  final _repo = DocuTrackerRepository.instance;
  late DocumentType _docType;
  String? _departmentId;
  late TextEditingController _targetRoleCtrl;
  late TextEditingController _delayCtrl;
  late TextEditingController _maxLevelCtrl;
  bool _notifySender = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _docType = documentTypeFromString(e?.documentType);
    _departmentId = e?.departmentId;
    _targetRoleCtrl = TextEditingController(
      text: e?.escalationTargetRole ?? 'supervisor',
    );
    _delayCtrl = TextEditingController(
      text: '${e?.escalationDelayMinutes ?? 60}',
    );
    _maxLevelCtrl = TextEditingController(
      text: '${e?.maxEscalationLevel ?? 3}',
    );
    _notifySender = e?.notifyOriginalSender ?? true;
  }

  @override
  void dispose() {
    _targetRoleCtrl.dispose();
    _delayCtrl.dispose();
    _maxLevelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = _targetRoleCtrl.text.trim();
    if (target.isEmpty) {
      setState(() => _error = 'Escalation target role is required.');
      return;
    }
    final delay = int.tryParse(_delayCtrl.text.trim()) ?? 0;
    final maxLevel = int.tryParse(_maxLevelCtrl.text.trim()) ?? 0;
    if (delay < 1 || maxLevel < 1) {
      setState(() => _error = 'Delay and max level must be at least 1.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final config = EscalationConfig(
      id: widget.existing?.id,
      documentType: _docType.value,
      departmentId: _departmentId,
      escalationTargetRole: target,
      escalationDelayMinutes: delay,
      maxEscalationLevel: maxLevel,
      notifyOriginalSender: _notifySender,
    );

    final DocuTrackerResult<EscalationConfig> result;
    if (widget.existing != null) {
      result = await _repo.updateEscalationConfig(config);
    } else {
      result = await _repo.createEscalationConfig(config);
    }

    if (!mounted) return;
    if (result is DocuTrackerSuccess<EscalationConfig>) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = result is DocuTrackerFailure<EscalationConfig>
          ? (result.message.isNotEmpty ? result.message : 'Save failed.')
          : 'Save failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final deptItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('All departments')),
      ...widget.departmentNames.entries.map(
        (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
      ),
    ];

    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add escalation rule' : 'Edit rule',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                DocuTrackerErrorBanner(message: _error!),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<DocumentType>(
                initialValue: _docType,
                decoration: DocuTrackerStyles.dropdownDecoration(
                  context,
                  'Document type',
                ),
                items: DocumentType.values
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.displayName),
                      ),
                    )
                    .toList(),
                onChanged: widget.existing != null
                    ? null
                    : (v) => v != null ? setState(() => _docType = v) : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _departmentId,
                decoration: DocuTrackerStyles.dropdownDecoration(
                  context,
                  'Department scope',
                ),
                items: deptItems,
                onChanged: (v) => setState(() => _departmentId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _targetRoleCtrl,
                decoration: DocuTrackerStyles.inputDecoration(
                  context,
                  'Escalate to role (e.g. supervisor, hr, admin)',
                  Icons.person_search_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _delayCtrl,
                keyboardType: TextInputType.number,
                decoration: DocuTrackerStyles.inputDecoration(
                  context,
                  'Delay after deadline (minutes)',
                  Icons.timer_outlined,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _maxLevelCtrl,
                keyboardType: TextInputType.number,
                decoration: DocuTrackerStyles.inputDecoration(
                  context,
                  'Max escalation levels',
                  Icons.stairs_rounded,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify original sender'),
                value: _notifySender,
                onChanged: (v) => setState(() => _notifySender = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
