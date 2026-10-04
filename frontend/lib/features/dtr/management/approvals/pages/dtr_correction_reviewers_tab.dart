import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class DtrCorrectionReviewersTab extends StatefulWidget {
  const DtrCorrectionReviewersTab({super.key});

  @override
  State<DtrCorrectionReviewersTab> createState() =>
      _DtrCorrectionReviewersTabState();
}

class _DtrCorrectionReviewersTabState extends State<DtrCorrectionReviewersTab> {
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _eligible = [];
  String? _primary;
  final List<String> _backups = [];
  String? _error;
  bool _loading = true;
  bool _saving = false;

  String get _dateText =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.get(
        '/api/dtr-corrections/reviewers',
        queryParameters: {'effective_date': _dateText},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final config = data['config'] as Map?;
      final ids = (config?['reviewer_ids'] as List? ?? const [])
          .map((id) => id.toString())
          .toList();
      if (!mounted) return;
      setState(() {
        _eligible = (data['eligible'] as List? ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _primary = ids.isEmpty ? null : ids.first;
        _backups
          ..clear()
          ..addAll(ids.skip(1));
      });
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_primary == null || (_eligible.length > 1 && _backups.isEmpty)) {
      setState(
        () => _error =
            'Choose a primary and a backup when another reviewer is available.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put(
        '/api/dtr-corrections/reviewers',
        data: {
          'effective_from': _dateText,
          'reviewer_ids': [_primary, ..._backups],
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DTR correction reviewers saved.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingApiError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final row in _eligible) row['id'].toString(): row['name'].toString(),
    };
    final primaryOptions = {...names};
    if (_primary != null && !primaryOptions.containsKey(_primary)) {
      primaryOptions[_primary!] = 'Unavailable reviewer';
    }
    final hairline = AppTheme.dashHairlineOf(context);
    final panel = AppTheme.dashPanelOf(context);
    final overview = Material(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Office-wide',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ListTile(
            selected: true,
            selectedColor: AppTheme.primaryNavy,
            selectedTileColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
            leading: const Icon(Icons.fact_check_outlined, size: 20),
            title: const Text('DTR Corrections'),
            subtitle: Text(
              _loading
                  ? 'Loading reviewers'
                  : _primary == null
                  ? 'Primary not configured'
                  : 'Primary assigned',
            ),
          ),
        ],
      ),
    );
    final editor = Material(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'DTR Correction Reviewers',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('Office-wide', style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 32),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading || _saving
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      setState(() => _date = picked);
                      await _load();
                    },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Effective date: $_dateText'),
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            DropdownButtonFormField<String>(
              key: ValueKey('primary-$_dateText-$_primary'),
              initialValue: _primary,
              decoration: const InputDecoration(
                labelText: 'Primary reviewer',
                border: OutlineInputBorder(),
              ),
              items: primaryOptions.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _primary = value;
                      _backups.remove(value);
                    }),
            ),
            const SizedBox(height: 16),
            Text(
              'Backup reviewers (${_backups.length}/5)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final id in _backups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(names[id] ?? 'Unavailable reviewer'),
                trailing: IconButton(
                  tooltip: 'Remove backup reviewer',
                  icon: const Icon(Icons.close),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _backups.remove(id)),
                ),
              ),
            if (_backups.length < 5)
              DropdownButtonFormField<String>(
                key: ValueKey('backup-$_dateText-${_backups.length}'),
                initialValue: null,
                decoration: const InputDecoration(
                  labelText: 'Add backup reviewer',
                  border: OutlineInputBorder(),
                ),
                items: names.entries
                    .where(
                      (entry) =>
                          entry.key != _primary &&
                          !_backups.contains(entry.key),
                    )
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _backups.add(value));
                      },
              ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save reviewers'),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              SizedBox(height: 126, width: double.infinity, child: overview),
              const SizedBox(height: 16),
              Expanded(child: editor),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth < 1000 ? 260 : 310,
              child: overview,
            ),
            const SizedBox(width: 24),
            Expanded(child: editor),
          ],
        );
      },
    );
  }
}
