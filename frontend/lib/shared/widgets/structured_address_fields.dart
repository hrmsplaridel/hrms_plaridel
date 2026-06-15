import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/shared/models/philippine_psgc_loader.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Province → City/Municipality → Barangay (dropdowns nationwide) + Street (text).
/// Persists as [encodeStructuredAddress] in a single `address` column.
class StructuredAddressForm extends StatefulWidget {
  const StructuredAddressForm({
    super.key,
    required this.streetController,
    this.initialRawAddress,
    required this.inputDecoration,
  });

  final TextEditingController streetController;
  final String? initialRawAddress;
  final InputDecoration Function(String hint) inputDecoration;

  @override
  StructuredAddressFormState createState() => StructuredAddressFormState();
}

class StructuredAddressFormState extends State<StructuredAddressForm> {
  String? _province;
  String? _city;
  String? _barangayDropdown;
  List<String> _cityOptions = [];
  List<String> _barangayOptions = [];
  bool _loadingProvince = false;
  bool _appliedInitial = false;

  @override
  void initState() {
    super.initState();
    if (!PhilippinePsgcData.isIndexLoaded) {
      unawaited(PhilippinePsgcData.ensureIndexLoaded().then((_) {
        if (!mounted || _province == null) return;
        _loadProvinceData(_province!);
      }));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedInitial) return;
    _appliedInitial = true;
    _applyInitial(widget.initialRawAddress);
  }

