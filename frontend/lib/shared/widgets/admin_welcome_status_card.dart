import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kClock12hrKey = 'dtr_clock_12hr';

/// Compact welcome header: live clock and date (shared across portal roles).
class AdminWelcomeStatusCard extends StatefulWidget {
  const AdminWelcomeStatusCard({super.key});

  @override
  State<AdminWelcomeStatusCard> createState() => _AdminWelcomeStatusCardState();
}

class _AdminWelcomeStatusCardState extends State<AdminWelcomeStatusCard> {
  late Timer _clockTimer;
  late DateTime _now;
  bool _use12Hour = true;

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
      constraints: const BoxConstraints(maxWidth: 280),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Container(
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppTheme.primaryNavy.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _timeLabel,
                            style: TextStyle(
                              fontSize: 22,
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
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Toggle time format',
            child: InkWell(
              onTap: _toggleClockFormat,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(6),
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
                child: Icon(
                  _use12Hour
                      ? Icons.schedule_rounded
                      : Icons.access_time_rounded,
                  size: 16,
                  color: AppTheme.primaryNavy.withValues(alpha: 0.88),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
