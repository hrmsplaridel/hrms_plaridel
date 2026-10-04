import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';

class LocatorSignatureSection extends StatefulWidget {
  const LocatorSignatureSection({super.key, required this.requestId});

  final String requestId;

  @override
  State<LocatorSignatureSection> createState() =>
      _LocatorSignatureSectionState();
}

class _LocatorSignatureSectionState extends State<LocatorSignatureSection> {
  DocuTrackerSourceSignatureBundle? _bundle;
  String? _error;
  bool _loading = true;

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
      sourceModule: 'dtr',
      sourceTable: 'locator_slips',
      sourceRecordId: widget.requestId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _bundle = bundle;
      _error = bundle == null
          ? provider.sourceSignatureError ?? 'Signatures unavailable'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }
    if (_error != null) {
      return Row(
        children: [
          Expanded(child: Text(_error!)),
          IconButton(
            onPressed: _load,
            tooltip: 'Retry signatures',
            icon: const Icon(Icons.refresh),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Signatures',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          for (final slot in const {
            'applicant': 'Applicant',
            'department_head': 'Department review',
            'hr_approver': 'Final review',
          }.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _bundle?.signatureFor(slot.key)?.isSigned == true
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${slot.value}: ${_status(slot.key)}')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _status(String slot) {
    final signature = _bundle?.signatureFor(slot);
    if (signature?.isSigned != true) return 'Not signed';
    final name = signature?.signerName?.trim() ?? '';
    return name.isEmpty ? 'Signed' : 'Signed by $name';
  }
}
