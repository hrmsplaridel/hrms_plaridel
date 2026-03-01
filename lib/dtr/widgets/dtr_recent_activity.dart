import 'package:flutter/material.dart';
import '../../landingpage/constants/app_theme.dart';
import '../../data/time_record.dart';

/// Recent time logs table for DTR dashboard.
class DtrRecentActivity extends StatelessWidget {
  const DtrRecentActivity({
    super.key,
    required this.records,
    this.loading = false,
  });

  final List<TimeRecord> records;
  final bool loading;

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Center(
          child: Text(
            'No time records yet.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              'Recent Time Logs',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppTheme.lightGray.withOpacity(0.5)),
              columns: const [
                DataColumn(label: Text('Employee')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Time In')),
                DataColumn(label: Text('Time Out')),
                DataColumn(label: Text('Hours')),
              ],
              rows: records.take(15).map((r) {
                final timeIn = r.timeIn?.toLocal();
                final timeOut = r.timeOut?.toLocal();
                final hours = r.totalHours != null
                    ? '${r.totalHours!.toStringAsFixed(1)} h'
                    : '—';
                return DataRow(
                  cells: [
                    DataCell(Text(r.employeeName ?? r.userId)),
                    DataCell(Text(_formatDate(r.recordDate))),
                    DataCell(Text(_formatTime(timeIn))),
                    DataCell(Text(_formatTime(timeOut))),
                    DataCell(Text(hours)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
