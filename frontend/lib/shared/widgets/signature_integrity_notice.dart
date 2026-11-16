import 'package:flutter/material.dart';

class SignatureIntegrityNotice extends StatelessWidget {
  const SignatureIntegrityNotice({super.key, required this.status});
  final String? status;
  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      'verified' => 'Signature matches this document revision.',
      'legacy_baseline' =>
        'Historical signature: integrity tracked from the security upgrade.',
      'legacy_unverified' => 'Historical signature awaiting the security upgrade.',
      'invalid' =>
        'This signature could not be verified. Review the document and sign again.',
      'paper_copy' => 'Signature copied from a paper approval record.',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: status == 'invalid'
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
