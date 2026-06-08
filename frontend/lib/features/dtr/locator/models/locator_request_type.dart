class LocatorRequestType {
  const LocatorRequestType({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.locationLabel,
    required this.locationHint,
    required this.dtrSlotLabel,
    required this.dtrPrintLabel,
    this.requiresAttachment = false,
    this.coverageMode = 'manual',
    this.isActive = true,
    this.isSystem = false,
    this.sortOrder = 0,
    this.id,
  });

  static const locator = LocatorRequestType(
    code: 'locator',
    label: 'Locator / Official Business',
    shortLabel: 'Locator',
    locationLabel: 'Office / Destination',
    locationHint: 'Enter office or destination',
    dtrSlotLabel: 'On Field',
    dtrPrintLabel: 'ON FIELD',
    isSystem: true,
    sortOrder: 10,
  );

  static const passSlip = LocatorRequestType(
    code: 'pass_slip',
    label: 'Pass Slip',
    shortLabel: 'Pass Slip',
    locationLabel: 'Destination / Location',
    locationHint: 'Enter destination or location',
    dtrSlotLabel: 'Pass Slip',
    dtrPrintLabel: 'PASS SLIP',
    isSystem: true,
    sortOrder: 20,
  );

  static const workFromHome = LocatorRequestType(
    code: 'work_from_home',
    label: 'Work From Home',
    shortLabel: 'WFH',
    locationLabel: 'Work Location',
    locationHint: 'Enter work location',
    dtrSlotLabel: 'WFH',
    dtrPrintLabel: 'WFH',
    coverageMode: 'wfh',
    isSystem: true,
    sortOrder: 30,
  );

  static const values = <LocatorRequestType>[locator, passSlip, workFromHome];

  final String? id;
  final String code;
  final String label;
  final String shortLabel;
  final String locationLabel;
  final String locationHint;
  final String dtrSlotLabel;
  final String dtrPrintLabel;
  final bool requiresAttachment;
  final String coverageMode;
  final bool isActive;
  final bool isSystem;
  final int sortOrder;

  bool get usesWfhCoverage => coverageMode == 'wfh' || code == 'work_from_home';

  LocatorRequestType copyWith({
    String? id,
    String? code,
    String? label,
    String? shortLabel,
    String? locationLabel,
    String? locationHint,
    String? dtrSlotLabel,
    String? dtrPrintLabel,
    bool? requiresAttachment,
    String? coverageMode,
    bool? isActive,
    bool? isSystem,
    int? sortOrder,
  }) {
    return LocatorRequestType(
      id: id ?? this.id,
      code: code ?? this.code,
      label: label ?? this.label,
      shortLabel: shortLabel ?? this.shortLabel,
      locationLabel: locationLabel ?? this.locationLabel,
      locationHint: locationHint ?? this.locationHint,
      dtrSlotLabel: dtrSlotLabel ?? this.dtrSlotLabel,
      dtrPrintLabel: dtrPrintLabel ?? this.dtrPrintLabel,
      requiresAttachment: requiresAttachment ?? this.requiresAttachment,
      coverageMode: coverageMode ?? this.coverageMode,
      isActive: isActive ?? this.isActive,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'label': label,
      'short_label': shortLabel,
      'location_label': locationLabel,
      'location_hint': locationHint,
      'dtr_slot_label': dtrSlotLabel,
      'dtr_print_label': dtrPrintLabel,
      'requires_attachment': requiresAttachment,
      'coverage_mode': coverageMode,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  static LocatorRequestType fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString().trim().toLowerCase();
    final fallback = fromCode(code);
    return fallback.copyWith(
      id: json['id']?.toString(),
      code: code == null || code.isEmpty ? fallback.code : code,
      label: _read(json, ['label'], fallback.label),
      shortLabel: _read(json, [
        'short_label',
        'shortLabel',
      ], fallback.shortLabel),
      locationLabel: _read(json, [
        'location_label',
        'locationLabel',
      ], fallback.locationLabel),
      locationHint: _read(json, [
        'location_hint',
        'locationHint',
      ], fallback.locationHint),
      dtrSlotLabel: _read(json, [
        'dtr_slot_label',
        'dtrSlotLabel',
      ], fallback.dtrSlotLabel),
      dtrPrintLabel: _read(json, [
        'dtr_print_label',
        'dtrPrintLabel',
      ], fallback.dtrPrintLabel),
      requiresAttachment: _readBool(json, [
        'requires_attachment',
        'requiresAttachment',
      ]),
      coverageMode: _read(json, [
        'coverage_mode',
        'coverageMode',
      ], fallback.coverageMode),
      isActive: _readBool(json, ['is_active', 'isActive'], fallback: true),
      isSystem: _readBool(json, ['is_system', 'isSystem']),
      sortOrder: _readInt(json, [
        'sort_order',
        'sortOrder',
      ], fallback.sortOrder),
    );
  }

  static LocatorRequestType fromCode(Object? value) {
    final code = value?.toString().trim().toLowerCase();
    for (final type in values) {
      if (type.code == code) return type;
    }
    if (code != null && code.isNotEmpty) {
      final label = code
          .split(RegExp(r'[_-]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
      return locator.copyWith(
        code: code,
        label: label.isEmpty ? code : label,
        shortLabel: label.isEmpty ? code : label,
        dtrSlotLabel: label.isEmpty ? code : label,
        dtrPrintLabel: (label.isEmpty ? code : label).toUpperCase(),
        isSystem: false,
      );
    }
    return locator;
  }

  static String _read(
    Map<String, dynamic> json,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  static bool _readBool(
    Map<String, dynamic> json,
    List<String> keys, {
    bool fallback = false,
  }) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase();
      if (text == 'true' || text == '1') return true;
      if (text == 'false' || text == '0') return false;
    }
    return fallback;
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> keys,
    int fallback,
  ) {
    for (final key in keys) {
      final value = int.tryParse(json[key]?.toString() ?? '');
      if (value != null) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocatorRequestType && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
