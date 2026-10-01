import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_signature_dialog.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

Future<Map<String, dynamic>?> promptLocatorSignature(
  BuildContext context, {
  String? requestId,
  String slot = 'applicant',
}) async {
  final provider = context.read<DocuTrackerProvider>();
  final auth = context.read<AuthProvider>();
  final actorId = auth.user?.id;
  if (actorId == null) return null;
  if (requestId != null) {
    final bundle = await provider.loadSourceSignatures(
      sourceModule: 'dtr',
      sourceTable: 'locator_slips',
      sourceRecordId: requestId,
    );
    if (!context.mounted || auth.user?.id != actorId) return null;
    if (bundle == null) {
      throw StateError(
        provider.sourceSignatureError ?? 'Unable to check signature.',
      );
    }
    final signature = bundle.signatureFor(slot);
    if (signature?.canSign != true) {
      throw StateError(
        'This request is no longer available for your approval.',
      );
    }
    if (signature?.isSigned == true && signature?.signedBy == actorId) {
      // The server rechecks the actor and revision inside the decision transaction.
      return const {};
    }
  }
  final choice = await showDocuTrackerSignatureDialog(
    context,
    provider: provider,
    title: slot == 'applicant' ? 'Sign and Submit' : 'Sign and Approve',
  );
  if (!context.mounted || auth.user?.id != actorId || choice == null) {
    return null;
  }
  return {
    if (choice.signatureAssetId != null)
      'signature_asset_id': choice.signatureAssetId,
    if (choice.imageBytes != null)
      'image_base64': base64Encode(choice.imageBytes!),
    'mime_type': choice.mimeType,
    'source_type': choice.sourceType,
    'is_saved': choice.saveForReuse,
  };
}
