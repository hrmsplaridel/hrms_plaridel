import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/learning_development/models/ld_training_requirements.dart';
import 'package:hrms_plaridel/features/learning_development/presentation/admin/widgets/ld_training_requirements_ui.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/shared/widgets/rsp_iframe_preview.dart';

enum _LdReqSort {
  latestSubmission,
  oldestSubmission,
  nameAsc,
  nameDesc,
}

/// Admin: monitor employee pre-training and post-training requirement submissions.
class LdTrainingRequirementsAdminSection extends StatefulWidget {
  const LdTrainingRequirementsAdminSection({super.key, this.onBackToLd});

  final VoidCallback? onBackToLd;

  @override
  State<LdTrainingRequirementsAdminSection> createState() =>
      _LdTrainingRequirementsAdminSectionState();
}

class _LdTrainingRequirementsAdminSectionState
    extends State<LdTrainingRequirementsAdminSection> {
  List<LdTrainingRequirementRecord> _records = [];
  bool _loading = true;
  final Set<String> _savingIds = {};
  final Set<String> _expandedIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _phaseFilter; // all | pre_pending | pre_ready | post_ready | complete
  _LdReqSort _sort = _LdReqSort.latestSubmission;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
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
        _records = list;
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
    final list = _records.where((r) {
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

    list.sort((a, b) {
      switch (_sort) {
        case _LdReqSort.latestSubmission:
          return b.sortSubmissionAt.compareTo(a.sortSubmissionAt);
        case _LdReqSort.oldestSubmission:
          return a.sortSubmissionAt.compareTo(b.sortSubmissionAt);
        case _LdReqSort.nameAsc:
          return (a.employeeName ?? '')
              .toLowerCase()
              .compareTo((b.employeeName ?? '').toLowerCase());
        case _LdReqSort.nameDesc:
          return (b.employeeName ?? '')
              .toLowerCase()
              .compareTo((a.employeeName ?? '').toLowerCase());
      }
    });
    return list;
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _selectFilter(String filter) {
    setState(() => _phaseFilter = _phaseFilter == filter ? null : filter);
  }

  Future<void> _setPreApproved(
    LdTrainingRequirementRecord r,
    bool approved,
  ) async {
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

  Future<void> _setPostApproved(
    LdTrainingRequirementRecord r,
    bool approved,
  ) async {
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
    final prePending = _records.where((r) => !r.hasPreTrainingDoc).length;
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
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(compact: compact),
        const SizedBox(height: 16),
        if (!_loading)
          _SummaryCardsRow(
            compact: compact,
            prePending: prePending,
            preReady: preReady,
            postReady: postReady,
            complete: complete,
            selected: _phaseFilter,
            onSelect: _selectFilter,
          ),
        if (!_loading) const SizedBox(height: 14),
        _buildToolbar(filteredCount: filtered.length, compact: compact),
        const SizedBox(height: 16),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_records.isEmpty)
          _emptyBox(
            'No employee training requirement records yet. Employees create a '
            'record when they open Training Requirements in their dashboard.',
          )
        else if (filtered.isEmpty)
          _emptyBox('No records match your filters.')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = filtered[i];
              return _EmployeeReqCard(
                record: r,
                expanded: _expandedIds.contains(r.id),
                saving: _savingIds.contains(r.id),
                onToggle: () => _toggleExpand(r.id),
                onPreApprove: () => _setPreApproved(r, true),
                onPreClear: r.preRequirementsApproved
                    ? () => _setPreApproved(r, false)
                    : null,
                onPostApprove: () => _setPostApproved(r, true),
                onPostClear: r.postRequirementsApproved
                    ? () => _setPostApproved(r, false)
                    : null,
              );
            },
          ),
      ],
    );
  }

  Widget _buildHeader({required bool compact}) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onBackToLd != null) ...[
          TextButton.icon(
            onPressed: widget.onBackToLd,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'Back to L&D',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: LdTrainingReqUi.accentOf(context),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          'Training Requirements',
          style: TextStyle(
            fontSize: compact ? 22 : 24,
            fontWeight: FontWeight.w800,
            color: LdTrainingReqUi.primaryTextOf(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Monitor pre-training and post-training document submissions.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: LdTrainingReqUi.secondaryTextOf(context),
          ),
        ),
      ],
    );

    final refresh = FilledButton.icon(
      onPressed: _loading ? null : _load,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Refresh'),
      style: FilledButton.styleFrom(
        backgroundColor: LdTrainingReqUi.accentOf(context),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: refresh),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        refresh,
      ],
    );
  }

  Widget _buildToolbar({
    required int filteredCount,
    required bool compact,
  }) {
    final search = TextField(
      controller: _searchController,
      decoration: LdTrainingReqUi.searchDecoration(context),
    );

    final status = InputDecorator(
      decoration: InputDecoration(
        labelText: 'Status',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: AppTheme.dashMutedSurfaceOf(context),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _phaseFilter,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: null, child: Text('All statuses')),
            DropdownMenuItem(
              value: 'pre_pending',
              child: Text('Pre-training missing'),
            ),
            DropdownMenuItem(
              value: 'pre_ready',
              child: Text('Pre-training review'),
            ),
            DropdownMenuItem(
              value: 'post_ready',
              child: Text('Post-training review'),
            ),
            DropdownMenuItem(value: 'complete', child: Text('Completed')),
          ],
          onChanged: _loading ? null : (v) => setState(() => _phaseFilter = v),
        ),
      ),
    );

    final sort = InputDecorator(
      decoration: InputDecoration(
        labelText: 'Sort',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: AppTheme.dashMutedSurfaceOf(context),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_LdReqSort>(
          value: _sort,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: _LdReqSort.latestSubmission,
              child: Text('Latest submission'),
            ),
            DropdownMenuItem(
              value: _LdReqSort.oldestSubmission,
              child: Text('Oldest submission'),
            ),
            DropdownMenuItem(
              value: _LdReqSort.nameAsc,
              child: Text('Employee name (A–Z)'),
            ),
            DropdownMenuItem(
              value: _LdReqSort.nameDesc,
              child: Text('Employee name (Z–A)'),
            ),
          ],
          onChanged: _loading
              ? null
              : (v) {
                  if (v != null) setState(() => _sort = v);
                },
        ),
      ),
    );

    final count = Text(
      '$filteredCount shown',
      style: TextStyle(
        color: LdTrainingReqUi.secondaryTextOf(context),
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: LdTrainingReqUi.toolbarDecoration(context),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                status,
                const SizedBox(height: 10),
                sort,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: count),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: status),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: sort),
                const SizedBox(width: 12),
                count,
              ],
            ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: LdTrainingReqUi.cardDecoration(context),
      child: Text(
        text,
        style: TextStyle(color: LdTrainingReqUi.secondaryTextOf(context)),
      ),
    );
  }
}

