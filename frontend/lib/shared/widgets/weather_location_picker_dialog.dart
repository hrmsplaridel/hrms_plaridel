import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/services/local_weather_service.dart';

/// Lets each user pick where dashboard weather should come from.
class WeatherLocationPickerDialog extends StatefulWidget {
  const WeatherLocationPickerDialog({super.key});

  @override
  State<WeatherLocationPickerDialog> createState() =>
      _WeatherLocationPickerDialogState();
}

class _WeatherLocationPickerDialogState
    extends State<WeatherLocationPickerDialog> {
  static const _accent = Color(0xFFE85D04);

  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  List<WeatherLocationOption> _searchResults = [];
  WeatherLocationSource _currentMode = WeatherLocationSource.municipalityDefault;

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadCurrentMode() async {
    final mode = await LocalWeatherService.instance.getLocationMode();
    if (!mounted) return;
    setState(() => _currentMode = mode);
  }

  void _onSearchChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _searchController.text.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _searchResults = []);
        return;
      }
      setState(() => _searching = true);
      final results = await LocalWeatherService.instance.searchPlaces(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    });
  }

  Future<void> _pick(WeatherLocationOption option) async {
    await LocalWeatherService.instance.saveManualLocation(option);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _useDevice() async {
    await LocalWeatherService.instance.setDeviceLocationMode();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _modeLabel => switch (_currentMode) {
    WeatherLocationSource.manual => 'Saved location',
    WeatherLocationSource.device => 'Device GPS',
    WeatherLocationSource.municipalityDefault =>
      LocalWeatherService.municipalityDefault.label,
  };

  IconData get _modeIcon => switch (_currentMode) {
    WeatherLocationSource.manual => Icons.bookmark_rounded,
    WeatherLocationSource.device => Icons.my_location_rounded,
    WeatherLocationSource.municipalityDefault => Icons.location_city_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);
    final hasQuery = _searchController.text.trim().length >= 2;
    final showResults = hasQuery && (_searching || _searchResults.isNotEmpty);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: const Color(0xFFFFF8F2),
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _accent.withValues(alpha: 0.12),
                      Colors.white,
                      const Color(0xFFF5F8FF),
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Icon(
                            Icons.cloud_outlined,
                            color: _accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Weather location',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(_modeIcon, size: 16, color: _accent),
                          const SizedBox(width: 8),
                          Text(
                            'Current',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _modeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search city or town',
                        helperText: 'Type at least 2 characters to search',
                        helperStyle: TextStyle(
                          fontSize: 11,
                          color: secondary.withValues(alpha: 0.9),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppTheme.primaryNavy.withValues(alpha: 0.7),
                        ),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : (_searchController.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _accent.withValues(alpha: 0.65),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (showResults)
                      _SearchResultsList(
                        searching: _searching,
                        results: _searchResults,
                        onPick: _pick,
                      )
                    else
                      _QuickPicksGrid(onPick: _pick),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: _accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _useDevice,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Use my location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
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
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({
    required this.searching,
    required this.results,
    required this.onPick,
  });

  final bool searching;
  final List<WeatherLocationOption> results;
  final ValueChanged<WeatherLocationOption> onPick;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Text(
          'No places found. Try another spelling or clear the search.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppTheme.dashTextSecondaryOf(context),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: results.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Colors.black.withValues(alpha: 0.06),
        ),
        itemBuilder: (context, index) {
          final place = results[index];
          return ListTile(
            dense: true,
            leading: Icon(
              Icons.place_outlined,
              size: 18,
              color: AppTheme.primaryNavy.withValues(alpha: 0.75),
            ),
            title: Text(
              place.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: AppTheme.dashTextSecondaryOf(context),
            ),
            onTap: () => onPick(place),
          );
        },
      ),
    );
  }
}

class _QuickPicksGrid extends StatelessWidget {
  const _QuickPicksGrid({required this.onPick});

  final ValueChanged<WeatherLocationOption> onPick;

  static const _accent = Color(0xFFE85D04);

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick picks',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: secondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LocalWeatherService.quickPresets.map((place) {
            final shortLabel = place.label.split(',').first.trim();
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => onPick(place),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.07),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: _accent.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        shortLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
