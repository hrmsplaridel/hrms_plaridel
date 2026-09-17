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
    this.sectionLabel = 'Address',
    this.twoColumn = false,
    this.onChanged,
  });

  final TextEditingController streetController;
  final String? initialRawAddress;
  final InputDecoration Function(String hint) inputDecoration;
  final String sectionLabel;
  final bool twoColumn;
  final VoidCallback? onChanged;

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
    widget.streetController.addListener(_notifyChanged);
    if (!PhilippinePsgcData.isIndexLoaded) {
      unawaited(
        PhilippinePsgcData.ensureIndexLoaded().then((_) {
          if (!mounted || _province == null) return;
          _loadProvinceData(_province!);
        }),
      );
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

  @override
  void dispose() {
    widget.streetController.removeListener(_notifyChanged);
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged?.call();
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
      _notifyChanged();
      return;
    }
    _province = v;
    _loadProvinceData(v);
    _notifyChanged();
  }

  void _onCityChanged(String? v) {
    setState(() {
      _city = v;
      _barangayDropdown = null;
      _barangayOptions = PhilippinePsgcData.barangaysFor(_province, v) ?? [];
    });
    _notifyChanged();
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

    final fieldStyle = AppTheme.dashFieldTextStyle(context);
    final hintStyle = AppTheme.dashFieldHintStyle(context);
    final sectionTitleColor = AppTheme.dashTextPrimaryOf(context);
    final tipColor = AppTheme.dashTextSecondaryOf(context);

    final provinceSelected = (_province ?? '').trim().isNotEmpty;
    final cityEnabled =
        provinceSelected && _hasProvinceData && !_loadingProvince;
    final barangayEnabled =
        cityEnabled && (_city ?? '').isNotEmpty && _barangayOptions.isNotEmpty;
    final mutedFill = AppTheme.dashIsDark(context)
        ? Colors.white.withValues(alpha: 0.03)
        : const Color(0xFFF3F4F6);

    InputDecoration fieldDec({
      String? hint,
      String? helper,
      bool enabled = true,
    }) {
      return dec(hint ?? '').copyWith(
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelText: null,
        hintText: hint,
        helperText: helper,
        filled: true,
        fillColor: enabled ? null : mutedFill,
      );
    }

    Widget labeled(String label, Widget field) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.dashTextPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          field,
        ],
      );
    }

    final provinceField = provinceItems.isEmpty
        ? Text(
            'Province list is still loading.',
            style: TextStyle(fontSize: 12, color: tipColor),
          )
        : DropdownButtonFormField<String>(
            key: ValueKey('province-$provinceInitial-${provinceItems.length}'),
            initialValue: provinceInitial,
            style: fieldStyle,
            dropdownColor: AppTheme.dashPanelOf(context),
            decoration: fieldDec(hint: 'Select province'),
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
          );

    final cityField = DropdownButtonFormField<String>(
      key: ValueKey('city-$cityInitial-${cityItems.length}'),
      initialValue: cityInitial,
      style: fieldStyle,
      dropdownColor: AppTheme.dashPanelOf(context),
      decoration: fieldDec(
        hint: !provinceSelected
            ? 'Select province first'
            : 'Select city / municipality',
        helper: !provinceSelected ? 'Select province first' : null,
        enabled: cityEnabled,
      ),
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
            (o) => DropdownMenuItem(value: o, child: Text(o, style: fieldStyle)),
          )
          .toList(),
      onChanged: cityEnabled && cityItems.isNotEmpty ? _onCityChanged : null,
    );

    final barangayField = DropdownButtonFormField<String>(
      key: ValueKey('brgy-$barangayInitial-${barangayItems.length}'),
      initialValue: barangayInitial,
      style: fieldStyle,
      dropdownColor: AppTheme.dashPanelOf(context),
      decoration: fieldDec(
        hint: !provinceSelected
            ? 'Select province first'
            : (_city ?? '').isEmpty
            ? 'Select city first'
            : 'Select barangay',
        helper: !provinceSelected
            ? 'Select province first'
            : (_city ?? '').isEmpty
            ? 'Select city / municipality first'
            : null,
        enabled: barangayEnabled,
      ),
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
            (o) => DropdownMenuItem(value: o, child: Text(o, style: fieldStyle)),
          )
          .toList(),
      onChanged: barangayEnabled
          ? (v) {
              setState(() => _barangayDropdown = v);
              _notifyChanged();
            }
          : null,
    );

    final streetField = TextFormField(
      controller: widget.streetController,
      style: fieldStyle,
      decoration: fieldDec(hint: 'Street / House No. / Building'),
      maxLines: widget.twoColumn ? 1 : 2,
    );

    Widget pair(Widget a, Widget b) {
      if (!widget.twoColumn) {
        return Column(
          children: [a, const SizedBox(height: 12), b],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.sectionLabel.trim().isNotEmpty) ...[
          Text(
            widget.sectionLabel,
            style: TextStyle(
              color: sectionTitleColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_loadingProvince)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading cities and barangays…',
                  style: TextStyle(fontSize: 12, color: tipColor),
                ),
              ],
            ),
          ),
        pair(
          labeled('Province', provinceField),
          labeled('City / Municipality', cityField),
        ),
        const SizedBox(height: 12),
        pair(
          labeled('Barangay', barangayField),
          labeled('Street / House No. / Building', streetField),
        ),
      ],
    );
  }
}
