import 'package:flutter/material.dart';

import '../data/philippine_address_data.dart';

/// Province → City/Municipality → Barangay (dropdown or text) + Street (text).
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
  final _cityManualController = TextEditingController();
  final _barangayManualController = TextEditingController();

  bool _appliedInitial = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedInitial) return;
    _appliedInitial = true;
    _applyInitial(widget.initialRawAddress);
  }

  void _applyInitial(String? raw) {
    final p = parseStoredAddress(raw);
    if (p.isStructured) {
      widget.streetController.text = p.street;
      _province = p.province.isNotEmpty ? p.province : null;
      if (_province == kProvinceMisamisOccidental) {
        final cityVal = p.city;
        if (cityVal.isNotEmpty &&
            misamisOccidentalCities.contains(cityVal)) {
          _city = cityVal;
          final brList = barangaysForMisOccCity(_city);
          if (brList != null && p.barangay.isNotEmpty) {
            if (brList.contains(p.barangay)) {
              _barangayDropdown = p.barangay;
            } else {
              _barangayManualController.text = p.barangay;
            }
          } else if (p.barangay.isNotEmpty) {
            _barangayManualController.text = p.barangay;
          }
        } else {
          _cityManualController.text = cityVal;
          _barangayManualController.text = p.barangay;
        }
      } else {
        _cityManualController.text = p.city;
        _barangayManualController.text = p.barangay;
      }
    } else {
      widget.streetController.text = p.street;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _cityManualController.dispose();
    _barangayManualController.dispose();
    super.dispose();
  }

  /// Single line for API `address` column.
  String composeEncoded() {
    final street = widget.streetController.text;
    final province = (_province ?? '').trim();

    String city;
    String barangay;

    if (province == kProvinceMisamisOccidental) {
      city = (_city ?? _cityManualController.text).trim();
      final brList = barangaysForMisOccCity(_city);
      if (brList != null) {
        barangay = (_barangayDropdown ?? _barangayManualController.text).trim();
      } else {
        barangay = _barangayManualController.text.trim();
      }
    } else {
      city = _cityManualController.text.trim();
      barangay = _barangayManualController.text.trim();
    }

    return encodeStructuredAddress(
      street: street,
      barangay: barangay,
      cityMunicipality: city,
      province: province,
    );
  }

  void _onProvinceChanged(String? v) {
    setState(() {
      _province = v;
      _city = null;
      _barangayDropdown = null;
      _cityManualController.clear();
      _barangayManualController.clear();
    });
  }

  void _onCityChanged(String? v) {
    setState(() {
      _city = v;
      _barangayDropdown = null;
      _barangayManualController.clear();
    });
  }

  bool get _isMisOcc => _province == kProvinceMisamisOccidental;

  List<String>? get _barangayList =>
      _isMisOcc ? barangaysForMisOccCity(_city) : null;

  @override
  Widget build(BuildContext context) {
    final dec = widget.inputDecoration;

    final provinceItems = List<String>.from(kPhilippineProvinces);
    if (_province != null && !provinceItems.contains(_province)) {
      provinceItems.add(_province!);
      provinceItems.sort();
    }

    final cityItems = List<String>.from(misamisOccidentalCities);
    if (_isMisOcc && _city != null && !cityItems.contains(_city)) {
      cityItems.add(_city!);
      cityItems.sort();
    }

    List<String> barangayItems = [];
    if (_barangayList != null) {
      barangayItems = List<String>.from(_barangayList!);
      if (_barangayDropdown != null &&
          !barangayItems.contains(_barangayDropdown)) {
        barangayItems.add(_barangayDropdown!);
        barangayItems.sort();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Address',
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _province,
          decoration: dec('Province'),
          hint: Text(
            'Province',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          isExpanded: true,
          items: provinceItems
              .map(
                (o) => DropdownMenuItem(value: o, child: Text(o)),
              )
              .toList(),
          onChanged: _onProvinceChanged,
        ),
        const SizedBox(height: 12),
        if (_isMisOcc) ...[
          DropdownButtonFormField<String>(
            value: _city,
            decoration: dec('City / Municipality'),
            hint: Text(
              'City / Municipality',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            isExpanded: true,
            items: cityItems
                .map(
                  (o) => DropdownMenuItem(value: o, child: Text(o)),
                )
                .toList(),
            onChanged: _onCityChanged,
          ),
        ] else ...[
          TextFormField(
            controller: _cityManualController,
            decoration: dec('City / Municipality (type)'),
          ),
        ],
        const SizedBox(height: 12),
        if (_barangayList != null) ...[
          DropdownButtonFormField<String>(
            value: _barangayDropdown,
            decoration: dec('Barangay'),
            hint: Text(
              'Barangay',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            isExpanded: true,
            items: barangayItems
                .map(
                  (o) => DropdownMenuItem(value: o, child: Text(o)),
                )
                .toList(),
            onChanged: (v) => setState(() => _barangayDropdown = v),
          ),
        ] else ...[
          TextFormField(
            controller: _barangayManualController,
            decoration: dec('Barangay (type)'),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: widget.streetController,
          decoration: dec(
            'Street / house no. / building (e.g. Rizal St., Blk 2)',
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 4),
        Text(
          'Tip: Choose Province first. For Misamis Occidental, pick City then Barangay from the list; '
          'for other provinces, type City and Barangay.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
        ),
      ],
    );
  }
}
