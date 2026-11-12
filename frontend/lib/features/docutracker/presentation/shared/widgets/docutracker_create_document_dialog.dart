import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/data/navigation/docutracker_document_navigation.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

/// Shows the DocuTracker "Create Document" flow: choose a type (with its
/// route preview), then enter details. The draft opens in the editor.
Future<void> showDocuTrackerCreateDocumentDialog(
  BuildContext context, {
  required AuthProvider auth,
  required DocuTrackerProvider provider,
  List<DocumentType>? allowedDocumentTypes,
  VoidCallback? onCreated,
}) async {
  final typeOptions = docuTrackerCreatableTypeOptions(allowedDocumentTypes);
  final size = MediaQuery.sizeOf(context);
  final isMobile = size.width < 600;

  Widget buildFlow(BuildContext _) => DocuTrackerCreateDocumentFlow(
    provider: provider,
    createdBy: auth.user?.id ?? '',
    typeOptions: typeOptions,
    isMobile: isMobile,
    onCreated: onCreated,
  );

  final DocuTrackerCreateDocumentResult? result;
  if (isMobile) {
    result = await showModalBottomSheet<DocuTrackerCreateDocumentResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: SizedBox(
            height: (size.height * 0.9).clamp(420.0, 860.0),
            child: buildFlow(ctx),
          ),
        ),
      ),
    );
  } else {
    result = await showDialog<DocuTrackerCreateDocumentResult>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: (size.width * 0.72).clamp(560.0, 820.0),
          height: (size.height * 0.8).clamp(540.0, 780.0),
          child: buildFlow(ctx),
        ),
      ),
    );
  }

  if (result == null || !context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(result.message)));
  await openDocuTrackerDocumentEditor(
    context,
    document: result.document,
    prefillNewDraft: true,
  );
}

/// Types offered in the create flow: only what the server allows. No built-in
/// types are added, so an empty list means the user cannot create anything.
List<DocumentType> docuTrackerCreatableTypeOptions(
  List<DocumentType>? allowedDocumentTypes,
) {
  final options = <DocumentType>[];
  for (final type in allowedDocumentTypes ?? const <DocumentType>[]) {
    if (!options.contains(type)) options.add(type);
  }
  return options;
}

/// Icon for a creatable document type card.
@visibleForTesting
IconData docuTrackerCreateTypeIcon(DocumentType type) {
  if (type == DocumentType.memo) return Icons.article_outlined;
  if (type == DocumentType.purchaseRequest) {
    return Icons.shopping_cart_outlined;
  }
  return Icons.description_outlined;
}

/// Short, honest description shown on type cards.
@visibleForTesting
String docuTrackerCreateTypeDescription(DocumentType type) {
  if (type == DocumentType.memo) {
    return 'Official memorandum layout with To, Subject, Date, body, and '
        'copy furnished. Print and Export PDF use this same official form.';
  }
  if (type == DocumentType.purchaseRequest) {
    return 'Editable purchase-request starter draft with line items. This is '
        'not a certified LGU PR form — complete and route it in the editor. '
        'Print and Export PDF use this same official form.';
  }
  return 'A routed document draft. When this type has a Printed form layout, '
      'you fill that form; otherwise you use the document editor. Print / '
      'Export PDF uses the admin printed form when one is saved.';
}

class DocuTrackerCreateDocumentResult {
  const DocuTrackerCreateDocumentResult({
    required this.document,
    required this.message,
  });

  final DocuTrackerDocument document;
  final String message;
}

class DocuTrackerCreateDocumentFlow extends StatefulWidget {
  const DocuTrackerCreateDocumentFlow({
    super.key,
    required this.provider,
    required this.createdBy,
    required this.typeOptions,
    this.isMobile = false,
    this.onCreated,
  });

  final DocuTrackerProvider provider;
  final String createdBy;
  final List<DocumentType> typeOptions;
  final bool isMobile;
  final VoidCallback? onCreated;

