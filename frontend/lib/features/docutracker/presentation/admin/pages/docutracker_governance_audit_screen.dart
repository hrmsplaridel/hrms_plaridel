import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_governance_audit_entry.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_module_header.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// Admin-only history of workflow and permission governance changes.
class DocuTrackerGovernanceAuditScreen extends StatefulWidget {
  const DocuTrackerGovernanceAuditScreen({super.key});

  @override
  State<DocuTrackerGovernanceAuditScreen> createState() =>
      _DocuTrackerGovernanceAuditScreenState();
}

class _DocuTrackerGovernanceAuditScreenState
    extends State<DocuTrackerGovernanceAuditScreen> {
  static const _pageSize = 50;

  final _repo = DocuTrackerRepository.instance;
  final _documentTypeController = TextEditingController();
  final _eventTypeController = TextEditingController();
  List<DocuTrackerGovernanceAuditEntry> _entries = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _documentTypeController.dispose();
    _eventTypeController.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append ? _loadingMore : _loading) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });

    try {
      final page = await _repo.listGovernanceAudit(
        documentType: _documentTypeController.text,
        eventType: _eventTypeController.text,
        limit: _pageSize,
        offset: append ? _entries.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _entries = append ? [..._entries, ...page] : page;
        _hasMore = page.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Unable to load the governance audit log. Please try again.';
      });
    }
  }

  String _titleForEvent(String eventType) =>
      eventType.replaceAll('_', ' ').replaceFirstMapped(
            RegExp(r'^.'),
            (match) => match.group(0)!.toUpperCase(),
          );

  String _formatTimestamp(BuildContext context, DateTime? timestamp) {
    if (timestamp == null) return 'Time unavailable';
    final local = timestamp.toLocal();
    final date = MaterialLocalizations.of(context).formatShortDate(local);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
    );
    return '$date, $time';
  }

  void _showDetails(DocuTrackerGovernanceAuditEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_titleForEvent(entry.eventType)),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailLine(label: 'Actor', value: entry.actorName ?? entry.actorId),
                _DetailLine(label: 'Entity', value: entry.entityType),
                if (entry.documentType != null)
                  _DetailLine(label: 'Document type', value: entry.documentType!),
                if (entry.workflowVersion != null)
                  _DetailLine(
                    label: 'Workflow version',
                    value: 'v${entry.workflowVersion}',
                  ),
                if ((entry.reason ?? '').trim().isNotEmpty)
                  _DetailLine(label: 'Reason', value: entry.reason!.trim()),
                const SizedBox(height: 12),
                _JsonState(title: 'Before', value: entry.beforeState),
                const SizedBox(height: 12),
                _JsonState(title: 'After', value: entry.afterState),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = DocuTrackerTokens.surfaceOf(context);
    final border = DocuTrackerTokens.borderSubtleOf(context);
    return Scaffold(
      body: DocuTrackerResponsiveBody(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back to permissions',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            DocuTrackerModuleHeader(
              title: 'Governance audit log',
              subtitle: 'Review confirmed workflow, assignee, and permission changes.',
              trailing: IconButton(
                tooltip: 'Refresh audit log',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: surface,
              borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 700;
                    final documentTypeField = TextField(
                      controller: _documentTypeController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Document type',
                        hintText: 'For example: memo',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                    );
                    final eventTypeField = TextField(
                      controller: _eventTypeController,
                      onSubmitted: (_) => _load(),
                      decoration: const InputDecoration(
                        labelText: 'Event type',
                        hintText: 'For example: workflow_published',
                        prefixIcon: Icon(Icons.tune_rounded),
                      ),
                    );
                    final applyButton = FilledButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.filter_alt_rounded, size: 18),
                      label: const Text('Apply filters'),
                    );
                    return narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              documentTypeField,
                              const SizedBox(height: 12),
                              eventTypeField,
                              const SizedBox(height: 12),
                              applyButton,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: documentTypeField),
                              const SizedBox(width: 12),
                              Expanded(child: eventTypeField),
                              const SizedBox(width: 12),
                              applyButton,
                            ],
                          );
                  },
                ),
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
            Expanded(child: _buildBody(surface, border)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Color surface, Color border) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          'No governance changes match these filters.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: _entries.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _entries.length) {
          return Center(
            child: OutlinedButton.icon(
              onPressed: _loadingMore ? null : () => _load(append: true),
              icon: _loadingMore
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(_loadingMore ? 'Loading...' : 'Load more'),
            ),
          );
        }
        final entry = _entries[index];
        final metadata = <String>[
          if (entry.documentType != null) entry.documentType!,
          if (entry.workflowVersion != null) 'v${entry.workflowVersion}',
          _formatTimestamp(context, entry.createdAt),
        ];
        return Material(
          color: surface,
          borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
            onTap: () => _showDetails(entry),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
              ),
              child: Row(
                children: [
                  Container(
                    height: 36,
                    width: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: DocuTrackerTokens.brandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: DocuTrackerTokens.brand,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleForEvent(entry.eventType),
                          style: DocuTrackerTokens.titleStyle(context),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entry.actorName ?? entry.actorId} | ${metadata.join(' | ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DocuTrackerTokens.metaStyle(context),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

class _JsonState extends StatelessWidget {
  const _JsonState({required this.title, required this.value});

  final String title;
  final Map<String, dynamic>? value;

  @override
  Widget build(BuildContext context) {
    final text = value == null || value!.isEmpty
        ? 'No recorded values'
        : const JsonEncoder.withIndent('  ').convert(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DocuTrackerTokens.titleStyle(context)),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.surfaceCream,
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
          ),
          child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ],
    );
  }
}
