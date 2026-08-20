part of '../pages/manage_holiday.dart';

class _HolidayRecord {
  const _HolidayRecord({
    required this.id,
    required this.dateFrom,
    required this.dateTo,
    required this.name,
    required this.holidayType,
    this.description,
    this.isActive = true,
    this.isRecurring = false,
    this.coverage = 'whole_day',
  });
  final String id;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String name;
  final String holidayType;
  final String? description;
  final bool isActive;
  final bool isRecurring;
  final String coverage;

  bool get isSingleDay =>
      dateFrom.year == dateTo.year &&
      dateFrom.month == dateTo.month &&
      dateFrom.day == dateTo.day;
}

class _HolidayDefaultItem {
  const _HolidayDefaultItem({
    required this.dateFrom,
    required this.dateTo,
    required this.name,
    required this.holidayType,
    required this.exists,
    this.description,
    this.existingId,
  });

  final DateTime dateFrom;
  final DateTime dateTo;
  final String name;
  final String holidayType;
  final String? description;
  final bool exists;
  final String? existingId;

  bool get isSingleDay =>
      dateFrom.year == dateTo.year &&
      dateFrom.month == dateTo.month &&
      dateFrom.day == dateTo.day;

  factory _HolidayDefaultItem.fromJson(Map<String, dynamic> json) {
    final fromRaw = json['date_from'] ?? json['holiday_date'];
    final toRaw = json['date_to'] ?? json['holiday_date'];
    return _HolidayDefaultItem(
      dateFrom: _ManageHolidayState._parseDateSafe(fromRaw),
      dateTo: _ManageHolidayState._parseDateSafe(toRaw),
      name: json['name'] as String? ?? '',
      holidayType: json['holiday_type'] as String? ?? 'regular',
      description: json['description'] as String?,
      exists: json['exists'] as bool? ?? false,
      existingId: json['existing_id']?.toString(),
    );
  }
}

class _HolidayDefaultsPreview {
  const _HolidayDefaultsPreview({
    required this.year,
    required this.label,
    required this.source,
    required this.supportedYears,
    required this.items,
    this.sourceMode,
    this.note,
  });

  final int year;
  final String label;
  final String source;
  final String? sourceMode;
  final String? note;
  final List<int> supportedYears;
  final List<_HolidayDefaultItem> items;

  int get readyCount => items.where((item) => !item.exists).length;
  int get existingCount => items.length - readyCount;

  factory _HolidayDefaultsPreview.fromJson(Map<String, dynamic> json) {
    final supported =
        (json['supported_years'] as List? ?? const [])
            .map((e) => (e as num?)?.toInt())
            .whereType<int>()
            .toList()
          ..sort();
    return _HolidayDefaultsPreview(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      label: json['label'] as String? ?? 'Philippine holidays',
      source: json['source'] as String? ?? 'Maintained holiday template',
      sourceMode: json['source_mode'] as String?,
      note: json['note'] as String?,
      supportedYears: supported,
      items: (json['holidays'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (e) => _HolidayDefaultItem.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

class _HolidayImportResult {
  const _HolidayImportResult({
    required this.createdCount,
    required this.skippedCount,
  });

  final int createdCount;
  final int skippedCount;
}