  @override
  State<DocuTrackerCreateDocumentFlow> createState() =>
      _DocuTrackerCreateDocumentFlowState();
}

class _DocuTrackerCreateDocumentFlowState
    extends State<DocuTrackerCreateDocumentFlow> {
  final _titleController = TextEditingController();
  final _purposeController = TextEditingController();
  final _titleFocus = FocusNode();

  /// Highlighted type on the picker step.
  DocumentType? _selectedType;

  /// Type confirmed for the details step (null while picking).
  DocumentType? _type;

  String? _pickedFileName;
  List<int>? _pickedFileBytes;
  String? _error;
  bool _creating = false;

  bool get _singleType => widget.typeOptions.length == 1;
  bool get _onDetails => _type != null;

  @override
  void initState() {
    super.initState();
    if (_singleType) {
      _selectedType = widget.typeOptions.single;
      _type = widget.typeOptions.single;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _purposeController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  List<WorkflowStep> _routeFor(DocumentType type) {
    DocumentRoutingConfig? config;
    for (final candidate in widget.provider.routingConfigs) {
      if (candidate.documentType == type) {
        config = candidate;
        break;
      }
    }
    final steps =
        config?.steps.where((step) => step.enabled).toList() ??
        <WorkflowStep>[];
    steps.sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    return steps;
  }

  void _goToDetails() {
    final selected = _selectedType;
    if (selected == null) return;
    setState(() {
      _type = selected;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _backToPicker() {
    setState(() {
      _type = null;
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) {
      return;
    }
    final file = result.files.single;
    setState(() {
      _pickedFileName = file.name;
      _pickedFileBytes = file.bytes;
      _error = null;
    });
  }

  Future<void> _create() async {
    if (_creating) return;
    final type = _type;
    final title = _titleController.text.trim();
    if (type == null) return;
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a document title.');
      _titleFocus.requestFocus();
      return;
    }
    final purpose = _purposeController.text.trim();
    setState(() {
      _creating = true;
      _error = null;
    });
    final provider = widget.provider;
    final created = await provider.createDocument(
      title: title,
      documentType: type,
      description: purpose.isEmpty ? null : purpose,
      createdBy: widget.createdBy,
    );
    if (!mounted) return;
    if (created == null) {
      final msg = provider.error?.trim();
      setState(() {
        _creating = false;
        _error = (msg != null && msg.isNotEmpty)
            ? docuTrackerDisplayError(msg)
            : 'Could not create document.';
      });
      return;
    }

    var message = 'Draft created. Write it in the editor, then submit.';
    final bytes = _pickedFileBytes;
    final fileName = _pickedFileName;
    if (bytes != null && fileName != null && created.id != null) {
      final uploaded = await provider.uploadAttachment(
        documentId: created.id!,
        fileBytes: bytes,
        fileName: fileName,
      );
      if (!mounted) return;
      if (uploaded == null) {
        final uploadErr = provider.error?.trim();
        final reason = (uploadErr != null && uploadErr.isNotEmpty)
            ? docuTrackerDisplayError(uploadErr)
            : 'upload failed';
        message =
            'Draft created, but the attachment was not uploaded ($reason). '
            'Attach it again from the document page.';
      } else {
        message = 'Draft created with attachment.';
      }
    }
    widget.onCreated?.call();
    Navigator.of(
      context,
    ).pop(DocuTrackerCreateDocumentResult(document: created, message: message));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: widget.isMobile ? 0 : media.viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Divider(
              height: 1,
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
            Expanded(
              child: widget.typeOptions.isEmpty
                  ? _buildNoTypes(context)
                  : _onDetails
                  ? _buildDetails(context, _type!)
                  : _buildTypePicker(context),
            ),
            Divider(
              height: 1,
              color: DocuTrackerTokens.borderSubtleOf(context),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final stepLabel = _singleType
        ? null
        : _onDetails
        ? 'Step 2 of 2'
        : 'Step 1 of 2';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stepLabel != null)
                  Text(
                    stepLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: DocuTrackerTokens.brand,
                    ),
                  ),
                if (stepLabel != null) const SizedBox(height: 4),
                Text(
                  _onDetails ? 'Draft details' : 'What are you creating?',
                  style: DocuTrackerTokens.titleStyle(
                    context,
                  ).copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  _onDetails
                      ? 'Give it a title. You write the full content in the '
                            'editor next.'
                      : 'Choose a document type to continue. Only types you '
                            'are allowed to create are listed.',
                  style: DocuTrackerTokens.metaStyle(context),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _creating ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTypes(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: DocuTrackerStyles.stateMessage(
        icon: Icons.lock_outline_rounded,
        color: DocuTrackerTokens.textMutedOf(context),
        message: 'You do not have permission to create any document type.',
      ),
    ),
  );

  Widget _buildTypePicker(BuildContext context) {
    return ListView.separated(
      key: const Key('docutracker-create-type-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      itemCount: widget.typeOptions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final type = widget.typeOptions[index];
        final selected = _selectedType == type;
        void select() => setState(() {
          _selectedType = type;
          _error = null;
        });
        void continueWithType() {
          setState(() => _selectedType = type);
          _goToDetails();
        }

        return _TypeCard(
          key: Key('docutracker-create-type-${type.value}'),
          type: type,
          route: _routeFor(type),
          selected: selected,
          onSelect: select,
          onContinue: continueWithType,
        );
      },
    );
  }

  Widget _buildDetails(BuildContext context, DocumentType type) {
    final route = _routeFor(type);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        if (_error != null) ...[
          Container(
            key: const Key('docutracker-create-error'),
            padding: const EdgeInsets.all(12),
            decoration: DocuTrackerTokens.errorBannerDecoration(context),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: DocuTrackerTokens.errorBannerIcon(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      color: DocuTrackerTokens.errorBannerForeground(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _SelectedTypeBanner(
          type: type,
          onChange: _singleType || _creating ? null : _backToPicker,
        ),
        const SizedBox(height: 8),
        Text(
          docuTrackerCreateTypeDescription(type),
          style: DocuTrackerTokens.metaStyle(context),
        ),
        const SizedBox(height: 20),
        const _FieldLabel(label: 'Document title', isRequired: true),
        const SizedBox(height: 6),
        TextField(
          key: const Key('docutracker-create-title'),
          controller: _titleController,
          focusNode: _titleFocus,
          enabled: !_creating,
          textInputAction: TextInputAction.next,
          decoration: DocuTrackerStyles.inputDecoration(
            context,
            'e.g. Office memorandum on leave guidelines',
            Icons.title_rounded,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 16),
        const _FieldLabel(label: 'Purpose', isOptional: true),
        const SizedBox(height: 6),
        TextField(
          key: const Key('docutracker-create-purpose'),
          controller: _purposeController,
          enabled: !_creating,
          maxLines: 4,
          decoration:
              DocuTrackerStyles.inputDecoration(
                context,
                'Brief purpose or opening text',
                Icons.notes_rounded,
              ).copyWith(
                helperText:
                    'Used as opening text in the editor. You can change it '
                    'there.',
                helperMaxLines: 2,
              ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel(label: 'Attachment', isOptional: true),
        const SizedBox(height: 6),
        _AttachmentPicker(
          fileName: _pickedFileName,
          enabled: !_creating,
          compact: widget.isMobile,
          onPick: _pickFile,
          onClear: () => setState(() {
            _pickedFileName = null;
            _pickedFileBytes = null;
          }),
        ),
        const SizedBox(height: 20),
        _NextStepsPanel(route: route),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final canGoBack = _onDetails && !_singleType;
    final onPicker = !_onDetails && widget.typeOptions.isNotEmpty;

    final secondary = OutlinedButton(
      key: const Key('docutracker-create-secondary'),
      onPressed: _creating
          ? null
          : canGoBack
          ? _backToPicker
          : () => Navigator.of(context).pop(),
      style: DocuTrackerStyles.outlinedButtonStyle(context),
      child: Text(canGoBack ? 'Back' : 'Cancel'),
    );

    final Widget primary;
    if (onPicker) {
      primary = FilledButton.icon(
        key: const Key('docutracker-create-continue'),
        onPressed: _selectedType == null ? null : _goToDetails,
        style: DocuTrackerStyles.primaryBrandButtonStyle(context),
        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
        label: const Text('Continue'),
      );
    } else if (_onDetails) {
      primary = FilledButton.icon(
        key: const Key('docutracker-create-submit'),
        onPressed: _creating ? null : _create,
        style: DocuTrackerStyles.primaryBrandButtonStyle(context),
        icon: _creating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.note_add_rounded, size: 19),
        label: Text(_creating ? 'Creating…' : 'Create Draft'),
      );
    } else {
      primary = const SizedBox.shrink();
    }

    return Container(
      color: DocuTrackerTokens.canvasOf(context),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      child: widget.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onPicker || _onDetails) primary,
                if (onPicker || _onDetails) const SizedBox(height: 12),
                secondary,
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                secondary,
                if (onPicker || _onDetails) ...[
                  const SizedBox(width: 16),
                  primary,
                ],
              ],
            ),
    );
  }
}

/// Plain-language name for who handles a workflow step, without exposing
/// user IDs to the submitter.
String docuTrackerCreateStepLabel(WorkflowStep step) {
  final label = step.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  if (step.assigneeSource == 'submitter_department_reviewers') {
    return 'Your department reviewer';
  }
  if (step.assigneeSource == 'department_reviewers') {
    return 'Department reviewer';
  }
  return 'Step ${step.stepOrder} reviewer';
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.label,
    this.isRequired = false,
    this.isOptional = false,
  });

  final String label;
  final bool isRequired;
  final bool isOptional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DocuTrackerTokens.textPrimaryOf(context),
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: DocuTrackerTokens.brand,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Required',
            style: DocuTrackerTokens.metaStyle(context).copyWith(
              color: DocuTrackerTokens.brand,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (isOptional) ...[
          const SizedBox(width: 8),
          Text('Optional', style: DocuTrackerTokens.metaStyle(context)),
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    super.key,
    required this.type,
    required this.route,
    required this.selected,
    required this.onSelect,
    required this.onContinue,
  });

  final DocumentType type;
  final List<WorkflowStep> route;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final signatureSteps = route.where((step) => step.requiresSignature);
    final borderColor = selected
        ? DocuTrackerTokens.brand
        : DocuTrackerTokens.borderSubtleOf(context);
    final fill = selected
        ? DocuTrackerTokens.brandSoftOf(context).withValues(alpha: 0.45)
        : DocuTrackerTokens.surfaceOf(context);

    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        side: BorderSide(color: borderColor, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // First tap selects; second tap (or Use this type / Continue) proceeds.
        onTap: () {
          if (selected) {
            onContinue();
          } else {
            onSelect();
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DocuTrackerTokens.brandSoftOf(context),
                  borderRadius: BorderRadius.circular(
                    DocuTrackerTokens.radiusSm,
                  ),
                ),
                child: Icon(
                  docuTrackerCreateTypeIcon(type),
                  color: DocuTrackerTokens.brand,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            type.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: DocuTrackerTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                          color: selected
                              ? DocuTrackerTokens.brand
                              : DocuTrackerTokens.textMutedOf(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      docuTrackerCreateTypeDescription(type),
                      style: DocuTrackerTokens.metaStyle(context),
                    ),
                    const SizedBox(height: 8),
                    if (route.isEmpty)
                      Text(
                        'No approval route published yet.',
                        style: DocuTrackerTokens.metaStyle(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      )
                    else
                      _RouteChain(route: route),
                    if (signatureSteps.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const _SignatureBadge(),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        key: Key('docutracker-create-use-${type.value}'),
                        onPressed: onContinue,
                        child: const Text('Use this type'),
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

class _RouteChain extends StatelessWidget {
  const _RouteChain({required this.route});

  final List<WorkflowStep> route;

  @override
  Widget build(BuildContext context) {
    final muted = DocuTrackerTokens.textMutedOf(context);
    final children = <Widget>[];
    for (var i = 0; i < route.length; i++) {
      if (i > 0) {
        children.add(Icon(Icons.arrow_forward_rounded, size: 14, color: muted));
      }
      children.add(
        Text(
          docuTrackerCreateStepLabel(route[i]),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: DocuTrackerTokens.textSecondaryOf(context),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _SignatureBadge extends StatelessWidget {
  const _SignatureBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.draw_outlined, size: 13, color: color),
          SizedBox(width: 4),
          Text(
            'Signatures required on route',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedTypeBanner extends StatelessWidget {
  const _SelectedTypeBanner({required this.type, this.onChange});

  final DocumentType type;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.brandSoftOf(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(
          color: DocuTrackerTokens.highlightPeachBorderOf(context),
        ),
      ),
      child: Row(
        children: [
          Icon(
            docuTrackerCreateTypeIcon(type),
            size: 20,
            color: DocuTrackerTokens.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              type.displayName,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: DocuTrackerTokens.isDark(context)
                    ? DocuTrackerTokens.brandMuted
                    : DocuTrackerTokens.brandDark,
              ),
            ),
          ),
          if (onChange != null)
            TextButton(
              key: const Key('docutracker-create-change-type'),
              onPressed: onChange,
              child: const Text('Change'),
            ),
        ],
      ),
    );
  }
}

class _AttachmentPicker extends StatelessWidget {
  const _AttachmentPicker({
    required this.fileName,
    required this.enabled,
    required this.onPick,
    required this.onClear,
    this.compact = false,
  });

  final String? fileName;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final choose = OutlinedButton.icon(
      key: const Key('docutracker-create-attach'),
      onPressed: enabled ? onPick : null,
      icon: const Icon(Icons.upload_file_rounded, size: 18),
      label: Text(fileName == null ? 'Choose file' : 'Change'),
    );

    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fileName ?? 'No file selected',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DocuTrackerTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'PDF, JPG, JPEG, or PNG — max 10 MB',
          style: DocuTrackerTokens.metaStyle(context),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      color: DocuTrackerTokens.textMutedOf(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: meta),
                    if (fileName != null)
                      IconButton(
                        tooltip: 'Remove file',
                        onPressed: enabled ? onClear : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                choose,
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.attach_file_rounded,
                  color: DocuTrackerTokens.textMutedOf(context),
                ),
                const SizedBox(width: 10),
                Expanded(child: meta),
                const SizedBox(width: 8),
                choose,
                if (fileName != null)
                  IconButton(
                    tooltip: 'Remove file',
                    onPressed: enabled ? onClear : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
    );
  }
}

class _NextStepsPanel extends StatelessWidget {
  const _NextStepsPanel({required this.route});

  final List<WorkflowStep> route;

  @override
  Widget build(BuildContext context) {
    final first = route.isEmpty ? null : route.first;
    final signatureStepCount = route
        .where((step) => step.requiresSignature)
        .length;
    final lines = <String>[
      'Creating a draft opens the editor so you can write content and place '
          'signature fields.',
      first == null
          ? 'Nothing is sent until you press Submit.'
          : 'Nothing is sent until you press Submit. It then goes to '
                'Step 1: ${docuTrackerCreateStepLabel(first)}.',
      if (signatureStepCount > 0)
        '$signatureStepCount ${signatureStepCount == 1 ? 'step requires' : 'steps require'} '
            'the reviewer to sign before approving.',
    ];
    return Container(
      key: const Key('docutracker-create-next-steps'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.canvasOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT HAPPENS NEXT',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
              color: DocuTrackerTokens.textMutedOf(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 15,
                      color: DocuTrackerTokens.brand,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 13,
                        color: DocuTrackerTokens.textSecondaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (route.length > 1) ...[
            const SizedBox(height: 4),
            _RouteChain(route: route),
          ],
        ],
      ),
    );
  }
}
