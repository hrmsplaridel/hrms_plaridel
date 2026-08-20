part of '../pages/manage_holiday.dart';

class _HolidayTemplateUploadDialog extends StatefulWidget {
  const _HolidayTemplateUploadDialog({required this.initialYear});

  final int initialYear;

  @override
  State<_HolidayTemplateUploadDialog> createState() =>
      _HolidayTemplateUploadDialogState();
}

class _HolidayTemplateUploadDialogState
    extends State<_HolidayTemplateUploadDialog> {
  late final TextEditingController _yearController;
  late final TextEditingController _labelController;
  late final TextEditingController _sourceController;
  late final TextEditingController _noteController;
  late final TextEditingController _csvController;

  bool _saving = false;
  String? _error;
  int _parsedCount = 0;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: widget.initialYear.toString(),
    );
    _labelController = TextEditingController(
      text: 'Philippines ${widget.initialYear} national holidays',
    );
    _sourceController = TextEditingController();
    _noteController = TextEditingController();
    _csvController = TextEditingController();
  }

  @override
  void dispose() {
    _yearController.dispose();
    _labelController.dispose();
    _sourceController.dispose();
    _noteController.dispose();
    _csvController.dispose();
    super.dispose();
  }

  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    setState(() {
      _csvController.text = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    });
    _validateCsv();
  }

  void _validateCsv() {
    try {
      final rows = _templateRowsFromCsv(_csvController.text);
      setState(() {
        _parsedCount = rows.length;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _parsedCount = 0;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _saveTemplate() async {
    final year = int.tryParse(_yearController.text.trim());
    if (year == null || year < 2000 || year > 2100) {
      setState(() => _error = 'Enter a valid year from 2000 to 2100.');
      return;
    }

    final rows = _tryParseRows();
    if (rows == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/holidays/ph-defaults/templates',
        data: {
          'year': year,
          'label': _labelController.text.trim().isEmpty
              ? 'Philippines $year national holidays'
              : _labelController.text.trim(),
          'source': _sourceController.text.trim().isEmpty
              ? 'Admin-maintained Philippine holiday template'
              : _sourceController.text.trim(),
          'note': _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          'holidays': rows,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(year);
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      setState(() {
        _saving = false;
        _error = data is Map && data['error'] != null
            ? data['error'].toString()
            : e.message ?? 'Could not save template.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save template: $e';
      });
    }
  }

  List<Map<String, dynamic>>? _tryParseRows() {
    try {
      final rows = _templateRowsFromCsv(_csvController.text);
      setState(() {
        _parsedCount = rows.length;
        _error = null;
      });
      return rows;
    } catch (e) {
      setState(() {
        _parsedCount = 0;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      return null;
    }
  }

  static List<Map<String, dynamic>> _templateRowsFromCsv(String csv) {
    final table = _parseCsv(
      csv,
    ).where((row) => row.any((cell) => cell.trim().isNotEmpty)).toList();
    if (table.length < 2) {
      throw Exception(
        'CSV must include a header row and at least one holiday.',
      );
    }

    final headers = table.first.map(_normalizeHeader).toList();
    int findColumn(List<String> names) =>
        headers.indexWhere((header) => names.contains(header));

    final dateFromIndex = findColumn(['date_from', 'date', 'start_date']);
    final dateToIndex = findColumn(['date_to', 'end_date']);
    final nameIndex = findColumn(['name', 'holiday', 'holiday_name']);
    final typeIndex = findColumn(['holiday_type', 'type']);
    final descriptionIndex = findColumn(['description', 'remarks', 'note']);
    final coverageIndex = findColumn(['coverage']);

    if (dateFromIndex < 0 || nameIndex < 0) {
      throw Exception('CSV needs date_from and name columns.');
    }

    String cell(List<String> row, int index) =>
        index >= 0 && index < row.length ? row[index].trim() : '';

    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < table.length; i++) {
      final row = table[i];
      final name = cell(row, nameIndex);
      if (name.isEmpty) continue;
      final dateFrom = _normalizeDateCell(cell(row, dateFromIndex), i + 1);
      final dateToRaw = cell(row, dateToIndex);
      final dateTo = dateToRaw.isEmpty
          ? dateFrom
          : _normalizeDateCell(dateToRaw, i + 1);
      if (dateTo.compareTo(dateFrom) < 0) {
        throw Exception('Row ${i + 1}: date_to must be after date_from.');
      }

      final holidayType = _normalizeHolidayType(cell(row, typeIndex));
      final coverage = holidayType == 'work_suspension'
          ? _normalizeCoverage(cell(row, coverageIndex))
          : 'whole_day';

      rows.add({
        'date_from': dateFrom,
        'date_to': dateTo,
        'name': name,
        'holiday_type': holidayType,
        'description': cell(row, descriptionIndex).isEmpty
            ? null
            : cell(row, descriptionIndex),
        'is_active': true,
        'recurring': false,
        'coverage': coverage,
        'sort_order': rows.length,
      });
    }

    if (rows.isEmpty) throw Exception('No valid holiday rows found.');
    return rows;
  }

  static String _normalizeHeader(String value) {
    return value
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s-]+'), '_');
  }

  static String _normalizeDateCell(String value, int rowNumber) {
    final text = value.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return text;

    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (slash != null) {
      final month = slash.group(1)!.padLeft(2, '0');
      final day = slash.group(2)!.padLeft(2, '0');
      final year = slash.group(3)!;
      return '$year-$month-$day';
    }

    throw Exception('Row $rowNumber: date must be YYYY-MM-DD.');
  }

  static String _normalizeHolidayType(String value) {
    final text = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (text.contains('suspension')) return 'work_suspension';
    if (text.contains('special')) return 'special';
    if (text.contains('local')) return 'local';
    return 'regular';
  }

  static String _normalizeCoverage(String value) {
    final text = value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (text == 'am' || text == 'am_only') return 'am_only';
    if (text == 'pm' || text == 'pm_only') return 'pm_only';
    return 'whole_day';
  }

  static List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        if (inQuotes && i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        row.add(cell.toString());
        cell.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(char);
      }
    }

    row.add(cell.toString());
    rows.add(row);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final headingColor = AppTheme.dashTextPrimaryOf(context);
    final mutedColor = AppTheme.dashTextSecondaryOf(context);
    const sampleCsv =
        'date_from,date_to,name,holiday_type,description,coverage\n'
        '2027-01-01,,New Year\'s Day,regular,Regular holiday,whole_day\n'
        '2027-03-27,,Black Saturday,special,Special non-working day,whole_day';

    return AlertDialog(
      backgroundColor: AppTheme.dashPanelOf(context),
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.upload_file_rounded,
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Add PH Holiday Template',
              style: TextStyle(
                color: headingColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: mutedColor),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 580,
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Year',
                      radius: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _labelController,
                    decoration: AppTheme.dashInputDecoration(
                      context,
                      labelText: 'Template label',
                      radius: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceController,
              decoration: AppTheme.dashInputDecoration(
                context,
                labelText: 'Source',
                hintText: 'Official proclamation / DOLE advisory',
                radius: 10,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: AppTheme.dashInputDecoration(
                context,
                labelText: 'Note',
                hintText: 'Optional',
                radius: 10,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Template CSV',
                    style: TextStyle(
                      color: headingColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickCsv,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Upload CSV'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _saving ? null : _validateCsv,
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Validate'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _csvController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: AppTheme.dashFieldTextStyle(
                  context,
                ).copyWith(fontFamily: 'Consolas', fontSize: 13),
                decoration: AppTheme.dashInputDecoration(
                  context,
                  hintText: sampleCsv,
                  radius: 10,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_parsedCount > 0)
                  _InlineTemplateStatus(
                    icon: Icons.check_circle_rounded,
                    text: '$_parsedCount holidays ready',
                    color: Colors.green,
                  ),
                if (_error != null)
                  Expanded(
                    child: _InlineTemplateStatus(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _saveTemplate,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: const Text('Save Template'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _InlineTemplateStatus extends StatelessWidget {
  const _InlineTemplateStatus({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
