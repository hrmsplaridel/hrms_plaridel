import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../landingpage/constants/app_theme.dart';

const String _kClock12hrKey = 'dtr_clock_12hr';

/// Real-time clock for DTR dashboards. Updates every second.
class RealTimeClock extends StatefulWidget {
  const RealTimeClock({super.key, this.accentColor});

  /// Icon and format-toggle accent (defaults to [AppTheme.primaryNavy]).
  final Color? accentColor;

  @override
  State<RealTimeClock> createState() => _RealTimeClockState();
}

class _RealTimeClockState extends State<RealTimeClock> {
  late Timer _timer;
  late String _timeStr;
  late String _dateStr;
  bool _use12Hour = false;

  @override
  void initState() {
    super.initState();
    _loadPreference();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _use12Hour = prefs.getBool(_kClock12hrKey) ?? false);
  }

  void _updateTime() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _timeStr = _formatTime(now);
      _dateStr = _formatDate(now);
    });
  }

  String _formatTime(DateTime dt) {
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    if (_use12Hour) {
      final hour12 = dt.hour == 0
          ? 12
          : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final h = hour12.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:$m:$s $ampm';
    }
    final h = dt.hour.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(DateTime dt) {
    const months = [
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    final accent = widget.accentColor ?? AppTheme.primaryNavy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? AppTheme.dashPanelOf(context) : AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text(
                _timeStr,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _dateStr,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.dashTextSecondaryOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  final next = !_use12Hour;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_kClock12hrKey, next);
                  if (mounted) setState(() => _use12Hour = next);
                },
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: accent,
                ),
                child: Text(
                  _use12Hour ? '24h' : '12h',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
