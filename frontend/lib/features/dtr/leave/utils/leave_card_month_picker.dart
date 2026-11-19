import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'leave_card_period_report.dart';

Future<DateTime?> showLeaveCardMonthPicker(
  BuildContext context, {
  required DateTime initial,
  required String title,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _MonthPicker(initial: initial, title: title),
);

class _MonthPicker extends StatefulWidget {
  const _MonthPicker({required this.initial, required this.title});
  final DateTime initial;
  final String title;
  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late final TextEditingController _year;
  @override
  void initState() {
    super.initState();
    _year = TextEditingController(text: '${widget.initial.year}');
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final year = int.tryParse(_year.text);
    final valid = year != null && year >= 1900 && year <= 9999;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: 'Year',
                  errorText: valid ? null : 'Enter a year from 1900 to 9999.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, size) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var month = 1; month <= 12; month++)
                      SizedBox(
                        width: (size.maxWidth - 16) / 3,
                        child: OutlinedButton(
                          onPressed: valid
                              ? () => Navigator.pop(
                                  context,
                                  DateTime(year, month),
                                )
                              : null,
                          child: Text(leaveCardMonths[month - 1]),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
