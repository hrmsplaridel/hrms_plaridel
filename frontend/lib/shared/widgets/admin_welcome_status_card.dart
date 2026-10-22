import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/services/local_weather_service.dart';
import 'package:hrms_plaridel/shared/widgets/weather_location_picker_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

const _kClock12hrKey = 'dtr_clock_12hr';

enum WelcomeStatusLayout { stacked, inline, adminHeader }

/// Compact welcome header: live clock, date, and local weather (shared across portal roles).
class AdminWelcomeStatusCard extends StatefulWidget {
  const AdminWelcomeStatusCard({
    super.key,
    this.layout = WelcomeStatusLayout.stacked,
    this.fillWidth = false,
  });

  /// [WelcomeStatusLayout.inline] is a single date / time / weather cluster
  /// without extra card chrome (used by the Mayor executive header).
  ///
  /// [WelcomeStatusLayout.adminHeader] is the compact time | weather cluster
  /// used only by the Admin dashboard welcome card.
  final WelcomeStatusLayout layout;

  /// When true, the admin-header cluster stretches (tablet/mobile). Desktop
  /// keeps the cluster shrink-wrapped on the right.
  final bool fillWidth;

  @override
  State<AdminWelcomeStatusCard> createState() => _AdminWelcomeStatusCardState();
}