class _SummaryCardsRow extends StatelessWidget {
  const _SummaryCardsRow({
    required this.compact,
    required this.prePending,
    required this.preReady,
    required this.postReady,
    required this.complete,
    required this.selected,
    required this.onSelect,
  });

  final bool compact;
  final int prePending;
  final int preReady;
  final int postReady;
  final int complete;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCard(
        label: 'Pre-training Missing',
        count: prePending,
        icon: Icons.warning_amber_rounded,
        color: LdTrainingReqUi.orange,
        selected: selected == 'pre_pending',
        onTap: () => onSelect('pre_pending'),
      ),
      _SummaryCard(
        label: 'Pre-training Review',
        count: preReady,
        icon: Icons.rate_review_outlined,
        color: LdTrainingReqUi.reviewBlue,
        selected: selected == 'pre_ready',
        onTap: () => onSelect('pre_ready'),
      ),
      _SummaryCard(
        label: 'Post-training Review',
        count: postReady,
        icon: Icons.assignment_turned_in_outlined,
        color: const Color(0xFF7C3AED),
        selected: selected == 'post_ready',
        onTap: () => onSelect('post_ready'),
      ),
      _SummaryCard(
        label: 'Completed',
        count: complete,
        icon: Icons.check_circle_outline_rounded,
        color: LdTrainingReqUi.success,
        selected: selected == 'complete',
        onTap: () => onSelect('complete'),
      ),
    ];

    if (!compact) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 420;
        if (!twoCol) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                cards[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 8),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 8),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: selected ? 0.55 : 0.22),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: LdTrainingReqUi.primaryTextOf(context),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeReqCard extends StatelessWidget {
  const _EmployeeReqCard({
    required this.record,
    required this.expanded,
    required this.saving,
    required this.onToggle,
    required this.onPreApprove,
    required this.onPreClear,
    required this.onPostApprove,
    required this.onPostClear,
  });

  final LdTrainingRequirementRecord record;
  final bool expanded;
  final bool saving;
  final VoidCallback onToggle;
  final VoidCallback onPreApprove;
  final VoidCallback? onPreClear;
  final VoidCallback onPostApprove;
  final VoidCallback? onPostClear;

  @override
  Widget build(BuildContext context) {
    final name = record.employeeName?.trim().isNotEmpty == true
        ? record.employeeName!.trim()
        : 'Employee';
    final preStatus = _preStatus(record);
    final postStatus = _postStatus(record);
    final submitted = LdTrainingReqUi.formatShortDate(record.sortSubmissionAt);
    final narrow = MediaQuery.sizeOf(context).width < 720;

    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor:
              LdTrainingReqUi.accentOf(context).withValues(alpha: 0.12),
          child: Text(
            LdTrainingReqUi.initials(name),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: LdTrainingReqUi.accentOf(context),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: LdTrainingReqUi.primaryTextOf(context),
                ),
              ),
              if (record.employeeEmail != null) ...[
                const SizedBox(height: 2),
                Text(
                  record.employeeEmail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: LdTrainingReqUi.secondaryTextOf(context),
                  ),
                ),
              ],
              if (record.trainingTitle?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 3),
                Text(
                  record.trainingTitle!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: LdTrainingReqUi.accentOf(
                      context,
                    ).withValues(alpha: 0.95),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final badges = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StatusBadge(label: 'Pre: ${preStatus.label}', color: preStatus.color),
        _StatusBadge(
          label: 'Post: ${postStatus.label}',
          color: postStatus.color,
        ),
        Text(
          submitted,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: LdTrainingReqUi.secondaryTextOf(context),
          ),
        ),
      ],
    );

    return Container(
      decoration: LdTrainingReqUi.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: identity),
                              Icon(
                                expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: LdTrainingReqUi.secondaryTextOf(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          badges,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 3, child: identity),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: badges),
                          const SizedBox(width: 4),
                          Icon(
                            expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: LdTrainingReqUi.secondaryTextOf(context),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _ExpandedDetails(
              record: record,
              saving: saving,
              onPreApprove: onPreApprove,
              onPreClear: onPreClear,
              onPostApprove: onPostApprove,
              onPostClear: onPostClear,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  static ({String label, Color color}) _preStatus(
    LdTrainingRequirementRecord r,
  ) {
    if (r.preRequirementsApproved) {
      return (label: 'Approved', color: LdTrainingReqUi.success);
    }
    if (r.hasPreTrainingDoc) {
      return (label: 'Review', color: LdTrainingReqUi.reviewBlue);
    }
    return (label: 'Missing', color: LdTrainingReqUi.orange);
  }

  static ({String label, Color color}) _postStatus(
    LdTrainingRequirementRecord r,
  ) {
    if (r.postRequirementsApproved) {
      return (label: 'Approved', color: LdTrainingReqUi.success);
    }
    if (!r.preRequirementsApproved) {
      return (label: 'Locked', color: LdTrainingReqUi.lockedGray);
    }
    if (r.hasAllPostTrainingDocs) {
      return (label: 'Review', color: LdTrainingReqUi.reviewBlue);
    }
    return (label: 'Pending', color: LdTrainingReqUi.orange);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
}

class _ExpandedDetails extends StatelessWidget {
  const _ExpandedDetails({
    required this.record,
    required this.saving,
    required this.onPreApprove,
    required this.onPreClear,
    required this.onPostApprove,
    required this.onPostClear,
  });

  final LdTrainingRequirementRecord record;
  final bool saving;
  final VoidCallback onPreApprove;
  final VoidCallback? onPreClear;
  final VoidCallback onPostApprove;
  final VoidCallback? onPostClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: LdTrainingReqUi.hairlineOf(context)),
        ),
        color: AppTheme.dashMutedSurfaceOf(context).withValues(alpha: 0.45),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhaseSection(
            title: 'Pre-training requirements',
            subtitle:
                'Invitation letter (mayor-approved) and Travel Order for training travel',
            kinds: const [
              LdTrainingRequirementDocKind.invitationLetter,
              LdTrainingRequirementDocKind.travelOrder,
            ],
            record: record,
            approved: record.preRequirementsApproved,
            canApprove:
                record.hasPreTrainingDoc && !record.preRequirementsApproved,
            onApprove: onPreApprove,
            onClear: onPreClear,
            saving: saving,
          ),
          const SizedBox(height: 12),
          _PhaseSection(
            title: 'Post-training requirements',
            subtitle:
                'Learning Application Plan (LAP) and Training Certificate',
            kinds: const [
              LdTrainingRequirementDocKind.lap,
              LdTrainingRequirementDocKind.trainingCertificate,
            ],
            record: record,
            approved: record.postRequirementsApproved,
            canApprove: record.preRequirementsApproved &&
                record.hasAllPostTrainingDocs &&
                !record.postRequirementsApproved,
            onApprove: onPostApprove,
            onClear: onPostClear,
            saving: saving,
            locked: !record.preRequirementsApproved,
            lockedMessage: 'Approve pre-training requirements first.',
          ),
        ],
      ),
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({
    required this.title,
    required this.subtitle,
    required this.kinds,
    required this.record,
    required this.approved,
    required this.canApprove,
    required this.onApprove,
    required this.onClear,
    required this.saving,
    this.locked = false,
    this.lockedMessage,
  });

  final String title;
  final String subtitle;
  final List<LdTrainingRequirementDocKind> kinds;
  final LdTrainingRequirementRecord record;
  final bool approved;
  final bool canApprove;
  final VoidCallback onApprove;
  final VoidCallback? onClear;
  final bool saving;
  final bool locked;
  final String? lockedMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LdTrainingReqUi.panelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LdTrainingReqUi.hairlineOf(context)),
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
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: LdTrainingReqUi.primaryTextOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: LdTrainingReqUi.secondaryTextOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (approved)
                _StatusBadge(label: 'Approved', color: LdTrainingReqUi.success)
              else if (locked)
                _StatusBadge(
                  label: 'Locked',
                  color: LdTrainingReqUi.lockedGray,
                )
              else
                _StatusBadge(label: 'Pending', color: LdTrainingReqUi.orange),
            ],
          ),
          if (locked && lockedMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              lockedMessage!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: LdTrainingReqUi.secondaryTextOf(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final sideBySide = c.maxWidth >= 560;
              final tiles = kinds
                  .map(
                    (k) => _DocCard(record: record, kind: k, locked: locked),
                  )
                  .toList();
              if (!sideBySide) {
                return Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      tiles[i],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: tiles[i]),
                  ],
                ],
              );
            },
          ),
          if (!locked && !approved) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: saving || !canApprove ? null : onApprove,
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Mark approved'),
                  style: FilledButton.styleFrom(
                    backgroundColor: LdTrainingReqUi.accentOf(context),
                    foregroundColor: Colors.white,
                  ),
                ),
                if (onClear != null)
                  TextButton(
                    onPressed: saving ? null : onClear,
                    child: const Text('Clear approval'),
                  ),
              ],
            ),
          ],
          if (approved && onClear != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: saving ? null : onClear,
              child: const Text('Clear approval'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.record,
    required this.kind,
    required this.locked,
  });

  final LdTrainingRequirementRecord record;
  final LdTrainingRequirementDocKind kind;
  final bool locked;

  static String _label(LdTrainingRequirementDocKind kind) {
    switch (kind) {
      case LdTrainingRequirementDocKind.invitationLetter:
        return 'Invitation letter (mayor-approved)';
      case LdTrainingRequirementDocKind.travelOrder:
        return 'Travel Order';
      case LdTrainingRequirementDocKind.lap:
        return 'Learning Application Plan (LAP)';
      case LdTrainingRequirementDocKind.trainingCertificate:
        return 'Training certificate';
    }
  }

  static IconData _icon(LdTrainingRequirementDocKind kind) {
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

  @override
  Widget build(BuildContext context) {
    final path = record.docPath(kind);
    final name = record.docDisplayName(kind);
    final has = path != null && path.isNotEmpty && name != null && name.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashMutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LdTrainingReqUi.hairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _icon(kind),
                size: 18,
                color: locked
                    ? LdTrainingReqUi.lockedGray
                    : LdTrainingReqUi.accentOf(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label(kind),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: LdTrainingReqUi.primaryTextOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (has) ...[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: LdTrainingReqUi.secondaryTextOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Submitted',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: LdTrainingReqUi.success,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _preview(context, path, name),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Preview'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: LdTrainingReqUi.accentOf(context),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _download(context, path, name),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Download'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: LdTrainingReqUi.accentOf(context),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              locked ? 'Unavailable' : 'Not submitted',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: locked
                    ? LdTrainingReqUi.lockedGray
                    : LdTrainingReqUi.orange,
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _url(String path, String fileName) {
    return LdTrainingRequirementRepo.instance.getAttachmentDownloadUrl(
      path,
      fileName: fileName,
    );
  }

  Future<void> _preview(
    BuildContext context,
    String path,
    String fileName,
  ) async {
    final url = await _url(path, fileName);
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

  Future<void> _download(
    BuildContext context,
    String path,
    String fileName,
  ) async {
    final url = await _url(path, fileName);
    if (!context.mounted || url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
