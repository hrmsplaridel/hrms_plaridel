import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../landingpage/constants/app_theme.dart';

class _CalendarEvent {
  const _CalendarEvent({
    required this.date,
    required this.type,
    required this.label,
    this.shiftStart,
    this.shiftEnd,
  });
  final String date;
  final String type;
  final String label;
  final String? shiftStart;
  final String? shiftEnd;
}

class ScheduleCalendar extends StatefulWidget {
  const ScheduleCalendar({super.key});

  @override
  State<ScheduleCalendar> createState() => _ScheduleCalendarState();
}

class _ScheduleCalendarState extends State<ScheduleCalendar> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _employees = [];
  List<_CalendarEvent> _events = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmployees();
      _loadEvents();
    });
  }

  Future<void> _loadEmployees() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/employees',
        queryParameters: {'status': 'Active'},
      );
      final data = res.data ?? [];
      _employees = (data).map((e) {
        final m = e as Map<String, dynamic>;
        return {'id': m['id'] as String, 'full_name': m['full_name'] as String? ?? '—'};
      }).toList();
      if (_employees.isNotEmpty && _selectedEmployeeId == null) {
        setState(() => _selectedEmployeeId = _employees.first['id'] as String);
        _loadEvents();
      }
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    final start = DateTime(_month.year, _month.month, 1);
    final end = DateTime(_month.year, _month.month + 1, 0);
    final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endStr = '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/calendar/events',
        queryParameters: {
          'start_date': startStr,
          'end_date': endStr,
          if (_selectedEmployeeId != null) 'employee_id': _selectedEmployeeId,
        },
      );
      final list = res.data?['events'] as List<dynamic>? ?? [];
      _events = list.map((e) {
        final m = e as Map<String, dynamic>;
        return _CalendarEvent(
          date: m['date'] as String? ?? '',
          type: m['type'] as String? ?? 'rest',
          label: m['label'] as String? ?? '',
          shiftStart: m['shift_start']?.toString(),
          shiftEnd: m['shift_end']?.toString(),
        );
      }).toList();
    } on DioException catch (e) {
      debugPrint('Load calendar events failed: ${e.response?.data ?? e.message}');
      _events = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  _CalendarEvent? _eventFor(String dateStr) {
    for (final e in _events) {
      if (e.date == dateStr) return e;
    }
    return null;
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final leadingEmpty = (firstWeekday - 1) % 7;
    final totalCells = leadingEmpty + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule Calendar',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'View employee shifts, rest days, and holidays in a calendar.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () {
                      setState(() {
                        _month = DateTime(_month.year, _month.month - 1, 1);
                        _loadEvents();
                      });
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_month.year} · ${_monthNames[_month.month - 1]}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () {
                      setState(() {
                        _month = DateTime(_month.year, _month.month + 1, 1);
                        _loadEvents();
                      });
                    },
                  ),
                ],
              ),
              if (_employees.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Employee:', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedEmployeeId,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: _employees.map((e) => DropdownMenuItem(value: e['id'] as String, child: Text(e['full_name'] as String, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedEmployeeId = v;
                            _loadEvents();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_loading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                Table(
                  border: TableBorder.all(color: AppTheme.lightGray, width: 0.5),
                  columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1), 5: FlexColumnWidth(1), 6: FlexColumnWidth(1)},
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: AppTheme.primaryNavy.withOpacity(0.08)),
                      children: _weekdays.map((w) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Center(child: Text(w, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.textPrimary))))).toList(),
                    ),
                    ...List.generate(rows, (rowIndex) {
                      return TableRow(
                        children: List.generate(7, (colIndex) {
                          final cellIndex = rowIndex * 7 + colIndex;
                          if (cellIndex < leadingEmpty) {
                            return Container(height: 72, color: AppTheme.lightGray.withOpacity(0.3));
                          }
                          final day = cellIndex - leadingEmpty + 1;
                          if (day > daysInMonth) {
                            return Container(height: 72, color: AppTheme.lightGray.withOpacity(0.3));
                          }
                          final dateStr = '${_month.year}-${_month.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                          final event = _eventFor(dateStr);
                          Color bg = Colors.white;
                          String subtitle = '';
                          if (event != null) {
                            if (event.type == 'holiday') {
                              bg = const Color(0xFFFFE0B2);
                              subtitle = event.label;
                            } else if (event.type == 'shift') {
                              bg = const Color(0xFFC8E6C9);
                              subtitle = event.label;
                              if (event.shiftStart != null && event.shiftEnd != null) {
                                final s = event.shiftStart!.length >= 5 ? event.shiftStart!.substring(0, 5) : event.shiftStart;
                                final e = event.shiftEnd!.length >= 5 ? event.shiftEnd!.substring(0, 5) : event.shiftEnd;
                                subtitle = '$subtitle $s–$e';
                              }
                            } else {
                              bg = AppTheme.lightGray.withOpacity(0.4);
                              subtitle = event.label;
                            }
                          }
                          return Container(
                            height: 72,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: bg, border: Border.all(color: AppTheme.lightGray)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$day', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
                                if (subtitle.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      subtitle,
                                      style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _legendItem(const Color(0xFFFFE0B2), 'Holiday'),
                    const SizedBox(width: 16),
                    _legendItem(const Color(0xFFC8E6C9), 'Shift'),
                    const SizedBox(width: 16),
                    _legendItem(AppTheme.lightGray.withOpacity(0.4), 'Rest day'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color, border: Border.all(color: AppTheme.lightGray))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}
