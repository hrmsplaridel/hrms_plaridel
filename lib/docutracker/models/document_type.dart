/// Document types with predefined workflows (Step 1 & 3).
enum DocumentType {
  memo,
  purchaseRequest,
  // Extensible: add more types as needed
}

extension DocumentTypeExtension on DocumentType {
  String get value => name;

  String get displayName => switch (this) {
    DocumentType.memo => 'Memo',
    DocumentType.purchaseRequest => 'Purchase Request',
  };
}

DocumentType documentTypeFromString(String? s) {
  if (s == null || s.isEmpty) return DocumentType.memo;
  // API may send snake_case (purchase_request) or display strings.
  final normalized = s.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  for (final e in DocumentType.values) {
    if (e.name.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '') == normalized) {
      return e;
    }
  }
  return DocumentType.memo;
}
