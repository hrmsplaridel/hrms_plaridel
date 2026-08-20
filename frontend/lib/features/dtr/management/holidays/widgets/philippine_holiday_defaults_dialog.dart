part of '../pages/manage_holiday.dart';

class _PhilippineHolidayDefaultsDialog extends StatefulWidget {
  const _PhilippineHolidayDefaultsDialog();

  @override
  State<_PhilippineHolidayDefaultsDialog> createState() =>
      _PhilippineHolidayDefaultsDialogState();
}

class _PhilippineHolidayDefaultsDialogState
    extends State<_PhilippineHolidayDefaultsDialog> {
  int _selectedYear = DateTime.now().year;
  List<int> _supportedYears = const [];
  _HolidayDefaultsPreview? _preview;
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPreview(_selectedYear);
    });
  }

  Future<void> _loadPreview(int year) async {
    setState(() {
      _selectedYear = year;
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/holidays/ph-defaults?year=$year',
      );
      final preview = _HolidayDefaultsPreview.fromJson(res.data ?? const {});
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _supportedYears = preview.supportedYears;
        _selectedYear = preview.year;
        _loading = false;
      });
    } on DioException catch (e) {
      final supported = _readSupportedYears(e.response?.data);
      if (supported.isNotEmpty && !supported.contains(year)) {
        final fallbackYear = supported.contains(DateTime.now().year)
            ? DateTime.now().year
            : supported.last;
        if (!mounted) return;
        setState(() {
          _supportedYears = supported;
          _selectedYear = fallbackYear;
        });
        await _loadPreview(fallbackYear);
        return;
      }
      if (!mounted) return;
      setState(() {
        _supportedYears = supported;
        _preview = null;
        _loading = false;
        _error = _apiError(e, 'Could not load Philippine holiday defaults.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _loading = false;
        _error = 'Could not load Philippine holiday defaults: $e';
      });
    }
  }

  Future<void> _importDefaults() async {
    final preview = _preview;
    if (preview == null || preview.readyCount == 0) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.post<Map<String, dynamic>>(
        '/api/holidays/ph-defaults/import',
        data: {'year': preview.year},
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _HolidayImportResult(
          createdCount: (res.data?['created_count'] as num?)?.toInt() ?? 0,
          skippedCount: (res.data?['skipped_count'] as num?)?.toInt() ?? 0,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = _apiError(e, 'Could not import Philippine holidays.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Could not import Philippine holidays: $e';
      });
    }
  }

  Future<void> _openTemplateUploadDialog() async {
    final savedYear = await openResponsiveRightSidePanel<int>(
      context: context,
      barrierLabel: 'Close holiday template upload',
      breakpoint: 900,
      minWidth: 760,
      initialWidthFraction: 0.58,
      builder: (_) =>
          _HolidayTemplateUploadDialog(initialYear: _selectedYear + 1),
    );
    if (!mounted || savedYear == null) return;
    await _loadPreview(savedYear);
  }

  List<int> get _yearOptions {
    final years = _preview?.supportedYears.isNotEmpty == true
        ? _preview!.supportedYears
        : _supportedYears;
    if (years.isEmpty) return [_selectedYear];
    return years;
  }

  static List<int> _readSupportedYears(dynamic data) {
    if (data is! Map) return const [];
    return (data['supported_years'] as List? ?? const [])
        .map((e) => (e as num?)?.toInt())
        .whereType<int>()
        .toList()
      ..sort();
  }

  static String _apiError(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return e.message ?? fallback;
  }

  String _dateLabel(_HolidayDefaultItem item) {
    final start = _ManageHolidayState._dateToYyyyMmDd(item.dateFrom);
    if (item.isSingleDay) return start;
    return '$start - ${_ManageHolidayState._dateToYyyyMmDd(item.dateTo)}';
  }

  String _typeLabel(String value) {
    return switch (value) {
      'regular' => 'Regular',
      'special' => 'Special non-working',
      'local' => 'Local',
      'work_suspension' => 'Work suspension',
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canImport = preview != null && preview.readyCount > 0 && !_importing;
    final headingColor = AppTheme.dashTextPrimaryOf(context);
    final mutedColor = AppTheme.dashTextSecondaryOf(context);

    return Material(
      color: AppTheme.dashPanelOf(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE85D04).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      color: Color(0xFFE85D04),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Generate PH Holidays',
                      style: TextStyle(
                        color: headingColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _importing
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: mutedColor),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(_selectedYear),
                            initialValue: _selectedYear,
                            decoration: AppTheme.dashInputDecoration(
                              context,
                              labelText: 'Year',
                              radius: 10,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: _yearOptions
                                .map(
                                  (year) => DropdownMenuItem<int>(
                                    value: year,
                                    child: Text(year.toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: _loading || _importing
                                ? null
                                : (year) {
                                    if (year != null) _loadPreview(year);
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (preview != null) ...[
                          _summaryChip(
                            '${preview.readyCount} ready',
                            const Color(0xFFE85D04),
                          ),
                          const SizedBox(width: 8),
                          _summaryChip(
                            '${preview.existingCount} existing',
                            Colors.green,
                          ),
                        ],
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loading || _importing
                              ? null
                              : _openTemplateUploadDialog,
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: const Text('Add Template'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (preview != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview.source,
                              style: TextStyle(
                                color: headingColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if ((preview.sourceMode ?? '').isNotEmpty)
                            _summaryChip(
                              preview.sourceMode == 'database'
                                  ? 'Saved template'
                                  : 'Built-in fallback',
                              preview.sourceMode == 'database'
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF64748B),
                            ),
                        ],
                      ),
                      if ((preview.note ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          preview.note!,
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : preview == null || preview.items.isEmpty
                          ? Center(
                              child: Text(
                                'No maintained template is available for this year.',
                                style: TextStyle(color: mutedColor),
                              ),
                            )
                          : ListView.separated(
                              itemCount: preview.items.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: AppTheme.dashHairlineOf(context),
                              ),
                              itemBuilder: (_, index) {
                                final item = preview.items[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    item.name,
                                    style: TextStyle(
                                      color: headingColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${_dateLabel(item)} · ${_typeLabel(item.holidayType)}',
                                    style: TextStyle(color: mutedColor),
                                  ),
                                  trailing: _statusPill(item.exists),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                border: Border(
                  top: BorderSide(color: AppTheme.dashHairlineOf(context)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: canImport ? _importDefaults : null,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_done_rounded, size: 18),
                    label: Text(
                      preview == null || preview.readyCount == 0
                          ? 'Nothing to import'
                          : 'Import ${preview.readyCount}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE85D04),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _statusPill(bool exists) {
    final color = exists ? Colors.green : const Color(0xFFE85D04);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        exists ? 'Exists' : 'Ready',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
