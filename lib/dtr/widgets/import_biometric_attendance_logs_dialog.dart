import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/biometric_import_preview.dart';
import '../models/biometric_import_result.dart';
import '../models/biometric_matched_employee.dart';
import '../repositories/biometric_import_repository.dart';
import '../utils/biometric_dat_parser.dart';

import '../../landingpage/constants/app_theme.dart';

class ImportBiometricAttendanceLogsDialog extends StatefulWidget {
  const ImportBiometricAttendanceLogsDialog({
    required this.onCancel,
    this.onImportSuccess,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback? onImportSuccess;

  @override
  State<ImportBiometricAttendanceLogsDialog> createState() =>
      _ImportBiometricAttendanceLogsDialogState();
}

class _ImportBiometricAttendanceLogsDialogState
    extends State<ImportBiometricAttendanceLogsDialog> {
  static const _matchingRepo = BiometricImportRepository();

  String? _selectedFileName;
  int? _selectedFileSizeBytes;
  String? _validationError;
  String? _parseError;
  BiometricImportPreview? _preview;
  bool _isReading = false;

  List<BiometricMatchedEmployee>? _matchedEmployees;
  String? _matchingError;
  bool _isMatching = false;

  bool _isImporting = false;

  int get _matchedCount => _matchedEmployees?.length ?? 0;
  int get _totalUniqueIds => _preview?.uniqueBiometricUserIdList.length ?? 0;
  int get _unmatchedCount => _totalUniqueIds - _matchedCount;
  List<String> get _unmatchedIds {
    final ids = _preview?.uniqueBiometricUserIdList ?? [];
    final matched = {...?_matchedEmployees?.map((e) => e.biometricUserId)};
    return ids.where((id) => !matched.contains(id)).toList();
  }

  bool get _canContinue =>
      _selectedFileName != null &&
      _validationError == null &&
      _parseError == null &&
      (_preview?.validParsedRows ?? 0) > 0 &&
      !_isReading &&
      !_isMatching &&
      !_isImporting &&
      _matchingError == null &&
      _matchedCount >= 1;

  static bool _isDatFileName(String name) =>
      name.toLowerCase().endsWith('.dat');

  void _resetSelection() {
    setState(() {
      _selectedFileName = null;
      _selectedFileSizeBytes = null;
      _validationError = null;
      _parseError = null;
      _preview = null;
      _isReading = false;
      _matchedEmployees = null;
      _matchingError = null;
      _isMatching = false;
    });
  }

  void _setValidationError(String msg) {
    setState(() => _validationError = msg);
  }

  Future<void> _pickDatFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['dat'],
      withData: true,
    );

    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      _resetSelection();
      return;
    }

    final file = result.files.single;
    final name = file.name;

    if (!_isDatFileName(name)) {
      _resetSelection();
      _setValidationError('Invalid file type. Please upload a `.dat` file.');
      return;
    }

