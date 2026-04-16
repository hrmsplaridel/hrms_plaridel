import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Barangays per city/municipality in Misamis Occidental (PSGC / PhilAtlas).
/// Loaded once from [assets/data/mis_occ_barangays.json].
class MisOccBarangaysData {
  MisOccBarangaysData._();

  static Map<String, List<String>>? _map;

  static bool get isLoaded => _map != null;

  /// Call from [main] before [runApp] so address forms always see data.
  static Future<void> load() async {
    if (_map != null) return;
    try {
      final s = await rootBundle.loadString('assets/data/mis_occ_barangays.json');
      final raw = json.decode(s) as Map<String, dynamic>;
      _map = raw.map(
        (k, v) => MapEntry(k, List<String>.from(v as List<dynamic>)),
      );
    } catch (e, st) {
      debugPrint('MisOccBarangaysData.load failed: $e\n$st');
      _map = {};
    }
  }

  /// Returns a sorted list for [city] when known; otherwise `null` (use free text).
  static List<String>? lookup(String? city) {
    if (city == null || _map == null) return null;
    final list = _map![city];
    if (list == null || list.isEmpty) return null;
    return list;
  }
}
