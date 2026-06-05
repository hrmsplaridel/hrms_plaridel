import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/services/local_weather_service.dart';
import 'package:hrms_plaridel/shared/widgets/weather_location_picker_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kClock12hrKey = 'dtr_clock_12hr';

/// Compact admin welcome header: live clock, date, and local weather.
class AdminWelcomeStatusCard extends StatefulWidget {
  const AdminWelcomeStatusCard({super.key});

  @override
  State<AdminWelcomeStatusCard> createState() => _AdminWelcomeStatusCardState();
}

class _AdminWelcomeStatusCardState extends State<AdminWelcomeStatusCard> {
  late Timer _clockTimer;
  late DateTime _now;
  bool _use12Hour = false;
  bool _weatherLoading = true;
  LocalWeatherSnapshot? _weather;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _loadPrefs();
    _loadWeather();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _use12Hour = prefs.getBool(_kClock12hrKey) ?? false);
  }

  Future<void> _loadWeather({bool force = false}) async {
    setState(() => _weatherLoading = true);
    try {
      final snapshot = await LocalWeatherService.instance.fetch(
        forceRefresh: force,
      );
      if (!mounted) return;
      setState(() {
        _weather = snapshot;
        _weatherLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _weatherLoading = false);
    }
  }

  Future<void> _changeLocation() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const WeatherLocationPickerDialog(),
    );
    if (changed == true) await _loadWeather(force: true);
  }

  Future<void> _toggleClockFormat() async {
    final next = !_use12Hour;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kClock12hrKey, next);
    if (mounted) setState(() => _use12Hour = next);
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    if (_use12Hour) {
      final h = _now.hour == 0
          ? 12
          : (_now.hour > 12 ? _now.hour - 12 : _now.hour);
      final ampm = _now.hour < 12 ? 'AM' : 'PM';
      return '${h.toString().padLeft(2, '0')}:$m:$s $ampm';
    }
    final h = _now.hour.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String get _dateLabel {
    return '${_weekdays[_now.weekday - 1]}, '
        '${_months[_now.month - 1]} ${_now.day}, ${_now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.dashPanelOf(context)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryNavy.withValues(alpha: dark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _timeLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _dateLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: AppTheme.dashHairlineOf(context),
          ),
          Expanded(
            child: _buildWeatherBlock(context, secondary, primary),
          ),
          const SizedBox(width: 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _toggleClockFormat,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    _use12Hour
                        ? Icons.schedule_rounded
                        : Icons.access_time_rounded,
                    size: 14,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                  ),
                ),
              ),
              InkWell(
                onTap: _weatherLoading ? null : () => _loadWeather(force: true),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: _weatherLoading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherBlock(
    BuildContext context,
    Color secondary,
    Color primary,
  ) {
    if (_weatherLoading && _weather == null) {
      return Text(
        'Loading weather…',
        style: TextStyle(fontSize: 10, color: secondary),
      );
    }

    final weather = _weather;
    if (weather == null) {
      return Text(
        'Weather unavailable',
        style: TextStyle(fontSize: 10, color: secondary),
      );
    }

    final locationHint = switch (weather.locationSource) {
      WeatherLocationSource.manual =>
        '${weather.locationLabel}\nTap to change your saved location.',
      WeatherLocationSource.device =>
        '${weather.locationLabel}\nUsing your device GPS. Tap to change.',
      WeatherLocationSource.municipalityDefault =>
        '${weather.locationLabel}\nTap to set your location.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(weather.icon, size: 13, color: const Color(0xFF1565C0)),
            const SizedBox(width: 4),
            Text(
              weather.temperatureLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: primary,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                weather.condition,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Tooltip(
          message: locationHint,
          child: InkWell(
            onTap: _changeLocation,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 11,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      weather.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                        decoration: TextDecoration.underline,
                        decorationColor: secondary.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.edit_location_alt_outlined,
                    size: 11,
                    color: AppTheme.primaryNavy.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
