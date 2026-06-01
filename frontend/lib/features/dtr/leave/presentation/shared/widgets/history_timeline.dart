import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

class LeaveHistoryEvent {
  const LeaveHistoryEvent({
    required this.label,
    required this.dateTime,
    required this.actor,
    this.remarks,
    this.completed = true,
  });

  final String label;
  final DateTime? dateTime;
  final String actor;
  final String? remarks;
  final bool completed;
}

class HistoryTimeline extends StatelessWidget {
  const HistoryTimeline({super.key, required this.events});

  final List<LeaveHistoryEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: List.generate(events.length, (index) {
        final event = events[index];
        final isLast = index == events.length - 1;
        return _TimelineItem(event: event, isLast: isLast);
      }),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event, required this.isLast});

  final LeaveHistoryEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.dashIsDark(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: event.completed
                        ? AppTheme.primaryNavy
                        : (dark
                              ? const Color(0xFF6B7280)
                              : Colors.grey.shade400),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppTheme.dashHairlineOf(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.label,
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDateTime(event.dateTime)} · ${event.actor}',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                  if ((event.remarks ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.remarks!.trim(),
                      style: TextStyle(
                        color: AppTheme.dashTextSecondaryOf(context),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '—';
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
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '${months[value.month - 1]} ${value.day}, ${value.year} $hour:$minute $meridiem';
}
