import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_history.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_history_presentation.dart';

typedef DocuTrackerHistoryPageLoader =
    Future<DocumentHistoryPage> Function({
      required int limit,
      required int offset,
      String? action,
    });

/// Latest events on the document page. The full list stays off this page.
class DocuTrackerActivityPreview extends StatefulWidget {
  const DocuTrackerActivityPreview({
    super.key,
    required this.entries,
    required this.onViewAll,
  });

  final List<DocumentHistoryEntry> entries;
  final VoidCallback onViewAll;

  @override
  State<DocuTrackerActivityPreview> createState() =>
      _DocuTrackerActivityPreviewState();
}

class _DocuTrackerActivityPreviewState
    extends State<DocuTrackerActivityPreview> {
  final Set<String> _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final newest = docuTrackerHistoryNewestFirst(widget.entries);
    final preview = newest.take(docuTrackerActivityPreviewCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < preview.length; i++)
          DocuTrackerActivityRow(
            entry: preview[i],
            rowKey: docuTrackerHistoryRowKey(preview[i], i),
            expanded: _expanded.contains(
              docuTrackerHistoryRowKey(preview[i], i),
            ),
            showConnector: i < preview.length - 1,
            onToggle: () {
              final key = docuTrackerHistoryRowKey(preview[i], i);
              setState(() {
                if (!_expanded.add(key)) _expanded.remove(key);
              });
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('docutracker-activity-view-all'),
            onPressed: widget.onViewAll,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('View all activities'),
          ),
        ),
      ],
    );
  }
}

class DocuTrackerActivityRow extends StatelessWidget {
  const DocuTrackerActivityRow({
    super.key,
    required this.entry,
    required this.rowKey,
    required this.expanded,
    required this.onToggle,
    this.showConnector = false,
  });

  final DocumentHistoryEntry entry;
  final String rowKey;
  final bool expanded;
  final VoidCallback onToggle;
  final bool showConnector;

  @override
  Widget build(BuildContext context) {
    final title = docuTrackerHistoryTitle(entry);
    final actor = docuTrackerHistoryActorName(entry);
    final time = entry.createdAt == null
        ? null
        : docuTrackerHistoryTimestamp(entry.createdAt!);
    final meta = [if (actor != null) actor, if (time != null) time].join(' · ');
    final iconColor = DocuTrackerTokens.toneOf(
      context,
      DocuTrackerTokens.brand,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: expanded
              ? 'Hide details for $title'
              : 'Show details for $title',
          child: InkWell(
            key: Key('docutracker-activity-row-$rowKey'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      docuTrackerHistoryIcon(entry),
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: DocuTrackerTokens.textPrimaryOf(context),
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: DocuTrackerTokens.textMutedOf(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: DocuTrackerTokens.textMutedOf(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 6),
            child: DocuTrackerActivityDetails(
              key: Key('docutracker-activity-details-$rowKey'),
              entry: entry,
            ),
          )
        else if (showConnector)
          const SizedBox(height: 2),
      ],
    );
  }
}

class DocuTrackerActivityDetails extends StatelessWidget {
  const DocuTrackerActivityDetails({super.key, required this.entry});

