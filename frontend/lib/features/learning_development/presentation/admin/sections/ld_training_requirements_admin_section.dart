import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/ld_training_requirements.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/admin/widgets/rsp_exam_editor_ui.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_iframe_preview.dart';

/// Admin: monitor employee pre-training and post-training requirement submissions.
class LdTrainingRequirementsAdminSection extends StatefulWidget {
  const LdTrainingRequirementsAdminSection({super.key});

  @override
  State<LdTrainingRequirementsAdminSection> createState() =>
      _LdTrainingRequirementsAdminSectionState();
}

class _LdTrainingRequirementsAdminSectionState
    extends State<LdTrainingRequirementsAdminSection> {
  List<LdTrainingRequirementRecord> _records = [];
  bool _loading = true;
  final Set<String> _savingIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _phaseFilter; // all | pre_pending | pre_ready | post_ready | complete

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LdTrainingRequirementRepo.instance.listAll();
      if (!mounted) return;
      setState(() {
        _records = list
          ..sort(
            (a, b) => (a.employeeName ?? '')
                .toLowerCase()
                .compareTo((b.employeeName ?? '').toLowerCase()),
          );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _records = [];
        _loading = false;
      });
    }
  }

  List<LdTrainingRequirementRecord> get _filtered {
    return _records.where((r) {
      if (_searchQuery.isNotEmpty) {
        final hay =
            '${r.employeeName} ${r.employeeEmail} ${r.trainingTitle ?? ''}'
                .toLowerCase();
        if (!hay.contains(_searchQuery)) return false;
      }
      switch (_phaseFilter) {
        case 'pre_pending':
          return !r.hasPreTrainingDoc;
        case 'pre_ready':
          return r.hasPreTrainingDoc && !r.preRequirementsApproved;
        case 'post_ready':
          return r.preRequirementsApproved &&
              r.hasAllPostTrainingDocs &&
              !r.postRequirementsApproved;
        case 'complete':
          return r.postRequirementsApproved;
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _setPreApproved(LdTrainingRequirementRecord r, bool approved) async {
    setState(() => _savingIds.add(r.id));
    try {
      await LdTrainingRequirementRepo.instance.setPreApproved(r.id, approved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Pre-training requirements approved.'
                : 'Pre-training approval cleared.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    } finally {
      if (mounted) setState(() => _savingIds.remove(r.id));
    }
  }

  Future<void> _setPostApproved(LdTrainingRequirementRecord r, bool approved) async {
    setState(() => _savingIds.add(r.id));
    try {
      await LdTrainingRequirementRepo.instance.setPostApproved(r.id, approved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Post-training requirements approved.'
                : 'Post-training approval cleared.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiError(e))),
      );
    } finally {
      if (mounted) setState(() => _savingIds.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final prePending =
        _records.where((r) => !r.hasPreTrainingDoc).length;
    final preReady = _records
        .where((r) => r.hasPreTrainingDoc && !r.preRequirementsApproved)
        .length;
    final postReady = _records
        .where(
          (r) =>
              r.preRequirementsApproved &&
              r.hasAllPostTrainingDocs &&
              !r.postRequirementsApproved,
        )
        .length;
    final complete = _records.where((r) => r.postRequirementsApproved).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryNavy.withValues(alpha: 0.14),
                    AppTheme.primaryNavyLight.withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: Icon(
                Icons.fact_check_outlined,
                color: AppTheme.dashIsDark(context)
                    ? AppTheme.primaryNavyLight
                    : AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Training Requirements',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.dashTextPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Monitor pre-training submissions (invitation letter for training travel, '
                    'mayor-approved) and post-training documents (LAP and training certificates).',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        if (!_loading) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _statChip('Pre: missing', prePending, Colors.orange.shade800,
                  'pre_pending'),
              _statChip('Pre: review', preReady, const Color(0xFF1565C0),
                  'pre_ready'),
              _statChip('Post: review', postReady, const Color(0xFF6A1B9A),
                  'post_ready'),
              _statChip('Complete', complete, const Color(0xFF2E7D32), 'complete'),
            ],
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search employee or training title…',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: AppTheme.dashMutedSurfaceOf(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: [
            DropdownButton<String?>(
              value: _phaseFilter,
              hint: const Text('All statuses'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All statuses')),
                DropdownMenuItem(
                  value: 'pre_pending',
                  child: Text('Pre: not submitted'),
                ),
                DropdownMenuItem(
                  value: 'pre_ready',
                  child: Text('Pre: ready for review'),
                ),
                DropdownMenuItem(
                  value: 'post_ready',
                  child: Text('Post: ready for review'),
                ),
                DropdownMenuItem(value: 'complete', child: Text('Complete')),
              ],
              onChanged: _loading ? null : (v) => setState(() => _phaseFilter = v),
            ),
            Text(
              '${filtered.length} shown',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ))
        else if (_records.isEmpty)
          _emptyBox(
            'No employee training requirement records yet. Employees create a record '
            'when they open Training Requirements in their dashboard.',
          )
        else if (filtered.isEmpty)
          _emptyBox('No records match your filters.')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) => _buildCard(filtered[i]),
          ),
      ],
    );
  }

  Widget _statChip(String label, int count, Color color, String filter) {
    final selected = _phaseFilter == filter;
    return ActionChip(
      label: Text('$count · $label'),
      backgroundColor: selected
          ? color.withValues(alpha: 0.18)
          : color.withValues(alpha: 0.08),
      onPressed: () => setState(
        () => _phaseFilter = selected ? null : filter,
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Text(text, style: TextStyle(color: AppTheme.dashTextSecondaryOf(context))),
    );
  }

  Widget _buildCard(LdTrainingRequirementRecord r) {
    final saving = _savingIds.contains(r.id);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.employeeName?.trim().isNotEmpty == true
                ? r.employeeName!.trim()
                : 'Employee',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          if (r.employeeEmail != null) ...[
            const SizedBox(height: 4),
            Text(
              r.employeeEmail!,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
          if (r.trainingTitle?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              'Training: ${r.trainingTitle!.trim()}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryNavy.withValues(alpha: 0.9),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _phaseBlock(
            title: 'Pre-training requirements',
            subtitle:
                'Invitation letter for training travel (approved by the mayor)',
            kinds: const [LdTrainingRequirementDocKind.invitationLetter],
            record: r,
            approved: r.preRequirementsApproved,
            canApprove: r.hasPreTrainingDoc && !r.preRequirementsApproved,
            onApprove: () => _setPreApproved(r, true),
            onClear: r.preRequirementsApproved
                ? () => _setPreApproved(r, false)
                : null,
            saving: saving,
          ),
          const SizedBox(height: 16),
          _phaseBlock(
            title: 'Post-training requirements',
            subtitle: 'Learning Application Plan (LAP) and Training Certificate',
            kinds: const [
              LdTrainingRequirementDocKind.lap,
              LdTrainingRequirementDocKind.trainingCertificate,
            ],
            record: r,
            approved: r.postRequirementsApproved,
            canApprove: r.preRequirementsApproved &&
                r.hasAllPostTrainingDocs &&
                !r.postRequirementsApproved,
            onApprove: () => _setPostApproved(r, true),
            onClear: r.postRequirementsApproved
                ? () => _setPostApproved(r, false)
                : null,
            saving: saving,
            locked: !r.preRequirementsApproved,
            lockedMessage: 'Approve pre-training requirements first.',
          ),
        ],
      ),
    );
  }

  Widget _phaseBlock({
    required String title,
    required String subtitle,
    required List<LdTrainingRequirementDocKind> kinds,
    required LdTrainingRequirementRecord record,
    required bool approved,
    required bool canApprove,
    required VoidCallback onApprove,
    required VoidCallback? onClear,
    required bool saving,
    bool locked = false,
    String? lockedMessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (approved)
                _badge('Approved', const Color(0xFF2E7D32))
              else if (locked)
                _badge('Locked', Colors.grey.shade700)
              else
                _badge('Pending', Colors.orange.shade800),
            ],
          ),
          if (locked && lockedMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              lockedMessage,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.dashTextSecondaryOf(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kinds
                .map((k) => _docTile(record: record, kind: k))
                .toList(),
          ),
          if (!locked && !approved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: saving || !canApprove ? null : onApprove,
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Mark approved'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryNavy,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: saving ? null : onClear,
                    child: const Text('Clear approval'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _docTile({
    required LdTrainingRequirementRecord record,
    required LdTrainingRequirementDocKind kind,
  }) {
    final path = record.docPath(kind);
    final name = record.docDisplayName(kind);
    final has = path != null && path.isNotEmpty && name != null;
    return SizedBox(
      width: 260,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.dashPanelOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.dashHairlineOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_kindLabel(kind), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (has)
              _AttachmentLink(path: path, fileName: name)
            else
              Text(
                'Not submitted',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.dashTextSecondaryOf(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return 'Invitation letter (mayor-approved)';
      case LdTrainingRequirementDocKind.lap:
        return 'Learning Application Plan (LAP)';
      case LdTrainingRequirementDocKind.trainingCertificate:
        return 'Training certificate';
    }
  }
}

class _AttachmentLink extends StatelessWidget {
  const _AttachmentLink({required this.path, required this.fileName});

  final String path;
  final String fileName;

  Future<void> _preview(BuildContext context) async {
    final url = await LdTrainingRequirementRepo.instance.getAttachmentDownloadUrl(
      path,
      fileName: fileName,
    );
    if (!context.mounted || url == null) return;
    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(fileName, overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: 720,
            height: 520,
            child: RspIframePreview(url: url),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _preview(context),
      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
      label: Text(fileName, overflow: TextOverflow.ellipsis, maxLines: 1),
      style: RspExamEditorUi.ghostAction(context),
    );
  }
}
