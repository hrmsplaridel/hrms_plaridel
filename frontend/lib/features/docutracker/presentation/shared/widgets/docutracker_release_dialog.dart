import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_release.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

typedef DocuTrackerReleaseOptionsLoader =
    Future<DocuTrackerReleaseOptions> Function(String documentId);

typedef DocuTrackerReleaseSubmitter =
    Future<DocuTrackerResult<DocuTrackerDocument>> Function({
      required String documentId,
      required String departmentId,
      String? remarks,
      String? idempotencyKey,
    });

/// Optional release remarks stay within this length (matches prior dialog).
const int docuTrackerReleaseRemarksMaxLength = 2000;

const String docuTrackerReleaseInfoViewOnly =
    'Authorized members of the selected department can open this document '
    'as view-only.';

const String docuTrackerReleaseInfoIrreversible =
    'A release cannot be changed after it is confirmed.';

const String docuTrackerReleaseNoDepartmentsFound = 'No departments found';

/// Case-insensitive name filter for the release department list.
List<DocuTrackerReleaseDepartment> docuTrackerFilterReleaseDepartments(
  Iterable<DocuTrackerReleaseDepartment> departments,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List<DocuTrackerReleaseDepartment>.of(departments);
  return departments
      .where((d) => d.name.toLowerCase().contains(q))
      .toList(growable: false);
}

/// Opens the release dialog (desktop) or bottom sheet (narrow). Returns the
/// released document, or null when dismissed.
Future<DocuTrackerDocument?> showDocuTrackerReleaseDialog(
  BuildContext context, {
  required DocuTrackerDocument document,
  DocuTrackerReleaseOptionsLoader? loadOptions,
  DocuTrackerReleaseSubmitter? submit,
}) {
  final repository = DocuTrackerRepository.instance;
  final loader = loadOptions ?? repository.getReleaseOptions;
  final submitter = submit ?? repository.releaseDocument;
  final width = MediaQuery.sizeOf(context).width;
  final isMobile = width < 600;

  Widget buildDialog() => DocuTrackerReleaseDialog(
    document: document,
    loadOptions: loader,
    submit: submitter,
    compact: isMobile,
  );

  if (isMobile) {
    return showModalBottomSheet<DocuTrackerDocument>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.sizeOf(ctx).height;
        final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DocuTrackerTokens.radiusLg),
            ),
            child: ColoredBox(
              color: DocuTrackerTokens.surfaceOf(ctx),
              child: SizedBox(
                height: (height * 0.88).clamp(420.0, 720.0),
                child: buildDialog(),
              ),
            ),
          ),
        );
      },
    );
  }

  return showDialog<DocuTrackerDocument>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        backgroundColor: DocuTrackerTokens.surfaceOf(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 480,
          height: (size.height * 0.78).clamp(520.0, 680.0),
          child: buildDialog(),
        ),
      );
    },
  );
}

class DocuTrackerReleaseDialog extends StatefulWidget {
  const DocuTrackerReleaseDialog({
    super.key,
    required this.document,
    required this.loadOptions,
    required this.submit,
    this.compact = false,
  });

  final DocuTrackerDocument document;
  final DocuTrackerReleaseOptionsLoader loadOptions;
  final DocuTrackerReleaseSubmitter submit;
  final bool compact;

  @override
  State<DocuTrackerReleaseDialog> createState() =>
      _DocuTrackerReleaseDialogState();
}

class _DocuTrackerReleaseDialogState extends State<DocuTrackerReleaseDialog> {
  final _remarksController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// One key per dialog open, so a retried confirm cannot release twice.
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
    _remarksController.addListener(_onRemarksChanged);
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _remarksController.removeListener(_onRemarksChanged);
    _searchController.removeListener(_onSearchChanged);
    _remarksController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onRemarksChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
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
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String? get _departmentName {
    final id = _departmentId;
    if (id == null) return null;
    for (final department in _options?.departments ?? const []) {
      if (department.id == id) return department.name;
    }
    return null;
  }

  List<DocuTrackerReleaseDepartment> get _filteredDepartments {
    final departments = _options?.departments ?? const [];
    return docuTrackerFilterReleaseDepartments(
      departments,
      _searchController.text,
    );
  }