class _AdminWelcomeStatusCardState extends State<AdminWelcomeStatusCard> {
  late Timer _clockTimer;
  late DateTime _now;
  bool _use12Hour = true;
  bool _weatherLoading = true;
  LocalWeatherSnapshot? _weather;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdaysLong = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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
  static const _monthsLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
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
    setState(() => _use12Hour = prefs.getBool(_kClock12hrKey) ?? true);
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
    if (_use12Hour) {
      final h = _now.hour == 0
          ? 12
          : (_now.hour > 12 ? _now.hour - 12 : _now.hour);
      final ampm = _now.hour < 12 ? 'AM' : 'PM';
      return '${h.toString().padLeft(2, '0')}:$m $ampm';
    }
    final h = _now.hour.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _compactTimeLabel {
    final m = _now.minute.toString().padLeft(2, '0');
    if (_use12Hour) {
      final h = _now.hour == 0
          ? 12
          : (_now.hour > 12 ? _now.hour - 12 : _now.hour);
      final ampm = _now.hour < 12 ? 'AM' : 'PM';
      return '${h.toString().padLeft(2, '0')}:$m $ampm';
    }
    final h = _now.hour.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _dateLabel {
    return '${_weekdays[_now.weekday - 1]}, '
        '${_months[_now.month - 1]} ${_now.day}, ${_now.year}';
  }

  String get _longDateLabel {
    return '${_weekdaysLong[_now.weekday - 1]}, '
        '${_monthsLong[_now.month - 1]} ${_now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);

    if (widget.layout == WelcomeStatusLayout.inline) {
      return _buildInlineCluster(primary, secondary);
    }

    if (widget.layout == WelcomeStatusLayout.adminHeader) {
      return _buildAdminHeaderCluster(primary, secondary);
    }

    Widget timeBlock({required bool compact}) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 8,
          vertical: compact ? 6 : 7,
        ),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.05)
              : AppTheme.primaryNavy.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: compact ? 12 : 13,
                  color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      compact ? _compactTimeLabel : _timeLabel,
                      style: TextStyle(
                        fontSize: compact ? 17 : 22,
                        fontWeight: FontWeight.w800,
                        color: primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              _dateLabel,
              style: TextStyle(
                fontSize: compact ? 9.5 : 10.5,
                fontWeight: FontWeight.w600,
                color: secondary,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [AppTheme.dashPanelOf(context), const Color(0xFF222A38)]
              : [Colors.white, const Color(0xFFFFFAF5)],
        ),
        borderRadius: BorderRadius.circular(14),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 250;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: timeBlock(compact: true))],
                ),
                const SizedBox(height: 8),
                _buildWeatherBlock(
                  context,
                  secondary,
                  primary,
                  dark,
                  compact: true,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _WelcomeActionButton(
                      icon: _use12Hour
                          ? Icons.schedule_rounded
                          : Icons.access_time_rounded,
                      tooltip: 'Toggle time format',
                      onTap: _toggleClockFormat,
                    ),
                    const SizedBox(width: 4),
                    _WelcomeActionButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh weather',
                      onTap: _weatherLoading
                          ? null
                          : () => _loadWeather(force: true),
                      loading: _weatherLoading,
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: timeBlock(compact: false)),
              Container(
                width: 1,
                height: 42,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: AppTheme.dashHairlineOf(context),
              ),
              Expanded(
                child: _buildWeatherBlock(
                  context,
                  secondary,
                  primary,
                  dark,
                  compact: false,
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WelcomeActionButton(
                    icon: _use12Hour
                        ? Icons.schedule_rounded
                        : Icons.access_time_rounded,
                    tooltip: 'Toggle time format',
                    onTap: _toggleClockFormat,
                  ),
                  _WelcomeActionButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh weather',
                    onTap: _weatherLoading
                        ? null
                        : () => _loadWeather(force: true),
                    loading: _weatherLoading,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Presentation-only city line for the Admin header. Does not change weather data.
  String _adminHeaderPlaceLabel(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Set location';
    if (t.toLowerCase().startsWith('oroquieta')) return 'Oroquieta City';
    final comma = t.indexOf(',');
    if (comma > 0) return t.substring(0, comma).trim();
    return t;
  }

  Widget _buildAdminHeaderCluster(Color primary, Color secondary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxWidth.isFinite;
        final narrow = bounded && constraints.maxWidth < 640;
        final time = _adminHeaderTimeGroup(primary, secondary);
        final weather = _adminHeaderWeatherGroup(primary, secondary);
        final location = _adminHeaderLocationGroup(secondary);
        final refresh = _adminHeaderRefresh();

        if (narrow || widget.fillWidth) {
          return Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              time,
              weather,
              if (location != null) location,
              refresh,
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            time,
            _adminHeaderDivider(),
            weather,
            if (location != null) ...[_adminHeaderDivider(), location],
            const SizedBox(width: 8),
            refresh,
          ],
        );
      },
    );
  }

  Widget _adminHeaderDivider() {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: AppTheme.dashHairlineOf(context),
    );
  }

  Widget _adminHeaderRefresh() {
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: _WelcomeActionButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh weather',
          onTap: _weatherLoading ? null : () => _loadWeather(force: true),
          loading: _weatherLoading,
          flat: true,
        ),
      ),
    );
  }

  Widget _adminHeaderTimeGroup(Color primary, Color secondary) {
    return Tooltip(
      message: 'Toggle time format',
      child: InkWell(
        onTap: _toggleClockFormat,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: AppTheme.primaryNavy.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: primary,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminHeaderWeatherGroup(Color primary, Color secondary) {
    if (_weatherLoading && _weather == null) {
      return Shimmer.fromColors(
        baseColor: AppTheme.dashIsDark(context)
            ? const Color(0xFF2A3140)
            : AppTheme.lightGray.withValues(alpha: 0.55),
        highlightColor: AppTheme.dashIsDark(context)
            ? const Color(0xFF3D4451)
            : AppTheme.white,
        period: const Duration(milliseconds: 1200),
        child: Container(
          width: 88,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.dashMutedSurfaceOf(context),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
    }

    final weather = _weather;
    if (weather == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: secondary),
          const SizedBox(width: 6),
          Text(
            'Weather unavailable',
            style: TextStyle(fontSize: 12.5, color: secondary, height: 1.2),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(weather.icon, size: 20, color: const Color(0xFF1565C0)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              weather.temperatureLabel,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: primary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                weather.condition,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget? _adminHeaderLocationGroup(Color secondary) {
    final weather = _weather;
    if (weather == null) return null;

    final isDefaultLocation =
        weather.locationSource == WeatherLocationSource.municipalityDefault;
    final locationHint = switch (weather.locationSource) {
      WeatherLocationSource.manual =>
        '${weather.locationLabel}\nTap to change your saved location.',
      WeatherLocationSource.device =>
        '${weather.locationLabel}\nUsing your device GPS. Tap to change.',
      WeatherLocationSource.municipalityDefault =>
        'No custom location set.\nTap to choose your location.',
    };

    return Tooltip(
      message: locationHint,
      child: InkWell(
        onTap: _changeLocation,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDefaultLocation
                    ? Icons.add_location_alt_outlined
                    : Icons.location_on_outlined,
                size: 16,
                color: AppTheme.primaryNavy.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  _adminHeaderPlaceLabel(weather.locationLabel),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineCluster(Color primary, Color secondary) {
    final weather = _weather;
    final tempLabel = weather?.temperatureLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _longDateLabel,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: secondary),
            InkWell(
              onTap: _toggleClockFormat,
              borderRadius: BorderRadius.circular(4),
              child: Tooltip(
                message: 'Toggle time format',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  child: Text(
                    _timeLabel,
                    style: TextStyle(
                      color: primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            Text(
              '|',
              style: TextStyle(color: secondary.withValues(alpha: 0.6)),
            ),
            if (_weatherLoading && weather == null)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: secondary,
                ),
              )
            else ...[
              Icon(
                weather?.icon ?? Icons.cloud_off_outlined,
                size: 14,
                color: secondary,
              ),
              InkWell(
                onTap: _changeLocation,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 1,
                  ),
                  child: Text(
                    tempLabel ?? '—',
                    style: TextStyle(
                      color: primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            InkWell(
              onTap: _weatherLoading ? null : () => _loadWeather(force: true),
              borderRadius: BorderRadius.circular(4),
              child: Tooltip(
                message: 'Refresh weather',
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 14,
                    color: secondary.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherBlock(
    BuildContext context,
    Color secondary,
    Color primary,
    bool dark, {
    required bool compact,
  }) {
    if (_weatherLoading && _weather == null) {
      return Shimmer.fromColors(
        baseColor: dark
            ? const Color(0xFF2A3140)
            : AppTheme.lightGray.withValues(alpha: 0.55),
        highlightColor: dark ? const Color(0xFF3D4451) : AppTheme.white,
        period: const Duration(milliseconds: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 72 : 88,
              height: compact ? 17 : 20,
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: compact ? 94 : 112,
              height: 9,
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),
      );
    }

    final weather = _weather;
    if (weather == null) {
      return Text(
        'Weather unavailable',
        style: TextStyle(fontSize: compact ? 10 : 10.5, color: secondary),
      );
    }

    final isDefaultLocation =
        weather.locationSource == WeatherLocationSource.municipalityDefault;
    final locationHint = switch (weather.locationSource) {
      WeatherLocationSource.manual =>
        '${weather.locationLabel}\nTap to change your saved location.',
      WeatherLocationSource.device =>
        '${weather.locationLabel}\nUsing your device GPS. Tap to change.',
      WeatherLocationSource.municipalityDefault =>
        'No custom location set.\nTap to choose your location.',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.05)
            : AppTheme.primaryNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(weather.icon, size: 14, color: const Color(0xFF1565C0)),
              const SizedBox(width: 4),
              Text(
                weather.temperatureLabel,
                style: TextStyle(
                  fontSize: compact ? 17 : 20,
                  fontWeight: FontWeight.w800,
                  color: primary,
                  height: 1.0,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      weather.condition,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 9.5 : 10,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (compact) ...[
            const SizedBox(height: 2),
            Text(
              weather.condition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: secondary,
              ),
            ),
          ],
          const SizedBox(height: 3),
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
                      isDefaultLocation
                          ? Icons.add_location_alt_outlined
                          : Icons.location_on_outlined,
                      size: 12,
                      color: AppTheme.primaryNavy.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        isDefaultLocation
                            ? 'Set location'
                            : weather.locationLabel,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 10 : 10.5,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                          decoration: TextDecoration.underline,
                          decorationColor: secondary.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.edit_location_alt_outlined,
                        size: 12,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeActionButton extends StatelessWidget {
  const _WelcomeActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
    this.flat = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool loading;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final iconWidget = loading
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          )
        : Icon(
            icon,
            size: 16,
            color: AppTheme.primaryNavy.withValues(alpha: 0.88),
          );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: flat
            ? Padding(padding: const EdgeInsets.all(6), child: iconWidget)
            : Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.07)
                      : AppTheme.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppTheme.primaryNavy.withValues(alpha: 0.14),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : Icon(
                        icon,
                        size: 14,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.88),
                      ),
              ),
      ),
    );
  }
}
