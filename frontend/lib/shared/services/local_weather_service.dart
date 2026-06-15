import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the dashboard weather location was resolved.
enum WeatherLocationSource { manual, device, municipalityDefault }

/// A selectable place for weather lookup.
class WeatherLocationOption {
  const WeatherLocationOption({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

/// Snapshot of local weather for dashboard headers.
class LocalWeatherSnapshot {
  const LocalWeatherSnapshot({
    required this.temperatureC,
    required this.feelsLikeC,
    required this.condition,
    required this.locationLabel,
    required this.weatherCode,
    required this.locationSource,
  });

  final double temperatureC;
  final double feelsLikeC;
  final String condition;
  final String locationLabel;
  final int weatherCode;
  final WeatherLocationSource locationSource;

  bool get usedDeviceLocation => locationSource == WeatherLocationSource.device;

  IconData get icon => weatherIconForCode(weatherCode);

  String get temperatureLabel => '${temperatureC.round()}°C';
}

class LocalWeatherService {
  LocalWeatherService._();

  static final LocalWeatherService instance = LocalWeatherService._();

  /// Municipality of Plaridel, Misamis Occidental (municipal hall area).
  static const municipalityDefault = WeatherLocationOption(
    label: 'Plaridel, Misamis Occidental',
    latitude: 8.6211,
    longitude: 123.7109,
  );

  static const _cacheDuration = Duration(minutes: 15);
  static const _kModeKey = 'weather_location_mode';
  static const _kLabelKey = 'weather_location_label';
  static const _kLatKey = 'weather_location_lat';
  static const _kLonKey = 'weather_location_lon';

  static const List<WeatherLocationOption> quickPresets = [
    municipalityDefault,
    WeatherLocationOption(
      label: 'Oroquieta, Misamis Occidental',
      latitude: 8.4859,
      longitude: 123.8044,
    ),
    WeatherLocationOption(
      label: 'Dipolog, Zamboanga del Norte',
      latitude: 8.5881,
      longitude: 123.3419,
    ),
    WeatherLocationOption(
      label: 'Cagayan de Oro, Misamis Oriental',
      latitude: 8.4542,
      longitude: 124.6319,
    ),
    WeatherLocationOption(
      label: 'Manila, Metro Manila',
      latitude: 14.5995,
      longitude: 120.9842,
    ),
    WeatherLocationOption(
      label: 'Cebu City, Cebu',
      latitude: 10.3157,
      longitude: 123.8854,
    ),
    WeatherLocationOption(
      label: 'Davao City, Davao del Sur',
      latitude: 7.1907,
      longitude: 125.4553,
    ),
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  LocalWeatherSnapshot? _cache;
  DateTime? _cacheAt;
  String? _cacheKey;

  Future<WeatherLocationSource> getLocationMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kModeKey);
    return switch (raw) {
      'manual' => WeatherLocationSource.manual,
      'device' => WeatherLocationSource.device,
      _ => WeatherLocationSource.municipalityDefault,
    };
  }

  Future<WeatherLocationOption?> getSavedManualLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final label = prefs.getString(_kLabelKey);
    final lat = prefs.getDouble(_kLatKey);
    final lon = prefs.getDouble(_kLonKey);
    if (label == null || lat == null || lon == null) return null;
    return WeatherLocationOption(label: label, latitude: lat, longitude: lon);
  }

  Future<void> saveManualLocation(WeatherLocationOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeKey, 'manual');
    await prefs.setString(_kLabelKey, option.label);
    await prefs.setDouble(_kLatKey, option.latitude);
    await prefs.setDouble(_kLonKey, option.longitude);
    _clearCache();
  }