  bool get _canConfirm =>
      _options?.canRelease == true &&
      _departmentId != null &&
      !_submitting &&
      !_loading;

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
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final secondary = DocuTrackerTokens.textSecondaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);
    final number = widget.document.documentNumber?.trim();
    final title = widget.document.title.trim();
    final padding = widget.compact
        ? const EdgeInsets.fromLTRB(20, 12, 20, 16)
        : const EdgeInsets.fromLTRB(24, 20, 24, 20);

    return Material(
      key: const ValueKey('docutracker-release-dialog'),
      color: DocuTrackerTokens.surfaceOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.compact)
            Center(
              child: Container(
                key: const ValueKey('docutracker-release-sheet-handle'),
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.borderStrongOf(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              widget.compact ? 8 : 20,
              padding.right,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: DocuTrackerTokens.brandSoftOf(context),
                    borderRadius: BorderRadius.circular(
                      DocuTrackerTokens.radiusSm,
                    ),
                  ),
                  child: Icon(
                    Icons.outbox_rounded,
                    color: DocuTrackerTokens.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Release Document',
                        style: TextStyle(
                          fontSize: widget.compact ? 18 : 20,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        typeName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: DocuTrackerTokens.brand,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('docutracker-release-close'),
                  tooltip: 'Cancel',
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(padding.left, 12, padding.right, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DocuTrackerTokens.insetOf(context),
                borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
                border: Border.all(
                  color: DocuTrackerTokens.borderSubtleOf(context),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (number != null && number.isNotEmpty)
                    Text(
                      number,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  Text(
                    title.isEmpty ? 'Untitled document' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : SingleChildScrollView(
                    padding: padding,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (options != null && !canRelease)
                          Text(
                            options.released
                                ? 'This document has already been released.'
                                : 'You are not authorized to release this '
                                      'document.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: muted,
                            ),
                          )
                        else if (options != null) ...[
                          Text(
                            'Release to department',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _DepartmentSearchList(
                            key: const ValueKey(
                              'docutracker-release-department',
                            ),
                            departments: options.departments,
                            filtered: _filteredDepartments,
                            selectedId: _departmentId,
                            searchController: _searchController,
                            searchFocus: _searchFocus,
                            enabled: !_submitting,
                            onSelect: (id) =>
                                setState(() => _departmentId = id),
                          ),
                          const SizedBox(height: 14),
                          _ReleaseInfoCard(
                            departmentName: _departmentName,
                            typeName: typeName,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey('docutracker-release-remarks'),
                            controller: _remarksController,
                            enabled: !_submitting,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: docuTrackerReleaseRemarksMaxLength,
                            textInputAction: TextInputAction.newline,
                            decoration: DocuTrackerStyles.inputDecoration(
                              context,
                              'Remarks (optional)',
                              Icons.notes_rounded,
                            ).copyWith(
                              hintText:
                                  'Add context for the receiving department',
                              alignLabelWithHint: true,
                              counterStyle: TextStyle(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            key: const ValueKey('docutracker-release-error'),
                            padding: const EdgeInsets.all(12),
                            decoration:
                                DocuTrackerTokens.errorBannerDecoration(
                              context,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: DocuTrackerTokens.errorBannerIcon(
                                    context,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color:
                                          DocuTrackerTokens
                                              .errorBannerForeground(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_loading && options == null) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _submitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _loading = true;
                                          _error = null;
                                        });
                                        _load();
                                      },
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
          ),
          Divider(height: 1, color: DocuTrackerTokens.borderSubtleOf(context)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              12,
              padding.right,
              widget.compact ? 12 + MediaQuery.paddingOf(context).bottom : 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: DocuTrackerStyles.outlinedButtonStyle(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const ValueKey('docutracker-release-confirm'),
                    onPressed: _canConfirm ? _confirm : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.outbox_rounded, size: 18),
                    label: Text(
                      _submitting ? 'Releasing…' : 'Confirm Release',
                    ),
                    style: DocuTrackerStyles.primaryBrandButtonStyle(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseInfoCard extends StatelessWidget {
  const _ReleaseInfoCard({
    required this.departmentName,
    required this.typeName,
  });

  final String? departmentName;
  final String typeName;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final selected = departmentName?.trim();
    return Container(
      key: const ValueKey('docutracker-release-info'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.highlightPeachOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(
          color: DocuTrackerTokens.highlightPeachBorderOf(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: DocuTrackerTokens.brand,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected == null || selected.isEmpty
                      ? 'Choose the department that should receive this '
                            '$typeName.'
                      : 'Will release to $selected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            docuTrackerReleaseInfoViewOnly,
            style: TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            docuTrackerReleaseInfoIrreversible,
            style: TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
        ],
      ),
    );
  }
}

class _DepartmentSearchList extends StatelessWidget {
  const _DepartmentSearchList({
    super.key,
    required this.departments,
    required this.filtered,
    required this.selectedId,
    required this.searchController,
    required this.searchFocus,
    required this.enabled,
    required this.onSelect,
  });

  final List<DocuTrackerReleaseDepartment> departments;
  final List<DocuTrackerReleaseDepartment> filtered;
  final String? selectedId;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final border = DocuTrackerTokens.borderSubtleOf(context);
    final primary = DocuTrackerTokens.textPrimaryOf(context);
    final muted = DocuTrackerTokens.textMutedOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('docutracker-release-department-search'),
          controller: searchController,
          focusNode: searchFocus,
          enabled: enabled && departments.isNotEmpty,
          textInputAction: TextInputAction.search,
          decoration: DocuTrackerStyles.inputDecoration(
            context,
            'Search departments',
            Icons.search_rounded,
          ).copyWith(
            hintText: departments.isEmpty
                ? 'No departments available'
                : 'Type to filter departments',
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: enabled
                        ? () {
                            searchController.clear();
                            searchFocus.requestFocus();
                          }
                        : null,
                    icon: const Icon(Icons.clear_rounded, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          key: const ValueKey('docutracker-release-department-list'),
          constraints: const BoxConstraints(maxHeight: 220, minHeight: 96),
          decoration: BoxDecoration(
            color: DocuTrackerTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
            border: Border.all(color: border),
          ),
          child: departments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No departments are available for release.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ),
                )
              : filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      docuTrackerReleaseNoDepartmentsFound,
                      key: const ValueKey(
                        'docutracker-release-department-empty',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ),
                )
              : Scrollbar(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: border.withValues(alpha: 0.7),
                    ),
                    itemBuilder: (context, index) {
                      final department = filtered[index];
                      final selected = department.id == selectedId;
                      return Material(
                        color: selected
                            ? DocuTrackerTokens.brand.withValues(
                                alpha: DocuTrackerTokens.isDark(context)
                                    ? 0.22
                                    : 0.1,
                              )
                            : Colors.transparent,
                        child: ListTile(
                          key: ValueKey(
                            'docutracker-release-department-${department.id}',
                          ),
                          enabled: enabled,
                          dense: true,
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 20,
                            color: selected
                                ? DocuTrackerTokens.brand
                                : muted,
                          ),
                          title: Text(
                            department.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: primary,
                            ),
                          ),
                          onTap: enabled
                              ? () => onSelect(department.id)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
