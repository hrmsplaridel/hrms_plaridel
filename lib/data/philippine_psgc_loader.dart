import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Nationwide Philippines PSGC: Province → City/Municipality → Barangay (dropdowns).
/// Index loads at startup; each province's full map loads on demand.
class PhilippinePsgcData {
  PhilippinePsgcData._();

  static const _indexPath = 'assets/data/ph_psgc/index.json';
  static const _provinceAssetPrefix = 'assets/data/ph_psgc/provinces/';

  static Map<String, _ProvinceIndexEntry>? _index;
  static final Map<String, Map<String, List<String>>> _provinceCache = {};

  static bool get isIndexLoaded => _index != null;

  /// Call from [main] before [runApp].
  static Future<void> loadIndex() async {
    if (_index != null) return;
    try {
      final raw = await rootBundle.loadString(_indexPath);
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _index = decoded.map((provName, value) {
        final m = value as Map<String, dynamic>;
        final cities = (m['cities'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return MapEntry(
          provName,
          _ProvinceIndexEntry(
            slug: m['slug'] as String? ?? '',
            cities: cities,
          ),
        );
      });
    } catch (e, st) {
      debugPrint('PhilippinePsgcData.loadIndex failed: $e\n$st');
      _index = null;
    }
  }

  /// Sorted province names for dropdowns.
  static List<String> provinceNames() {
    if (_index == null || _index!.isEmpty) return [];
    final list = _index!.keys.toList();
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  /// City/municipality names for [province] (from index; no barangay load).
  static List<String>? citiesForProvince(String? province) {
    if (province == null || _index == null) return null;
    final entry = _index![province];
    if (entry == null || entry.cities.isEmpty) return null;
    return List<String>.from(entry.cities);
  }

  /// Loads full city → barangays map for [province] (cached).
  static Future<Map<String, List<String>>?> loadProvinceMap(
    String province,
  ) async {
    if (_provinceCache.containsKey(province)) {
      return _provinceCache[province];
    }
    final slug = _index?[province]?.slug;
    if (slug == null || slug.isEmpty) return null;
    try {
      final raw = await rootBundle.loadString('$_provinceAssetPrefix$slug.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final map = decoded.map(
        (city, list) => MapEntry(
          city,
          List<String>.from(list as List<dynamic>),
        ),
      );
      _provinceCache[province] = map;
      return map;
    } catch (e, st) {
      debugPrint(
        'PhilippinePsgcData.loadProvinceMap($province) failed: $e\n$st',
      );
      return null;
    }
  }

  /// Barangays for [city] after [loadProvinceMap] for [province].
  static List<String>? barangaysFor(String? province, String? city) {
    if (province == null || city == null) return null;
    final map = _provinceCache[province];
    if (map == null) return null;
    final list = map[city];
    if (list == null || list.isEmpty) return null;
    return list;
  }

  /// Whether index lists this province with at least one city.
  static bool hasProvinceData(String? province) {
    if (province == null || _index == null) return false;
    final entry = _index![province];
    return entry != null && entry.cities.isNotEmpty;
  }
}

class _ProvinceIndexEntry {
  const _ProvinceIndexEntry({required this.slug, required this.cities});

  final String slug;
  final List<String> cities;
}