  Future<void> setDeviceLocationMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeKey, 'device');
    _clearCache();
  }

  Future<void> resetToMunicipalityDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeKey, 'default');
    await prefs.remove(_kLabelKey);
    await prefs.remove(_kLatKey);
    await prefs.remove(_kLonKey);
    _clearCache();
  }

  void _clearCache() {
    _cache = null;
    _cacheAt = null;
    _cacheKey = null;
  }

  Future<List<WeatherLocationOption>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://geocoding-api.open-meteo.com/v1/search',
        queryParameters: {
          'name': q,
          'count': 10,
          'language': 'en',
          'format': 'json',
          'country': 'PH',
        },
      );
      final results = res.data?['results'];
      if (results is! List) return [];

      final options = <WeatherLocationOption>[];
      for (final item in results) {
        if (item is! Map) continue;
        final name = item['name']?.toString();
        final lat = (item['latitude'] as num?)?.toDouble();
        final lon = (item['longitude'] as num?)?.toDouble();
        if (name == null || lat == null || lon == null) continue;
        final admin1 = item['admin1']?.toString();
        final country = item['country']?.toString();
        final label = [
          name,
          if (admin1 != null && admin1.isNotEmpty) admin1,
          if (country != null && country.isNotEmpty) country,
        ].join(', ');
        options.add(
          WeatherLocationOption(label: label, latitude: lat, longitude: lon),
        );
      }
      return options;
    } catch (_) {
      return [];
    }
  }

  Future<LocalWeatherSnapshot> fetch({bool forceRefresh = false}) async {
    final resolved = await _resolveLocation();
    final cacheKey =
        '${resolved.source.name}:${resolved.latitude}:${resolved.longitude}';

    if (!forceRefresh &&
        _cache != null &&
        _cacheAt != null &&
        _cacheKey == cacheKey &&
        DateTime.now().difference(_cacheAt!) < _cacheDuration) {
      return _cache!;
    }

    final current = await _fetchCurrentWeather(
      resolved.latitude,
      resolved.longitude,
    );
    final snapshot = LocalWeatherSnapshot(
      temperatureC: current.temperatureC,
      feelsLikeC: current.feelsLikeC,
      condition: weatherLabelForCode(current.weatherCode),
      locationLabel: resolved.label,
      weatherCode: current.weatherCode,
      locationSource: resolved.source,
    );

    _cache = snapshot;
    _cacheAt = DateTime.now();
    _cacheKey = cacheKey;
    return snapshot;
  }

  Future<
    ({
      double latitude,
      double longitude,
      String label,
      WeatherLocationSource source,
    })
  >
  _resolveLocation() async {
    final mode = await getLocationMode();

    if (mode == WeatherLocationSource.manual) {
      final saved = await getSavedManualLocation();
      if (saved != null) {
        return (
          latitude: saved.latitude,
          longitude: saved.longitude,
          label: saved.label,
          source: WeatherLocationSource.manual,
        );
      }
    }

    if (mode == WeatherLocationSource.device) {
      final device = await _tryDeviceLocation();
      if (device != null) return device;
    }

    return (
      latitude: municipalityDefault.latitude,
      longitude: municipalityDefault.longitude,
      label: municipalityDefault.label,
      source: WeatherLocationSource.municipalityDefault,
    );
  }

  Future<
    ({
      double latitude,
      double longitude,
      String label,
      WeatherLocationSource source,
    })?
  >
  _tryDeviceLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final lat = position.latitude;
      final lon = position.longitude;
      final label =
          await _reverseGeocode(lat, lon) ?? _formatCoords(lat, lon);
      return (
        latitude: lat,
        longitude: lon,
        label: label,
        source: WeatherLocationSource.device,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://geocoding-api.open-meteo.com/v1/reverse',
        queryParameters: {
          'latitude': lat,
          'longitude': lon,
          'language': 'en',
          'format': 'json',
          'count': 1,
        },
      );
      final results = res.data?['results'];
      if (results is! List || results.isEmpty) return null;
      final place = results.first;
      if (place is! Map) return null;
      final name = place['name']?.toString();
      final admin1 = place['admin1']?.toString();
      if (name == null || name.isEmpty) return null;
      if (admin1 != null && admin1.isNotEmpty) return '$name, $admin1';
      return name;
    } catch (_) {
      return null;
    }
  }

  Future<({double temperatureC, double feelsLikeC, int weatherCode})>
  _fetchCurrentWeather(double lat, double lon) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': lat,
        'longitude': lon,
        'current': 'temperature_2m,apparent_temperature,weather_code',
        'timezone': 'auto',
      },
    );
    final current = res.data?['current'];
    if (current is! Map) {
      throw Exception('Weather data unavailable');
    }
    return (
      temperatureC: _toDouble(current['temperature_2m']),
      feelsLikeC: _toDouble(current['apparent_temperature']),
      weatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatCoords(double lat, double lon) {
    return '${lat.toStringAsFixed(2)}°, ${lon.toStringAsFixed(2)}°';
  }
}

IconData weatherIconForCode(int code) {
  if (code == 0) return Icons.wb_sunny_rounded;
  if (code <= 3) return Icons.wb_cloudy_rounded;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 67) return Icons.water_drop_rounded;
  if (code >= 71 && code <= 77) return Icons.ac_unit_rounded;
  if (code >= 80 && code <= 82) return Icons.grain_rounded;
  if (code >= 95) return Icons.thunderstorm_rounded;
  return Icons.cloud_queue_rounded;
}

String weatherLabelForCode(int code) {
  if (code == 0) return 'Clear sky';
  if (code == 1) return 'Mainly clear';
  if (code == 2) return 'Partly cloudy';
  if (code == 3) return 'Overcast';
  if (code == 45 || code == 48) return 'Foggy';
  if (code >= 51 && code <= 55) return 'Drizzle';
  if (code >= 56 && code <= 57) return 'Freezing drizzle';
  if (code >= 61 && code <= 65) return 'Rain';
  if (code >= 66 && code <= 67) return 'Freezing rain';
  if (code >= 71 && code <= 77) return 'Snow';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 85 && code <= 86) return 'Snow showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Cloudy';
}
