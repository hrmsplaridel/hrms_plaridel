import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';
import 'package:hrms_plaridel/features/docutracker/services/employee_directory_lookup.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

class DocuTrackerSourceSignatureCard extends StatefulWidget {
  const DocuTrackerSourceSignatureCard({
    super.key,
    required this.sourceModule,
    required this.sourceTable,
    required this.sourceRecordId,
    this.slotKey = 'applicant',
    this.title = 'Applicant E-Signature',
    this.unsignedMessage = 'No applicant signature yet',
    this.waitingMessage = 'Waiting for the applicant to sign.',
    this.savedMessage = 'Signature saved.',
    this.onChanged,
  });

  final String sourceModule;
  final String sourceTable;
  final String sourceRecordId;
  final String slotKey;
  final String title;
  final String unsignedMessage;
  final String waitingMessage;
  final String savedMessage;
  final ValueChanged<DocuTrackerSourceSignatureBundle>? onChanged;

  @override
  State<DocuTrackerSourceSignatureCard> createState() =>
      _DocuTrackerSourceSignatureCardState();
}

class _DocuTrackerSourceSignatureCardState
    extends State<DocuTrackerSourceSignatureCard> {
  DocuTrackerSourceSignatureBundle? _bundle;
  bool _loading = true;
  bool _signing = false;
  bool _assigning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final provider = context.read<DocuTrackerProvider>();
    final bundle = await provider.loadSourceSignatures(
      sourceModule: widget.sourceModule,
      sourceTable: widget.sourceTable,
      sourceRecordId: widget.sourceRecordId,
    );
    if (!mounted) return;
    setState(() {
      _bundle = bundle;
      _error = bundle == null
          ? provider.sourceSignatureError ??
                'The signature could not be loaded.'
          : null;
      _loading = false;
    });
    if (bundle != null) widget.onChanged?.call(bundle);
  }

  Future<void> _assignSigner() async {
    final directory = EmployeeDirectoryLookup();
    await directory.load();
    if (!mounted) return;
    var query = '';
    final signerId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          final matches = directory.entries
              .where((employee) {
                final needle = query.trim().toLowerCase();
                if (needle.isEmpty) return true;
                return [
                  employee.fullName,
                  employee.departmentName,
                  employee.positionName,
                ].whereType<String>().any(
                  (value) => value.toLowerCase().contains(needle),
                );
              })
              .take(15)
              .toList(growable: false);
          return AlertDialog(
            title: Text('Assign ${widget.title}'),
            content: SizedBox(
              width: 480,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Search employee',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => updateDialog(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('No active employee found.'))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final employee = matches[index];
                              final details =
                                  [
                                        employee.departmentName,
                                        employee.positionName,
                                      ]
                                      .whereType<String>()
                                      .where((value) => value.trim().isNotEmpty)
                                      .join(' | ');
                              return ListTile(
                                title: Text(employee.fullName),
                                subtitle: details.isEmpty
                                    ? null
                                    : Text(details),
                                trailing:
                                    employee.id ==
                                        _bundle
                                            ?.signatureFor(widget.slotKey)
                                            ?.assignedSignerId
                                    ? const Icon(Icons.check_rounded)
                                    : null,
                                onTap: () =>
                                    Navigator.pop(dialogContext, employee.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || signerId == null) return;

    final current = _bundle?.signatureFor(widget.slotKey);
    final needsRecoveryRemarks =
        current != null &&
        current.assignedSignerId.trim().isNotEmpty &&
        current.assignedSignerId != signerId &&
        (current.assignmentSource == 'creator' ||
            current.assignmentSource == 'automatic');

    String? recoveryRemarks;
    if (needsRecoveryRemarks) {
      recoveryRemarks = await _promptRecoveryRemarks(
        current.assignmentSource == 'creator'
            ? 'This field belongs to the form creator. Enter recovery remarks to reassign it.'
            : 'This signer was assigned automatically. Enter recovery remarks to override it.',
      );
      if (!mounted || recoveryRemarks == null) return;
    }

    setState(() {
      _assigning = true;
      _error = null;
    });
    final provider = context.read<DocuTrackerProvider>();
    final bundle = await provider.assignSourceSignature(
      sourceModule: widget.sourceModule,
      sourceTable: widget.sourceTable,
      sourceRecordId: widget.sourceRecordId,
      slotKey: widget.slotKey,
      assignedSignerId: signerId,
      recoveryRemarks: recoveryRemarks,
    );
    if (!mounted) return;
    setState(() {
      _assigning = false;
      if (bundle != null) {
        _bundle = bundle;
      } else {
        _error =
            provider.sourceSignatureError ?? 'The signer was not assigned.';
      }
    });
    if (bundle != null) widget.onChanged?.call(bundle);
  }

  Future<String?> _promptRecoveryRemarks(String message) async {
    final controller = TextEditingController();
    final remarks = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Recovery remarks required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Remarks (min 5 characters)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 5) return;
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Reassign'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return remarks;
  }

  Future<void> _sign() async {
    final provider = context.read<DocuTrackerProvider>();
    final choice = await showDocuTrackerSignatureDialog(
      context,
      provider: provider,
    );
    if (!mounted || choice == null) return;
    setState(() {
      _signing = true;
      _error = null;
    });
    final bundle = await provider.signSourceSignature(
      sourceModule: widget.sourceModule,
      sourceTable: widget.sourceTable,
      sourceRecordId: widget.sourceRecordId,
      slotKey: widget.slotKey,
      signatureAssetId: choice.signatureAssetId,
      imageBytes: choice.imageBytes,
      mimeType: choice.mimeType,
      sourceType: choice.sourceType,
      saveForReuse: choice.saveForReuse,
    );
    if (!mounted) return;
    setState(() {
      _signing = false;
      if (bundle != null) {
        _bundle = bundle;
      } else {
        _error = provider.sourceSignatureError ?? 'The form was not signed.';
      }
    });
    if (bundle != null) {
      widget.onChanged?.call(bundle);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.savedMessage)));
    }
  }

  String _formatSignedAt(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final signature = _bundle?.signatureFor(widget.slotKey);
    final canAssign = signature?.canAssign ?? (_bundle?.canAssign == true);
    final canSign = signature?.canSign == true;
    final isCreatorAssigned = signature?.assignmentSource == 'creator';
    final hasAssignedSigner = (signature?.assignedSignerId ?? '')
        .trim()
        .isNotEmpty;
    final unsignedMessage = canAssign && !canSign
        ? hasAssignedSigner
              ? 'Waiting for the assigned signer'
              : 'No signer assigned yet'
        : widget.unsignedMessage;
    final waitingMessage = canAssign && !hasAssignedSigner
        ? 'Assign an account before this field can be signed.'
        : widget.waitingMessage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.draw_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (signature?.isSigned == true)
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF047857),
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ),
          ] else ...[
            Container(
              height: 104,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: DocuTrackerTokens.borderSubtleOf(context),
                ),
              ),
              child: signature?.isSigned == true
                  ? Image.memory(
                      signature!.signatureImageBytes!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    )
                  : Text(
                      unsignedMessage,
                      style: const TextStyle(
                        color: DocuTrackerTokens.textMuted,
                      ),
                    ),
            ),
            if (signature?.isSigned == true) ...[
              const SizedBox(height: 8),
              Text(
                [
                      signature?.signerName,
                      if (signature?.signedAt != null)
                        _formatSignedAt(signature!.signedAt!),
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' | '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DocuTrackerTokens.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
            if ((signature?.assignedSignerName ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                isCreatorAssigned
                    ? 'Prepared by ${signature!.assignedSignerName}'
                    : signature?.assignmentSource == 'automatic'
                    ? 'Automatically assigned to ${signature!.assignedSignerName}'
                    : 'Assigned to ${signature!.assignedSignerName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DocuTrackerTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (signature?.canSign == true)
              FilledButton.icon(
                onPressed: _signing ? null : _sign,
                icon: _signing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        signature?.isSigned == true
                            ? Icons.edit_rounded
                            : Icons.draw_rounded,
                      ),
                label: Text(
                  signature?.isSigned == true
                      ? 'Change Signature'
                      : 'Add Signature',
                ),
              )
            else
              Text(
                signature?.isSigned == true
                    ? 'The signature is saved on this form.'
                    : waitingMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DocuTrackerTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            if (isCreatorAssigned) ...[
              const SizedBox(height: 8),
              const Text(
                'This field belongs to the person who created the form.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DocuTrackerTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
            if (canAssign) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _assigning || _signing ? null : _assignSigner,
                icon: _assigning
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  (signature?.assignedSignerId ?? '').isEmpty
                      ? 'Assign signer'
                      : 'Change signer',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