    await _readAndPreviewDatFile(name: name, platformFile: file);
  }

  void _handleDroppedPayload(Object payload) {
    // Best-effort drag-and-drop support: only validates extension + captures name/size.
    if (payload is PlatformFile) {
      final name = payload.name;
      if (!_isDatFileName(name)) {
        _resetSelection();
        _setValidationError('Invalid file type. Please upload a `.dat` file.');
        return;
      }
      _readAndPreviewDatFile(name: name, platformFile: payload);
      return;
    }

    _resetSelection();
    _setValidationError(
      'Unsupported drop payload. Please upload a `.dat` file.',
    );
  }

  Future<void> _readAndPreviewDatFile({
    required String name,
    required PlatformFile platformFile,
  }) async {
    if (!mounted) return;

    setState(() {
      _selectedFileName = name;
      _selectedFileSizeBytes = platformFile.size;
      _validationError = null;
      _parseError = null;
      _preview = null;
      _isReading = true;
    });

    try {
      final bytes = platformFile.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _parseError =
              'Could not read file content from this selection. Please try clicking to select the file again.';
          _isReading = false;
        });
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      final preview = BiometricDatParser.parse(
        content: content,
        fileName: name,
      );

      final hasAtLeastOneValidRow = preview.validParsedRows > 0;
      setState(() {
        _preview = preview;
        _parseError = hasAtLeastOneValidRow
            ? null
            : 'No valid biometric rows were found. Expected tab-separated columns where column 1 is biometric user id and column 2 is timestamp.';
        _isReading = false;
        _matchedEmployees = null;
        _matchingError = null;
        _isMatching = false;
      });

      if (hasAtLeastOneValidRow &&
          preview.uniqueBiometricUserIdList.isNotEmpty &&
          mounted) {
        _fetchEmployeeMatching(preview.uniqueBiometricUserIdList);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parseError = 'Failed to parse the selected `.dat` file: $e';
        _isReading = false;
      });
    }
  }

  Future<void> _fetchEmployeeMatching(List<String> biometricUserIds) async {
    if (!mounted || biometricUserIds.isEmpty) return;

    setState(() {
      _isMatching = true;
      _matchingError = null;
      _matchedEmployees = null;
    });

    try {
      final matched = await _matchingRepo.findEmployeesByBiometricIds(
        biometricUserIds,
      );
      if (!mounted) return;
      setState(() {
        _matchedEmployees = matched;
        _matchingError = null;
        _isMatching = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg =
          (e.response?.data is Map &&
              (e.response!.data as Map)['error'] != null)
          ? (e.response!.data as Map)['error'].toString()
          : e.message ?? 'Failed to match employees';
      setState(() {
        _matchingError = msg;
        _matchedEmployees = null;
        _isMatching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _matchingError = 'Failed to match employees: $e';
        _matchedEmployees = null;
        _isMatching = false;
      });
    }
  }

  Future<void> _onContinue() async {
    final fileName = _selectedFileName ?? '';
    final preview = _preview;
    final matchedEmployees = _matchedEmployees;

    if (preview == null ||
        matchedEmployees == null ||
        matchedEmployees.isEmpty) {
      return;
    }

    final biometricToUserId = <String, String>{};
    for (final e in matchedEmployees) {
      if (e.id.isNotEmpty && e.biometricUserId.isNotEmpty) {
        biometricToUserId[e.biometricUserId] = e.id;
      }
    }

    final matchedRows = <Map<String, dynamic>>[];
    int unmatchedRowCount = 0;
    for (final row in preview.parsedRows) {
      final userId = biometricToUserId[row.biometricUserId];
      if (userId == null) {
        unmatchedRowCount++;
        continue;
      }
      matchedRows.add({
        'user_id': userId,
        'biometric_user_id': row.biometricUserId,
        'logged_at': row.loggedAt.toUtc().toIso8601String(),
        'raw_line': row.rawLine,
        if (row.verifyCode != null && row.verifyCode!.isNotEmpty)
          'verify_code': row.verifyCode,
        if (row.punchCode != null && row.punchCode!.isNotEmpty)
          'punch_code': row.punchCode,
        if (row.workCode != null && row.workCode!.isNotEmpty)
          'work_code': row.workCode,
      });
    }

    if (matchedRows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matched rows to import.')),
      );
      return;
    }

    setState(() => _isImporting = true);

    try {
      final apiResponse = await _matchingRepo.importBiometricLogs(
        rows: matchedRows,
        sourceFileName: fileName,
      );

      if (!mounted) return;

      final result = BiometricImportResult(
        totalParsedRows: preview.validParsedRows,
        matchedRowsAttempted: matchedRows.length,
        inserted: apiResponse.inserted,
        duplicatesSkipped: apiResponse.duplicatesSkipped,
        unmatchedRows: unmatchedRowCount,
        invalidRows: preview.invalidRows,
        summariesInserted: apiResponse.summariesInserted,
        summariesUpdated: apiResponse.summariesUpdated,
      );

      await _showImportResultDialog(result);
      if (!mounted) return;
      widget.onImportSuccess?.call();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg =
          (e.response?.data is Map &&
              (e.response!.data as Map)['error'] != null)
          ? (e.response!.data as Map)['error'].toString()
          : e.message ?? 'Failed to import biometric logs';
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $msg')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _showImportResultDialog(BiometricImportResult result) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 10),
            const Text('Import Complete'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Summary of imported biometric attendance logs.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _PreviewRow(
                label: 'Total parsed rows',
                value: '${result.totalParsedRows}',
              ),
              const SizedBox(height: 6),
              _PreviewRow(
                label: 'Matched rows attempted',
                value: '${result.matchedRowsAttempted}',
              ),
              const SizedBox(height: 6),
              _PreviewRow(label: 'Inserted', value: '${result.inserted}'),
              const SizedBox(height: 6),
              _PreviewRow(
                label: 'Duplicates skipped',
                value: '${result.duplicatesSkipped}',
              ),
              const SizedBox(height: 6),
              _PreviewRow(
                label: 'Unmatched rows',
                value: '${result.unmatchedRows}',
              ),
              const SizedBox(height: 6),
              _PreviewRow(
                label: 'Invalid rows',
                value: '${result.invalidRows}',
              ),
              const SizedBox(height: 12),
              Text(
                'DTR Daily Summary',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _PreviewRow(
                label: 'Summaries inserted',
                value: '${result.summariesInserted}',
              ),
              const SizedBox(height: 6),
              _PreviewRow(
                label: 'Summaries updated',
                value: '${result.summariesUpdated}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Biometric Attendance Logs'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload exported attendance log files from biometric devices (.dat format).',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _DatFileDropArea(
              selectedFileName: _selectedFileName,
              onPickFile: _pickDatFile,
              onDropPayload: _handleDroppedPayload,
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationError!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_isReading) ...[
              const SizedBox(height: 12),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ],
            if (_parseError != null) ...[
              const SizedBox(height: 10),
              Text(
                _parseError!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import Preview',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PreviewRow(label: 'File', value: _preview!.fileName),
                    const SizedBox(height: 6),
                    _PreviewRow(
                      label: 'Non-empty rows',
                      value: '${_preview!.totalNonEmptyRows}',
                    ),
                    const SizedBox(height: 6),
                    _PreviewRow(
                      label: 'Valid parsed rows',
                      value: '${_preview!.validParsedRows}',
                    ),
                    const SizedBox(height: 6),
                    _PreviewRow(
                      label: 'Invalid / skipped',
                      value: '${_preview!.invalidRows}',
                    ),
                    const SizedBox(height: 6),
                    _PreviewRow(
                      label: 'Unique biometric IDs',
                      value: '${_preview!.uniqueBiometricUserIds}',
                    ),
                    const SizedBox(height: 6),
                    _PreviewRow(
                      label: 'Earliest timestamp',
                      value:
                          _preview!.earliestTimestamp?.toIso8601String() ?? '—',
                    ),
                    const SizedBox(height: 6),
                    _PreviewRow(
                      label: 'Latest timestamp',
                      value:
                          _preview!.latestTimestamp?.toIso8601String() ?? '—',
                    ),
                  ],
                ),
              ),
            ],
            if (_isMatching) ...[
              const SizedBox(height: 12),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Matching biometric IDs to employees...',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
            if (_matchingError != null) ...[
              const SizedBox(height: 12),
              Text(
                _matchingError!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_preview != null &&
                !_isMatching &&
                _matchedEmployees != null &&
                _matchingError == null) ...[
              const SizedBox(height: 12),
              _MatchingSummarySection(
                totalUniqueIds: _totalUniqueIds,
                matchedCount: _matchedCount,
                unmatchedCount: _unmatchedCount,
                matchedEmployees: _matchedEmployees!,
                unmatchedIds: _unmatchedIds,
              ),
              if (_matchedCount == 0) ...[
                const SizedBox(height: 10),
                Text(
                  'No matching employees were found for the biometric IDs in this file.',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canContinue ? _onContinue : null,
          child: _isImporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

class _DatFileDropArea extends StatelessWidget {
  const _DatFileDropArea({
    required this.selectedFileName,
    required this.onPickFile,
    required this.onDropPayload,
  });

  final String? selectedFileName;
  final Future<void> Function() onPickFile;
  final void Function(Object payload) onDropPayload;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAccept: (_) => true,
      onAccept: onDropPayload,
      builder: (context, _, __) {
        return InkWell(
          onTap: () {
            onPickFile();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.lightGray.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.file_upload_rounded,
                      color: AppTheme.primaryNavy,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Click to select file or drag and drop (.dat)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  selectedFileName ?? 'No file selected yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: selectedFileName != null
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MatchingSummarySection extends StatelessWidget {
  const _MatchingSummarySection({
    required this.totalUniqueIds,
    required this.matchedCount,
    required this.unmatchedCount,
    required this.matchedEmployees,
    required this.unmatchedIds,
  });

  final int totalUniqueIds;
  final int matchedCount;
  final int unmatchedCount;
  final List<BiometricMatchedEmployee> matchedEmployees;
  final List<String> unmatchedIds;

  static const int _matchedPreviewLimit = 5;
  static const int _unmatchedPreviewLimit = 10;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Employee Matching',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _PreviewRow(
            label: 'Total unique IDs in file',
            value: '$totalUniqueIds',
          ),
          const SizedBox(height: 6),
          _PreviewRow(label: 'Matched', value: '$matchedCount'),
          const SizedBox(height: 6),
          _PreviewRow(label: 'Unmatched', value: '$unmatchedCount'),
          if (matchedEmployees.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Matched employees (up to $_matchedPreviewLimit)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...matchedEmployees
                .take(_matchedPreviewLimit)
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${e.biometricUserId} — ${e.fullName}${e.employeeNumber != null ? ' (EMP-${e.employeeNumber!.toString().padLeft(3, '0')})' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          ],
          if (unmatchedIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Unmatched biometric IDs (up to $_unmatchedPreviewLimit)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...unmatchedIds
                .take(_unmatchedPreviewLimit)
                .map(
                  (id) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      id,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
