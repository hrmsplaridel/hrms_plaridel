import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/styles/docutracker_styles.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_routing_config.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_type.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/workflow_step.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_builder_screen.dart';
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
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: SizedBox(
          height: (size.height * 0.9).clamp(420.0, 860.0),
          child: buildFlow(ctx),
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
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => DocuTrackerDocumentBuilderScreen(
        document: result!.document,
        prefillNewDraft: true,
      ),
    ),
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
  DocumentType? _type;
  String? _pickedFileName;
  List<int>? _pickedFileBytes;
  String? _error;
  bool _creating = false;

  bool get _singleType => widget.typeOptions.length == 1;

  @override
  void initState() {
    super.initState();
    if (_singleType) _type = widget.typeOptions.single;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _purposeController.dispose();
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
    final type = _type;
    final title = _titleController.text.trim();
    if (type == null) return;
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a document title.');
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
    final onDetails = _type != null;
    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, onDetails),
          Divider(height: 1, color: DocuTrackerTokens.borderSubtleOf(context)),
          Expanded(
            child: widget.typeOptions.isEmpty
                ? _buildNoTypes(context)
                : onDetails
                ? _buildDetails(context, _type!)
                : _buildTypePicker(context),
          ),
          Divider(height: 1, color: DocuTrackerTokens.borderSubtleOf(context)),
          _buildFooter(context, onDetails),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool onDetails) {
    final stepLabel = _singleType
        ? null
        : onDetails
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
                const SizedBox(height: 4),
                Text(
                  onDetails ? 'Draft details' : 'What are you creating?',
                  style: DocuTrackerTokens.titleStyle(context),
                ),
                const SizedBox(height: 4),
                Text(
                  onDetails
                      ? 'Give it a title. You write the full content in the '
                            'editor next.'
                      : 'Pick a document type. Each one follows its own '
                            'approval route.',
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
      padding: const EdgeInsets.all(20),
      itemCount: widget.typeOptions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final type = widget.typeOptions[index];
        return _TypeCard(
          key: Key('docutracker-create-type-${type.value}'),
          type: type,
          route: _routeFor(type),
          onTap: () => setState(() {
            _type = type;
            _error = null;
          }),
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
          onChange: _singleType || _creating
              ? null
              : () => setState(() {
                  _type = null;
                  _error = null;
                }),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('docutracker-create-title'),
          controller: _titleController,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: DocuTrackerStyles.inputDecoration(
            context,
            'Document title',
            Icons.title_rounded,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('docutracker-create-purpose'),
          controller: _purposeController,
          maxLines: 4,
          decoration:
              DocuTrackerStyles.inputDecoration(
                context,
                'Purpose (optional)',
                Icons.notes_rounded,
              ).copyWith(
                helperText:
                    'Used as the opening text in the editor. You can change '
                    'it there.',
                helperMaxLines: 2,
              ),
        ),
        const SizedBox(height: 16),
        _AttachmentPicker(
          fileName: _pickedFileName,
          enabled: !_creating,
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

  Widget _buildFooter(BuildContext context, bool onDetails) {
    final canGoBack = onDetails && !_singleType;
    final secondary = OutlinedButton(
      onPressed: _creating
          ? null
          : canGoBack
          ? () => setState(() {
              _type = null;
              _error = null;
            })
          : () => Navigator.of(context).pop(),
      style: DocuTrackerStyles.outlinedButtonStyle(),
      child: Text(canGoBack ? 'Back' : 'Cancel'),
    );
    final primary = FilledButton.icon(
      key: const Key('docutracker-create-submit'),
      onPressed: !onDetails || _creating ? null : _create,
      style: DocuTrackerStyles.primaryButtonStyle(),
      icon: _creating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.edit_document, size: 18),
      label: const Text('Create & Open Editor'),
    );
    return Container(
      color: DocuTrackerTokens.canvasOf(context),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      child: widget.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onDetails) primary,
                if (onDetails) const SizedBox(height: 8),
                secondary,
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                secondary,
                if (onDetails) ...[const SizedBox(width: 12), primary],
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

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    super.key,
    required this.type,
    required this.route,
    required this.onTap,
  });

  final DocumentType type;
  final List<WorkflowStep> route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signatureSteps = route.where((step) => step.requiresSignature);
    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        side: BorderSide(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                child: const Icon(
                  Icons.description_outlined,
                  color: DocuTrackerTokens.brand,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: DocuTrackerTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (route.isEmpty)
                      Text(
                        'No approval route published yet.',
                        style: DocuTrackerTokens.metaStyle(context),
                      )
                    else
                      _RouteChain(route: route),
                    if (signatureSteps.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const _SignatureBadge(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: DocuTrackerTokens.textMutedOf(context),
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
        border: Border.all(color: DocuTrackerTokens.highlightPeachBorderOf(context)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 20,
            color: DocuTrackerTokens.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              type.displayName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: DocuTrackerTokens.brandDark,
              ),
            ),
          ),
          if (onChange != null)
            TextButton(onPressed: onChange, child: const Text('Change')),
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
  });

  final String? fileName;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusSm),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.attach_file_rounded,
            color: DocuTrackerTokens.textMutedOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName ?? 'Attachment (optional)',
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
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const Key('docutracker-create-attach'),
            onPressed: enabled ? onPick : null,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(fileName == null ? 'Choose file' : 'Change'),
          ),
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
      'The draft opens in the editor so you can write it and place '
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