  @override
  void didUpdateWidget(covariant StructuredAddressForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRawAddress != widget.initialRawAddress) {
      _applyInitial(widget.initialRawAddress);
    }
  }

  Future<void> applyRawAddress(String? rawAddress) {
    return _applyInitial(rawAddress);
  }

  Future<void> _loadProvinceData(String province) async {
    setState(() {
      _loadingProvince = true;
      _city = null;
      _barangayDropdown = null;
      _cityOptions = [];
      _barangayOptions = [];
    });
    await PhilippinePsgcData.ensureIndexLoaded();
    if (!mounted) return;
    setState(() {
      _cityOptions = PhilippinePsgcData.citiesForProvince(province) ?? [];
    });
    await PhilippinePsgcData.loadProvinceMap(province);
    if (!mounted) return;
    setState(() => _loadingProvince = false);
  }

  Future<void> _applyInitial(String? raw) async {
    final p = parseStoredAddress(raw);
    widget.streetController.text = p.street;
    if (!p.isStructured || p.province.isEmpty) {
      setState(() {});
      return;
    }

    _province = p.province;
    await _loadProvinceData(p.province);

    final cities = _cityOptions;
    if (p.city.isNotEmpty) {
      if (cities.contains(p.city)) {
        _city = p.city;
      } else {
        _cityOptions = [...cities, p.city]..sort();
        _city = p.city;
      }
      _barangayOptions =
          PhilippinePsgcData.barangaysFor(p.province, _city) ?? [];
      if (p.barangay.isNotEmpty) {
        if (_barangayOptions.contains(p.barangay)) {
          _barangayDropdown = p.barangay;
        } else {
          _barangayOptions = [..._barangayOptions, p.barangay]..sort();
          _barangayDropdown = p.barangay;
        }
      }
    }

    if (mounted) setState(() {});
  }

  /// Single line for API `address` column.
  String composeEncoded() {
    return encodeStructuredAddress(
      street: widget.streetController.text,
      barangay: (_barangayDropdown ?? '').trim(),
      cityMunicipality: (_city ?? '').trim(),
      province: (_province ?? '').trim(),
    );
  }

  void _onProvinceChanged(String? v) {
    if (v == null) {
      setState(() {
        _province = null;
        _city = null;
        _barangayDropdown = null;
        _cityOptions = [];
        _barangayOptions = [];
      });
      return;
    }
    _province = v;
    _loadProvinceData(v);
  }

  void _onCityChanged(String? v) {
    setState(() {
      _city = v;
      _barangayDropdown = null;
      _barangayOptions = PhilippinePsgcData.barangaysFor(_province, v) ?? [];
    });
  }

  bool get _hasProvinceData =>
      _province != null && PhilippinePsgcData.hasProvinceData(_province);

  @override
  Widget build(BuildContext context) {
    final dec = widget.inputDecoration;

    var provinceItems = PhilippinePsgcData.provinceNames();
    if (provinceItems.isEmpty) {
      provinceItems = List<String>.from(kPhilippineProvinces);
    }
    if (_province != null && !provinceItems.contains(_province)) {
      provinceItems.add(_province!);
      provinceItems.sort();
    }
    final provinceInitial =
        _province != null && provinceItems.contains(_province)
        ? _province
        : null;

    final cityItems = List<String>.from(_cityOptions);
    if (_city != null && !cityItems.contains(_city)) {
      cityItems.add(_city!);
      cityItems.sort();
    }
    final cityInitial = _city != null && cityItems.contains(_city)
        ? _city
        : null;

    final barangayItems = List<String>.from(_barangayOptions);
    if (_barangayDropdown != null &&
        !barangayItems.contains(_barangayDropdown)) {
      barangayItems.add(_barangayDropdown!);
      barangayItems.sort();
    }
    final barangayInitial =
        _barangayDropdown != null && barangayItems.contains(_barangayDropdown)
        ? _barangayDropdown
        : null;

    final streetFilled = widget.streetController.text.trim().isNotEmpty;
    final provinceFilled = (_province ?? '').trim().isNotEmpty;
    final cityFilled = (_city ?? '').trim().isNotEmpty;
    final barangayFilled = (_barangayDropdown ?? '').trim().isNotEmpty;
    final isComplete =
        provinceFilled && cityFilled && barangayFilled && streetFilled;

    final fieldStyle = AppTheme.dashFieldTextStyle(context);
    final hintStyle = AppTheme.dashFieldHintStyle(context);
    final sectionTitleColor = AppTheme.dashTextPrimaryOf(context);
    final tipColor = AppTheme.dashTextSecondaryOf(context);

    final provinceSelected = (_province ?? '').trim().isNotEmpty;
    final cityEnabled =
        provinceSelected && _hasProvinceData && !_loadingProvince;
    final barangayEnabled =
        cityEnabled && (_city ?? '').isNotEmpty && _barangayOptions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Address',
          style: TextStyle(
            color: sectionTitleColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (provinceItems.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Province list is still loading. Stop and restart the app '
              '(full restart, not hot reload) if this does not clear.',
              style: TextStyle(fontSize: 12, color: tipColor, height: 1.4),
            ),
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey('province-$provinceInitial-${provinceItems.length}'),
            initialValue: provinceInitial,
            style: fieldStyle,
            dropdownColor: AppTheme.dashPanelOf(context),
            decoration: dec('Province'),
            hint: Text('Select province', style: hintStyle),
            isExpanded: true,
            items: provinceItems
                .map(
                  (o) => DropdownMenuItem(
                    value: o,
                    child: Text(o, style: fieldStyle),
                  ),
                )
                .toList(),
            onChanged: _onProvinceChanged,
          ),
        const SizedBox(height: 16),
        if (_loadingProvince)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Loading cities and barangays…',
                  style: TextStyle(fontSize: 13, color: tipColor),
                ),
              ],
            ),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey('city-$cityInitial-${cityItems.length}'),
          initialValue: cityInitial,
          style: fieldStyle,
          dropdownColor: AppTheme.dashPanelOf(context),
          decoration: dec('City / Municipality'),
          hint: Text(
            !provinceSelected
                ? 'Select province first'
                : cityItems.isEmpty
                ? 'Loading cities…'
                : 'Select city / municipality',
            style: hintStyle,
          ),
          isExpanded: true,
          items: cityItems
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: fieldStyle),
                ),
              )
              .toList(),
          onChanged: cityEnabled && cityItems.isNotEmpty ? _onCityChanged : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('brgy-$barangayInitial-${barangayItems.length}'),
          initialValue: barangayInitial,
          style: fieldStyle,
          dropdownColor: AppTheme.dashPanelOf(context),
          decoration: dec('Barangay'),
          hint: Text(
            !provinceSelected
                ? 'Select province first'
                : (_city ?? '').isEmpty
                ? 'Select city / municipality first'
                : barangayItems.isEmpty
                ? 'Loading barangays…'
                : 'Select barangay',
            style: hintStyle,
          ),
          isExpanded: true,
          items: barangayItems
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: fieldStyle),
                ),
              )
              .toList(),
          onChanged: barangayEnabled
              ? (v) => setState(() => _barangayDropdown = v)
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.streetController,
          style: fieldStyle,
          decoration: dec(
            'Street / house no. / building (e.g. Rizal St., Blk 2)',
          ),
          maxLines: 2,
        ),
        if (!isComplete) ...[
          const SizedBox(height: 8),
          Text(
            'Tip: Choose Province, then City/Municipality, then Barangay. '
            'Lists cover all provinces in the Philippines (PSGC).',
            style: TextStyle(fontSize: 11, color: tipColor, height: 1.3),
          ),
        ],
      ],
    );
  }
}