  final DocumentHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textSecondaryOf(context);
    final lines = <String>[
      if (docuTrackerHistoryStatusTransition(entry) case final status?)
        'Status: $status',
      if (docuTrackerHistoryStepLine(entry) case final step?) step,
      if (entry.remarks?.trim().isNotEmpty == true) entry.remarks!.trim(),
      if (entry.action?.trim().isNotEmpty == true)
        'Recorded action: ${entry.action}',
      if (docuTrackerHistoryActorName(entry) == null &&
          (entry.actorId?.trim().isNotEmpty ?? false))
        'Actor id: ${entry.actorId!.trim()}',
      for (final item in _metadataLines(entry)) item,
    ];
    if (lines.isEmpty) {
      return Text(
        'No additional details were recorded.',
        style: TextStyle(fontSize: 12, color: muted),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DocuTrackerTokens.insetOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  line,
                  style: TextStyle(fontSize: 12, height: 1.35, color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _metadataLines(DocumentHistoryEntry entry) {
    final lines = <String>[];
    for (final mapEntry in entry.metadata.entries) {
      final value = mapEntry.value;
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text == '{}' || text == '[]') continue;
      lines.add('${mapEntry.key}: $text');
    }
    return lines;
  }
}

/// Full history in the slide-in panel. Remote pages come from [loadPage].
/// [localEntries] is for history that is not stored on the DocuTracker API.
class DocuTrackerActivityHistoryPanel extends StatefulWidget {
  const DocuTrackerActivityHistoryPanel({
    super.key,
    this.loadPage,
    this.localEntries = const [],
  });

  final DocuTrackerHistoryPageLoader? loadPage;
  final List<DocumentHistoryEntry> localEntries;

  @override
  State<DocuTrackerActivityHistoryPanel> createState() =>
      _DocuTrackerActivityHistoryPanelState();
}

class _DocuTrackerActivityHistoryPanelState
    extends State<DocuTrackerActivityHistoryPanel> {
  String? _action;
  int _offset = 0;
  bool _loading = false;
  String? _error;
  List<DocumentHistoryEntry> _items = const [];
  int _total = 0;
  final Set<String> _expanded = <String>{};

  bool get _remote => widget.loadPage != null;

  @override
  void initState() {
    super.initState();
    if (_remote) {
      _loading = true;
      _reload(markLoading: false);
    } else {
      _applyLocal();
    }
  }

  void _applyLocal() {
    final filtered = docuTrackerHistoryNewestFirst(
      widget.localEntries,
    ).where((entry) => _action == null || entry.action == _action).toList();
    final page = filtered.skip(_offset).take(docuTrackerActivityPageSize);
    _items = page.toList(growable: false);
    _total = filtered.length;
    _error = null;
    _loading = false;
  }

  Future<void> _reload({bool markLoading = true}) async {
    if (!_remote) {
      setState(_applyLocal);
      return;
    }
    if (markLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.loadPage!(
        limit: docuTrackerActivityPageSize,
        offset: _offset,
        action: _action,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('DocuTracker activity history failed to load: $error');
      setState(() {
        _loading = false;
        _error = _readableHistoryError(error);
      });
    }
  }

  void _changeFilter(String? action) {
    setState(() {
      _action = action;
      _offset = 0;
      _expanded.clear();
    });
    _reload();
  }

  void _changePage(int nextOffset) {
    setState(() {
      _offset = nextOffset;
      _expanded.clear();
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final start = _total == 0 ? 0 : _offset + 1;
    final end = _offset + _items.length;
    final canPrevious = _offset > 0 && !_loading;
    final canNext = _offset + docuTrackerActivityPageSize < _total && !_loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<String?>(
            key: Key('docutracker-activity-filter-${_action ?? 'all'}'),
            initialValue: _action,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Event type',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
              ),
            ),
            items: [
              for (final filter in docuTrackerHistoryFilters)
                DropdownMenuItem<String?>(
                  value: filter.action,
                  child: Text(filter.label),
                ),
            ],
            onChanged: _loading ? null : _changeFilter,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _PanelMessage(
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _reload,
                )
              : _items.isEmpty
              ? _PanelMessage(
                  message: _action == null
                      ? 'No history yet.'
                      : 'No activity matches this filter.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: DocuTrackerTokens.borderSubtleOf(context),
                  ),
                  itemBuilder: (context, index) {
                    final entry = _items[index];
                    final key = docuTrackerHistoryRowKey(
                      entry,
                      _offset + index,
                    );
                    return DocuTrackerActivityRow(
                      entry: entry,
                      rowKey: key,
                      expanded: _expanded.contains(key),
                      onToggle: () {
                        setState(() {
                          if (!_expanded.add(key)) _expanded.remove(key);
                        });
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              TextButton(
                key: const Key('docutracker-activity-previous'),
                onPressed: canPrevious
                    ? () => _changePage(_offset - docuTrackerActivityPageSize)
                    : null,
                child: const Text('Previous'),
              ),
              Expanded(
                child: Text(
                  _total == 0 ? '0 events' : '$start–$end of $_total',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: DocuTrackerTokens.textMutedOf(context),
                  ),
                ),
              ),
              TextButton(
                key: const Key('docutracker-activity-next'),
                onPressed: canNext
                    ? () => _changePage(_offset + docuTrackerActivityPageSize)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _readableHistoryError(Object error) {
  final message = error
      .toString()
      .replaceFirst(RegExp(r'^(?:[A-Za-z]+Exception|TypeError):\s*'), '')
      .trim();
  if (message.isEmpty ||
      message.contains('DioException') ||
      message.contains('TypeError') ||
      message.contains('is not a subtype') ||
      message.contains('JSArray') ||
      message.contains('RequestOptions') ||
      message.contains('took longer than')) {
    return 'Activity history could not be loaded.';
  }
  return message;
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DocuTrackerTokens.textSecondaryOf(context),
                fontSize: 14,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Collapsed until the reviewer chooses to write. Posting still uses
/// the caller's authorization and audit path.
class DocuTrackerInternalNoteComposer extends StatefulWidget {
  const DocuTrackerInternalNoteComposer({
    super.key,
    required this.controller,
    required this.busy,
    required this.onPost,
  });

  final TextEditingController controller;
  final bool busy;
  final Future<bool> Function() onPost;

  @override
  State<DocuTrackerInternalNoteComposer> createState() =>
      _DocuTrackerInternalNoteComposerState();
}

class _DocuTrackerInternalNoteComposerState
    extends State<DocuTrackerInternalNoteComposer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('docutracker-detail-add-note'),
          onPressed: widget.busy ? null : () => setState(() => _open = true),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text('Add internal note'),
        ),
      );
    }

    return Container(
      key: const Key('docutracker-detail-note-composer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.canvasOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ADD INTERNAL NOTE FOR REVIEWERS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DocuTrackerTokens.textMutedOf(context),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.controller,
            enabled: !widget.busy,
            minLines: 2,
            maxLines: 4,
            decoration: DocuTrackerStyles.inputDecoration(
              context,
              'Write a note (logged to the audit trail)',
              Icons.edit_note_rounded,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('docutracker-detail-cancel-note'),
                onPressed: widget.busy
                    ? null
                    : () {
                        widget.controller.clear();
                        setState(() => _open = false);
                      },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('docutracker-detail-post-note'),
                onPressed: widget.busy
                    ? null
                    : () async {
                        final ok = await widget.onPost();
                        if (ok && mounted) setState(() => _open = false);
                      },
                style: DocuTrackerStyles.primaryButtonStyle(),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Post Note'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
