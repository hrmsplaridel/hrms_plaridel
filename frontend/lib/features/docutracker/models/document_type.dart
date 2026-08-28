/// A document category used to select routing, permissions, and escalation.
///
/// Built-in types remain available for compatibility, while administrators can
/// create additional types by publishing a workflow for a new value.
class DocumentType {
  const DocumentType._(this.value, this.displayName);

  static const memo = DocumentType._('memo', 'Memo');
  static const purchaseRequest = DocumentType._(
    'purchaseRequest',
    'Purchase Request',
  );

  static const values = <DocumentType>[memo, purchaseRequest];

  final String value;
  final String displayName;

  factory DocumentType.fromValue(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return memo;

    for (final type in values) {
      if (_comparisonKey(type.value) == _comparisonKey(value)) return type;
    }
    return DocumentType._(value, _displayNameFor(value));
  }

  /// Builds a stable machine value from an admin-entered display name.
  factory DocumentType.fromDisplayName(String name) {
    final displayName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (displayName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Document type name is required.',
      );
    }
    final value = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (value.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Document type name is invalid.',
      );
    }
    return DocumentType.fromValue(value);
  }

  static String _comparisonKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

  static String _displayNameFor(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .split(RegExp(r'[\s_-]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => part.length == 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');

  @override
  bool operator ==(Object other) =>
      other is DocumentType &&
      _comparisonKey(other.value) == _comparisonKey(value);

  @override
  int get hashCode => _comparisonKey(value).hashCode;
}

DocumentType documentTypeFromString(String? value) =>
    DocumentType.fromValue(value);
