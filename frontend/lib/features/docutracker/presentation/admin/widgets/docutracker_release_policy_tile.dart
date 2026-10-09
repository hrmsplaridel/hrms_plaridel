import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/docutracker/data/dto/docutracker_api_result.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_release.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';

typedef DocuTrackerReleasePoliciesLoader =
    Future<List<DocuTrackerReleasePolicy>> Function();

typedef DocuTrackerReleasePolicySaver =
    Future<DocuTrackerResult<DocuTrackerReleasePolicy>> Function({
      required String documentType,
      required bool requiresRelease,
    });

/// Admin toggle: whether approved documents of [documentType] wait for an
/// authorized release to a department. Saved immediately, separately from
/// the workflow version, and applied at the next final approval.
class DocuTrackerReleasePolicyTile extends StatefulWidget {
  const DocuTrackerReleasePolicyTile({
    super.key,
    required this.documentType,
    this.loadPolicies,
    this.savePolicy,
  });

  final String documentType;
  final DocuTrackerReleasePoliciesLoader? loadPolicies;
  final DocuTrackerReleasePolicySaver? savePolicy;

  @override
  State<DocuTrackerReleasePolicyTile> createState() =>
      _DocuTrackerReleasePolicyTileState();
}

class _DocuTrackerReleasePolicyTileState
    extends State<DocuTrackerReleasePolicyTile> {
  bool? _requiresRelease;
  bool _saving = false;
  String? _error;

  DocuTrackerReleasePoliciesLoader get _load =>
      widget.loadPolicies ?? DocuTrackerRepository.instance.getReleasePolicies;

  DocuTrackerReleasePolicySaver get _save =>
      widget.savePolicy ?? DocuTrackerRepository.instance.setReleasePolicy;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final policies = await _load();
      if (!mounted) return;
      final policy = policies
          .where((p) => p.documentType == widget.documentType)
          .firstOrNull;
      setState(() => _requiresRelease = policy?.requiresRelease ?? false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggle(bool value) async {
    final previous = _requiresRelease;
    setState(() {
      _requiresRelease = value;
      _saving = true;
      _error = null;
    });
    final result = await _save(
      documentType: widget.documentType,
      requiresRelease: value,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result is DocuTrackerFailure<DocuTrackerReleasePolicy>) {
        _requiresRelease = previous;
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _requiresRelease;
    final muted = DocuTrackerTokens.textMutedOf(context);
    return Material(
      color: DocuTrackerTokens.surfaceOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
        side: BorderSide(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('docutracker-release-policy-switch'),
            secondary: const Icon(Icons.outbox_outlined),
            title: const Text('Require release after final approval'),
            subtitle: Text(
              'Approved documents wait until an authorized user releases them '
              'to a department. Applies to documents approved from now on.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            value: value ?? false,
            onChanged: value == null || _saving ? null : _toggle,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
