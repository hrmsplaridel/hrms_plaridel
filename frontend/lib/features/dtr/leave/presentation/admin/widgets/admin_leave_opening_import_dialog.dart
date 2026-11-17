import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_share.dart';

const openingBalanceImportHeader =
    'employee_number,cutoff_date,sick_leave_days,vacation_leave_days,qualifying_leave_days,reason';

class AdminLeaveOpeningImportDialog extends StatefulWidget {
  const AdminLeaveOpeningImportDialog({super.key, this.onSavingChanged});
  final ValueChanged<bool>? onSavingChanged;
  @override
  State<AdminLeaveOpeningImportDialog> createState() => _OpeningImportState();
}

class _OpeningImportState extends State<AdminLeaveOpeningImportDialog> {
  final _csv = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false, _valid = false, _confirmed = false;
  String? _error;
  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _rows = [];
    _valid = false;
    _confirmed = false;
    _error = null;
  });

  void _setBusy(bool value) {
    setState(() => _busy = value);
    widget.onSavingChanged?.call(value);
  }

  Future<void> _upload() async {
    if (_busy) return;
    _setBusy(true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 262144 || file.bytes == null) {
        throw const FormatException(
          'Use a UTF-8 CSV file no larger than 256 KB.',
        );
      }
      final text = utf8.decode(file.bytes!);
      _csv.text = text.replaceFirst('\uFEFF', '');
      _changed();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? 'Use a valid UTF-8 CSV file no larger than 256 KB.'
              : userFacingApiError(error),
        );
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _template() async {
    if (_busy) return;
    _setBusy(true);
    try {
      await saveOrDownloadFile(
        Uint8List.fromList(utf8.encode('$openingBalanceImportHeader\r\n')),
        'opening-leave-balances.csv',
        'text/csv;charset=utf-8',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = userFacingApiError(error));
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _request({bool commit = false}) async {
    if (_busy || (commit && (!_valid || !_confirmed))) return;
    _setBusy(true);
    setState(() => _error = null);
    try {
      final response = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/leave/admin/opening-balances/import',
        data: {
          'csv': _csv.text,
          'mode': commit ? 'import' : 'preview',
          'confirmed': commit && _confirmed,
        },
      );
      if (!mounted) return;
      final data = response.data!;
      if (commit) {
        _setBusy(false);
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _rows = (data['rows'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _valid = data['valid'] == true && _rows.isNotEmpty;
        _confirmed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _valid = false;
        _confirmed = false;
        _error = userFacingApiError(error);
        if (error is DioException && error.response?.data is Map) {
          final rows = error.response!.data['rows'];
          if (rows is List) {
            _rows = rows
                .map((r) => Map<String, dynamic>.from(r as Map))
                .toList();
          }
        }
      });
    } finally {
      if (mounted && _busy) _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 900,
        height: math.min(740, MediaQuery.sizeOf(context).height - 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Import opening balances',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Upload or paste a UTF-8 CSV with up to 200 employees (256 KB). Match by employee number, not biometric ID. Existing opening balances cannot be overwritten.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _template,
                          icon: const Icon(Icons.download),
                          label: const Text('Download template'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _upload,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload CSV'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Required columns:'),
                    const SelectableText(
                      openingBalanceImportHeader,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cutoff: YYYY-MM-DD, the last day of a completed month. SL/VL are verified available days, not additional credits. Qualifying leave days: verified Vacation/Forced Leave used from January 1 (or hire date) through the cutoff; enter 0 only if verified. Reason: HR leave-card/source reference. Amounts allow up to 3 decimals.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('opening-import-csv'),
                      controller: _csv,
                      enabled: !_busy,
                      minLines: 4,
                      maxLines: 7,
                      maxLength: 262144,
                      onChanged: (_) => _changed(),
                      decoration: const InputDecoration(
                        labelText: 'CSV content',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_rows.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _valid
                            ? '${_rows.length} employees ready to import. No changes saved yet.'
                            : 'Fix all row errors, then validate again. No changes saved.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      ..._rows.map(
                        (row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Row ${row['row']} · Employee ${row['employee_number']} ${row['employee_name'] ?? ''}\n'
                            '${row['error'] ?? 'Cutoff ${row['cutoff_date']} · SL ${row['sick_leave_days']} · VL ${row['vacation_leave_days']} · Historical usage ${row['qualifying_leave_days']} days'}\nSource: ${row['reason'] ?? ''}',
                            style: TextStyle(
                              color: row['error'] == null
                                  ? null
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirmed,
                      onChanged: _busy || !_valid
                          ? null
                          : (value) =>
                                setState(() => _confirmed = value == true),
                      title: const Text(
                        'I verified every balance and historical usage against the HR source through each cutoff.',
                      ),
                    ),
                    const Text(
                      'The whole batch is saved together. If any row fails, no employee balance is imported.',
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || _csv.text.trim().isEmpty
                        ? null
                        : () => _request(),
                    child: const Text('Validate preview'),
                  ),
                  FilledButton(
                    onPressed: _busy || !_valid || !_confirmed
                        ? null
                        : () => _request(commit: true),
                    child: Text(_busy ? 'Processing…' : 'Import balances'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
