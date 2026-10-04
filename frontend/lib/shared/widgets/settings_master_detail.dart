import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

class SettingsListEntry {
  const SettingsListEntry({
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.group,
  });
  final String id;
  final String title;
  final IconData icon;
  final String? subtitle;
  final String? group;
}

class SettingsMasterDetail extends StatefulWidget {
  const SettingsMasterDetail({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.onSelected,
    required this.detail,
    required this.searchLabel,
    this.navigationEnabled = true,
  });
  final List<SettingsListEntry> entries;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final Widget detail;
  final String searchLabel;
  final bool navigationEnabled;

  @override
  State<SettingsMasterDetail> createState() => _SettingsMasterDetailState();
}

class _SettingsMasterDetailState extends State<SettingsMasterDetail> {
  final _search = TextEditingController();
  bool _showDetail = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _list(bool compact) {
    final query = _search.text.trim().toLowerCase();
    final entries = widget.entries
        .where((e) => e.title.toLowerCase().contains(query))
        .toList();
    return Material(
      color: AppTheme.dashPanelOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.dashHairlineOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.searchLabel,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              key: const PageStorageKey('settings-selection-list'),
              primary: false,
              children: [
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No matches.'),
                  ),
                for (var i = 0; i < entries.length; i++) ...[
                  if (entries[i].group != null &&
                      (i == 0 || entries[i - 1].group != entries[i].group))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        entries[i].group!,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ListTile(
                    key: ValueKey('settings-entry-${entries[i].id}'),
                    selected: entries[i].id == widget.selectedId,
                    selectedColor: AppTheme.primaryNavy,
                    selectedTileColor: AppTheme.primaryNavy.withValues(
                      alpha: 0.1,
                    ),
                    leading: Icon(entries[i].icon, size: 20),
                    title: Text(
                      entries[i].title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: entries[i].subtitle == null
                        ? null
                        : Text(
                            entries[i].subtitle!,
                            style: const TextStyle(fontSize: 12),
                          ),
                    trailing: compact
                        ? const Icon(Icons.chevron_right, size: 18)
                        : null,
                    enabled: widget.navigationEnabled,
                    onTap: () {
                      widget.onSelected(entries[i].id);
                      setState(() => _showDetail = true);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final detail = Material(
        color: AppTheme.dashPanelOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppTheme.dashHairlineOf(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.detail,
      );
      if (compact) {
        if (!_showDetail) return _list(true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: widget.navigationEnabled
                  ? () => setState(() => _showDetail = false)
                  : null,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to list'),
            ),
            Expanded(child: detail),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: constraints.maxWidth < 1000 ? 260 : 310,
            child: _list(false),
          ),
          const SizedBox(width: 24),
          Expanded(child: detail),
        ],
      );
    },
  );
}
